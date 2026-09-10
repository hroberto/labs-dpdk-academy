#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Configura (se preciso) e compila todos os tópicos do projeto.
# Uso: scripts/build-all.sh [diretorio-de-build]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=${1:-build}

if [ ! -f "$BUILD/build.ninja" ]; then
    echo "==> configurando em '$BUILD'"
    meson setup "$BUILD"
fi
echo "==> compilando"
meson compile -C "$BUILD"
