#!/usr/bin/env bash
# L2 — a sonda de paradas roda e relata de forma coerente.
#
# NAO AFIRMA NADA SOBRE O VALOR DAS PARADAS. Esse valor depende da maquina e e
# o objeto da medicao; um teste que exigisse um limite viraria uma medicao
# disfarcada de asserção, e falharia em maquina carregada por motivo certo.
#
# O que se verifica e o CONTRATO: a sonda mede, classifica, relata a janela, e
# diz explicitamente quando /proc/interrupts nao esta legivel em vez de calar.
set -euo pipefail
BIN=${1:?uso: l2_run.sh <stall_probe>}
out=$(mktemp)
trap 'rm -f "$out"' EXIT

falhas=0
check() { # <descricao> <status>
    if [ "$2" -eq 0 ]; then echo "  ok - $1"; else echo "  FALHA - $1"; falhas=$((falhas+1)); fi
}

"$BIN" 0 0.2 1000 >"$out" 2>&1
check "codigo de saida 0" $?

grep -q "^samples: [0-9]" "$out"; check "relatou numero de amostras" $?
grep -q "^max stall: [0-9]* ns" "$out"; check "relatou a maior parada" $?
grep -q "^p99.9 floor: [0-9]* ns" "$out"; check "relatou o piso do p99,9" $?

# A janela e aritmetica, nao medicao: tem de sair igual em qualquer maquina.
grep -q "512 descriptors: 34.4 us" "$out"
check "janela de 512 descritores confere com a aritmetica" $?

# A leitura de /proc/interrupts ou traz vetores, ou diz que nao conseguiu.
# Silencio nao e opcao aceitavel.
grep -qE "interrupts on cpu 0 (during the run|: UNAVAILABLE)" "$out"
check "relatou interrupcoes ou declarou indisponivel" $?

# Parametro invalido tem de ser recusado, com codigo distinto de erro de execucao.
rc=0; "$BIN" 0 0 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]; check "duracao zero recusada com codigo 2" $?

rc=0; "$BIN" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ]; check "sem argumentos recusado com codigo 2" $?

[ "$falhas" -eq 0 ]
