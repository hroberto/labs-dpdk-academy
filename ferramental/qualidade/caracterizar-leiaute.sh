#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# =========================================================================
# CARACTERIZAR A SENSIBILIDADE DE CADA ROTULO AO LEIAUTE DO BINARIO
#
#   sudo ./ferramental/qualidade/caracterizar-leiaute.sh [opcoes] <programa>...
#
#   --repeticoes N      execucoes por artefato (padrao 20; o `meson.build`
#                       adotou "cinco a vinte" e os casos marginais do
#                       `custo-mckenney` nao se resolveram com dez)
#   --alinhamentos "…"  valores de `-falign-loops` (padrao "16 32 64 128")
#
# POR QUE ISTO NAO E UMA ETAPA DO `run-all.sh`
#
# Todo o `run-all.sh` mede a MAQUINA sob um artefato fixo. Isto mede o
# INSTRUMENTO, variando o artefato de proposito. Sao perguntas opostas: uma
# segura o binario para ver a maquina, a outra segura a maquina para ver o
# binario.
#
# Os gatilhos tambem diferem. A coleta normal se repete quando o hardware
# muda; a sensibilidade de um rotulo so muda quando o CODIGO daquele programa
# muda. E a saida daqui e CALIBRACAO -- o `sensibilidade-leiaute.tsv`, que e
# entrada do `comparar-hardware.py`. Calibracao e medicao compartilhando
# gatilho faria a regua ser recalibrada pelos dados que ela julga.
#
# O QUE ELE RESPONDE
#
# Para cada rotulo, tres perguntas que separam tres coisas distintas:
#
#   reprodutibilidade  a faixa entre execucoes do MESMO artefato
#   envelope           a variacao das medianas ENTRE alinhamentos
#   identificabilidade o sinal e a materialidade do efeito sobrevivem ao
#                      envelope?
#
# UMA VARIAVEL, E SO UMA. As flags saem do `compile_commands.json` do build do
# projeto, e so `-falign-loops` e substituido. A caracterizacao de 27/09/2026
# compilou com `cc -Wall -std=c11 -O2 -g -pthread` e esqueceu
# `-D_FILE_OFFSET_BITS=64`, que o meson passa -- os artefatos diferiam da
# producao em mais de uma variavel, e o desenho exige exatamente uma.
#
# O MODO E TEXTO, E O PORTAO RECUSA SESSAO GRAFICA
#
# A §7 da metodologia manda mediana e razao para "maquina dedicada, sessao
# grafica permitida", e dispersao para modo texto. Isto cai nos dois lados: a
# grandeza e comparacao de medianas, e a resolucao exigida e de dispersao --
# separar leiaute de variacao entre execucoes.
#
# Decide o segundo, e a razao esta medida: em 27/09/2026 uma execucao
# perturbada em dez moveu a faixa de `lock, best case` em 84% (um valor de
# 3,79 entre nove de 2,04), e `2 threads on 2 physical cores` teve 3038,70
# entre valores de 3690. Foi sessao grafica viva.
#
# O GOVERNOR VAI FIXO em `performance`, e restaurado no fim. Ele e a unica
# razao pela qual o modo grafico parecia melhor para medianas -- a rampa de
# relogio em texto, que o `custo-alocacao` mostrou indo de 4,33 a 5,57 GHz
# DENTRO da medicao. Com ele fixo, o argumento some.
# =========================================================================
set -u
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"

REPETICOES=20
ALINHAMENTOS="16 32 64 128"
while [ $# -gt 0 ]; do
    case "$1" in
        --repeticoes)    REPETICOES=$2; shift 2 ;;
        --alinhamentos)  ALINHAMENTOS=$2; shift 2 ;;
        -*) echo "opcao desconhecida: $1" >&2; exit 2 ;;
        *)  break ;;
    esac
done
[ $# -ge 1 ] || {
    echo "uso: $0 [--repeticoes N] [--alinhamentos \"16 32 64 128\"] <programa>..." >&2
    echo "  exemplo: $0 custo-comunicacao custo-mckenney" >&2
    exit 2
}
PROGRAMAS="$*"

# ---- PORTAO 1: ROOT, porque o governor exige ----------------------------
[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo (fixar o governor exige root)." >&2; exit 1; }
DONO=${SUDO_USER:-$(stat -c %U "$RAIZ" 2>/dev/null || echo root)}

# ---- PORTAO 2: SESSAO GRAFICA RECUSADA ----------------------------------
# Assimetrico como o da campanha: aqui a ausencia de sessao NAO e a hipotese,
# e sim a condicao que torna a faixa entre execucoes legivel.
graficos=$(pgrep -c -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" 2>/dev/null)
graficos=${graficos:-0}
if [ "$graficos" -ne 0 ]; then
    echo "FALHA: a caracterizacao exige modo texto, e ha $graficos processo(s) grafico(s)." >&2
    pgrep -a -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" | sed 's/^/           /' >&2
    echo "       sudo grub-reboot modo-texto && systemctl reboot -i" >&2
    exit 1
fi

# ---- PORTAO 3: RECONSTRUIR ANTES DE LER AS FLAGS ------------------------
#
# O contrato desta etapa e simples e precisa continuar simples:
#
#   a caracterizacao deriva as flags do BUILD NORMAL ATUAL, que acabou de
#   passar pela mesma reconstrucao que a campanha usa.
#
# Conferir a data do `compile_commands.json` nao bastaria: uma mudanca no
# `meson.build` altera as flags sem tocar em nenhum `.c`, e o arquivo ficaria
# "recente" descrevendo outra coisa. `build-all.sh` e no-op quando nada mudou,
# entao reconstruir custa segundos e fecha o caso inteiro. Chamado sozinho ou
# pela ETAPA 5 do `run-all`, o caminho e o mesmo.
# O BUILD ALVO E O QUE A CAMPANHA MEDE, e nao um qualquer.
#
# `campanha-hardware.sh` mede binarios de `build-precommit`. Caracterizar a
# partir de `build` produziria artefatos de OUTRA familia, e a classificacao
# resultante nao valeria para os rotulos que a campanha coleta -- que e
# exatamente a inferencia que o `comparar-hardware.py` recusa quando o
# `text_sha256` difere.
BUILD_ALVO=${DPDK_ACADEMY_BUILD:-build-precommit}
echo "==> reconstruindo o build normal (no-op se nada mudou): $BUILD_ALVO"
if ! sudo -u "$DONO" -H ./scripts/build-all.sh "$BUILD_ALVO" > /tmp/caracterizar-build.$$.log 2>&1; then
    echo "FALHA: a compilacao nao passou. A caracterizacao NAO comeca." >&2
    tail -20 /tmp/caracterizar-build.$$.log >&2
    rm -f /tmp/caracterizar-build.$$.log
    exit 1
fi
rm -f /tmp/caracterizar-build.$$.log

# SO O BUILD NORMAL, E NUNCA UM FALLBACK.
#
# A versao anterior aceitava `build-san` quando `build` faltava. O `build-san`
# e configurado com `-Db_sanitize=address,undefined`, e suas flags trazem
#
#     -fsanitize=address,undefined -fno-omit-frame-pointer
#
# O `-fno-omit-frame-pointer` sozinho ja muda alocacao de registradores e
# leiaute -- que e A VARIAVEL SOB ESTUDO. Caracterizar a partir dali mediria o
# efeito do sanitizador e chamaria de sensibilidade ao leiaute.
CC_JSON="$BUILD_ALVO/compile_commands.json"
[ -f "$CC_JSON" ] || { echo "FALHA: $CC_JSON nao existe mesmo apos reconstruir." >&2; exit 1; }

CARIMBO="$(date +%Y-%m-%d-%H%M)"
SAIDA="docs/01-fundamentos/medicoes/historico/$CARIMBO-leiaute"
mkdir -p "$SAIDA/saidas" "$SAIDA/artefatos"
MANIFESTO="$SAIDA/manifesto.txt"
. "$RAIZ/ferramental/qualidade/identidade-artefato.sh"
{
    echo "# manifesto da caracterizacao de leiaute $CARIMBO"
    echo "# STATUS: PASS (mediu), SKIP (pre-requisito ausente), FAIL (correu e reprovou)"
    printf '%-40s %-7s %s\n' "CELL" "STATUS" "RC"
} > "$MANIFESTO"

# ---- O GOVERNOR, E A RESTAURACAO QUE NAO DEPENDE DE CHEGAR AO FIM -------
GOV_ANTES=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo desconhecido)
fixar_gov() {
    for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        echo "$1" > "$c" 2>/dev/null || :
    done
}
restaurar_gov() {
    [ "$GOV_ANTES" = "desconhecido" ] || { fixar_gov "$GOV_ANTES"; echo "==> governor restaurado para $GOV_ANTES"; }
}
# TRAPS SEPARADOS: o de saida limpa, os de sinal limpam E TERMINAM. Um trap de
# INT que so limpa devolve o controle e a caracterizacao segue depois de o
# operador achar que a interrompeu -- foi o defeito que o `run-all` corrigiu.
trap 'restaurar_gov' EXIT
trap 'echo "==> interrompido (SIGINT)" >&2; exit 130' INT
trap 'echo "==> terminado (SIGTERM)" >&2; exit 143' TERM
fixar_gov performance
echo "==> governor: $GOV_ANTES -> performance (restaurado no fim)"

# ---- A CONDICAO VAI NO ARQUIVO, e nao so na tela ------------------------
{
    echo "tipo           : caracterizacao de sensibilidade ao leiaute"
    echo "modo detectado : texto ($graficos processo(s) grafico(s))"
    echo "carimbo        : $CARIMBO"
    echo "programas      : $PROGRAMAS"
    echo "alinhamentos   : $ALINHAMENTOS"
    echo "repeticoes     : $REPETICOES por artefato"
    echo "governor       : $GOV_ANTES -> performance"
    echo "execucao       : completa"
    echo
} > "$SAIDA/ambiente.txt"
./scripts/ambiente.sh >> "$SAIDA/ambiente.txt" 2>&1

# ---- CONSTRUIR AS VARIANTES --------------------------------------------
# A RECEITA VEM DE UM ARQUIVO CARREGADO, e nao de um trecho daqui: o
# `l1_ancora_producao.sh` carrega o mesmo, e para de reconstruir a funcao por
# `sed`. A razao esta no cabecalho dele.
. "$RAIZ/ferramental/qualidade/receita-build.sh"

# O ALINHAMENTO DO PROJETO, que e o ponto de ancoragem do portao abaixo.
AL_PRODUCAO=$(grep -oE "falign-loops=[0-9]+" "$CC_JSON" | head -1 | cut -d= -f2)
[ -n "$AL_PRODUCAO" ] || { echo "FALHA: nao li o -falign-loops do build." >&2; exit 1; }
echo "==> alinhamento de producao: $AL_PRODUCAO"

# A PROCEDENCIA DA ARVORE, dita e nao adivinhada. E a mesma string que o
# `vcs_tag` do meson grava no `academy_version.h`, entao o campo do artefato
# passa a concordar com a linha `origin:` que o programa imprime.
ORIGEM_FONTE=$(sudo -u "$DONO" git describe --always --dirty --tags 2>/dev/null || echo nao-disponivel)
echo "==> procedencia da arvore: $ORIGEM_FONTE"

BINARIOS=""
for prog in $PROGRAMAS; do
    fonte=$(fonte_do_programa "$prog") || { echo "FALHA: $prog nao esta no $CC_JSON" >&2; exit 1; }
    # A PROCEDENCIA DO FONTE, por programa. E ela que diz, depois, se a
    # classificacao envelheceu: rotulo caracterizado contra um fonte que
    # mudou nao autoriza mais comparacao nenhuma.
    commit_fonte=$(sudo -u "$DONO" git log -1 --format=%H -- "$fonte" 2>/dev/null || echo desconhecido)
    echo "# FONTE $prog"            >> "$MANIFESTO"
    echo "#   path=${fonte#$RAIZ/}" >> "$MANIFESTO"
    echo "#   commit=$commit_fonte" >> "$MANIFESTO"
    for al in $ALINHAMENTOS; do
        bin="$RAIZ/$SAIDA/artefatos/$prog.al$al"
        erro="$SAIDA/artefatos/$prog.al$al.erro"
        if ( eval "$(comando_de "$prog" "$al" "$bin")" ) 2>"$erro"; then
            rm -f "$erro"
            identidade_artefato "$bin" \
                "$(comando_de "$prog" "$al" "$bin" | sed 's/^cd [^&]*&& //')" \
                "$ORIGEM_FONTE"
            BINARIOS="$BINARIOS $prog:$al"
            echo "    construido: $prog -falign-loops=$al"
        else
            printf '%-40s %-7s %s\n' "$prog.al$al" "FAIL" "build" >> "$MANIFESTO"
            echo "    FALHA ao construir $prog -falign-loops=$al" >&2
            sed 's/^/        /' "$erro" >&2
        fi
    done

    # O PORTAO QUE TERIA PEGO O DEFEITO DE 27/09/2026 NA HORA.
    #
    # No alinhamento de producao, o artefato da caracterizacao tem de ser o
    # MESMO que a campanha mede -- mesmo `.text`, byte a byte. Se nao for,
    # alguma coisa alem do alinhamento variou, e a classificacao resultante
    # nao valeria para os rotulos que a campanha coleta.
    #
    # Naquele dia variou: o comando era remontado a mao e perdia o `-I` do
    # diretorio de build, onde `academy_version.h` e gerado. Os artefatos
    # compilaram sem a linha de procedencia, com outro `.text`, e a
    # caracterizacao descreveu um instrumento que ninguem mede.
    # SEM ANCORA, ZERO MEDICOES. Nao ha desfecho intermediario aqui.
    #
    # A primeira versao imprimia AVISO e seguia quando faltava um dos lados --
    # o que e degradar o portao a informacao. E `_sha_secao` devolve
    # `nao-disponivel` quando nao ha secao: com os dois lados assim, a
    # igualdade era satisfeita pela SENTINELA e a ancora aprovava sem comparar
    # coisa nenhuma. Os dois sao fail-open no portao que existe para fechar
    # fail-open.
    prod=$(printf '%s' "$CC_JSON" | sed 's|/compile_commands.json||')
    # AMBIGUIDADE ABORTA, em vez de escolher a primeira.
    #
    # Era `find ... | head -1`. Hoje o alvo e unico e funciona; no dia em que
    # dois diretorios do build tiverem um executavel com o mesmo nome, a ancora
    # escolheria um deles em SILENCIO e a caracterizacao passaria a descrever
    # um instrumento que talvez nao seja o medido -- que e literalmente o
    # defeito que este portao existe para pegar, entrando pela escolha
    # arbitraria em vez de pelo comando remontado.
    prod_bins=$(find "$prod" -type f -name "$prog" -perm -u+x 2>/dev/null)
    n_prod=$(printf '%s\n' "$prod_bins" | grep -c . || true)
    if [ "$n_prod" -gt 1 ]; then
        echo "FALHA: achei $n_prod executaveis chamados $prog em $prod." >&2
        printf '%s\n' "$prod_bins" | sed 's/^/           /' >&2
        echo "  Escolher um deles em silencio produziria uma ancora sobre o" >&2
        echo "  binario errado. Diga qual com DPDK_ACADEMY_BUILD." >&2
        exit 1
    fi
    prod_bin=$(printf '%s\n' "$prod_bins" | head -1)
    meu="$RAIZ/$SAIDA/artefatos/$prog.al$AL_PRODUCAO"
    [ -n "$prod_bin" ] || {
        echo "FALHA: nao achei o binario de producao de $prog em $prod." >&2
        echo "  Sem o instrumento de referencia nao ha o que ancorar." >&2
        exit 1; }
    [ -f "$meu" ] || {
        echo "FALHA: a variante $prog.al$AL_PRODUCAO nao foi construida." >&2
        echo "  E ela que ancora a caracterizacao no instrumento medido." >&2
        exit 1; }
    a=$(_sha_secao "$prod_bin" .text)
    b=$(_sha_secao "$meu" .text)
    # O VALOR TEM DE ESTAR NO DOMINIO ANTES DE SER COMPARADO.
    for h in "$a" "$b"; do
        printf '%s' "$h" | grep -qE '^[0-9a-f]{64}$' || {
            echo "FALHA: nao li a secao .text para ancorar $prog (obtive '$h')." >&2
            echo "  Comparar sentinelas aprovaria a ancora sem comparar nada." >&2
            exit 1; }
    done
    if [ "$a" = "$b" ]; then
        echo "    ancora: $prog.al$AL_PRODUCAO reproduz o binario de producao"
    else
        echo "FALHA: $prog no alinhamento de producao NAO reproduz o binario medido." >&2
        echo "  producao      : ${a:0:16}  ($prod_bin)" >&2
        echo "  caracterizacao: ${b:0:16}" >&2
        echo "  Algo alem de -falign-loops variou; a classificacao nao valeria." >&2
        exit 1
    fi
done
[ -n "$BINARIOS" ] || { echo "FALHA: nenhum artefato construido." >&2; exit 1; }

# ---- MEDIR, COM A ORDEM CONTRABALANCEADA --------------------------------
# A ordem se inverte nas repeticoes pares. Sem isso, o primeiro artefato de
# cada rodada mede sempre no relogio mais frio e a diferenca entre artefatos
# absorve a diferenca entre posicoes.
echo "==> medindo: $(echo $BINARIOS | wc -w) artefato(s) x $REPETICOES repeticoes  ($(date +%T))"
rep=1
while [ "$rep" -le "$REPETICOES" ]; do
    if [ $((rep % 2)) -eq 1 ]; then ordem="$BINARIOS"; else ordem=$(echo $BINARIOS | tr ' ' '\n' | tac | tr '\n' ' '); fi
    for par in $ordem; do
        prog=${par%%:*}; al=${par##*:}
        saida="$SAIDA/saidas/r$rep-al$al-$prog.txt"
        if sudo -u "$DONO" -H "$SAIDA/artefatos/$prog.al$al" > "$saida" 2>&1; then
            rc=0
        else
            rc=$?
        fi
        case "$rc" in 0) est=PASS ;; 77) est=SKIP ;; *) est=FAIL ;; esac
        printf '%-40s %-7s %s\n' "$(basename "$saida")" "$est" "$rc" >> "$MANIFESTO"
    done
    echo "    repeticao $rep de $REPETICOES concluida  ($(date +%T))"
    rep=$((rep + 1))
done

chown -R "$DONO" "$SAIDA"
falhas=$(awk '$2 == "FAIL" { n++ } END { print n + 0 }' "$MANIFESTO")
echo
echo "==> CONCLUIDA  $(date -Is)"
echo "    saida: $SAIDA"
echo "    celulas com FAIL: $falhas"
echo
echo "    Para classificar:"
echo "      ./ferramental/qualidade/classificar-leiaute.py $SAIDA"
[ "$falhas" -eq 0 ] || { echo "==> CARACTERIZACAO COM FALHA: $falhas celula(s)" >&2; exit 1; }
exit 0
