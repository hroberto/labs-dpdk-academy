#!/usr/bin/env bash
# =========================================================================
# UMA EXECUCAO, TUDO QUE PRECISA DA MAQUINA LIMPA
#
#   sudo ./ferramental/qualidade/run-all.sh
#
# O nome da coleta se monta sozinho:
#
#   2026-09-25-1035-expo6000-canal-duplo
#   \____________/ \____________________/
#    carimbo da         configuracao lida
#    execucao           do `dmidecode`
#
# O carimbo vem na frente para que `ls` devolva a ordem cronologica sem
# ninguem pedir. Passe um nome so quando quiser rotular uma condicao que o
# hardware nao expressa (um braco de controle, uma replica); o carimbo e
# acrescentado de qualquer jeito.
#
# Para a condicao limpa, antes:
#   sudo grub-reboot modo-texto && sudo reboot
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

# O PORTAO DE ROOT VEM ANTES DE TUDO, e a ordem nao e arbitraria.
#
# `--cachear-memoria` le o `dmidecode`, que exige privilegio. Sem root ele
# falha CALADO, e a derivacao do nome abaixo usaria o cache anterior -- ou
# seja, nomearia a coleta com a configuracao de memoria que a maquina tinha
# ANTES. E exatamente o erro que a derivacao existe para impedir, entrando
# pela porta dos fundos.
[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo." >&2; exit 1; }

# O NOME DA COLETA E DERIVADO DO HARDWARE, e o argumento vira opcional.
#
# Ate aqui o nome era digitado, e foi assim que uma coleta JEDEC 4800 nasceu
# rotulada como se fosse EXPO 6000: o operador sabia da BIOS, o comando nao.
# Derivar do `dmidecode` fecha essa porta -- o nome passa a ser consequencia do
# que a maquina E, nao do que alguem lembrou de escrever.
#
# O cache e refeito ANTES de ler, pela mesma razao: um cache anterior ao ultimo
# boot descreveria a configuracao anterior, e o nome herdaria o erro.
#
# O argumento explicito continua aceito e tem precedencia. Ele serve para o
# caso em que se quer nomear uma condicao que o hardware nao expressa -- um
# braco de controle, uma replica, um teste de governor.
./scripts/ambiente.sh --cachear-memoria >/dev/null 2>&1 \
    && chown "${SUDO_USER:-root}" .ambiente-memoria 2>/dev/null

derivar_config() {
    [ -r .ambiente-memoria ] || return 1
    # shellcheck disable=SC1091
    . ./.ambiente-memoria 2>/dev/null || return 1
    local vel pentes perfil canal
    vel=$(printf '%s' "${CACHE_VEL:-}" | grep -oE '^[0-9]+') || return 1
    pentes=$(printf '%s' "${CACHE_CANAIS:-}" | grep -oE '^[0-9]+') || return 1
    [ -n "$vel" ] && [ -n "$pentes" ] || return 1
    # 4800 MT/s e o padrao JEDEC do DDR5 desta plataforma; acima disso so com
    # perfil EXPO ligado na BIOS. A distincao e o que a coleta precisa dizer.
    if [ "$vel" -le 4800 ]; then perfil="jedec$vel"; else perfil="expo$vel"; fi
    case "$pentes" in
        1) canal="canal-unico" ;;
        2) canal="canal-duplo" ;;
        *) canal="canal-${pentes}pentes" ;;
    esac
    printf '%s-%s' "$perfil" "$canal"
}

# `--so-ruido` ATRAVESSA ATE A CAMPANHA, e existe para experimento de fonte.
#
# Uma intervencao sobre o que TOMA a CPU -- desligar o power gating da GPU, por
# exemplo -- precisa da procedencia e dos passos de ruido, e nao e afetada pelo
# resto. Rodar as quatro etapas para responder isso custaria uma hora em vez de
# vinte minutos, e a diferenca vira desculpa para nao repetir.
#
# A ETAPA 1 NAO E PULADA NEM AQUI, e e a razao principal de passar pelo
# `run-all` em vez de chamar a campanha direto: e ela que grava a linha de boot
# do kernel, e `amdgpu.pg_mask=0` vive exatamente ali. Experimento cuja
# intervencao nao esta no arquivo e anedota.
SO_RUIDO=0
if [ "${1:-}" = "--so-ruido" ]; then SO_RUIDO=1; shift; fi

CONFIG="${1:-}"
if [ -z "$CONFIG" ]; then
    CONFIG=$(derivar_config) || {
        echo "FALHA: nao derivei a configuracao do hardware." >&2
        echo "  Passe o nome explicitamente: $0 <configuracao>" >&2
        echo "  exemplo: $0 2026-09-25-expo6000-canal-duplo" >&2
        exit 2
    }
    DERIVADO=1
else
    DERIVADO=0
fi

# O DONO NAO E UM NOME FIXO, e a razao e de reproducao, nao de estilo.
#
# Sob `sudo`, `$USER` vale root -- entao e `$SUDO_USER` que diz quem chamou.
# Quando nem ele existe, o dono do proprio repositorio e a melhor resposta
# disponivel: e a conta que vai precisar ler o que este script gravar. Um nome
# de login escrito no arquivo faz o script funcionar numa maquina so, que e o
# oposto do que um protocolo versionado serve para ser.
DONO=${SUDO_USER:-$(stat -c %U "$RAIZ" 2>/dev/null || logname 2>/dev/null || echo root)}
# O CARIMBO VAI NA FRENTE, e e `YYYY-MM-DD-HHMM`.
#
# Ate aqui a hora ia no fim -- `...-canal-duplo-1035` -- e a data no comeco. O
# nome ficava ordenavel por dia e NAO por execucao: duas coletas do mesmo dia
# apareciam juntas na listagem, mas fora de ordem entre si, e a hora so se lia
# depois de atravessar o resto do nome.
#
# Com o carimbo inteiro na frente, `ls` devolve a ordem cronologica de graca, e
# e isso que se quer de um historico. O que vem depois descreve a CONFIGURACAO,
# que e o segundo criterio natural de leitura.
CARIMBO="$(date +%Y-%m-%d-%H%M)"
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
echo "  configuracao : $CONFIG  $([ "$DERIVADO" -eq 1 ] && echo "(derivada do hardware)" || echo "(informada)")"
echo "  carimbo      : $CARIMBO"
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
SAIDA_AMB="docs/01-fundamentos/medicoes/historico/$CARIMBO-$CONFIG-ambiente"
echo
echo "==> ETAPA 1/4  procedencia da maquina  ($(date +%T))"

# RECONSTRUIR ANTES DE MEDIR, E NAO SO CONFERIR QUE O BINARIO EXISTE.
#
# Ate aqui o script so perguntava se o executavel estava no lugar. Um `build/`
# de tres dias atras passa nessa pergunta, e a coleta inteira sai com o codigo
# antigo enquanto a linha de procedencia aponta para o commit de hoje -- a pior
# combinacao possivel, porque o arquivo parece integro.
#
# `meson compile` e no-op quando nada mudou, entao o custo disto e alguns
# segundos; o custo de nao fazer e uma campanha de uma hora que mede outro
# programa. Se a compilacao falhar, NAO se coleta: binario que nao compila hoje
# nao produz numero publicavel hoje.
echo "    reconstruindo (no-op se nada mudou)"
if ! sudo -u "$DONO" -H ./scripts/build-all.sh > "/tmp/run-all-build.$$.log" 2>&1; then
    echo "FALHA: a compilacao nao passou. A coleta NAO comeca." >&2
    tail -20 "/tmp/run-all-build.$$.log" >&2
    exit 1
fi
grep -cE '^\[[0-9]+/[0-9]+\]' "/tmp/run-all-build.$$.log" 2>/dev/null \
    | sed 's/^/    alvos recompilados: /'
rm -f "/tmp/run-all-build.$$.log"

mkdir -p "$SAIDA_AMB"
chown "$DONO" .ambiente-memoria 2>/dev/null   # o cache ja foi refeito ao derivar o nome
{
    echo "modo detectado : $MODO ($graficos processo(s) grafico(s))"
    echo "configuracao   : $CONFIG"
    echo "carimbo        : $CARIMBO"
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
SAIDA_SONDA="docs/01-fundamentos/medicoes/historico/$CARIMBO-$CONFIG-sonda"
echo
echo "==> ETAPA 2/4  sonda atomic relaxed  ($(date +%T))"
if [ "$SO_RUIDO" -eq 1 ]; then
    echo "    PULADA (--so-ruido): a sonda mede custo, nao ruido"
elif [ ! -x "$SONDA" ]; then
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
echo "==> ETAPA 3/4  campanha completa  ($(date +%T))"
# O MODO VAI DETECTADO, nao fixo. `--fixar-governor` vale nos dois: em texto
# porque nada aquece a CPU, em grafico porque tira a unica variavel que o
# compositor ainda move sem declarar.
# O NOME VAI JA CARIMBADO. A campanha detecta o carimbo e nao aplica outro --
# sem isso ela usaria o horario de QUANDO ELA comeca, que e minutos depois das
# etapas anteriores, e a mesma execucao apareceria sob dois nomes.
EXTRA=""
[ "$SO_RUIDO" -eq 1 ] && EXTRA="--so-ruido"
# shellcheck disable=SC2086
./ferramental/qualidade/campanha.sh "--$MODO" $EXTRA --fixar-governor "$CARIMBO-$CONFIG"
rc=$?

# --------------------------------------------------------------------------
# ETAPA 4: as invocacoes unicas da trilha.
#
# NAO SAO CAMPANHA, e o README delas diz isso: execucao unica nao carrega
# dispersao nem serve de linha de base. Servem para que o bloco publicado no
# topico tenha um arquivo por tras, que e o minimo que este projeto exige de
# qualquer numero.
#
# Ficavam de fora deste script por acidente, nao por principio -- e por isso
# eram os unicos blocos do material que so se refaziam a mao, com a invocacao
# copiada do README. Copiar invocacao a mao e como o nome da coleta era
# montado ate ontem.
#
# As invocacoes abaixo sao as que os documentos publicam. Mudar uma delas aqui
# sem mudar no documento faz o bloco divergir da propria procedencia, e o
# `verificar-blocos.py` acusa.
# --------------------------------------------------------------------------
echo
echo "==> ETAPA 4/4  invocacoes unicas da trilha  ($(date +%T))"
if [ "$SO_RUIDO" -eq 1 ]; then
    echo "    PULADA (--so-ruido)"
    echo
    echo "=========================================================="
    echo "  run-all CONCLUIDO  $(date -Is)"
    echo "=========================================================="
    exit 0
fi
T02=trilha/01-fundamentos/02-mempool-ring
SAIDA_T02="$T02/historico/$CARIMBO-$CONFIG"
SAIDA_CPP="$T02/alternativas/cpp23/historico/$CARIMBO-$CONFIG"
PR=build/$T02/pipeline_ring
PRV=build/$T02/pipeline_ring_vazado
PKT=build/$T02/alternativas/cpp23/packet_pipeline

if [ ! -x "$PR" ] || [ ! -x "$PRV" ] || [ ! -x "$PKT" ]; then
    echo "    PULADO: binarios do topico 02 ausentes; rode ./scripts/build-all.sh"
else
    mkdir -p "$SAIDA_T02" "$SAIDA_CPP"
    ./scripts/ambiente.sh > "$SAIDA_T02/ambiente.txt" 2>&1

    # `--file-prefix` proprio: sem ele, duas invocacoes simultaneas ou um
    # residuo de execucao anterior disputam a mesma area de hugepage.
    #
    # O CODIGO DE SAIDA NAO E CONFERIDO AQUI, e isso e deliberado:
    # `pipeline_ring_vazado` termina com 1 POR DESENHO -- ele existe para
    # demonstrar o vazamento e o sinaliza pela saida. Tratar rc != 0 como falha
    # faria o script "consertar" o unico programa que esta certo em falhar. O
    # que se confere e a SAIDA ter conteudo, que e o que vira procedencia.
    sudo -u "$DONO" -H "$PR"  -l 0   --no-huge --file-prefix=topico02 -- -n 10 \
        > "$SAIDA_T02/pipeline_ring.n10.txt" 2>&1
    sudo -u "$DONO" -H "$PR"  -l 0,2 --no-huge --file-prefix=topico02 -- -n 2000000 -b 256 \
        > "$SAIDA_T02/pipeline_ring.2m-b256.txt" 2>&1
    sudo -u "$DONO" -H "$PRV" -l 0,2 --no-huge --file-prefix=topico02 -- -n 2000000 -b 256 \
        > "$SAIDA_T02/pipeline_ring_vazado.2m-b256.txt" 2>&1
    sudo -u "$DONO" -H "$PKT" -n 10 \
        > "$SAIDA_CPP/packet_pipeline.n10.txt" 2>&1

    # A EXCECAO DESTA ETAPA, E ELA E DECLARADA.
    #
    # Esta etapa e de invocacao unica, e `custo-anel-cpp` nao cabe nessa regra:
    # o nivel 2 do README do cpp23 publica MEDIANAS DE 10 EXECUCOES por ponto.
    # Uma invocacao so nao sustenta esse bloco, e ate agora nada no projeto
    # produzia as dez -- a tabela existia sem coleta que a refizesse.
    #
    # Sao dez saidas numeradas, no mesmo formato `*.r<N>.txt` que a campanha
    # usa, para que o mesmo apurador as leia.
    ANELCPP=build/$T02/alternativas/cpp23/custo-anel-cpp
    if [ -x "$ANELCPP" ]; then
        echo "    custo-anel-cpp: 10 execucoes (o README publica medianas de 10)"
        for r in $(seq 1 10); do
            sudo -u "$DONO" -H "$ANELCPP" > "$SAIDA_CPP/custo-anel-cpp.r$r.txt" 2>&1
        done
        n=$(ls "$SAIDA_CPP"/custo-anel-cpp.r*.txt 2>/dev/null | wc -l)
        echo "    custo-anel-cpp: $n de 10 saidas"
    else
        echo "    PULADO: custo-anel-cpp ausente em $ANELCPP"
    fi

    for f in "$SAIDA_T02"/pipeline_ring*.txt "$SAIDA_CPP"/packet_pipeline*.txt; do
        [ -s "$f" ] && printf "    %-42s %s bytes\n" "$(basename "$f")" "$(stat -c %s "$f")" \
                    || printf "    %-42s VAZIO\n" "$(basename "$f")"
    done
    chown -R "$DONO" "$SAIDA_T02" "$SAIDA_CPP"
    echo "    saida: $SAIDA_T02"
    echo "           $SAIDA_CPP"
fi

echo
echo "=========================================================="
echo "  run-all CONCLUIDO  $(date -Is)   (campanha rc=$rc)"
echo
echo "  Para voltar ao modo grafico:"
echo "    sudo systemctl set-default graphical.target && sudo reboot"
echo "  (ou so reinicie: o boot unico ja expirou)"
echo "=========================================================="
exit "$rc"
