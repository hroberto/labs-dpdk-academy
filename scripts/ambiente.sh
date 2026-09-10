#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Registro do ambiente de medição.
#
# POR QUE ESTE SCRIPT EXISTE
#
# Todo número publicado neste projeto foi medido numa máquina específica, e a
# regra editorial é que **resultado experimental sem contexto de hardware não é
# resultado universal**. Só que descrever a máquina em prosa, documento por
# documento, produz três problemas que já apareceram aqui:
#
#   1. a descrição diverge entre arquivos, e ninguém percebe;
#   2. ela envelhece em silêncio quando o kernel ou o DPDK são atualizados;
#   3. quem reproduz numa máquina diferente não sabe o que comparar.
#
# A solução é não escrever a descrição: gerá-la. Este script emite o registro no
# formato que os documentos citam, e serve tanto para a máquina de referência
# quanto para a de quem estiver reproduzindo.
#
# Uso:
#   ./scripts/ambiente.sh              # texto legível
#   ./scripts/ambiente.sh --markdown   # tabela pronta para colar em documento
set -u

MODO=${1:-texto}

v() { # v <comando...> -> valor ou "-"
    local saida
    saida=$("$@" 2>/dev/null | head -1)
    printf '%s' "${saida:--}"
}

# --- coleta ---------------------------------------------------------------
# ATENÇÃO: nada aqui depende do TEXTO do lscpu. A saída dele é traduzida — nesta
# máquina sai em português —, e um parsing por rótulo em inglês devolve campos
# vazios em silêncio. Foi o que aconteceu na primeira versão deste script, o que
# é irônico num script cuja razão de existir é reprodutibilidade. As formas
# usadas abaixo, `lscpu -p=` e o sysfs, são independentes de idioma.
CPU_MODELO=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)
CPU_LOGICAS=$(nproc)
lscpu_col() { lscpu -p="$1" 2>/dev/null | grep -v '^#' | sort -u | wc -l; }
CPU_FISICOS=$(lscpu -p=CORE,SOCKET 2>/dev/null | grep -v '^#' | sort -u | wc -l)
CPU_SOQUETES=$(lscpu_col SOCKET)
CPU_SMT=$([ "${CPU_FISICOS:-0}" -gt 0 ] && echo $((CPU_LOGICAS / CPU_FISICOS)) || echo "-")
# L3 pode ter várias instâncias (uma por CCD, em Ryzen): reportar as duas coisas.
CPU_L3_TAM=$(cat /sys/devices/system/cpu/cpu0/cache/index3/size 2>/dev/null || echo "-")
CPU_L3_N=$(cat /sys/devices/system/cpu/cpu*/cache/index3/id 2>/dev/null | sort -u | wc -l)
CPU_L3="$CPU_L3_TAM x $CPU_L3_N instancia(s)"
# Domínios de cache L3: é o que separa "mesmo CCD" de "CCDs diferentes".
CPU_DOMINIOS=$(cat /sys/devices/system/cpu/cpu*/cache/index3/shared_cpu_list 2>/dev/null | sort -u | tr '\n' ' ')
CPU_FLAGS=$(grep -o 'constant_tsc\|nonstop_tsc\|tsc_known_freq\|invariant_tsc' /proc/cpuinfo | sort -u | tr '\n' ' ')

# Governor e frequência decidem se a medição é comparável entre execuções.
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "-")
TURBO_INTEL=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "-")
TURBO_AMD=$(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo "-")

NUMA_NOS=$(lscpu_col NODE)
HUGE_TOTAL=$(awk '/^HugePages_Total:/{print $2}' /proc/meminfo)
HUGE_LIVRES=$(awk '/^HugePages_Free:/{print $2}' /proc/meminfo)
HUGE_TAM=$(awk '/^Hugepagesize:/{print $2" "$3}' /proc/meminfo)
MEM_TOTAL=$(awk '/^MemTotal:/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)

KERNEL=$(uname -r)
DISTRO=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
CMDLINE=$(tr ' ' '\n' < /proc/cmdline 2>/dev/null | grep -E 'iommu|hugepages|isolcpus|nohz|mitigations|processor\.max_cstate|intel_idle' | tr '\n' ' ')
[ -z "$CMDLINE" ] && CMDLINE="(nenhum parâmetro relevante)"

DPDK=$(v pkg-config --modversion libdpdk)
CC=$(v cc --version)
MESON=$(v meson --version)
NINJA=$(v ninja --version)

# Mitigações de CPU mudam o custo de syscall em ordem de grandeza: sem isto,
# comparar com a literatura leva a conclusão errada.
#
# CUIDADO COM O FORMATO — duas armadilhas já cortaram exatamente o dado caro:
#
#   1. o valor de uma mitigação ATIVA contém ':' no meio. O kernel publica
#      "spectre_v2:Mitigation: Enhanced / Automatic IBRS; IBPB: conditional;
#      STIBP: always-on; RSB filling; ...". Separar por ':' e guardar só o
#      segundo campo reduz tudo a "spectre_v2=Mitigation", que não informa nada
#      — e informa MENOS justamente nas ativas, que são as que custam ciclo;
#   2. truncar a string inteira num limite fixo (`cut -c1-200`) descarta o fim
#      da lista. Como a ordem é alfabética, o que some é spectre_*, srso e
#      vmscape: de novo, as caras. E some em silêncio, sem reticência.
#
# A forma abaixo corta no PRIMEIRO ':' apenas, e não trunca nada. Para caber na
# leitura sem perder informação, as ativas saem por extenso e as inativas viram
# uma lista de nomes: "Not affected" não custa ciclo nenhum, e é o custo que
# este campo existe para registrar.
mitig_pares() { # -> "nome<TAB>valor", uma por linha, valor íntegro
    grep -H . /sys/devices/system/cpu/vulnerabilities/* 2>/dev/null \
        | sed 's|.*/vulnerabilities/||; s|:|\t|'
}
MITIG_ATIVAS=$(mitig_pares | awk -F'\t' '$2 != "Not affected" {printf "%s%s=%s", sep, $1, $2; sep="; "}')
MITIG_INATIVAS=$(mitig_pares | awk -F'\t' '$2 == "Not affected" {printf "%s%s", sep, $1; sep=", "}')
[ -z "$MITIG_ATIVAS" ] && [ -z "$MITIG_INATIVAS" ] && MITIG_ATIVAS="(não expostas)"
[ -z "$MITIG_ATIVAS" ] && MITIG_ATIVAS="(nenhuma ativa)"
[ -z "$MITIG_INATIVAS" ] && MITIG_INATIVAS="(nenhuma)"

# Sem `cut`: o nome da NIC é curto o bastante para caber inteiro, e cortá-lo
# produzia "RTL8125 2.5GbE Control" — que parece um modelo, e não é.
NIC=$(lspci -nn 2>/dev/null | grep -i 'ethernet' | head -1)
[ -z "$NIC" ] && NIC="-"
NIC_DRV="-"
if [ -n "${NIC#-}" ]; then
    iface=$(ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')
    [ -n "$iface" ] && NIC_DRV=$(basename "$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null)" 2>/dev/null)
fi

# --- saída ----------------------------------------------------------------
if [ "$MODO" = "--markdown" ]; then
    cat <<EOF
| Item | Valor |
|---|---|
| CPU | $CPU_MODELO |
| Núcleos / threads | $CPU_FISICOS físicos, $CPU_LOGICAS lógicos ($CPU_SMT thread(s) por núcleo) |
| Soquetes / nós NUMA | $CPU_SOQUETES / $NUMA_NOS |
| L3 | $CPU_L3 |
| Domínios de cache L3 | \`$CPU_DOMINIOS\` |
| Sinalizadores de TSC | $CPU_FLAGS |
| Governor / turbo | $GOVERNOR / intel=$TURBO_INTEL amd_boost=$TURBO_AMD |
| Memória | $MEM_TOTAL |
| Hugepages | $HUGE_TOTAL de $HUGE_TAM ($HUGE_LIVRES livres) |
| Kernel | $KERNEL |
| Distribuição | $DISTRO |
| Linha de comando do kernel | \`$CMDLINE\` |
| NIC | $NIC |
| Driver da NIC | $NIC_DRV |
| DPDK | $DPDK |
| Compilador | $CC |
| Meson / Ninja | $MESON / $NINJA |
| Mitigações ativas | $MITIG_ATIVAS |
| Mitigações não aplicáveis | $MITIG_INATIVAS |
EOF
    exit 0
fi

cat <<EOF

== Ambiente de medição ==

  Processador
    modelo ................. $CPU_MODELO
    nucleos/threads ........ $CPU_FISICOS fisicos, $CPU_LOGICAS logicos ($CPU_SMT por nucleo)
    soquetes / nos NUMA .... $CPU_SOQUETES / $NUMA_NOS
    L3 ..................... $CPU_L3
    dominios de cache L3 ... $CPU_DOMINIOS
    sinalizadores de TSC ... $CPU_FLAGS

  Estado de frequencia (decide se a medicao e comparavel entre execucoes)
    governor ............... $GOVERNOR
    turbo .................. intel_no_turbo=$TURBO_INTEL  amd_boost=$TURBO_AMD

  Memoria
    total .................. $MEM_TOTAL
    hugepages .............. $HUGE_TOTAL de $HUGE_TAM ($HUGE_LIVRES livres)

  Sistema
    kernel ................. $KERNEL
    distribuicao ........... $DISTRO
    linha de comando ....... $CMDLINE
    mitigacoes ativas ...... $MITIG_ATIVAS
    nao aplicaveis ......... $MITIG_INATIVAS

  Rede
    NIC .................... $NIC
    driver ................. $NIC_DRV

  Ferramental
    DPDK ................... $DPDK
    compilador ............. $CC
    meson / ninja .......... $MESON / $NINJA

  Para colar num documento: ./scripts/ambiente.sh --markdown

EOF
