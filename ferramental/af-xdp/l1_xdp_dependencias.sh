#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -eu
base=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# A arvore falsa espelha o layout REAL: os testes e seus alvos vivem lado a
# lado em ferramental/af-xdp/. Antes ela imitava scripts/ + scripts/tests/, e a
# mudanca de lugar deixou copia e invocacao apontando para diretorios
# diferentes -- o teste procurava onde nao havia copiado.
mkdir -p "$tmp/ferramental/af-xdp"
cp "$base/lib-xdp.sh" "$tmp/ferramental/af-xdp/"
cp "$base/l1_xdp.sh" "$base/l1_xdp_bitmask.sh" "$tmp/ferramental/af-xdp/"
bash "$tmp/ferramental/af-xdp/l1_xdp.sh" > "$tmp/shell.txt"
rc=0
bash "$tmp/ferramental/af-xdp/l1_xdp_bitmask.sh" > "$tmp/bitmask.txt" || rc=$?
[ "$rc" -eq 77 ]
grep -q 'SKIP:' "$tmp/bitmask.txt"
echo 'PASS: shell executado; bitmask sem helper registrada como SKIP'
