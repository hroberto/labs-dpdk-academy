#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# A receita do caracterizador converge para o instrumento de producao.
#
# POR QUE ESTE TESTE EXISTE
#
# Em 27/09/2026 a ETAPA 5 correu 40 minutos em maquina dedicada, com 160 de 160
# celulas PASS e os oito artefatos reproduzindo byte a byte. E caracterizou o
# instrumento ERRADO.
#
#     producao / campanha          eaf9abfa...
#     caracterizacao com header    eaf9abfa...   <- coincide
#     caracterizacao sem header    394f847c...   <- o que foi medido
#
# O caracterizador remontava `cc -I<medicoes> $flags` a partir de uma SELECAO
# de flags, e perdia os outros `-I` que o meson passa -- entre eles o do
# diretorio de build, onde `academy_version.h` e gerado. O `statistics.h` o
# inclui sob `__has_include`: sem ele, outro codigo, outro `.text`.
#
# O CONTROLE NEGATIVO QUE FALTAVA
#
# No alinhamento de producao a variante tem de ser o MESMO binario que a
# campanha mede. Se nao for, alguma coisa alem de `-falign-loops` variou, e a
# classificacao nao valeria para os rotulos que a campanha coleta.
#
# E o teste prova os DOIS lados: que o controle reconhece identidade (al64
# reproduz) e que reconhece diferenca (al32 nao reproduz). Um controle que so
# sabe dizer "igual" aprovaria uma receita que ignorasse o alinhamento.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
cd "$raiz" || exit 1
fonte="$raiz/ferramental/qualidade/caracterizar-leiaute.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }

# O BUILD DE REFERENCIA E O QUE A CAMPANHA MEDE.
CC_JSON=""
for d in "${DPDK_ACADEMY_BUILD:-build-precommit}" build; do
    [ -f "$d/compile_commands.json" ] && { CC_JSON="$d/compile_commands.json"; break; }
done
[ -n "$CC_JSON" ] || { echo "PULADO: sem compile_commands.json; rode ./scripts/build-all.sh"; exit 77; }
PROG=custo-comunicacao
BASE=$(dirname "$CC_JSON")
prod=$(find "$BASE" -type f -name "$PROG" -perm -u+x 2>/dev/null | head -1)
[ -n "$prod" ] || { echo "PULADO: $PROG nao construido em $BASE"; exit 77; }

. "$raiz/ferramental/qualidade/identidade-artefato.sh"
eval "$(sed -n '/^comando_de() {/,/^}/p' "$fonte")"
declare -F comando_de >/dev/null || { echo "FALHA: nao extrai comando_de()"; exit 1; }

falhas=0
total=0
conferir() { # <descricao> <obtido> <esperado>
    total=$((total + 1))
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

AL_PROD=$(grep -oE "falign-loops=[0-9]+" "$CC_JSON" | head -1 | cut -d= -f2)
conferir "o build declara um alinhamento" \
    "$(printf '%s' "$AL_PROD" | grep -cE '^[0-9]+$')" "1"

sha_prod=$(_sha_secao "$prod" .text)
construir() { # <alinhamento> -> sha256 da .text, ou vazio
    # DUAS DECLARACOES, e nao uma. Sob `set -u`, `local a=$1 b="x$a"` expande
    # TODAS as palavras da linha antes de atribuir qualquer uma -- e `$a`
    # ainda nao existe. Falha com "variavel nao associada" apontando para a
    # linha seguinte, longe da causa.
    local al=$1
    local saida="$tmp/$PROG.al$al"
    ( eval "$(comando_de "$PROG" "$al" "$saida")" ) >/dev/null 2>&1 || return 1
    _sha_secao "$saida" .text
}

# ---- 1. NO ALINHAMENTO DE PRODUCAO, a receita converge -----------------
sha_ancora=$(construir "$AL_PROD") || { echo "FALHA: nao compilei $PROG no alinhamento $AL_PROD"; exit 1; }
conferir "al$AL_PROD reproduz o .text do binario que a campanha mede" \
    "$sha_ancora" "$sha_prod"

# ---- 2. E O CONTROLE SABE DIZER DIFERENTE ------------------------------
# Sem este lado, uma receita que ignorasse `-falign-loops` passaria no caso 1.
outro=32; [ "$AL_PROD" = "32" ] && outro=16
sha_outro=$(construir "$outro") || { echo "FALHA: nao compilei $PROG no alinhamento $outro"; exit 1; }
conferir "al$outro NAO reproduz producao -- o alinhamento muda o instrumento" \
    "$([ "$sha_outro" = "$sha_prod" ] && echo igual || echo diferente)" "diferente"

# ---- 3. e a diferenca e do alinhamento, nao do acaso -------------------
# Recompilar o MESMO alinhamento tem de dar o MESMO `.text`. Sem isto, o caso 2
# poderia estar medindo nao-determinismo do compilador.
conferir "recompilar al$AL_PROD devolve o mesmo .text" \
    "$(construir "$AL_PROD")" "$sha_ancora"

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: $total assercoes; no alinhamento de producao a receita converge para o instrumento medido"
