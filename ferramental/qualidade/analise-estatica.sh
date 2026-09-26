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

# PULAR NA MAQUINA DE QUEM ESTUDA, FALHAR NA CI.
#
# Ausencia de ferramenta e fato legitimo no laptop de quem acompanha o
# material, e exigir cppcheck ali afastaria quem so quer compilar. Na CI e
# outra coisa: o job instala a ferramenta de proposito, e um PULADO ali
# significa que a instalacao quebrou -- e o verde passaria a afirmar uma
# analise que nao aconteceu.
exigir() { [ -n "${CI:-}" ] || [ -n "${ANALISE_ESTATICA_EXIGIR:-}" ]; }
pular() {
    echo "  PULADO: $1"
    exigir && { echo "  (na CI isto e FALHA: a analise nao aconteceu)"; exit 1; }
    exit 0
}

if [ ! -x "$CPPCHECK" ]; then
    pular "cppcheck ausente (CPPCHECK=<caminho> para apontar)"
fi
if [ ! -f "$BUILD/compile_commands.json" ]; then
    pular "$BUILD/compile_commands.json ausente; rode scripts/build-all.sh"
fi

saida=$(mktemp); trap 'rm -f "$saida"' EXIT
"$CPPCHECK" --project="$BUILD/compile_commands.json" \
    --enable=warning,style,performance,portability \
    --inline-suppr \
    --suppressions-list=ferramental/qualidade/cppcheck-suppressoes.txt \
    --suppress=missingIncludeSystem --suppress=checkersReport \
    -j "$(nproc)" \
    --template='{file}:{line}: [{severity}/{id}] {message}' \
    2>"$saida" >/dev/null; rc_cppcheck=$?

# TRES ESTADOS, E NAO DOIS. O `|| true` que estava aqui engolia o codigo de
# saida: analisador que morre no meio produzia arquivo curto ou vazio, e o
# script relatava "0 achado(s)" -- ou seja, ANALISE QUE NAO ACONTECEU virava
# analise limpa. cppcheck devolve 1 quando ACHA algo, entao so os outros
# codigos sao falha de execucao.
if [ "$rc_cppcheck" -ne 0 ] && [ "$rc_cppcheck" -ne 1 ]; then
    echo "  FALHA: cppcheck terminou com codigo $rc_cppcheck -- a analise nao concluiu"
    sed -n '1,5p' "$saida" | sed 's/^/    /'
    exit 1
fi

# So o que e NOSSO: o cppcheck tambem analisa os cabecalhos do DPDK e da glibc
# que as unidades incluem, e o que esta em /usr nao e deste projeto consertar.
#
# O CRITERIO E "FORA DA ARVORE", E NAO "COMECA COM /". A versao anterior
# descartava toda linha iniciada por barra, o que funciona enquanto o
# `compile_commands.json` guarda caminho relativo para as fontes do projeto --
# e passa a descartar TODOS os achados nossos no dia em que ele guardar caminho
# absoluto. O filtro que esconde o proprio achado e pior que filtro nenhum.
raiz=$(pwd -P)
nossos=$(awk -v raiz="$raiz/" '
    {
        caminho = $0; sub(/:.*/, "", caminho)
        if (caminho ~ /^\//) { if (index(caminho, raiz) == 1) print }
        else print
    }' "$saida" | sort -u || true)
n=$(printf '%s' "$nossos" | grep -c . || true)

if [ "$n" -eq 0 ]; then
    echo "  cppcheck $("$CPPCHECK" --version | awk '{print $2}'): 0 achado(s) nas fontes do projeto"
    exit 0
fi
printf '%s\n' "$nossos" | sed 's/^/    /'
echo "  cppcheck: $n achado(s) nas fontes do projeto"
exit 1
