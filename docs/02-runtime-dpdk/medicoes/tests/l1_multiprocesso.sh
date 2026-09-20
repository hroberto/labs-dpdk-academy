#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Exercita os runners reais com pre-requisitos e processos controlados.
set -eu
origem=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$origem/l3_multiprocesso.sh" "$origem/l3_primario_morre.sh" "$tmp/"
mkdir "$tmp/runtime" "$tmp/huge"
export XDG_RUNTIME_DIR="$tmp/runtime"
export DPDK_ACADEMY_HUGE_DIR="$tmp/huge"

# A biblioteca real deve rejeitar diretorio comum e respeitar caminho explicito.
. "$origem/lib-hugetlbfs.sh"
if hugetlbfs_disponivel "$tmp/huge"; then
    echo 'FALHA: diretorio comum aceito como hugetlbfs'
    exit 1
fi
if hugetlbfs_disponivel ""; then
    echo 'FALHA: caminho vazio aceito como hugetlbfs'
    exit 1
fi
[ "$(descobrir_hugetlbfs)" = "$tmp/huge" ] || exit 1
echo '  ok - biblioteca real rejeita diretorio comum/vazio e preserva escolha explicita'

cat > "$tmp/lib-hugetlbfs.sh" <<'LIB'
descobrir_hugetlbfs() { printf '%s' "$DPDK_ACADEMY_HUGE_DIR"; }
hugetlbfs_disponivel() { return "${REQUISITO_RC:-0}"; }
LIB
cat > "$tmp/primario" <<'PRIMARY'
#!/usr/bin/env bash
echo 'aguardando o assinante conectar'
exec sleep 30
PRIMARY
chmod +x "$tmp/primario"

falhas=0
verificar() {
    local esperado=$1 rc=0
    shift
    bash "$@" > "$tmp/saida" 2>&1 || rc=$?
    if [ "$rc" -eq "$esperado" ]; then
        echo "  ok - $* => $rc"
    else
        echo "  FALHA - $* => $rc, esperado $esperado"
        cat "$tmp/saida"
        falhas=$((falhas + 1))
    fi
}
for runner in l3_multiprocesso.sh l3_primario_morre.sh; do
    export REQUISITO_RC=1
    verificar 77 "$tmp/$runner" /bin/false /bin/false
    export REQUISITO_RC=0
    verificar 1 "$tmp/$runner" /bin/false /bin/true
    verificar 1 "$tmp/$runner" /bin/true /bin/true
    # O runner deve rejeitar o secundario antes de esperar o primario terminar.
    verificar 1 "$tmp/$runner" "$tmp/primario" /bin/false
done
[ "$falhas" -eq 0 ]
