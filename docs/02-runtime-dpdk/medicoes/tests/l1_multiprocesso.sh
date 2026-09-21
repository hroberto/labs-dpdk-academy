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

# A LIMPEZA PRECISA DE UM TESTE NEGATIVO, pelo mesmo motivo que o invariante do
# pool precisa: uma verificacao que nunca acusou e indistinguivel de uma que
# nunca roda. Ate 21/09/2026 a limpeza do l3_multiprocesso olhava o diretorio
# errado e a suite ficava verde.
conferir_sem_residuo academia_x >/dev/null || {
    echo 'FALHA: conferir_sem_residuo acusou residuo num diretorio limpo'
    exit 1
}
: > "$tmp/huge/academia_x_plantado"
if conferir_sem_residuo academia_x >/dev/null; then
    echo 'FALHA: conferir_sem_residuo NAO acusou um residuo plantado'
    exit 1
fi
rm -f "$tmp/huge/academia_x_plantado"
echo '  ok - conferir_sem_residuo acusa residuo plantado e absolve diretorio limpo'

cat > "$tmp/lib-hugetlbfs.sh" <<'LIB'
descobrir_hugetlbfs() { printf '%s' "$DPDK_ACADEMY_HUGE_DIR"; }
hugetlbfs_disponivel() { return "${REQUISITO_RC:-0}"; }
# Controlavel pelo teste: e assim que se prova que o runner CONSULTA o
# resultado da limpeza, sem precisar adivinhar o PREFIXO que ele sorteia.
conferir_sem_residuo() { return "${RESIDUO_RC:-0}"; }
LIB
cat > "$tmp/primario" <<'PRIMARY'
#!/usr/bin/env bash
echo 'aguardando o assinante conectar'
exec sleep 30
PRIMARY
chmod +x "$tmp/primario"

# CAMINHO FELIZ COM DUBLES.
#
# Ate 21/09/2026 este meta-teste so tinha casos de FALHA e de PULO. Sem um caso
# que termine em 0, nao ha como observar nada que o runner faca DEPOIS de dar
# certo -- e a verificacao da limpeza acontece exatamente ali. A primeira
# tentativa de testa-la usou um cenario que ja saia com 1 por outro motivo, e
# passou com a fiacao removida: um teste que confirma o esperado pelo motivo
# errado.
#
# Os dubles imitam a SAIDA dos programas reais, porque o runner decide por
# `grep`. Se a saida dos programas mudar, estes dubles mudam junto -- o que este
# arquivo verifica e a logica do RUNNER, nao a dos programas.
export DPDK_ACADEMY_TICKS=7
cat > "$tmp/primario_ok" <<'POK'
#!/usr/bin/env bash
echo 'waiting for the subscriber to connect'
echo 'memzone virtual address 0xfeed0000'
echo 'sequence gaps injected .. 3'
sleep 1
POK
cat > "$tmp/secundario_ok" <<'SOK'
#!/usr/bin/env bash
echo 'secondary process attached'
echo 'memzone virtual address 0xfeed0000'
echo 'ticks accepted .......... 7'
echo 'gaps detected 3'
echo 'publication -> observation 123 ns'
echo 'crossed books ........... 0'
SOK
chmod +x "$tmp/primario_ok" "$tmp/secundario_ok"

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

# O PAR QUE ISOLA A FIACAO DA LIMPEZA.
#
# As duas linhas diferem em UMA coisa: o veredito da verificacao de residuo.
# A primeira prova que o caminho feliz termina em 0; a segunda, que um residuo
# o derruba. Um runner que ignorasse a verificacao passaria na primeira e
# falharia na segunda -- que e como se sabe que a segunda esta medindo a
# fiacao, e nao outra coisa.
# So o l3_multiprocesso: o l3_primario_morre MATA o primario e espera outro
# desfecho, entao estes dubles nao o representam. Cobrir os dois exigiria um
# segundo par de dubles, e o que se quer isolar aqui e a fiacao da limpeza --
# que e a mesma nos dois arquivos.
export RESIDUO_RC=0
verificar 0 "$tmp/l3_multiprocesso.sh" "$tmp/primario_ok" "$tmp/secundario_ok"
export RESIDUO_RC=1
verificar 1 "$tmp/l3_multiprocesso.sh" "$tmp/primario_ok" "$tmp/secundario_ok"
export RESIDUO_RC=0
[ "$falhas" -eq 0 ]
