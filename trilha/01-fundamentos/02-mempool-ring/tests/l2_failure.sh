#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -eu
bin=${1:?}; mode=${2:?}
out=$(mktemp); trap 'rm -f "$out"' EXIT
rc=0
cores=0
if [ "$mode" = pausedtwo ]; then
    [ "$(getconf _NPROCESSORS_ONLN)" -ge 2 ] || { echo 'SKIP: duas CPUs'; exit 77; }
    cores=0,1
fi
"$bin" -l "$cores" --no-huge --no-pci --file-prefix="academy_failure_$$" -- -n 64 -b 32 -t 20 >"$out" 2>&1 || rc=$?
cat "$out"
case "$mode" in
  leak)
    [ "$rc" -eq 1 ]
    grep -q 'INVARIANTE VIOLADO' "$out"
    grep -Eq 'nao couberam na fila: [1-9][0-9]*' "$out" ;;
  paused|pausedtwo)
    [ "$rc" -eq 3 ]
    grep -q 'SEM PROGRESSO' "$out"
    grep -q 'Objetos livres no pool ao final: 4095 de 4095' "$out"
    grep -q 'Objetos descartados no encerramento: 64' "$out" ;;
  *) exit 2 ;;
esac
