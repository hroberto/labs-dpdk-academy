#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# O parceiro de comparacao sai da TOPOLOGIA, e nao de aritmetica.
#
# POR QUE ESTE TESTE EXISTE
#
# `bench-ccd.sh` le os dominios de L3 no sysfs, imprime-os na tela, e entao
# escolhia o consumidor "do mesmo dominio" como `A + 2` -- ignorando o que
# acabara de ler. Nesta maquina acerta por coincidencia do enumerador: o CCD0 e
# `0-5,12-17`, logo 0 e 2 sao vizinhos. Noutra topologia o script que existe
# para comparar DENTRO do dominio compararia ENTRE dominios, com o rotulo
# errado -- e um numero certo por acidente de layout e um numero errado
# esperando outra maquina.
#
# Sao duas condicoes, e as duas importam:
#   - mesmo dominio de L3, que E a variavel do experimento;
#   - nucleo fisico distinto, senao a medicao troca distancia de cache por
#     disputa de unidades de execucao.
#
# As funcoes sao extraidas do arquivo real; copia-las deixaria este teste verde
# enquanto o script divergisse.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
fonte="$raiz/scripts/bench-ccd.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }

eval "$(sed -n '/^expandir() {/,/^}/p;/^irmaos_de() {/,/^}/p;/^parceiro_no_dominio() {/,/^}/p' "$fonte")"
for f in expandir irmaos_de parceiro_no_dominio; do
    declare -F "$f" >/dev/null || { echo "FALHA: nao extrai $f() de bench-ccd.sh"; exit 1; }
done

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
falhas=0
conferir() { # <descricao> <obtido> <esperado>
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}

# ---- expandir: as tres formas que o sysfs emite -------------------------
conferir "faixa"            "$(expandir '0-3')"        "0 1 2 3 "
conferir "lista de faixas"  "$(expandir '0-2,8-10')"   "0 1 2 8 9 10 "
conferir "cpu isolada"      "$(expandir '5')"          "5 "
conferir "mistura"          "$(expandir '0,4-6')"      "0 4 5 6 "

# ---- irmaos_de: o teste controla o sysfs --------------------------------
# A funcao le um caminho absoluto, entao a stub troca `cat` por uma que
# responde a partir do diretorio temporario. Sem isso o teste dependeria da
# topologia da maquina que o roda -- e a maquina de CI nao e a de referencia.
cat() { # shellcheck disable=SC2317
    case "$1" in
        */cpu0/topology/thread_siblings_list) echo "0,12" ;;
        */cpu6/topology/thread_siblings_list) echo "6,18" ;;
        */cpu9/topology/thread_siblings_list) echo "9" ;;
        *) command cat "$@" ;;
    esac
}

# ---- parceiro_no_dominio ------------------------------------------------
conferir "escolhe a proxima CPU do mesmo dominio" \
    "$(parceiro_no_dominio 0 '0-5,12-17')" "1"
conferir "funciona no segundo dominio" \
    "$(parceiro_no_dominio 6 '6-11,18-23')" "7"

# O CASO QUE A ARITMETICA ERRAVA: com o dominio comecando noutro numero,
# `A + 2` sai da lista. Aqui o dominio e `0,1,2,3` e o irmao de 0 e 12 -- que
# nem pertence a ele.
conferir "nao inventa CPU fora do dominio" \
    "$(parceiro_no_dominio 0 '0-1')" "1"

# NUCLEO FISICO DISTINTO: com o dominio reduzido ao par SMT, nao ha parceiro
# valido, e recusar e a resposta certa. Medir aqui compararia disputa por
# unidades de execucao e chamaria isso de distancia de cache.
rc=0; parceiro_no_dominio 0 '0,12' >/dev/null || rc=$?
conferir "recusa quando so resta o irmao SMT" "$rc" "1"

# SEM IRMAO SMT (sysfs devolve so a propria CPU), qualquer outra do dominio vale.
conferir "sem SMT, a proxima do dominio serve" \
    "$(parceiro_no_dominio 9 '9-11')" "10"

# SYSFS MUDO: `thread_siblings_list` ausente ou ilegivel.
#
# Este caso existe porque um mutante sobreviveu sem ele. `thread_siblings_list`
# SEMPRE inclui a propria CPU, entao a conferencia de irmao ja descarta `a` --
# e a guarda `[ "$c" = "$a" ]` parecia redundante. Ela so tem valor exatamente
# aqui: sem resposta do sysfs, a lista de irmaos fica vazia e o laco escolheria
# a PROPRIA CPU como parceiro, produzindo uma comparacao de um nucleo contra
# ele mesmo rotulada como "mesmo dominio".
conferir "com o sysfs mudo, nao escolhe a propria CPU" \
    "$(parceiro_no_dominio 77 '77-79')" "78"

unset -f cat

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 10 assercoes; parceiro escolhido por topologia, nao por A+2"
