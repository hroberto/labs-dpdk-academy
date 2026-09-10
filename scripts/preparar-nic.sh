#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Prepara uma NIC física para o DPDK, com as travas que evitam perder a máquina.
#
# POR QUE ISTO É UM SCRIPT, E COM TANTA VERIFICAÇÃO
#
# Tirar uma placa de rede do kernel é a operação mais perigosa da trilha, e a
# falha é imediata e total: se a interface bindada for a que carrega o seu
# acesso, a sessão morre no meio do comando e a recuperação exige console
# físico. Nenhuma outra coisa que este projeto pede tem esse custo.
#
# O `dpdk-devbind.py` não protege contra isso -- ele avisa em alguns casos e
# obedece em todos. Este script recusa antes de tentar.
#
# AS TRAVAS, e o que cada uma impede:
#
#   1. rota default -- a interface que carrega o default gateway nunca é
#      bindada. É a trava que impede perder acesso remoto.
#   2. endereço configurado -- interface com IP ativo indica uso; exige --forcar.
#   3. IOMMU ligado -- sem ele o vfio-pci só funciona em modo no-IOMMU, que
#      remove o isolamento de DMA. O script recusa em vez de sugerir o modo
#      inseguro.
#   4. grupo IOMMU -- lista todos os membros e recusa se houver outro
#      *endpoint* além da NIC. Pontes (`pcieport`) não contam: o VFIO as
#      permite, e é por isso que um grupo "compartilhado com uma ponte" não é
#      impedimento -- premissa que este projeto já publicou errada.
#   5. PMD existe -- confere que há driver do DPDK para o par PCI, em vez de
#      bindar e descobrir depois que nenhum PMD reivindica o dispositivo.
#
# Uso:
#   ./scripts/preparar-nic.sh --status          # o que existe, sem alterar nada
#   sudo ./scripts/preparar-nic.sh 08:00.0      # binda ao vfio-pci
#   sudo ./scripts/preparar-nic.sh --desfazer 08:00.0
set -u

ACAO="bind"
FORCAR=0
BDF=""
DRIVER=""
for arg in "$@"; do
    case "$arg" in
        --status)   ACAO="status" ;;
        --desfazer) ACAO="desfazer" ;;
        --forcar)   FORCAR=1 ;;
        --driver=*) DRIVER="${arg#--driver=}" ;;
        -*)         echo "opcao desconhecida: $arg" >&2; exit 2 ;;
        *)          BDF="$arg" ;;
    esac
done

# shellcheck source=lib-nic.sh
. "$(dirname "$0")/lib-nic.sh"

erro() { printf '  RECUSADO - %s\n' "$1" >&2; }
ok()   { printf '  ok    - %s\n' "$1"; }
info() { printf '  info  - %s\n' "$1"; }

# Normaliza 08:00.0 -> 0000:08:00.0
normalizar() { case "$1" in *:*:*) printf '%s' "$1" ;; *) printf '0000:%s' "$1" ;; esac; }

iface_de() { # <bdf> -> nome da interface, ou vazio se já não está no kernel
    local n
    for n in /sys/bus/pci/devices/$1/net/*; do
        [ -e "$n" ] && { basename "$n"; return; }
    done
    printf ''
}

# --- status: não altera nada, e é o modo padrão de inspeção ---------------
if [ "$ACAO" = "status" ] || [ -z "$BDF" ]; then
    echo "== NICs e o que o DPDK pode fazer com elas =="
    echo ""
    echo "  rota default sai por: $(ip route show default 2>/dev/null | awk '{print $5; exit}')"
    echo "  grupos IOMMU no sistema: $(ls -d /sys/kernel/iommu_groups/* 2>/dev/null | wc -l)"
    echo ""
    echo "  modelo de driver por dispositivo:"
    for d in /sys/bus/pci/devices/*; do
        [ -d "$d/net" ] || continue
        b=$(basename "$d")
        vv=$(vendor_de "$b")
        m=$(modelo_de_driver "$vv")
        extra=$(nome_do_vendor "$vv")
        printf '    %-14s %-10s %s\n' "$b" "$m" "${extra:+-- $extra}"
    done
    echo ""
    if command -v dpdk-devbind.py >/dev/null 2>&1; then
        dpdk-devbind.py --status-dev net 2>/dev/null | sed 's/^/  /'
    else
        info "dpdk-devbind.py nao encontrado"
    fi
    [ -z "$BDF" ] && { echo ""; echo "  Para preparar uma: sudo $0 <BDF>"; }
    exit 0
fi

BDF=$(normalizar "$BDF")
[ -e "/sys/bus/pci/devices/$BDF" ] || { erro "dispositivo $BDF nao existe"; exit 1; }

# --- desfazer: devolve ao driver do kernel --------------------------------
#
# O driver de volta é DESCOBERTO, não fixo. A primeira versão desta função
# escrevia `--bind=r8169` literal: funcionava nesta máquina por coincidência, e
# religaria QUALQUER placa num driver de Realtek -- numa Intel ou Mellanox isso
# falha, e falha depois de a placa já estar fora do kernel.
#
# O `unused=` do devbind lista os drivers que o dispositivo aceita e que não
# estão em uso. É o próprio DPDK dizendo de onde a placa veio.
driver_de_volta() { # <bdf>
    dpdk-devbind.py --status-dev net 2>/dev/null | awk -v bdf="$1" '
        $1 == bdf {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^unused=/) {
                    sub(/^unused=/, "", $i)
                    split($i, a, ",")
                    if (a[1] != "" && a[1] != "vfio-pci") { print a[1]; exit }
                }
        }'
}

if [ "$ACAO" = "desfazer" ]; then
    echo "== Devolvendo $BDF ao kernel =="
    alvo=${DRIVER:-$(driver_de_volta "$BDF")}
    if [ -z "$alvo" ]; then
        erro "nao descobri o driver de origem de $BDF"
        echo "         Informe explicitamente: $0 --desfazer --driver=<nome> $BDF" >&2
        echo "         Candidatos: dpdk-devbind.py --status-dev net" >&2
        exit 1
    fi
    info "driver de origem: $alvo"
    dpdk-devbind.py --bind="$alvo" "$BDF" || { erro "falha ao religar em $alvo"; exit 1; }
    ok "religado em $alvo; confira com 'ip link'"
    exit 0
fi

echo "== Preparando $BDF para o DPDK =="
echo ""

# TRAVA 0 -- o MODELO DE DRIVER, antes de tudo. Bindar uma placa bifurcada ao
# vfio-pci nao e "subotimo": tira do PMD o driver de kernel de que ele depende,
# e o dispositivo para de funcionar dos dois lados.
VENDOR=$(vendor_de "$BDF")
if [ "$(modelo_de_driver "$VENDOR")" = "bifurcado" ]; then
    erro "$BDF nao deve ser bindado ao vfio-pci"
    echo "" >&2
    explicar_bifurcado "$BDF" "$VENDOR" >&2
    exit 1
fi
ok "modelo de driver: captura total (vfio-pci) -- bind se aplica"

# TRAVA 1 -- a mais importante: a interface que carrega o seu acesso.
IFACE=$(iface_de "$BDF")
DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
if [ -n "$IFACE" ] && [ "$IFACE" = "$DEFAULT_IFACE" ]; then
    erro "$IFACE carrega a rota default. Bindar isto derruba o acesso a maquina."
    echo "         Use outra NIC, ou mova a rota antes. Este script nao forca isso." >&2
    exit 1
fi
ok "${IFACE:-(sem interface)} nao carrega a rota default (${DEFAULT_IFACE:-nenhuma})"

# TRAVA 2 -- endereço configurado indica uso.
if [ -n "$IFACE" ] && ip -br addr show "$IFACE" 2>/dev/null | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    if [ "$FORCAR" -eq 0 ]; then
        erro "$IFACE tem endereco IP configurado. Use --forcar se for mesmo isso."
        exit 1
    fi
    info "$IFACE tem IP, mas --forcar foi passado"
else
    ok "${IFACE:-(sem interface)} sem endereco IP configurado"
fi

# TRAVA 3 -- IOMMU. Sem ele o vfio-pci exige no-IOMMU, que remove o isolamento
# de DMA: o dispositivo passa a poder escrever em qualquer lugar da memoria.
if [ "$(ls -d /sys/kernel/iommu_groups/* 2>/dev/null | wc -l)" -eq 0 ]; then
    erro "IOMMU desligado. Ligue no kernel (intel_iommu=on ou amd_iommu=on)."
    echo "         Sem IOMMU o vfio-pci so funciona em modo no-IOMMU, sem" >&2
    echo "         isolamento de DMA -- exceção de laboratorio, nunca padrao." >&2
    exit 1
fi
ok "IOMMU ativo"

# TRAVA 4 -- os outros membros do grupo. Pontes nao impedem; endpoints sim.
GRUPO=$(basename "$(readlink -f "/sys/bus/pci/devices/$BDF/iommu_group" 2>/dev/null)" 2>/dev/null)
if [ -n "$GRUPO" ]; then
    outros=0
    for dev in /sys/kernel/iommu_groups/"$GRUPO"/devices/*; do
        d=$(basename "$dev")
        [ "$d" = "$BDF" ] && continue
        drv=$(basename "$(readlink -f "/sys/bus/pci/devices/$d/driver" 2>/dev/null)" 2>/dev/null)
        case "$drv" in
            pcieport|pci-stub|vfio-pci|"") info "grupo $GRUPO: $d ($drv) - ponte ou livre, nao impede" ;;
            *) erro "grupo $GRUPO: $d usa '$drv' e nao e ponte"; outros=$((outros + 1)) ;;
        esac
    done
    if [ "$outros" -gt 0 ]; then
        echo "         Todo endpoint do grupo IOMMU vai junto para o vfio-pci." >&2
        echo "         Verifique o que $d faz antes de continuar." >&2
        exit 1
    fi
    ok "grupo IOMMU $GRUPO tem a NIC como unico endpoint"
fi

# TRAVA 5 -- existe PMD para este par PCI?
PAR=$(lspci -n -s "${BDF#0000:}" 2>/dev/null | awk '{print $3}')
if [ -n "$PAR" ]; then
    ven=${PAR%%:*}; dev=${PAR##*:}
    achou=""
    for so in /usr/lib/*/dpdk/pmds-*/librte_net_*.so; do
        [ -e "$so" ] || continue
        if python3 - "$so" "$ven" "$dev" <<'EOF' 2>/dev/null
import sys
data=open(sys.argv[1],'rb').read()
v=int(sys.argv[2],16).to_bytes(2,'little'); d=int(sys.argv[3],16).to_bytes(2,'little')
sys.exit(0 if v+d in data else 1)
EOF
        then achou=$(basename "$so"); break; fi
    done
    if [ -n "$achou" ]; then
        ok "PMD encontrado para $PAR: $achou"
    else
        info "nenhum PMD do DPDK reivindica $PAR — o bind funciona, mas nenhuma"
        info "aplicacao vai enxergar a porta. Considere --vdev."
    fi
fi

echo ""
echo "  Todas as travas passaram. Bindando..."
modprobe vfio-pci || { erro "modprobe vfio-pci falhou"; exit 1; }
[ -n "$IFACE" ] && ip link set "$IFACE" down 2>/dev/null
dpdk-devbind.py --bind=vfio-pci "$BDF" || { erro "dpdk-devbind falhou"; exit 1; }

echo ""
ok "$BDF agora usa vfio-pci"
echo ""
echo "  Confira:  dpdk-devbind.py --status-dev net"
echo "  Teste:    dpdk-testpmd -l 0-1 -- --total-num-mbufs=2048 --stats-period=1"
echo "  Desfazer: sudo $0 --desfazer $BDF"
echo ""
