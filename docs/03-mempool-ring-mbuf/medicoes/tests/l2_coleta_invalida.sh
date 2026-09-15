#!/usr/bin/env bash
# O erro esperado precisa acontecer na coleta, depois da EAL.
set -eu
out=$(mktemp)
trap 'rm -f "$out"' EXIT
rc=0
"${1:?binario}" -l 0 --no-huge --no-pci --file-prefix="academy_invalid_$$" >"$out" 2>&1 || rc=$?
cat "$out"
[ "$rc" -eq 1 ]
grep -qi 'coleta invalida' "$out"
# A primeira coleta obrigatoria falha: nenhuma tabela final pode ser publicada.
if grep -Eq '^[[:space:]]*(malloc/free|mempool get/put)[[:space:],]+[0-9-]' "$out"; then
    echo 'FALHA: coleta invalida acompanhada de resultado publicado' >&2
    exit 1
fi
