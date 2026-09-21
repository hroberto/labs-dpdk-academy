#!/usr/bin/env bash
# O erro esperado precisa acontecer na coleta, depois da EAL.
set -eu
out=$(mktemp)
# O segundo alvo e o diretorio de runtime do --file-prefix, que o DPDK nao
# remove sozinho. Os dois num trap so porque um segundo `trap ... EXIT`
# SUBSTITUI o primeiro em vez de somar.
trap 'rm -f "$out"; rm -rf "${XDG_RUNTIME_DIR:-/var/run}"/dpdk/academy_*_$$' EXIT
rc=0
"${1:?binario}" -l 0 --no-huge --no-pci --file-prefix="academy_invalid_$$" >"$out" 2>&1 || rc=$?
cat "$out"
[ "$rc" -eq 1 ]
grep -qi 'invalid collection' "$out"
# A primeira coleta obrigatoria falha: nenhuma tabela final pode ser publicada.
if grep -Eq '^[[:space:]]*(malloc/free|mempool get/put)[[:space:],]+[0-9-]' "$out"; then
    echo 'FALHA: coleta invalida acompanhada de resultado publicado' >&2
    exit 1
fi
