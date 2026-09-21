#!/usr/bin/env bash
# Analise estatica com cppcheck sobre as fontes do projeto.
#
# POR QUE ISTO EXISTE
#
# O portao ja exige build com zero aviso, e zero aviso do gcc nao e zero
# defeito: o compilador olha uma unidade de traducao por vez e nao faz analise
# de fluxo entre chamadas. O cppcheck olha o que o gcc nao olha.
#
# Na primeira execucao, em 21/09/2026 com a 2.22.0, achou 34 pontos no codigo
# do projeto. Um era defeito de verdade -- `%d` para `rte_socket_id()`, que
# devolve `unsigned int` -- e o resto se dividiu entre limpeza que valia fazer e
# falso positivo que valia DECLARAR, em cppcheck-suppressoes.txt, cada um com o
# motivo.
#
# A BARRA E ZERO, pela mesma razao que a barra de avisos do compilador e zero:
# uma lista de achados tolerados vira ruido, e ruido tolerado e como um
# analisador morre.
#
# USA O compile_commands.json, e isso importa: sem as flags reais, o cppcheck
# analisa um programa que nao e o que se compila -- outros -D, outros include,
# outro padrao de linguagem.
set -euo pipefail
cd "$(dirname "$0")/../.."

CPPCHECK=${CPPCHECK:-$(command -v cppcheck || echo "$HOME/opt/cppcheck-2.22.0/bin/cppcheck")}
BUILD=${1:-build}

if [ ! -x "$CPPCHECK" ]; then
    echo "  PULADO: cppcheck ausente (CPPCHECK=<caminho> para apontar)"
    exit 0
fi
if [ ! -f "$BUILD/compile_commands.json" ]; then
    echo "  PULADO: $BUILD/compile_commands.json ausente; rode scripts/build-all.sh"
    exit 0
fi

saida=$(mktemp); trap 'rm -f "$saida"' EXIT
"$CPPCHECK" --project="$BUILD/compile_commands.json" \
    --enable=warning,style,performance,portability \
    --inline-suppr \
    --suppressions-list=ferramental/qualidade/cppcheck-suppressoes.txt \
    --suppress=missingIncludeSystem --suppress=checkersReport \
    -j "$(nproc)" \
    --template='{file}:{line}: [{severity}/{id}] {message}' \
    2>"$saida" >/dev/null || true

# So o que e NOSSO: o cppcheck tambem analisa os cabecalhos do DPDK e da glibc
# que as unidades incluem, e o que esta em /usr nao e deste projeto consertar.
nossos=$(grep -v '^/' "$saida" | sort -u || true)
n=$(printf '%s' "$nossos" | grep -c . || true)

if [ "$n" -eq 0 ]; then
    echo "  cppcheck $("$CPPCHECK" --version | awk '{print $2}'): 0 achado(s) nas fontes do projeto"
    exit 0
fi
printf '%s\n' "$nossos" | sed 's/^/    /'
echo "  cppcheck: $n achado(s) nas fontes do projeto"
exit 1
