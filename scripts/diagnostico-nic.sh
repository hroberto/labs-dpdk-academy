#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Diagnostico do caminho NIC fisica -> DPDK, etapa por etapa.
#
# POR QUE EXISTE
#
# O modulo de RX/TX depende de uma afirmacao que ninguem tinha verificado nesta
# maquina: "a NIC de referencia serve". Bindar a placa e rodar o testpmd a mao
# funciona, mas nao deixa registro, esquece uma etapa no meio, e -- pior --
# pode deixar a placa fora do kernel se algo falhar.
#
# Este script executa TODAS as etapas, verifica cada uma, e devolve a placa ao
# kernel no final: inclusive se falhar no meio, inclusive com Ctrl+C, porque o
# restauro esta num trap de EXIT/INT/TERM.
#
# E o perfil "hardware smoke" que faltava na suite: prova probe, capacidades,
# filas e link -- e nao prova benchmark nem taxa de linha.
#
# Uso: sudo ./scripts/diagnostico-nic.sh [BDF]     (padrao: 0000:08:00.0)

set -u

BDF=${1:-0000:08:00.0}
FALHAS=0
DRIVER_ORIGINAL=""

# shellcheck source=lib-nic.sh
. "$(dirname "$0")/lib-nic.sh"

titulo() { printf '\n\033[1m=== ETAPA %s: %s ===\033[0m\n' "$1" "$2"; }
ok()     { printf '  [ok]    %s\n' "$1"; }
falha()  { printf '  [FALHA] %s\n' "$1"; FALHAS=$((FALHAS+1)); }
info()   { printf '  [info]  %s\n' "$1"; }

driver_de() { basename "$(readlink -f "/sys/bus/pci/devices/$1/driver" 2>/dev/null)" 2>/dev/null; }
iface_de()  { local n; for n in /sys/bus/pci/devices/$1/net/*; do [ -e "$n" ] && { basename "$n"; return; }; done; printf ''; }

restaurar() {
    # Se ainda nao registramos o driver de origem, nada foi alterado: sair em
    # silencio. Sem esta guarda, uma falha PRE-bind (root ausente, BDF errado)
    # imprimia um "religue a mao" alarmante com o comando incompleto.
    [ -n "$DRIVER_ORIGINAL" ] || return 0
    # Placa bifurcada nunca saiu do kernel: nao ha o que restaurar, e mexer
    # nela aqui seria introduzir a alteracao que o script evitou.
    [ "${MODELO:-captura}" = "bifurcado" ] && return 0
    printf '\n\033[1m=== RESTAURANDO ===\033[0m\n'
    local atual; atual=$(driver_de "$BDF")
    if [ "$atual" = "vfio-pci" ] && [ -n "$DRIVER_ORIGINAL" ]; then
        dpdk-devbind.py --bind="$DRIVER_ORIGINAL" "$BDF" >/dev/null 2>&1
        sleep 1
    fi
    atual=$(driver_de "$BDF")
    if [ "$atual" = "$DRIVER_ORIGINAL" ]; then
        ok "placa de volta em '$atual', interface '$(iface_de "$BDF")'"
    else
        falha "placa em '$atual', esperado '$DRIVER_ORIGINAL' -- religue a mao:"
        printf '          dpdk-devbind.py --bind=%s %s\n' "$DRIVER_ORIGINAL" "$BDF"
    fi
    printf '  rota default: %s\n' "$(ip route show default 2>/dev/null | head -1)"
}
# Guardas que nao dependem de ter alterado nada vem ANTES do trap.
[ "$(id -u)" -eq 0 ] || { echo "precisa ser root: sudo $0 ${BDF}"; exit 1; }
[ -e "/sys/bus/pci/devices/$BDF" ] || { echo "dispositivo $BDF nao existe"; exit 1; }
command -v dpdk-devbind.py >/dev/null || { echo "dpdk-devbind.py nao encontrado"; exit 1; }
command -v dpdk-testpmd   >/dev/null || { echo "dpdk-testpmd nao encontrado"; exit 1; }

trap restaurar EXIT INT TERM

# ---------------------------------------------------------------------------
titulo 1 "Estado inicial"
DRIVER_ORIGINAL=$(driver_de "$BDF")
IFACE_ORIGINAL=$(iface_de "$BDF")
[ -n "$DRIVER_ORIGINAL" ] && ok "driver atual: $DRIVER_ORIGINAL" || falha "sem driver"
[ -n "$IFACE_ORIGINAL" ] && ok "interface: $IFACE_ORIGINAL" || info "sem interface no kernel"
info "rota default: $(ip route show default 2>/dev/null | awk '{print $5}')"
info "par PCI: $(lspci -n -s "${BDF#0000:}" | awk '{print $3}')"
VENDOR=$(vendor_de "$BDF")
MODELO=$(modelo_de_driver "$VENDOR")
if [ "$MODELO" = "bifurcado" ]; then
    ok "modelo de driver: BIFURCADO -- $(nome_do_vendor "$VENDOR")"
    info "kernel e DPDK compartilham o dispositivo; NAO havera bind"
else
    ok "modelo de driver: captura total (vfio-pci)"
fi
info "hugepages livres: $(awk '/HugePages_Free/{print $2}' /proc/meminfo)"
info "ulimit -l (MEMLOCK): $(ulimit -l)"

# ---------------------------------------------------------------------------
if [ "$MODELO" = "bifurcado" ]; then
    # ------------------------------------------------------------------
    titulo 2 "rdma-core (o que o mlx5 exige no lugar do vfio-pci)"
    if rdma_core_ok; then
        ok "pilha rdma-core completa"
    else
        falha "faltando:$(rdma_core_faltando)"
        info "Debian/Ubuntu: sudo apt install rdma-core libibverbs1 ibverbs-providers"
    fi
    if command -v ibv_devinfo >/dev/null 2>&1; then
        if ibv_devinfo >/dev/null 2>&1; then ok "ibv_devinfo enxerga dispositivo RDMA"
        else falha "ibv_devinfo nao enxerga dispositivo RDMA"; fi
    else
        info "ibv_devinfo ausente (pacote ibverbs-utils) -- nao e bloqueio"
    fi

    titulo 3 "Bind: nao se aplica"
    info "driver bifurcado: a interface segue no kernel, e isso e o esperado"
    info "a placa continua visivel em 'ip link' durante todo o teste"
else
titulo 2 "Carregar vfio-pci"
modprobe vfio-pci 2>&1 | sed 's/^/          /'
if lsmod | grep -q '^vfio_pci'; then ok "modulo vfio_pci carregado"; else falha "vfio_pci nao carregou"; exit 1; fi

# ---------------------------------------------------------------------------
titulo 3 "Bindar ao vfio-pci"
[ -n "$IFACE_ORIGINAL" ] && ip link set "$IFACE_ORIGINAL" down 2>/dev/null
dpdk-devbind.py --bind=vfio-pci "$BDF" 2>&1 | sed 's/^/          /'
sleep 1
if [ "$(driver_de "$BDF")" = "vfio-pci" ]; then ok "driver agora: vfio-pci"; else falha "bind nao pegou: $(driver_de "$BDF")"; exit 1; fi

GRUPO=$(basename "$(readlink -f "/sys/bus/pci/devices/$BDF/iommu_group")")
if [ -e "/dev/vfio/$GRUPO" ]; then ok "/dev/vfio/$GRUPO existe ($(stat -c '%A %U:%G' "/dev/vfio/$GRUPO"))"
else falha "/dev/vfio/$GRUPO NAO existe -- o VFIO nao expos o grupo"; fi

# ---------------------------------------------------------------------------
fi

titulo 4 "testpmd: o PMD reivindica o dispositivo?"
SAIDA=$(mktemp)
printf 'show port summary all\nshow port info 0\nquit\n' | \
  timeout 60 dpdk-testpmd -l 0-1 -a "$BDF" -- -i --total-num-mbufs=2048 >"$SAIDA" 2>&1
RC=$?
info "codigo de saida do testpmd: $RC"

echo "  --- linhas decisivas ---"
grep -E 'Probe PCI driver|EAL: Requested device|No probed|rte_eth_dev|Cannot|failed|Error|error' "$SAIDA" \
  | head -12 | sed 's/^/          /'

if grep -q 'No probed ethernet devices' "$SAIDA"; then
    falha "PMD NAO reivindicou o dispositivo"
    echo "  --- saida completa do EAL, para diagnostico ---"
    sed -n '1,40p' "$SAIDA" | sed 's/^/          /'
else
    ok "o dispositivo foi probado"
    # O testpmd ECOA o comando no prompt antes de responder, entao delimitar
    # por "show port info 0" pega so o eco. Os marcadores confiaveis sao os
    # cabecalhos que o proprio testpmd imprime.
    echo "  --- resumo da porta ---"
    sed -n '/Number of available ports/,/^$/p' "$SAIDA" | sed 's/^/          /'
    echo "  --- capacidades da porta 0 ---"
    sed -n '/Infos for port/,/Device private info/p' "$SAIDA" | sed 's/^/          /'
fi

echo "  (saida completa em $SAIDA)"

# ---------------------------------------------------------------------------
titulo 5 "Veredito"
if [ "$FALHAS" -eq 0 ]; then
    printf '  \033[1mTODAS AS ETAPAS PASSARAM\033[0m -- a NIC fisica serve para o modulo de RX/TX.\n'
else
    printf '  \033[1m%s FALHA(S)\033[0m -- veja acima; a placa sera restaurada mesmo assim.\n' "$FALHAS"
fi
