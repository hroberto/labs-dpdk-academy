#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Diagnóstico não destrutivo de suporte a AF_XDP zero-copy por interface.
#
# Ordem das evidências:
#   1. feature NETDEV_XDP_ACT_XSK_ZEROCOPY anunciada pelo netdev;
#   2. inspeção heurística do módulo do driver;
#   3. bind real com XDP_ZEROCOPY (não executado automaticamente).
#
# A inspeção de símbolos NÃO é uma pré-condição formal: otimização, inlining,
# símbolos internos, renomeação de símbolos ou mudanças de implementação podem
# produzir falsos negativos. Ela serve para responder "vale a pena tentar?",
# não para afirmar "isso funciona".
#
# Uso:
#   ./scripts/xdp-zerocopy.sh [interface|driver]
#
# Exemplos:
#   ./scripts/xdp-zerocopy.sh enp8s0        # por interface
#   ./scripts/xdp-zerocopy.sh i40e          # por driver, sem precisar da placa
#   ./scripts/xdp-zerocopy.sh               # escolhe uma interface fisica

set -u

usage() {
    cat <<EOF
Uso: $0 [interface|driver]

Consulta a capacidade AF_XDP zero-copy de uma interface e mostra uma inspeção
heurística do módulo do driver. O script não carrega programas XDP e não altera
a configuração da rede.

O argumento pode ser uma INTERFACE (enp8s0) ou um DRIVER (i40e). O modo por
driver existe para comparar placas que não estão nesta máquina — é o que produz
a tabela i40e/ice/ixgbe do módulo de projeto final. Sem argumento, escolhe uma
interface física.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
fi

# Prefere uma interface ETHERNET com driver PCI, e não a da rota padrão.
#
# A rota padrão desta máquina, por exemplo, sai por Wi-Fi; o material do projeto
# fala da Ethernet. Diagnosticar a placa errada não é erro grave, mas responde
# a outra pergunta.
escolher_interface() {
    local candidata caminho tipo

    for caminho in /sys/class/net/*; do
        [ -e "$caminho" ] || continue
        candidata=${caminho##*/}
        [ "$candidata" = lo ] && continue
        [ -e "$caminho/device/driver" ] || continue
        # 1 = ARPHRD_ETHER. Wi-Fi tambem reporta 1, entao exclui-se quem tem
        # diretorio wireless/ ou phy80211.
        tipo=$(cat "$caminho/type" 2>/dev/null || echo 0)
        [ "$tipo" = "1" ] || continue
        [ -e "$caminho/wireless" ] || [ -e "$caminho/phy80211" ] && continue
        printf '%s\n' "$candidata"
        return 0
    done

    candidata=$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')
    if [ -n "$candidata" ] && [ -e "/sys/class/net/$candidata" ]; then
        printf '%s\n' "$candidata"
        return 0
    fi

    for caminho in /sys/class/net/*; do
        [ -e "$caminho" ] || continue
        candidata=${caminho##*/}
        [ "$candidata" = lo ] && continue
        if [ -e "$caminho/device/driver" ]; then
            printf '%s\n' "$candidata"
            return 0
        fi
    done

    return 1
}

iface=${1:-}
modo="interface"

if [ -z "$iface" ]; then
    iface=$(escolher_interface) || {
        echo "Erro: não foi possível descobrir uma interface física." >&2
        exit 2
    }
elif [ ! -e "/sys/class/net/$iface" ]; then
    # Não é interface. Antes de recusar, veja se é o nome de um DRIVER: o modo
    # por driver permite comparar placas ausentes desta máquina.
    if command -v modinfo >/dev/null 2>&1 && modinfo -n "$iface" >/dev/null 2>&1; then
        modo="driver"
    else
        printf 'Erro: "%s" nao e uma interface nem um driver conhecido.\n' "$iface" >&2
        printf '  interfaces: %s\n' "$(ls /sys/class/net | grep -v '^lo$' | tr '\n' ' ')" >&2
        exit 2
    fi
fi

if [ "$modo" = "driver" ]; then
    driver=$iface
    iface="(nenhuma — consulta por driver)"
    pci="-"
else
    driver_path=$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null || true)
    driver=${driver_path##*/}
    [ -n "$driver_path" ] || driver="desconhecido/virtual"

    pci="-"
    if [ -e "/sys/class/net/$iface/device" ]; then
        pci=$(basename "$(readlink -f "/sys/class/net/$iface/device")")
    fi
fi

if [ "$modo" = "driver" ]; then
    printf '\n== AF_XDP zero-copy: inspeção do DRIVER ==\n'
else
    printf '\n== AF_XDP zero-copy: diagnóstico da INTERFACE ==\n'
fi
printf '  kernel ....... %s\n' "$(uname -r)"
[ "$modo" = "driver" ] || printf '  interface .... %s\n' "$iface"
printf '  driver ....... %s\n' "$driver"
printf '  dispositivo .. %s\n' "$pci"

if [ "$modo" != "driver" ]; then
    operstate=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "?")
    carrier=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || echo "?")
    printf '  estado ....... %s (carrier=%s)\n' "$operstate" "$carrier"
    if [ "$operstate" != "up" ]; then
        printf '  AVISO: a interface nao esta ativa. Algumas consultas podem\n'
        printf '         responder de forma incompleta; confira a heuristica do\n'
        printf '         modulo abaixo antes de concluir pela ausencia de suporte.\n'
    fi
fi

printf '\n-- Infraestrutura do kernel --\n'
config=""
if [ -r /proc/config.gz ]; then
    config=$(zgrep -E '^(CONFIG_XDP_SOCKETS|CONFIG_BPF|CONFIG_BPF_SYSCALL)=' /proc/config.gz 2>/dev/null || true)
elif [ -r "/boot/config-$(uname -r)" ]; then
    config=$(grep -E '^(CONFIG_XDP_SOCKETS|CONFIG_BPF|CONFIG_BPF_SYSCALL)=' "/boot/config-$(uname -r)" 2>/dev/null || true)
fi

if [ -n "$config" ]; then
    printf '%s\n' "$config" | sed 's/^/  /'
else
    echo "  configuração do kernel indisponível para leitura"
fi

printf '\n-- Capacidade anunciada pelo netdev --\n'
capacidade="desconhecida"
if [ "$modo" = "driver" ]; then
    echo "  consulta por DRIVER: nao ha netdev para interrogar."
    echo "  Só a inspeção do módulo abaixo se aplica neste modo."
elif [ "$(id -u)" -ne 0 ] && command -v xdp-loader >/dev/null 2>&1; then
    # Dito explicitamente: sem isto o veredito cai em "inconclusivo" e o leitor
    # nao descobre que faltou apenas privilegio.
    echo "  xdp-loader exige root para ler as features do netdev."
    echo "  Repita com: sudo $0 $iface"
elif command -v xdp-loader >/dev/null 2>&1; then
    feature_output=$(xdp-loader features "$iface" 2>&1)
    feature_rc=$?
    printf '%s\n' "$feature_output" | sed 's/^/  /'

    if [ "$feature_rc" -eq 0 ]; then
        campo() { printf '%s\n' "$feature_output" |
            awk -F: -v k="$1" '$1 == k {gsub(/[[:space:]]/, "", $2); print tolower($2); exit}'; }
        zc_line=$(campo NETDEV_XDP_ACT_XSK_ZEROCOPY)
        basico=$(campo NETDEV_XDP_ACT_BASIC)
        case "$zc_line" in
            yes|sim) capacidade="sim" ;;
            no|nao|não) capacidade="não" ;;
        esac
    fi
else
    echo "  xdp-loader não encontrado; instale xdp-tools para consultar a feature."
fi

printf '\n-- Heurística do módulo (evidência secundária) --\n'
module=""
if [ "$driver" != "desconhecido/virtual" ] && command -v modinfo >/dev/null 2>&1; then
    module=$(modinfo -n "$driver" 2>/dev/null || true)
fi

if [ -z "$module" ]; then
    echo "  módulo não localizado"
elif [ "$module" = "(builtin)" ]; then
    echo "  driver incorporado ao kernel; não há módulo separado para inspecionar"
elif [ ! -r "$module" ]; then
    printf '  módulo sem permissão de leitura: %s\n' "$module"
elif ! command -v nm >/dev/null 2>&1; then
    echo "  nm não encontrado; inspeção ignorada"
else
    tmp=$(mktemp) || exit 2
    trap 'rm -f "$tmp"' EXIT

    case "$module" in
        *.zst)
            if command -v zstd >/dev/null 2>&1; then
                zstd -dcq "$module" >"$tmp" 2>/dev/null || true
            fi
            ;;
        *.xz)
            if command -v xz >/dev/null 2>&1; then
                xz -dc "$module" >"$tmp" 2>/dev/null || true
            fi
            ;;
        *.gz)
            if command -v gzip >/dev/null 2>&1; then
                gzip -dc "$module" >"$tmp" 2>/dev/null || true
            fi
            ;;
        *) cp "$module" "$tmp" 2>/dev/null || true ;;
    esac

    if [ "$(head -c 4 "$tmp" 2>/dev/null || true)" != $'\x7fELF' ]; then
        printf '  não foi possível obter um ELF legível de %s\n' "$module"
    else
        # ATENCAO AO PADRAO. A versao anterior usava
        #     grep -E '(^|[^[:alnum:]_])xsk_[[:alnum:]_]*'
        # e devolvia ZERO para todo driver, inclusive os que tem suporte -- o
        # mesmo sintoma do bug que este script veio substituir. Causa: no ERE do
        # GNU grep, o `^` dentro de um grupo de alternancia faz a expressao
        # inteira parar de casar. Verificado: `[^[:alnum:]_]xsk_` casa 1 na
        # mesma linha em que `(^|[^[:alnum:]_])xsk_` casa 0.
        #
        # `\<xsk_` (fronteira de palavra) faz o que se queria e funciona: casa
        # `U xsk_get_pool_from_qid`, nao casa `i40e_xsk_any_rx_ring_enabled`.
        #
        # Os dois numeros dizem coisas diferentes:
        #   chamadas ao nucleo XSK -> o driver USA a infraestrutura de zero-copy
        #   codigo XSK do driver   -> o driver IMPLEMENTA caminhos XSK proprios
        chamadas=$(nm -u "$tmp" 2>/dev/null | grep -c '\<xsk_' || true)
        proprios=$(nm --defined-only "$tmp" 2>/dev/null | grep -c 'xsk_' || true)
        # xdp_ separa DOIS casos que "0 simbolos xsk_" nao distingue:
        #   xdp_ > 0 e xsk_ = 0  -> tem XDP nativo, nao tem zero-copy
        #   xdp_ = 0 e xsk_ = 0  -> nao tem XDP NENHUM; so resta o modo generico,
        #                          em que o eBPF roda depois do sk_buff
        # Medido nesta maquina: r8169 = 0 simbolos xdp_; i40e = 37.
        xdp=$(nm -a "$tmp" 2>/dev/null | grep -c 'xdp_' || true)
        n=$chamadas
        printf '  módulo ....... %s\n' "$module"
        printf '  simbolos xdp_ (XDP nativo) %s\n' "$xdp"
        printf '  chamadas ao nucleo XSK ... %s\n' "$chamadas"
        printf '  codigo XSK do driver ..... %s\n' "$proprios"
        if [ "$n" -eq 0 ]; then
            echo "  interpretação: nenhuma evidência indireta de zero-copy no módulo; isto não prova a ausência total, mas indica baixa probabilidade de suporte neste ambiente."
        else
            echo "  interpretação: há indício de integração XSK no módulo; isto ainda não confirma que o bind com XDP_ZEROCOPY será aceito pela interface atual."
        fi
    fi
fi

printf '\n-- Veredito --\n'
case "$capacidade" in
    sim)
        echo "  O netdev anuncia AF_XDP zero-copy; esta e uma pista forte, mas a prova final continua sendo o bind real com XDP_ZEROCOPY."
        ;;
    não)
        if [ "${basico:-}" = "no" ] || [ "${basico:-}" = "nao" ]; then
            # Caso mais severo, e o que a RTL8125 desta maquina apresenta.
            echo "  O netdev NAO anuncia XDP NATIVO (NETDEV_XDP_ACT_BASIC: no) -- nem zero-copy,"
            echo "  nem o caminho nativo. Aqui o AF_XDP so funciona em modo GENERICO (SKB), em que"
            echo "  o eBPF roda DEPOIS da alocacao do sk_buff: e o mais lento dos modos, e nao"
            echo "  representa AF_XDP para fins de medicao."
            echo "  Consequencia pratica: 'xdpsock -N' tambem falha, nao so '-z'."
        else
            echo "  O netdev anuncia XDP nativo, mas NAO zero-copy. XDP_ZEROCOPY deve falhar; o"
            echo "  caminho nativo com copia continua disponivel, e nao equivale a zero-copy."
        fi
        ;;
    *)
        echo "  Resultado inconclusivo: sem a feature do netdev ou um bind real, nao e possivel afirmar suporte operacional."
        ;;
esac

if [ "$modo" = "driver" ]; then
    cat <<EOF

-- Prova funcional --
  Não se aplica: este modo inspeciona o módulo de um driver que pode nem estar
  presente nesta máquina. A prova exige a placa e uma interface ativa; rode
  então "$0 <interface>" na máquina que a tiver.
EOF
else
    cat <<EOF

-- Prova funcional (executar separadamente) --
  Use uma ferramenta que force XDP_ZEROCOPY; não aceite fallback silencioso.
  Com o exemplo xdpsock, a forma típica para RX/queue 0 é:

    sudo xdpsock -i $iface -q 0 -N -z -r

  -N força XDP nativo; -z força zero-copy. Se o driver não suportar o caminho,
  o bind deve falhar. Rodar sem -z não prova zero-copy, pois pode haver fallback
  automático para copy mode.
EOF
fi
