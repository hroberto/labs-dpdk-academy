#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -eu

# O DPDK NAO REMOVE O DIRETORIO DE RUNTIME do --file-prefix ao encerrar, e
# ate 21/09/2026 nenhum runner L2 removia: 97 diretorios acumulados em
# /run/user/<uid>/dpdk/, cada um com config e os fbarray, em tmpfs. O sufixo
# e o PID DESTE script, entao o glob nao alcanca execucao alheia.
bin=${1:?}; mode=${2:?}
out=$(mktemp)
# UM trap so: um segundo `trap ... EXIT` SUBSTITUI o primeiro em vez de somar,
# e foi assim que a primeira versao desta limpeza nao removeu nada.
trap 'rm -f "$out"; rm -rf "${XDG_RUNTIME_DIR:-/var/run}"/dpdk/academy_*_$$' EXIT
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
    grep -q 'INVARIANT VIOLATED' "$out"
    grep -Eq 'nao couberam na fila: [1-9][0-9]*' "$out" ;;
  paused|pausedtwo)
    [ "$rc" -eq 3 ]
    grep -q 'NO PROGRESS' "$out"
    grep -q 'Free objects in the pool at the end: 4095 of 4095' "$out"
    grep -q 'Objects dropped at shutdown: 64' "$out" ;;
  *) exit 2 ;;
esac
