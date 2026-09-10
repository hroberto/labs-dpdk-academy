#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Executa a suíte de testes do projeto.
#
#   L1 — lógica pura (GTest), sem EAL, sem hugepages, sem NIC. Roda em qualquer
#        máquina e é onde ficam as asserções finas sobre o comportamento.
#   L2 — integração: exercita o binário como o estudante o executa, incluindo os
#        argumentos da EAL e a integridade do mempool após o uso.
#
# Uso: scripts/test-all.sh [l1|l2|l3]  [diretorio-de-build]
#
# Os TRES niveis se distinguem pelo que EXIGEM, nao pela profundidade:
#   l1  nada alem do compilador          -- roda em qualquer lugar
#   l2  a EAL em processo unico, sem privilegio  -- roda em qualquer lugar
#   l3  algo que o HOST precisa conceder: hugetlbfs gravavel, varios nucleos
#       fisicos, dois dominios de cache L3, IOMMU, NIC. Onde faltar, o teste
#       sai com 77 e o Meson conta como PULADO -- nunca como sucesso.
set -euo pipefail
cd "$(dirname "$0")/.."
NIVEL=${1:-}
BUILD=${2:-build}

if [ ! -f "$BUILD/build.ninja" ]; then
    echo "==> configurando em '$BUILD'"
    meson setup "$BUILD"
fi

case "$NIVEL" in
    l1|L1) meson test -C "$BUILD" --suite l1 --print-errorlogs ;;
    l2|L2) meson test -C "$BUILD" --suite l2 --print-errorlogs ;;
    l3|L3) meson test -C "$BUILD" --suite l3 --print-errorlogs ;;
    "")    meson test -C "$BUILD" --print-errorlogs ;;
    *)     echo "uso: $0 [l1|l2|l3] [diretorio-de-build]" >&2; exit 2 ;;
esac
