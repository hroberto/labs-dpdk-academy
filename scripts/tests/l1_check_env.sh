#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L1 do veredito de hugepages do `check-env.sh`.
#
# POR QUE ESTE TESTE EXISTE
#
# `check-env.sh` é a primeira coisa que alguém roda neste projeto, e por muito
# tempo ele relatou os dois fatos das hugepages SEPARADOS, sem tirar a conclusão:
#
#     ok    - 1024 hugepages de 2048 kB reservadas (1024 livres)
#     info  - /dev/hugepages montado (root:root drwxr-xr-x)
#
# As duas linhas parecem boas. O leitor segue em frente, e só descobre o problema
# quando os testes L3 pulam, muito depois — porque para o DPDK multiprocesso são
# necessárias as duas coisas AO MESMO TEMPO: páginas reservadas E um ponto
# `hugetlbfs` gravável pelo usuário. Reservada não é utilizável.
#
# O veredito foi acrescentado. Este teste existe para que ele não suma nem
# passe a mentir, e confere DUAS coisas:
#
#   1. que existe veredito -- a regressão de voltar a relatar fatos soltos sem
#      conclusão é acusada;
#   2. que o veredito CORRESPONDE à máquina -- o teste re-apura a condição por
#      conta própria e compara. Um veredito que sempre diz "pode rodar" passaria
#      no item 1 e falha aqui.
#
# É L1 porque não precisa de EAL, de DPDK nem de privilégio: lê `/proc/meminfo`,
# a tabela de montagem, e compara com o que o script afirmou.
set -u

RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
falhas=0
check() {
    if [ "$2" -eq 0 ]; then echo "  ok    - $1"
    else echo "  FALHA - $1"; falhas=$((falhas + 1)); fi
}

echo "== L1: o veredito de hugepages do check-env =="

# --- 0. A DECISAO, exercitada nos DOIS ramos --------------------------------
#
# Esta parte existe por causa de um mutante equivalente. Enquanto a decisao vivia
# embutida no check-env.sh, trocá-la por "sempre NAO" era indistinguivel do
# codigo certo NESTA maquina, onde a resposta e NAO. Recebendo o estado como
# argumento, os dois ramos passam a ser exercitaveis em qualquer lugar.
# shellcheck source=../lib-hugepages.sh
. "$RAIZ/scripts/lib-hugepages.sh"

hugepages_veredito 1024 /mnt/huge; check "reservadas E ponto gravavel -> L3 pode rodar" $?
hugepages_veredito 1024 "";        check "reservadas SEM ponto gravavel -> recusa" "$([ $? -ne 0 ]; echo $?)"
grep -qi "reservada nao e utilizavel" <<<"$_HUGE_MOTIVO"
check "e o motivo nomeia a distincao que o caso exige" $?
hugepages_veredito 0 /mnt/huge;    check "ponto gravavel SEM reserva -> recusa" "$([ $? -ne 0 ]; echo $?)"
hugepages_veredito 0 "";           check "nada de nada -> recusa" "$([ $? -ne 0 ]; echo $?)"
hugepages_veredito "" /mnt/huge;   check "total NAO APURADO -> recusa (nao vira zero)" "$([ $? -ne 0 ]; echo $?)"
grep -qi "nao apurado" <<<"$_HUGE_MOTIVO"
check "e o motivo distingue nao-apurado de zero" $?

saida=$(cd "$RAIZ" && bash scripts/check-env.sh 2>&1) || true

# --- 1. o veredito existe, e é UM só ---------------------------------------
pode=$(grep -c "L3 pode rodar" <<<"$saida")
nao_pode=$(grep -c "L3 NAO pode rodar" <<<"$saida")
[ $((pode + nao_pode)) -eq 1 ]
check "emite exatamente um veredito sobre L3 (encontrados: $pode positivo, $nao_pode negativo)" $?

# --- 2. o veredito corresponde à máquina ------------------------------------
#
# Re-apuração independente: o teste não confia no script, refaz a conta.
total=$(awk '/HugePages_Total/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
gravavel=""
while read -r ponto; do
    [ -n "$ponto" ] || continue
    [ -w "$ponto" ] && gravavel=$ponto
done <<EOF
$(mount 2>/dev/null | awk '$5 == "hugetlbfs" { print $3 }')
EOF

if [ "${total:-0}" -gt 0 ] && [ -n "$gravavel" ]; then
    esperado="pode"
else
    esperado="nao_pode"
fi

if [ "$esperado" = "pode" ]; then
    [ "$pode" -eq 1 ]
    check "a maquina TEM hugepage utilizavel e o veredito diz que L3 pode rodar" $?
else
    [ "$nao_pode" -eq 1 ]
    check "a maquina NAO tem hugepage utilizavel e o veredito diz que L3 nao pode" $?
fi

# --- 3. quando recusa, aponta a saida --------------------------------------
#
# Diagnóstico sem conserto é meio diagnóstico. A frase que importa é a do
# comando, e ela precisa citar o script que resolve.
if [ "$nao_pode" -eq 1 ]; then
    grep -q "preparar-hugepages.sh" <<<"$saida"
    check "ao recusar, aponta scripts/preparar-hugepages.sh" $?
    grep -q "PULAM" <<<"$saida"
    check "ao recusar, diz que os L3 PULAM (e nao falham)" $?
else
    echo "  info  - esta maquina tem hugepage utilizavel; o ramo de recusa nao foi exercitado"
fi

# --- 4. a distincao que o veredito existe para fazer -------------------------
#
# "Reservada" e "utilizavel" precisam aparecer como coisas diferentes. Se o
# script voltar a tratar reserva como suficiente, esta assercao cai.
if [ "${total:-0}" -gt 0 ] && [ -z "$gravavel" ]; then
    grep -qiE "Reservada nao e utilizavel|NENHUM ponto hugetlbfs" <<<"$saida"
    check "com paginas reservadas e nenhuma gravavel, explica a distincao" $?
fi

echo ""
if [ $falhas -eq 0 ]; then
    echo "L1: todos os testes passaram"
else
    echo "L1: $falhas falha(s)"
    exit 1
fi
