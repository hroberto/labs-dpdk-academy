#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L2 (integração) da alternativa C++23.
#
# Aqui não há EAL: "integração" significa exercitar o binário de ponta a ponta.
# O valor didático está nas duas primeiras asserções, que repetem EXATAMENTE o
# contrato verificado no L2 da versão DPDK (10 pacotes, 695 bytes). É isso que
# torna a comparação entre as duas implementações honesta: mesma entrada, mesma
# saída esperada, arquiteturas diferentes.
#
# Uso: l2_run.sh <caminho-do-binario>
set -u
BIN=${1:?uso: l2_run.sh <caminho-do-binario>}
falhas=0

check() { if [ "$2" -eq 0 ]; then echo "  ok    - $1"; else echo "  FALHA - $1"; falhas=$((falhas + 1)); fi; }

saida=$("$BIN" -n 10 2>&1); rc=$?
check "n=10: codigo de saida 0" "$([ $rc -eq 0 ]; echo $?)"
grep -q "^Pacotes processados: 10$" <<<"$saida"; check "n=10: processa exatamente 10 pacotes" $?
grep -q "^Total de bytes: 695$" <<<"$saida"; check "n=10: 695 bytes (mesmo contrato da versao DPDK)" $?

saida=$("$BIN" -n 100000 -b 64 2>&1); rc=$?
check "n=100000 b=64: codigo de saida 0" "$([ $rc -eq 0 ]; echo $?)"
grep -q "^Pacotes processados: 100000$" <<<"$saida"; check "n=100000: contagem exata" $?
grep -q "^Lote (burst): 64 " <<<"$saida"; check "n=100000: tamanho de lote aplicado" $?

# --- Modo de dois nucleos (-c): o espelho do `-l 0,N` da versao DPDK -------
#
# Existe para que o nivel 2 da comparacao tenha os dois lados medidos. O que se
# exige aqui e o mesmo do lado DPDK: mudar a colocacao e decisao de desempenho,
# NUNCA de semantica -- o resultado tem de ser identico ao de um thread.
CPUS=$(nproc 2>/dev/null || echo 1)
if [ "$CPUS" -lt 3 ]; then
    echo "  PULADO - modo de dois nucleos (maquina com $CPUS CPU)"
else
    saida=$("$BIN" -n 10 -c 2 2>&1); rc=$?
    check "2 threads: codigo de saida 0" "$([ $rc -eq 0 ]; echo $?)"
    grep -q "^Pacotes processados: 10$" <<<"$saida"; check "2 threads: mesma contagem de 1 thread" $?
    grep -q "^Total de bytes: 695$" <<<"$saida";     check "2 threads: mesmos 695 bytes" $?
    grep -q "^Modo: 2 threads" <<<"$saida";          check "2 threads: modo reportado" $?

    # Volume alto: e onde um erro de ordenacao no anel apareceria como pacote
    # perdido. Com 200k o anel de 1024 da mais de 190 voltas.
    saida=$("$BIN" -n 200000 -b 32 -c 2 2>&1)
    grep -q "^Pacotes processados: 200000$" <<<"$saida"
    check "2 threads: 200k pacotes sem perda entre nucleos" $?

    # REPETICAO CURTA: a corrida de ENCERRAMENTO so aparece com poucos pacotes,
    # quando produtor e consumidor terminam quase juntos -- e aparecia em uma
    # execucao a cada muitas, o que a tornava invisivel num teste unico.
    #
    # O defeito: o consumidor lia "anel vazio" com `cauda_` defasado e, so
    # depois, "produtor terminou" atualizado -- e saia deixando pacotes. Foi
    # encontrado porque a suite roda em PARALELO, e a contencao de CPU alargou a
    # janela. Um teste que roda sozinho nao o encontraria.
    perdidos=0
    for _ in $(seq 1 40); do
        n=$("$BIN" -n 10 -c 2 2>/dev/null | sed -n 's/^Pacotes processados: //p')
        [ "$n" = "10" ] || perdidos=$((perdidos + 1))
    done
    [ "$perdidos" -eq 0 ]
    check "2 threads: 40 execucoes curtas sem perder pacote no encerramento" $?
fi

"$BIN" -b 0 >/dev/null 2>&1; check "lote 0 e rejeitado"          "$([ $? -ne 0 ]; echo $?)"
"$BIN" --x >/dev/null 2>&1;  check "opcao desconhecida e rejeitada" "$([ $? -ne 0 ]; echo $?)"

if [ $falhas -eq 0 ]; then echo "L2: todos os testes passaram"; else echo "L2: $falhas falha(s)"; exit 1; fi
