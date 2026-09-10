#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L3 do módulo 02 — EIXO DE FALHA (ROADMAP, Etapa 7.5).
#
# A pergunta: o que acontece quando o processo primário MORRE com secundários
# ainda vivos?
#
# O teste `l3_multiprocesso.sh` valida o caminho feliz: o secundário encontra a
# memzone, lê no mesmo endereço virtual, conta as mesmas lacunas. Este aqui
# derruba o primário no meio e observa o que sobra.
#
# A RESPOSTA QUE ESTE TESTE DOCUMENTA
#
# Nada avisa o secundário. Não há batimento cardíaco, não há contrato de
# liveness, não há sinal. A memória compartilhada continua mapeada e legível,
# porque as páginas do hugetlbfs sobrevivem ao processo que as criou enquanto
# alguém as mantiver mapeadas. O secundário simplesmente continua lendo — e o
# que ele lê é o ÚLTIMO estado publicado, para sempre.
#
# Em feed-secundario.c isso aparece como `while (lidos < total)` (linha 126):
# um laço que espera dados que nunca mais virão. O processo não trava por
# defeito; ele espera correta e indefinidamente por um produtor que não existe
# mais. É a diferença entre "parou de funcionar" e "parou de receber", e do
# lado de fora as duas parecem iguais.
#
# POR QUE ISSO IMPORTA MAIS QUE UM CRASH
#
# Um crash é observável. Um consumidor que serve dados velhos com aparência de
# dados novos não é — e num servidor de market data, agir sobre um livro de
# ofertas congelado é pior do que não agir. Detectar isso é responsabilidade da
# APLICAÇÃO: número de sequência, timestamp de publicação, watchdog. O DPDK não
# oferece nenhum dos três.
#
# REQUISITO DE AMBIENTE: o mesmo do l3_multiprocesso.sh — hugetlbfs gravável.
# Onde faltar, sai com 77 (PULADO), nunca com 0.
#
# Uso: l3_primario_morre.sh <feed-primario> <feed-secundario>
set -u

PRIMARIO=${1:?uso: l3_primario_morre.sh <feed-primario> <feed-secundario>}
SECUNDARIO=${2:?uso: l3_primario_morre.sh <feed-primario> <feed-secundario>}

PREFIXO="academia_morte_$$"
# Alto de propósito: o primário precisa continuar publicando quando for morto,
# senão o teste mediria um encerramento normal.
TOTAL=${DPDK_ACADEMY_TICKS:-4000000}
LCORE_PRIMARIO=${LCORE_PRIMARIO:-0}
LCORE_SECUNDARIO=${LCORE_SECUNDARIO:-1}
# Quanto tempo damos ao secundário para perceber sozinho que o primário morreu.
# A tese do teste é que ele NUNCA percebe; a espera existe para dar chance.
ESPERA_S=${DPDK_ACADEMY_ESPERA:-5}

SAIDA_P=$(mktemp) || exit 1
SAIDA_S=$(mktemp) || exit 1
pid_primario=""
pid_secundario=""

limpar() {
    [ -n "$pid_secundario" ] && kill -9 "$pid_secundario" 2>/dev/null
    [ -n "$pid_primario" ] && kill -9 "$pid_primario" 2>/dev/null
    wait 2>/dev/null
    rm -f "$SAIDA_P" "$SAIDA_S"
    rm -rf "${XDG_RUNTIME_DIR:-/var/run}/dpdk/${PREFIXO}" 2>/dev/null
    rm -f "/dev/hugepages/${PREFIXO}"* 2>/dev/null
    [ -n "${DPDK_ACADEMY_HUGE_DIR:-}" ] && rm -f "${DPDK_ACADEMY_HUGE_DIR}/${PREFIXO}"* 2>/dev/null
    return 0
}
trap limpar EXIT

falhas=0
check() {
    if [ "$2" -eq 0 ]; then
        echo "  ok    - $1"
    else
        echo "  FALHA - $1"
        falhas=$((falhas + 1))
    fi
}

pular() {
    echo "  PULADO - $1"
    echo ""
    echo "  Este teste exige hugetlbfs compartilhado entre processos, igual ao"
    echo "  l3_multiprocesso.sh. Habilite com:"
    echo ""
    echo "    sudo ./scripts/preparar-hugepages.sh"
    echo "    export DPDK_ACADEMY_HUGE_DIR=/mnt/huge-academia"
    echo ""
    echo "L3: pulado (ambiente sem memoria compartilhada entre processos)"
    exit 77
}

echo "== L3: o primario morre, o secundario continua =="
echo "  prefixo de runtime: $PREFIXO"
echo ""

# Descobre o hugetlbfs em vez de exigir a variavel exportada a mao -- ver o
# porque em lib-hugetlbfs.sh. DPDK_ACADEMY_HUGE_DIR continua vencendo, quando
# definida, para permitir apontar uma montagem especifica.
# shellcheck source=lib-hugetlbfs.sh
. "$(dirname "$0")/lib-hugetlbfs.sh"
DPDK_ACADEMY_HUGE_DIR=$(descobrir_hugetlbfs)
export DPDK_ACADEMY_HUGE_DIR
EXTRA_EAL=${DPDK_ACADEMY_HUGE_DIR:+--huge-dir=$DPDK_ACADEMY_HUGE_DIR}
[ -n "$DPDK_ACADEMY_HUGE_DIR" ] && echo "  hugetlbfs: $DPDK_ACADEMY_HUGE_DIR"

# --- 1. primário publicando -----------------------------------------------
# shellcheck disable=SC2086
"$PRIMARIO" -l "$LCORE_PRIMARIO" --file-prefix="$PREFIXO" --no-pci $EXTRA_EAL \
    -- "$TOTAL" cadencia >"$SAIDA_P" 2>&1 &
pid_primario=$!

for _ in $(seq 1 100); do
    grep -q "aguardando o assinante conectar" "$SAIDA_P" 2>/dev/null && break
    kill -0 "$pid_primario" 2>/dev/null || break
    sleep 0.2
done

if grep -q "EAL nao inicializou" "$SAIDA_P" 2>/dev/null; then
    sed 's/^/    | /' "$SAIDA_P"
    pular "a EAL nao subiu com memoria compartilhada real"
fi
if ! kill -0 "$pid_primario" 2>/dev/null; then
    sed 's/^/    | /' "$SAIDA_P"
    pular "o primario encerrou antes de publicar"
fi

# --- 2. secundário anexado -------------------------------------------------
# shellcheck disable=SC2086
"$SECUNDARIO" -l "$LCORE_SECUNDARIO" --file-prefix="$PREFIXO" --no-pci \
    --proc-type=secondary $EXTRA_EAL >"$SAIDA_S" 2>&1 &
pid_secundario=$!

for _ in $(seq 1 100); do
    grep -qE "endereco virtual|processo secundario|tipo de processo" "$SAIDA_S" 2>/dev/null && break
    kill -0 "$pid_secundario" 2>/dev/null || break
    sleep 0.2
done

if ! kill -0 "$pid_secundario" 2>/dev/null; then
    sed 's/^/    | /' "$SAIDA_S"
    pular "o secundario nao conseguiu se anexar a memoria do primario"
fi
check "secundario anexou-se a memoria do primario" 0

# --- 3. a morte ------------------------------------------------------------
# SIGKILL, e não SIGTERM: queremos morte súbita, sem chance de encerramento
# ordenado. É o caso ruim -- OOM killer, falha de hardware, `kill -9` de um
# operador apressado.
echo ""
echo "  matando o primario (SIGKILL, sem encerramento ordenado)..."
kill -9 "$pid_primario" 2>/dev/null
wait "$pid_primario" 2>/dev/null
rc_primario=$?
pid_primario=""
check "primario morreu por sinal (codigo $rc_primario, esperado != 0)" \
    "$([ $rc_primario -ne 0 ]; echo $?)"

# --- 4. o que sobra --------------------------------------------------------
sleep "$ESPERA_S"

if kill -0 "$pid_secundario" 2>/dev/null; then
    vivo=0
else
    vivo=1
fi

# A tese: o secundário continua VIVO, sem erro, esperando dados que não virão.
check "secundario sobreviveu a morte do primario (nao houve segfault)" "$vivo"

if [ "$vivo" -eq 0 ]; then
    check "secundario NAO detectou a morte apos ${ESPERA_S}s: segue esperando" 0
    ! grep -qiE "primario morreu|produtor ausente|conexao perdida|peer.*(dead|gone)" "$SAIDA_S"
    check "secundario nao emitiu nenhum aviso de produtor ausente" $?
    ! grep -q "ticks aceitos" "$SAIDA_S"
    check "secundario nao concluiu: ficou no laco 'while (lidos < total)'" $?

    kill -9 "$pid_secundario" 2>/dev/null
    wait "$pid_secundario" 2>/dev/null
    pid_secundario=""
    check "so um sinal externo encerra o secundario" 0
else
    wait "$pid_secundario" 2>/dev/null
    rc_s=$?
    pid_secundario=""
    echo "  nota: o secundario encerrou sozinho com codigo $rc_s."
    sed 's/^/    | /' "$SAIDA_S"
    check "secundario encerrou sozinho -- a tese deste teste precisa de revisao" 1
fi

echo ""
echo "  Conclusao: a memoria compartilhada sobrevive ao dono, e nada avisa quem"
echo "  a le. Detectar produtor ausente e responsabilidade da APLICACAO --"
echo "  sequencia, timestamp de publicacao, watchdog. O DPDK nao oferece nenhum."

if [ $falhas -eq 0 ]; then
    echo ""
    echo "L3: todos os testes passaram"
else
    echo ""
    echo "L3: $falhas falha(s)"
    exit 1
fi
