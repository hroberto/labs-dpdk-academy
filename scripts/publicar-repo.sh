#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Aplica a descricao e os topicos do repositorio no GitHub.
#
# POR QUE ISTO E UM SCRIPT, E NAO UMA ANOTACAO
#
# `description` e `topics` sao a superficie de descoberta do projeto: e o que a
# busca do GitHub indexa e o que aparece no preview de um link no LinkedIn. Sao
# tambem a unica parte do material que NAO vive num arquivo -- moram na API do
# GitHub, e portanto some da revisao, do diff e da memoria de quem configurou.
#
# Versionar aqui resolve tres coisas: o texto passa por revisao como qualquer
# outro; quem clonar sabe qual e a descricao pretendida; e reaplicar depois de
# um acidente e um comando, nao uma arqueologia.
#
# E o mesmo raciocinio de `scripts/ambiente.sh`: nao descreva em prosa o que
# pode ser gerado.
#
# Uso:
#   ./scripts/publicar-repo.sh --mostrar    # so imprime o que seria aplicado
#   ./scripts/publicar-repo.sh              # aplica (exige gh autenticado)
set -u

# --- o conteudo, que e o que importa nesta revisao -------------------------
#
# A descricao tem limite pratico de ~350 caracteres no GitHub, mas o que aparece
# em preview e busca sao os primeiros ~150. Por isso a frase que distingue o
# projeto vem primeiro, e nao a categoria: "guia de DPDK" nao diferencia nada.
DESCRICAO='DPDK study guide where every published number has a program that produces it. Measured on a named machine, and corrected when the measurement disagreed — including against the official docs. Portuguese prose, English code.'

# Topicos: o GitHub aceita ate 20, minusculas, hifens. A ordem nao importa para
# a busca, mas os primeiros aparecem no cartao do repositorio.
TOPICOS=(
    dpdk
    data-plane
    kernel-bypass
    packet-processing
    networking
    cpp23
    systems-programming
    performance-engineering
    benchmarking
    linux
    meson
    learning-resources
    portuguese
)

if [ "${1:-}" = "--mostrar" ]; then
    echo "description:"
    echo "  $DESCRICAO"
    echo ""
    echo "topics (${#TOPICOS[@]}):"
    printf '  %s\n' "${TOPICOS[@]}"
    echo ""
    echo "Comando equivalente:"
    printf '  gh repo edit --description "%s" \\\n' "$DESCRICAO"
    printf '     --add-topic %s \\\n' "${TOPICOS[@]}" | sed '$ s/ \\$//'
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "gh nao encontrado. Instale o GitHub CLI, ou rode com --mostrar e" >&2
    echo "aplique a descricao e os topicos pela interface web." >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "gh nao autenticado. Rode 'gh auth login'." >&2
    exit 1
fi
if ! git remote get-url origin >/dev/null 2>&1; then
    echo "sem remote 'origin'. Crie o repositorio primeiro:" >&2
    echo "  gh repo create dpdk-academy --public --source=. --push" >&2
    exit 1
fi

args=(--description "$DESCRICAO")
for t in "${TOPICOS[@]}"; do args+=(--add-topic "$t"); done
gh repo edit "${args[@]}" && echo "  descricao e ${#TOPICOS[@]} topicos aplicados"
