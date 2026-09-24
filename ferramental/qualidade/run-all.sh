#!/usr/bin/env bash
# =========================================================================
# UMA EXECUCAO, TUDO QUE PRECISA DA MAQUINA LIMPA
#
#   sudo grub-reboot modo-texto && sudo reboot
#   (no console)  sudo ./ferramental/qualidade/run-all.sh <configuracao>
#
# POR QUE UM SO SCRIPT
#
# Cada coleta deste projeto custa um reboot, e o que separa uma condicao valida
# de uma invalida e nao ter esquecido um passo. Tres roteiros soltos em `temp/`
# ja produziram, neste mes, uma coleta rotulada com a configuracao errada e uma
# campanha que pulou o passo de hardware em silencio.
#
# Este script e a lista completa. O que nao esta aqui nao precisa da maquina
# limpa; o que esta, precisa, e roda na ordem em que a condicao se degrada
# menos.
#
# POR QUE VERSIONADO, E NAO EM `temp/`
#
# O cabecalho do `campanha-hardware.sh` ja paga essa licao: a primeira campanha
# do projeto rodou de um script solto que a limpeza apagou junto com os dados,
# e um protocolo que nao sobrevive a um reboot nao e reproduzivel por definicao.
#
# A ORDEM IMPORTA, e nao e alfabetica
#
#   1. sonda    e curta (~2 min) e mede o estado mais fragil -- o relogio na
#               partida. Rodar depois da campanha mediria uma CPU ja aquecida
#               por meia hora, que e outra condicao.
#   2. campanha e longa (~55 min) e se beneficia da CPU quente.
#
# O GOVERNOR FICA FIXO NAS DUAS
#
# Medido em 24/09/2026: em modo texto nada aquece a CPU entre invocacoes, entao
# toda execucao e a primeira apos ociosidade. Com `performance`, o relogio para
# de subir durante a medicao e os absolutos voltam a ser comparaveis com os de
# modo grafico. A §5.1 da metodologia dos fundamentos tem a cadeia inteira.
# =========================================================================
set -u
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ" || exit 1

CONFIG="${1:-}"
if [ -z "$CONFIG" ]; then
    echo "uso: $0 <configuracao>" >&2
    echo "  exemplo: $0 2026-09-25-expo6000-canal-duplo" >&2
    echo "  a configuracao nomeia as coletas; hora e minuto entram sozinhos." >&2
    exit 2
fi
[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo." >&2; exit 1; }

DONO=${SUDO_USER:-henrique}
SELO="$(date +%H%M)"
SONDA=build/docs/01-fundamentos/medicoes/sonda-relaxed

# O MODO E DETECTADO, NAO EXIGIDO -- e isso muda o que a coleta pode afirmar.
#
# A primeira versao recusava rodar com sessao grafica viva. A regra estava certa
# para o experimento que originou o script e errada como porta de entrada: quem
# tem maquina de trabalho ficava sem poder medir nada.
#
# O que a sessao grafica tira nao e a validade da medicao; e UM contrafactual.
# A etapa 1 pergunta se o estado de 1,818 ciclos aparece quando ninguem carrega
# o irmao SMT. Em modo texto a carga e zero POR CONSTRUCAO, e a resposta vale.
# Em modo grafico o compositor carrega o irmao de forma intermitente -- foi
# assim que o `custo-espera` deu 0,397 e a sonda, no mesmo dia, deu 1,125 --,
# entao a ausencia do estado nao prova nada e a presenca nao surpreende.
#
# Dai: os dois modos coletam, e o veredito da etapa 1 muda conforme o modo.
graficos=$(pgrep -c -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" 2>/dev/null)
graficos=${graficos:-0}
if [ "$graficos" -eq 0 ]; then
    MODO=texto
else
    MODO=grafico
fi

echo "=========================================================="
echo "  run-all  $(date -Is)"
echo "  configuracao : $CONFIG"
echo "  selo         : $SELO"
echo "  modo detectado: $MODO ($graficos processo(s) grafico(s))"
if [ "$MODO" = "grafico" ]; then
    pgrep -a -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" | sed 's/^/                 /'
    echo
    echo "  O QUE ESTE MODO PERMITE AFIRMAR, E O QUE NAO"
    echo "    permite: o modelo de ciclos, que nao depende de a carga ser zero."
    echo "    NAO permite: o contrafactual da etapa 1. O compositor carrega o"
    echo "    irmao SMT de forma intermitente, entao a ausencia do estado de"
    echo "    1,818 ciclos aqui nao prova que ele exige carga externa."
    echo "    Para esse, reinicie em multi-user.target."
fi
echo "=========================================================="

# --------------------------------------------------------------------------
# ETAPA 1: A MAQUINA, ANTES DE MEDIR QUALQUER COISA.
#
# Nao e cerimonia de abertura: e a unica parte que nao da para reconstruir
# depois. Quem ler estes numeros daqui a um ano precisa saber em que CPU, com
# que memoria, com que BIOS e com que mitigacoes eles sairam -- e o projeto ja
# perdeu uma comparacao inteira por ter descoberto tarde que a memoria mudou.
#
# Os dois scripts existem e fazem isto melhor do que um bloco novo faria:
#
#   ambiente.sh          o hardware e o ferramental: processador, nucleos,
#                        NUMA, L3, memoria e velocidade, placa, BIOS, NIC e
#                        driver, kernel, mitigacoes, versao do DPDK.
#   ambiente-medicao.sh  o que decide se a medicao e COMPARAVEL: governor,
#                        turbo, C-states, isolamento. Ele apura e declara; nao
#                        muda nada.
#
# O cache de memoria e refeito antes, porque `ambiente.sh` le a velocidade dele
# e um cache anterior ao ultimo boot descreveria a configuracao ANTERIOR -- que
# e exatamente o erro que o portao do `campanha-hardware.sh` existe para pegar.
# --------------------------------------------------------------------------
SAIDA_AMB="docs/01-fundamentos/medicoes/historico/$CONFIG-ambiente-$SELO"
echo
echo "==> ETAPA 1/3  procedencia da maquina  ($(date +%T))"
mkdir -p "$SAIDA_AMB"
./scripts/ambiente.sh --cachear-memoria >/dev/null 2>&1 \
    && chown "$DONO" .ambiente-memoria 2>/dev/null
{
    echo "modo detectado : $MODO ($graficos processo(s) grafico(s))"
    echo "configuracao   : $CONFIG"
    echo "selo           : $SELO"
    echo
} > "$SAIDA_AMB/ambiente.txt"
./scripts/ambiente.sh >> "$SAIDA_AMB/ambiente.txt" 2>&1
./scripts/ambiente-medicao.sh > "$SAIDA_AMB/ambiente-medicao.txt" 2>&1 \
    || echo "    AVISO: ambiente-medicao.sh saiu com erro; ambiente incompleto"
chown -R "$DONO" "$SAIDA_AMB"
grep -E 'modelo|velocidade|pentes|governor|turbo|NIC |kernel ' "$SAIDA_AMB/ambiente.txt" \
    | sed 's/^ */    /'
echo "    saida: $SAIDA_AMB"

# --------------------------------------------------------------------------
# ETAPA 2: a sonda do `atomic relaxed`, tres condicoes.
#
# Responde se o modelo de CICLOS construido em modo grafico sobrevive aqui. E a
# unica etapa em que a carga no irmao SMT e ZERO por construcao, entao e a
# unica que pode afirmar o contrafactual da §5.
# --------------------------------------------------------------------------
SAIDA_SONDA="docs/01-fundamentos/medicoes/historico/$CONFIG-sonda-$SELO"
echo
echo "==> ETAPA 2/3  sonda atomic relaxed  ($(date +%T))"
if [ ! -x "$SONDA" ]; then
    echo "    PULADO: $SONDA ausente; rode ./scripts/build-all.sh"
else
    mkdir -p "$SAIDA_SONDA"
    CPU=0
    IRMAO=$(cut -d, -f2 < /sys/devices/system/cpu/cpu$CPU/topology/thread_siblings_list)
    N=20000

    GOV_ANTES=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    fixar_gov() {
        for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
            echo "$1" > "$c" 2>/dev/null || :
        done
        [ "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)" = "$1" ]
    }
    # O governor volta ao que era mesmo se o script morrer no meio.
    trap 'fixar_gov "$GOV_ANTES" >/dev/null 2>&1; echo "==> governor restaurado para $GOV_ANTES"' EXIT INT TERM

    {
        echo "modo detectado  : $MODO"
        echo "cpu             : $CPU (irmao SMT $IRMAO)"
        echo "amostras        : $N por condicao"
        echo "governor inicial: $GOV_ANTES"
        echo "processos grafic: $graficos"
        echo "kernel          : $(uname -r)"
        echo "cmdline         : $(cat /proc/cmdline)"
        [ "$MODO" = "grafico" ] && echo "RESSALVA        : carga no irmao SMT nao e zero;" \
            "o contrafactual da condicao 3 nao vale neste modo"
    } > "$SAIDA_SONDA/ambiente.txt"

    resumir() { # <rotulo> <arquivo>
        printf "    %-22s " "$1"
        grep -E 'CICLOS' "$2" | sed 's/^ *//'
    }

    echo "    1. powersave, irmao ocioso"
    fixar_gov powersave || echo "       AVISO: nao fixei powersave"
    "$SONDA" "$N" "$CPU" > "$SAIDA_SONDA/powersave.txt" 2>&1
    resumir "powersave" "$SAIDA_SONDA/powersave.txt"

    echo "    2. performance, irmao ocioso"
    if fixar_gov performance; then
        "$SONDA" "$N" "$CPU" > "$SAIDA_SONDA/performance.txt" 2>&1
        resumir "performance" "$SAIDA_SONDA/performance.txt"
    else
        echo "       FALHA ao fixar performance" | tee "$SAIDA_SONDA/performance.txt"
    fi

    echo "    3. performance, irmao SMT $IRMAO saturado"
    taskset -c "$IRMAO" bash -c 'while :; do :; done' &
    SPIN=$!
    sleep 1
    "$SONDA" "$N" "$CPU" > "$SAIDA_SONDA/performance-smt.txt" 2>&1
    kill "$SPIN" 2>/dev/null; wait "$SPIN" 2>/dev/null
    resumir "performance+SMT" "$SAIDA_SONDA/performance-smt.txt"

    # O GOVERNOR VOLTA ANTES DA ETAPA 2, e nao so no trap do fim.
    #
    # A etapa 1 termina com `performance` ligado. Se a campanha comecasse
    # assim, ela gravaria "era performance" no proprio `ambiente.txt` -- e a
    # procedencia diria que a maquina ja estava fixada quando nao estava. O
    # trap continua existindo para o caso de morte no meio; isto aqui e para o
    # caso normal.
    fixar_gov "$GOV_ANTES" >/dev/null 2>&1 \
        && echo "    governor de volta em $GOV_ANTES antes da etapa 2"

    # VEREDITO DA ETAPA 1, e ele depende do modo.
    #
    # O modelo preve que os CICLOS nao mudem com governor nem com modo -- so
    # com a carga no irmao SMT. Isso e testavel nos dois modos. O que so o modo
    # texto testa e o contrafactual: sem carga, o estado alto NAO aparece.
    ciclos() { # <arquivo>  -> ciclos pelo periodo final
        sed -n 's/.*CICLOS por operacao:.*  *\([0-9.]*\) (pelo final).*/\1/p' "$1" 2>/dev/null
    }
    c1=$(ciclos "$SAIDA_SONDA/powersave.txt")
    c2=$(ciclos "$SAIDA_SONDA/performance.txt")
    c3=$(ciclos "$SAIDA_SONDA/performance-smt.txt")
    echo
    echo "    veredito da etapa 1 (modo $MODO)"
    printf "      powersave        ciclos %-7s  previa 1,125\n" "${c1:-?}"
    printf "      performance      ciclos %-7s  previa 1,125\n" "${c2:-?}"
    printf "      performance+SMT  ciclos %-7s  previa 1,818\n" "${c3:-?}"
    LC_ALL=C awk -v a="${c1:-0}" -v b="${c2:-0}" -v m="$MODO" 'BEGIN {
        ok = (a > 1.09 && a < 1.16 && b > 1.09 && b < 1.16)
        print ok ? "      MODELO SUSTENTADO: ciclos invariantes ao governor" \
                 : "      MODELO REFUTADO: os ciclos mudaram com o governor"
        if (m == "grafico")
            print "      (o contrafactual da condicao 3 NAO foi testado: ha sessao grafica)"
    }'

    chown -R "$DONO" "$SAIDA_SONDA"
    echo "    saida: $SAIDA_SONDA"
fi

# --------------------------------------------------------------------------
# ETAPA 3: a campanha completa, com o governor fixo.
#
# `campanha.sh` cuida do proprio governor, do proprio portao e da propria
# comparacao. Aqui ele e so chamado com os argumentos certos -- que e o ponto
# deste arquivo: os argumentos certos deixam de depender de memoria.
# --------------------------------------------------------------------------
echo
echo "==> ETAPA 3/3  campanha completa  ($(date +%T))"
# O MODO VAI DETECTADO, nao fixo. `--fixar-governor` vale nos dois: em texto
# porque nada aquece a CPU, em grafico porque tira a unica variavel que o
# compositor ainda move sem declarar.
./ferramental/qualidade/campanha.sh "--$MODO" --fixar-governor "$CONFIG"
rc=$?

echo
echo "=========================================================="
echo "  run-all CONCLUIDO  $(date -Is)   (campanha rc=$rc)"
echo
echo "  Para voltar ao modo grafico:"
echo "    sudo systemctl set-default graphical.target && sudo reboot"
echo "  (ou so reinicie: o boot unico ja expirou)"
echo "=========================================================="
exit "$rc"
