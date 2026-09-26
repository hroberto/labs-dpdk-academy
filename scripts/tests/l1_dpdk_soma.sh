#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# O DPDK baixado e conferido, e o que a conferencia prova esta declarado.
#
# POR QUE ESTE TESTE EXISTE
#
# `preparar-dpdk.sh` baixava o tarball com `curl` e extraia direto. Todo numero
# deste repositorio e medido contra o prefixo que sai dali, e nada conferia que
# o conteudo era o mesmo de antes -- um espelho que troque o arquivo em
# silencio, um download truncado ou um proxy que devolva outra coisa viravam
# numero publicado.
#
# A ASSIMETRIA QUE MOTIVOU: `subprojects/gtest.wrap` ja fixava o googletest com
# `source_hash` e `patch_hash`. O projeto sabia fixar dependencia; nao fazia
# isso com aquela contra a qual tudo e medido.
#
# O QUE A CONFERENCIA NAO PROVA: nao e atestacao upstream. Em 26/09/2026 o
# `fast.dpdk.org` respondeu 404 para `sha256sums.txt`, `.sha256` e `.asc`, e a
# pagina de download nao traz hash. A soma fixada e a do artefato que produziu
# os numeros publicados -- confianca no primeiro uso. Dize-lo e melhor que
# chamar de verificacao o que nao e.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
fonte="$raiz/scripts/preparar-dpdk.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }

eval "$(sed -n '/^soma_conhecida() {/,/^}/p;/^conferir_tarball() {/,/^}/p' "$fonte")"
for f in soma_conhecida conferir_tarball; do
    declare -F "$f" >/dev/null || { echo "FALHA: nao extrai $f() de preparar-dpdk.sh"; exit 1; }
done

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
falhas=0
conferir() { # <descricao> <obtido> <esperado>
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}

# Um arquivo de conteudo conhecido serve de tarball falso: a funcao so faz
# sha256sum, entao nao precisa ser um .tar.xz de verdade.
alvo="$tmp/falso.tar.xz"
printf 'conteudo qualquer\n' > "$alvo"
soma_do_falso=$(sha256sum "$alvo" | cut -d' ' -f1)

# ---- as versoes medidas tem soma fixada ---------------------------------
# Se alguem remover uma delas, o gate de download deixa de existir para aquela
# versao sem que nada mais acuse.
for v in 25.11 26.07; do
    conferir "a versao $v tem soma fixada" \
        "$(soma_conhecida "$v" | wc -c)" "65"
done
conferir "versao desconhecida nao tem soma" "$(soma_conhecida 99.99)" ""

# ---- soma diferente REPROVA ---------------------------------------------
rc=0; conferir_tarball 25.11 "$alvo" 0 >/dev/null 2>&1 || rc=$?
conferir "soma diferente da fixada reprova" "$rc" "1"

# ---- soma igual APROVA ---------------------------------------------------
# Trocar a soma esperada pela do arquivo falso prova o lado positivo sem
# precisar do tarball real, que a CI nao tem.
soma_conhecida() { [ "$1" = "99.98" ] && echo "$soma_do_falso"; }
rc=0; conferir_tarball 99.98 "$alvo" 0 >/dev/null 2>&1 || rc=$?
conferir "soma igual a fixada aprova" "$rc" "0"

# ---- VERSAO SEM SOMA: recusa por padrao ----------------------------------
# E o ponto do achado: aceitar em silencio uma versao nao fixada devolveria o
# defeito inteiro pela porta dos fundos.
soma_conhecida() { echo ""; }
rc=0; conferir_tarball 99.99 "$alvo" 0 >/dev/null 2>&1 || rc=$?
conferir "versao sem soma reprova por padrao" "$rc" "1"

saida=$(conferir_tarball 99.99 "$alvo" 0 2>&1 || true)
conferir "a recusa diz a soma obtida, para poder ser adotada" \
    "$(printf '%s' "$saida" | grep -c "$soma_do_falso")" "1"

# ---- --sem-conferencia: passa, mas ANUNCIA -------------------------------
rc=0; conferir_tarball 99.99 "$alvo" 1 >/dev/null 2>&1 || rc=$?
conferir "com --sem-conferencia, segue" "$rc" "0"
saida=$(conferir_tarball 99.99 "$alvo" 1 2>&1)
conferir "e anuncia que nao e comparavel com o historico" \
    "$(printf '%s' "$saida" | grep -ci 'NAO e comparavel')" "1"

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 9 assercoes; o tarball do DPDK e conferido, e o escape e declarado"
