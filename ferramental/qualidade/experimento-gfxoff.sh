#!/usr/bin/env bash
# A GPU ou a sessão gráfica? — intervenção sobre o GFXOFF, sem reiniciar.
#
# O QUE ESTE EXPERIMENTO SEPARA
#
# O rastreamento da §6.6 do tópico de isolamento nomeia
# `amdgpu_device_delay_enable_gfx_off` como a função presente nas paradas da
# casa das centenas de microssegundos, e a associação está medida: doze
# execuções em treze segundos com sessão gráfica viva, nenhuma sem ela. Uma
# associação, porém, não distingue duas leituras:
#
#   (a) o custo vem da reativação do *power gating* do bloco GFX;
#   (b) o custo vem da sessão gráfica por outro caminho, e o `gfx_off` é
#       apenas mais um sintoma dela.
#
# Só a intervenção separa as duas: desligar o GFXOFF com a sessão gráfica VIVA.
#
# PRÉ-REGISTRO
#
#   HIPÓTESE.   O modo alto vem da reativação do *power gating* do bloco GFX.
#
#   PREVISÃO 1 (quantitativa). A `Max Single` das janelas com GFXOFF desligado
#               fica sistematicamente abaixo da das janelas com ele ligado, e as
#               janelas ligadas concordam entre si ao longo dos ciclos.
#
#   PREVISÃO 2 (atribuição). A caça ao rastro com limiar de parada NOMEIA
#               `amdgpu_device_delay_enable_gfx_off` no estado ligado e NÃO o
#               encontra no estado desligado.
#
#   REFUTADA SE. A `Max Single` não separar os dois estados, ou a função
#               continuar sendo nomeada com o GFXOFF desligado.
#
#   NULO NÃO É REFUTAÇÃO SE nada distinguir as janelas em medida nenhuma --
#               isso indicaria que a escrita não teve efeito. Ver a ressalva
#               sobre o teste de suporte em `amdgpu_gfx_off_ctrl`, abaixo.
#
# DUAS MEDIÇÕES, PORQUE UMA NÃO SERVE PARA AS DUAS PERGUNTAS
#
# `rtla ... -t` só grava o rastro quando a sessão é PARADA por `-s`/`-S`/`-a`.
# Uma janela com limiar de parada termina no primeiro evento grande, e por isso
# não serve de janela quantitativa; uma janela sem limiar nunca grava rastro, e
# por isso não nomeia função nenhuma.
#
# A primeira versão deste script usava `-T 1` -- que é limiar de CONTAGEM, não
# de parada -- e ainda assim procurava por um arquivo de rastro. O arquivo nunca
# existia, e o `grep` sobre arquivo ausente devolvia zero: um "0 ocorrências"
# que era, na verdade, "não medi". Daí as duas fases separadas abaixo, e daí o
# `SEM RASTRO` explícito onde antes saía um zero.
#
# POR QUE QUATRO BYTES, E NÃO `echo`
#
# `amdgpu_debugfs_gfxoff_write` rejeita, ANTES de tocar na GPU, qualquer escrita
# cujo tamanho ou deslocamento não seja múltiplo de quatro:
#
#       test $0x3,%dl ; jne -> movq $-22      (-EINVAL)
#       mov (%rcx),%rax ; and $0x3,%eax ; jne -> movq $-22
#       ...
#       call __get_user_4 ; setne %sil ; call amdgpu_gfx_off_ctrl
#
# A interface é um vetor de `u32` binários, não texto. `printf '0'` escreve um
# byte, e 1 & 3 = 1. O kernel permite a operação: CONFIG_DEBUG_FS_ALLOW_ALL=y,
# `lockdown` em `[none]`, sem `debugfs=` na linha de boot.
#
# SEMÂNTICA:  palavra == 0  ->  amdgpu_gfx_off_ctrl(adev, false)  -> DESLIGA
#             palavra != 0  ->  amdgpu_gfx_off_ctrl(adev, true)   -> religa
#
# RESSALVA DE INTERPRETAÇÃO. `amdgpu_gfx_off_ctrl` começa com um teste de
# suporte e retorna sem efeito quando o bit não está presente. Um resultado nulo
# precisa ser distinguido de "a escrita não fez nada" antes de contar como
# refutação.
#
# O CONTADOR PRECISA FECHAR
#
# `amdgpu_gfx_off_ctrl` não é interruptor: é contagem de pedidos
# (`gfx_off_req_count`). Cada desligamento incrementa; cada religamento
# decrementa, e só ao chegar a zero o driver reenfileira o trabalho atrasado.
# Uma palavra 0 exige exatamente uma palavra != 0 depois. Por isso cada ciclo
# deste script escreve uma vez em cada sentido, e religa também em INT/TERM.
#
# EXIGE MÁQUINA DEDICADA e SESSÃO GRÁFICA VIVA.
#
#   uso:  sudo bash ferramental/qualidade/experimento-gfxoff.sh [saida]
#         CICLOS=5 JANELA=30 sudo -E bash ferramental/qualidade/experimento-gfxoff.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

CPU=${CPU:-2}
JANELA=${JANELA:-30}      # segundos por célula quantitativa
CICLOS=${CICLOS:-3}       # pares A/B
LIMIAR=${LIMIAR:-300}     # us: para a sessão e grava o rastro
CACA=${CACA:-120}         # segundos de teto para a caça ao rastro

[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo (debugfs exige root)." >&2; exit 1; }
command -v rtla    >/dev/null || { echo "FALHA: rtla ausente." >&2; exit 1; }
command -v python3 >/dev/null || { echo "FALHA: python3 ausente." >&2; exit 1; }

KNOB=$(ls /sys/kernel/debug/dri/*/amdgpu_gfxoff 2>/dev/null | head -1)
[ -n "$KNOB" ] || { echo "FALHA: amdgpu_gfxoff nao encontrado." >&2; exit 1; }

graficos=$(pgrep -c -x 'Xorg|Xwayland|gnome-shell|kwin_wayland|sway' 2>/dev/null || true)
graficos=${graficos:-0}
if [ "$graficos" -eq 0 ]; then
    echo "FALHA: nenhum processo grafico vivo." >&2
    echo "       E a sessao ativa que distingue 'e a GPU' de 'e a sessao'." >&2
    exit 1
fi

SAIDA=${1:-trilha/03-performance/03-isolamento-cpu/historico/$(date +%Y-%m-%d-%H%M)-gfxoff-intervencao}
DONO=${SUDO_USER:-$(stat -c %U . 2>/dev/null || echo root)}
mkdir -p "$SAIDA"

# `os.write` de uma palavra, no deslocamento zero. Nem `echo` nem `dd`: o
# primeiro escreve texto e o segundo trunca por padrao.
escrever() { # <valor u32>
    python3 - "$KNOB" "$1" <<'PY' 2>&1
import os, struct, sys
fd = os.open(sys.argv[1], os.O_WRONLY)
try:
    print("ok %d bytes" % os.write(fd, struct.pack("<I", int(sys.argv[2]))))
finally:
    os.close(fd)
PY
}

DESLIGADO=0
desligar() {
    local r; r=$(escrever 0)
    case "$r" in
        ok*) DESLIGADO=1; return 0 ;;
        *)   echo "FALHA: escrita recusada -> $r" >&2; return 1 ;;
    esac
}
religar() {
    [ "$DESLIGADO" -eq 1 ] || return 0
    DESLIGADO=0
    local r; r=$(escrever 1)
    case "$r" in
        ok*) return 0 ;;
        *)   echo "AVISO: nao religuei o GFXOFF -> $r; contador desbalanceado, reinicie." >&2 ;;
    esac
}
trap religar EXIT INT TERM

# FASE 1 -- janela quantitativa. Sem limiar de parada: a janela tem de correr
# inteira para que `Max Single` signifique "o maior evento em JANELA segundos".
medir() { # <rotulo>
    rtla osnoise top -c "$CPU" -d "${JANELA}s" -q > "$SAIDA/osnoise-$1.txt" 2>&1 || true
}
# `Max Single` e o campo 7, e a contagem e facil de errar porque o CABECALHO
# tem nomes de duas palavras. A linha de dados e:
#
#   CPU Period Runtime Noise %CPUAval MaxNoise MaxSingle HW NMI IRQ Softirq Thread
#    1    2       3      4      5        6         7      8   9  10    11     12
#
# `MaxNoise` e o maior total de ruido num periodo; `MaxSingle` e o maior EVENTO
# isolado -- e a hipotese e sobre um evento isolado longo, nao sobre a soma.
max_single() { # <rotulo>  -> us, ou vazio
    awk -v c="$CPU" '$1==c { print $7 }' "$SAIDA/osnoise-$1.txt" 2>/dev/null | tail -1
}

# FASE 2 -- caca ao rastro. COM limiar de parada, que e a unica forma de o
# `-t` gravar arquivo. A sessao termina no primeiro evento >= LIMIAR.
cacar() { # <rotulo>
    local arq="$SAIDA/trace-$1.txt"
    rm -f "$arq"
    rtla osnoise top -c "$CPU" -d "${CACA}s" -a "$LIMIAR" -t "$arq" -q \
        > "$SAIDA/osnoise-caca-$1.txt" 2>&1 || true
    if [ ! -s "$arq" ]; then
        echo "SEM RASTRO (nenhum evento >= ${LIMIAR}us em ${CACA}s)"
    elif grep -qi 'gfx_off\|gfxoff' "$arq"; then
        echo "NOMEIA gfx_off -> $(grep -oim1 '[a-z_]*gfx_off[a-z_]*' "$arq")"
    else
        echo "rastro gravado, SEM gfx_off -> $(grep -oim1 'function [a-z_0-9]*' "$arq" || echo 'funcao nao identificada')"
    fi
}

{
    echo "knob            : $KNOB"
    echo "cpu medida      : $CPU"
    echo "ciclos          : $CICLOS pares de ${JANELA}s"
    echo "caca ao rastro  : limiar ${LIMIAR}us, teto ${CACA}s"
    echo "processos grafic: $graficos"
    echo "kernel          : $(uname -r)"
    echo "cmdline         : $(cat /proc/cmdline)"
    echo "pg_mask         : $(cat /sys/module/amdgpu/parameters/pg_mask 2>/dev/null)"
    echo "governor        : $(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor 2>/dev/null)"
} > "$SAIDA/ambiente.txt"

echo "==> intervencao GFXOFF  $(date -Is)"
echo "    saida : $SAIDA"
echo "    plano : $CICLOS x (ligado ${JANELA}s, desligado ${JANELA}s) + 2 cacas de ate ${CACA}s"
echo

# --------------------------------------------------------------------------
# FASE 1. A-B-A REPETIDO, e nao uma vez.
#
# Com um par so, "o desligado deu menos" e indistinguivel de deriva: a sessao
# grafica nao produz carga constante. Alternar CICLOS vezes da observacoes
# pareadas -- cada B tem um A imediatamente antes e outro depois --, e deriva
# que atinja um arm atinge o outro no mesmo intervalo.
# --------------------------------------------------------------------------
echo "==> FASE 1/2  janelas quantitativas"
printf "    %-6s %-12s %10s\n" "ciclo" "estado" "MaxSingle"
printf "    %-6s %-12s %10s\n" "-----" "------------" "---------"
for i in $(seq 1 "$CICLOS"); do
    medir "c$i-ligado"
    printf "    %-6s %-12s %10s us\n" "$i" "ligado" "$(max_single "c$i-ligado")"

    desligar || exit 1
    medir "c$i-desligado"
    printf "    %-6s %-12s %10s us\n" "$i" "DESLIGADO" "$(max_single "c$i-desligado")"
    religar
done

echo
echo "==> FASE 2/2  caca ao rastro (limiar ${LIMIAR}us)"
echo "    com GFXOFF ligado ..."
r_lig=$(cacar "ligado")
printf "      %s\n" "$r_lig"
desligar || exit 1
echo "    com GFXOFF desligado ..."
r_des=$(cacar "desligado")
printf "      %s\n" "$r_des"
religar

echo
echo "==> RESULTADO"
python3 - "$SAIDA" "$CPU" <<'PY'
import glob, os, re, statistics, sys
saida, cpu = sys.argv[1], sys.argv[2]
def ms(rotulo):
    p = os.path.join(saida, "osnoise-%s.txt" % rotulo)
    try:
        for l in open(p):
            c = l.split()
            if c and c[0] == cpu:
                return float(c[6])   # Max Single; ver o comentario em max_single()
    except OSError:
        pass
    return None
lig, des = [], []
for f in sorted(glob.glob(os.path.join(saida, "osnoise-c*-ligado.txt"))):
    v = ms(os.path.basename(f)[8:-4])
    if v is not None: lig.append(v)
for f in sorted(glob.glob(os.path.join(saida, "osnoise-c*-desligado.txt"))):
    v = ms(os.path.basename(f)[8:-4])
    if v is not None: des.append(v)
print("    Max Single, us")
print("      GFXOFF ligado    n=%d  %s" % (len(lig), lig))
print("      GFXOFF DESLIGADO n=%d  %s" % (len(des), des))
if lig and des:
    print("      medianas: ligado %.0f, desligado %.0f" % (
        statistics.median(lig), statistics.median(des)))
    pares = list(zip(lig, des))
    favor = sum(1 for a, b in pares if b < a)
    print("      pares em que o DESLIGADO deu menos: %d de %d" % (favor, len(pares)))
    print()
    print("      n pequeno: isto e sinal, nao inferencia. Para um teste do sinal")
    print("      com poder, rode com CICLOS=10.")
PY
echo
echo "    Atribuicao por funcao"
printf "      ligado    : %s\n" "$r_lig"
printf "      desligado : %s\n" "$r_des"
echo
echo "    A PREVISAO exige: desligado abaixo do ligado em quase todos os pares,"
echo "    E a funcao nomeada no ligado e ausente no desligado. 'SEM RASTRO' nos"
echo "    dois lados nao refuta nada -- significa que o limiar nao disparou."

chown -R "$DONO" "$SAIDA" 2>/dev/null || true
echo
echo "==> CONCLUIDO  $(date -Is)"
