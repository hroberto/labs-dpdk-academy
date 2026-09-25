#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L2 (integração) do tópico 01 — EAL de verdade.
#
# Diferente do L1 (lógica pura, sem DPDK), o L2 inicializa a EAL no processo e
# valida o CONTRATO DE LINHA DE COMANDO: quantos lcores a EAL cria, quantos
# argumentos ela consome, e como ela reage a uma opção inválida. Isso é conteúdo
# do tópico, não detalhe de teste — por isso o L2 exercita o binário como o
# estudante o executa, em vez de chamar rte_eal_init() de dentro de um framework.
#
# Cobre também os DOIS caminhos de falha da EAL, que se comportam de forma
# diferente: argumento desconhecido encerra o processo dentro da própria EAL,
# enquanto valor inválido devolve -1 e deixa o programa tratar.
#
# Roda sem hugepages e sem NIC: --no-huge com prefixo proprio.
#
# Uso: l2_run.sh <caminho-do-binario>
set -u

# O DPDK NAO REMOVE O DIRETORIO DE RUNTIME do --file-prefix ao encerrar, e
# ate 21/09/2026 nenhum runner L2 removia: 97 diretorios acumulados em
# /run/user/<uid>/dpdk/, cada um com config e os fbarray, em tmpfs. O sufixo
# e o PID DESTE script, entao o glob nao alcanca execucao alheia.
trap 'rm -rf "${XDG_RUNTIME_DIR:-/var/run}"/dpdk/academy_*_$$' EXIT
BIN=${1:?uso: l2_run.sh <caminho-do-binario>}
# `--no-huge` com prefixo proprio, e NAO `--in-memory --no-huge`.
#
# A combinacao anterior e rejeitada pelo DPDK 23.11: `--no-huge` liga
# `--legacy-mem` por dentro, e `--legacy-mem` e incompativel com `--in-memory`.
# A EAL responde "Option --legacy-mem is not compatible with --in-memory" e
# aborta. No 25.11 a restricao nao existe -- o defeito so aparecia na CI.
#
# O `--file-prefix` com $$ substitui o isolamento que `--in-memory` dava: sem
# ele, execucoes concorrentes disputam /run/user/*/dpdk/rte/config e uma falha
# com "Is another primary process running?".
EAL_ARGS=${EAL_ARGS:--l 0 --no-huge --file-prefix=academy_eal_$$}
falhas=0

# PULO PARCIAL: CONTADO E DECLARADO, e nao `exit 77`.
#
# O `exit 77` do topico 02 existe porque la o caminho INTEIRO ficava
# indisponivel -- sem duas CPUs nao ha o que testar, e o teste que saia com zero
# afirmava ter testado. Aqui o pulo e PARCIAL: algumas verificacoes nao rodam e
# as demais rodam de verdade. Sair 77 descartaria as que rodaram, e essas sao
# resultado.
#
# O que faltava era o pulo APARECER: um "PULADO" no meio da saida some entre
# dezenas de linhas verdes, e o resumo final dizia "todos os testes passaram"
# sem dizer quantos nao foram tentados. Agora o resumo conta.
pulados=0
pular() { echo "  PULADO - $1"; pulados=$((pulados + 1)); }

check() { if [ "$2" -eq 0 ]; then echo "  ok    - $1"; else echo "  FALHA - $1"; falhas=$((falhas + 1)); fi; }

# Guarda a ultima saida capturada, para poder mostra-la se algo falhar.
#
# POR QUE ISTO EXISTE: a primeira execucao desta suite na CI falhou com "EAL
# inicializa e reporta sucesso: FALHA" e MAIS NADA. O teste dizia qual asserção
# quebrou e escondia a razao -- a mensagem da EAL, que e justamente o que se
# precisa para diagnosticar. Um teste que falha sem mostrar a evidencia obriga
# quem investiga a reproduzir o ambiente, o que num runner de CI e caro.
ultima_saida=""
mostrar_diagnostico() {
    [ -n "$ultima_saida" ] || return 0
    echo ""
    echo "  --- saida do programa na ultima execucao (diagnostico) ---"
    sed 's/^/    | /' <<<"$ultima_saida"
}

saida=$("$BIN" $EAL_ARGS -- a b c 2>&1); rc=$?

ultima_saida="$saida"
check "codigo de saida 0" "$([ $rc -eq 0 ]; echo $?)"
grep -q "EAL initialised successfully" <<<"$saida"; check "EAL inicializa e reporta sucesso" $?
grep -q "DPDK version: DPDK" <<<"$saida"; check "rte_version() reportada" $?
grep -q "Lcores available: 1 " <<<"$saida"; check "'-l 0' resulta em exatamente 1 lcore" $?
grep -q "Arguments left for the application: 3" <<<"$saida"; check "argumentos apos '--' chegam a aplicacao" $?

# --- Os DOIS caminhos de falha, que não são o mesmo ---
#
# Isto merece explicação porque o teste anterior passava pelo motivo errado:
# verificava apenas "código != 0", que é verdade nos dois casos e não distingue
# nada. São mecanismos diferentes, e só um deles chega ao código da aplicação.
#
# 1. ARGUMENTO DESCONHECIDO: a EAL encerra o processo ela mesma, com código 234.
#    rte_eal_init() não retorna, então o tratamento de erro do programa NÃO roda.
#
#    CUIDADO DE PORTABILIDADE: o codigo 234 e a mensagem "unknown argument" vem
#    de `librte_argparse`, que so existe a partir do DPDK 24.03 -- conferido com
#    `strings`: a string esta em librte_argparse.so e nao em librte_eal.so. Numa
#    release anterior, o mesmo argumento sai com outro codigo e outra mensagem, e
#    afirmar 234 falharia em VERMELHO sem haver defeito no programa. Por isso as
#    duas assercoes especificas da argparse sao condicionais; a propriedade
#    ESTRUTURAL -- o ramo de erro da aplicacao NAO executa -- vale em qualquer
#    release e continua sendo exigida.
saida=$("$BIN" --opcao-inexistente 2>&1); rc=$?
ultima_saida="$saida"
if ldconfig -p 2>/dev/null | grep -q 'librte_argparse'; then
    check "opcao desconhecida encerra o processo com 234 (nao 1)" "$([ $rc -eq 234 ]; echo $?)"
    grep -q "unknown argument" <<<"$saida"; check "a EAL identifica o argumento desconhecido" $?
else
    pular "codigo 234 e mensagem da argparse (DPDK < 24.03 nesta maquina): 2 verificacoes"
fi
check "opcao desconhecida nao sai com sucesso" "$([ $rc -ne 0 ]; echo $?)"

# Esta tambem depende da release, e a primeira execucao na CI mostrou por que:
# COM argparse (>= 24.03) a EAL encerra o processo e o ramo de erro da aplicacao
# NAO roda; SEM argparse, rte_eal_init() devolve -1 e o ramo de erro RODA. Sao
# comportamentos opostos, e ambos corretos para a sua release. Afirmar so um
# deles falha em vermelho na outra.
if ldconfig -p 2>/dev/null | grep -q 'librte_argparse'; then
    ! grep -q "Error initialising the EAL" <<<"$saida"
    check "o ramo de erro da APLICACAO nao executa (a EAL encerra antes)" $?
else
    grep -q "Error initialising the EAL" <<<"$saida"
    check "o ramo de erro da APLICACAO executa (rte_eal_init devolveu -1)" $?
fi

# 2. ARGUMENTO VÁLIDO COM VALOR IMPOSSÍVEL: aí sim rte_eal_init() devolve -1, e
#    quem trata o erro é o programa. É o único ramo que exercita hello_dpdk.c.
saida=$("$BIN" -l 999 2>&1); rc=$?
ultima_saida="$saida"
check "lcore inexistente faz a aplicacao sair com codigo != 0" "$([ $rc -ne 0 ]; echo $?)"
grep -q "Error initialising the EAL" <<<"$saida"
check "o ramo de erro da APLICACAO executa nesse caso" $?

if [ $falhas -eq 0 ]; then
    if [ "$pulados" -eq 0 ]; then
        echo "L2: todos os testes passaram"
    else
        echo "L2: todos os testes passaram, com $pulados NAO TENTADO(S)"
    fi
else
    mostrar_diagnostico
    echo ""
    echo "L2: $falhas falha(s), $pulados pulo(s)"
    exit 1
fi
