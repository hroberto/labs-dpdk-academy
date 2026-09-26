#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# O contrato de linha de comando do `stall_probe`: converte, confere a faixa,
# ou recusa.
#
# Uso: l1_stall_probe_cli.sh <binario>
#
# POR QUE ESTE TESTE EXISTE
#
# Duas classes distintas, e o programa errava nas duas.
#
# LIXO QUE VIRA NUMERO VALIDO. `atoi("abc")` devolve 0, e zero e uma CPU
# legitima: a guarda `cpu < 0` nao pegava nada. Medido antes: `stall_probe abc 1`
# media a CPU 0, imprimia "cpu 0" e saia com 0.
#
# NUMERO VALIDO FORA DO DOMINIO. `1e30` passa por todas as conferencias de um
# `double` -- nao e lixo, nao e parcial, nao e NaN nem infinito -- e depois
# `(uint64_t)(segundos * 1e9)` com esse valor e comportamento INDEFINIDO: nao
# cabe no tipo. Medido antes: era aceito, anunciando
# "1000000000000000019884624838656.0 s".
#
# Ser sintaticamente um numero nao e pertencer ao dominio da operacao, e e
# essa a fronteira que estes casos fixam.
set -u
bin=${1:?uso: $0 <binario>}
[ -x "$bin" ] || { echo "  FALHA: $bin nao e executavel"; exit 1; }
falhas=0

recusa() { # <descricao> <argumentos...>
    local descricao=$1; shift
    local rc=0
    timeout 20 "$bin" "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 124 ]; then
        echo "  FALHA: $descricao -- NAO TERMINOU (deveria recusar de imediato)"
        falhas=$((falhas + 1))
    elif [ "$rc" -ne 2 ]; then
        echo "  FALHA: $descricao -- esperava rc=2, obteve $rc"
        falhas=$((falhas + 1))
    fi
}

aceita() { # <descricao> <argumentos...>
    local descricao=$1; shift
    local rc=0
    timeout 40 "$bin" "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "  FALHA: $descricao -- esperava rc=0, obteve $rc"
        falhas=$((falhas + 1))
    fi
}

# ---- a CPU: lixo nao pode virar a CPU 0 ---------------------------------
recusa "cpu 'abc'"            abc 1
recusa "cpu '2x' (parcial)"   2x 1
recusa "cpu negativa"         -1 1
recusa "cpu acima da faixa"   99999 1

# ---- a DURACAO: faixa faz parte do contrato -----------------------------
recusa "segundos 'xyz'"       0 xyz
recusa "segundos '1.5s'"      0 1.5s
recusa "segundos zero"        0 0
recusa "segundos negativo"    0 -1
recusa "segundos 'nan'"       0 nan
# O CASO DO TRANSBORDO, que motivou o teto. Sem a guarda, a conversao para
# nanossegundos fica fora da faixa de uint64_t.
recusa "segundos 1e30"        0 1e30
recusa "segundos 86401 (um segundo acima do teto)" 0 86401

# ---- o LIMIAR ------------------------------------------------------------
recusa "limiar 'abc'"         0 1 abc
recusa "limiar negativo"      0 1 -1

# ---- a CPU do provocador -------------------------------------------------
# A SONDA VAI NA CPU 1, E NAO NA 0, DE PROPOSITO.
#
# Com a sonda em 0, `atoi("abc")` daria 0 e o programa recusaria por OUTRA
# guarda -- "provoker CPU must differ from probe CPU" --, devolvendo o mesmo
# rc=2 com ou sem a conferencia de conversao. Medido: o mutante que troca
# `academy_arg_int` por `atoi` SOBREVIVIA a este caso. Com a sonda em 1, o
# zero de `atoi` seria uma CPU valida e distinta, e so a conferencia pega.
recusa "provocador 'abc'"     1 1 1000 abc
recusa "provocador acima da faixa" 1 1 1000 99999

# ---- E O CAMINHO VALIDO CONTINUA MEDINDO.
# Um teste que so recusa aprovaria um programa que recusa sempre; e o teto
# precisa ser INCLUSIVO, senao a guarda estaria um a menos.
aceita "duracao curta e valida"  0 1
aceita "limiar explicito"        0 1 2000

# O TETO E INCLUSIVO, e provar isso sem esperar um dia exige outra tatica.
#
# Rodar com 86400 mediria por 24 h. O que interessa nao e a medicao, e sim que
# o programa NAO recuse na conferencia de faixa: ele e interrompido logo apos
# comecar, e o veredito e a AUSENCIA da mensagem de teto. Sem este caso, trocar
# `>` por `>=` sobrevivia -- medido.
saida=$(mktemp); trap 'rm -f "$saida"' EXIT
timeout 3 "$bin" 0 86400 > "$saida" 2>&1
if grep -q "above the accepted ceiling" "$saida"; then
    echo "  FALHA: 86400 recusado, mas o teto e inclusivo"
    falhas=$((falhas + 1))
fi
# E o de cima do teto TEM de trazer a mensagem, senao a assercao acima
# passaria tambem num programa que nunca a imprime.
timeout 5 "$bin" 0 86401 > "$saida" 2>&1
if ! grep -q "above the accepted ceiling" "$saida"; then
    echo "  FALHA: 86401 devia ser recusado pelo teto, com a razao dita"
    falhas=$((falhas + 1))
fi

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 19 casos; converte, confere a faixa (inclusive no teto), ou recusa"
