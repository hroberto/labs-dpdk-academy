#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L2 do módulo 02 — o modelo multiprocesso da EAL, de verdade.
#
# Este é o único teste do projeto que sobe DOIS processos DPDK que compartilham
# memória. Ele valida o que nenhum teste em processo único consegue validar:
#
#   1. que o secundário encontra, pelo NOME, uma memzone que ele não criou;
#   2. que a região aparece no MESMO endereço virtual nos dois processos;
#   3. que o dado publicado de um lado é lido do outro sem cópia;
#   4. que a contagem de lacunas de sequência bate entre produtor e consumidor.
#
# REQUISITO DE AMBIENTE: memória compartilhada entre processos exige hugetlbfs
# com permissão de escrita. Nem --in-memory nem --no-huge servem — o primeiro
# desabilita o suporte a secundário por definição, e o segundo usa memória
# anônima, que o outro processo não consegue mapear. Onde faltar esse requisito
# o teste INFORMA e sai com 0: falta de privilégio no host não é defeito do
# código, e transformar isso em falha vermelha ensinaria a ignorar o teste.
#
# Uso: l2_multiprocesso.sh <feed-primario> <feed-secundario>
set -u

PRIMARIO=${1:?uso: l2_multiprocesso.sh <feed-primario> <feed-secundario>}
SECUNDARIO=${2:?uso: l2_multiprocesso.sh <feed-primario> <feed-secundario>}

# Prefixo único por execução: é ele que isola esta instância de qualquer outro
# processo DPDK na máquina. Sem isso, duas execuções simultâneas disputariam os
# mesmos arquivos de runtime.
PREFIXO="academia_l2_$$"
TOTAL=${DPDK_ACADEMY_TICKS:-20000}
LCORE_PRIMARIO=${LCORE_PRIMARIO:-0}
LCORE_SECUNDARIO=${LCORE_SECUNDARIO:-1}

SAIDA_P=$(mktemp) || exit 1
SAIDA_S=$(mktemp) || exit 1
pid_primario=""

limpar() {
    [ -n "$pid_primario" ] && kill "$pid_primario" 2>/dev/null
    wait "$pid_primario" 2>/dev/null
    rm -f "$SAIDA_P" "$SAIDA_S"
    rm -rf "${XDG_RUNTIME_DIR:-/var/run}/dpdk/${PREFIXO}" 2>/dev/null
    rm -f "/dev/hugepages/${PREFIXO}"* 2>/dev/null
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
    echo "  Este teste exige hugetlbfs compartilhado entre processos."
    echo "  Habilite-o com estes três comandos:"
    echo ""
    echo "    sudo mkdir -p /mnt/huge-academia"
    echo "    sudo mount -t hugetlbfs -o pagesize=2M,uid=\$(id -u) nodev /mnt/huge-academia"
    echo "    export DPDK_ACADEMY_HUGE_DIR=/mnt/huge-academia"
    echo ""
    echo "  Depois, rode novamente a suíte."
    echo "  Detalhes no README do módulo 02."
    echo ""
    echo "L3: pulado (ambiente sem memoria compartilhada entre processos)"
    # 77 = PULADO para o Meson, e nao sucesso. Sair com 0 fazia a suite reportar
    # OK com as NOVE verificacoes deste script nao avaliadas -- e no runner do
    # CI o requisito nunca existe, entao ele nunca verificou nada e sempre
    # apareceu verde.
    exit 77
}

echo "== L2: feed handler primario + assinante secundario =="
echo "  prefixo de runtime: $PREFIXO"
echo "  ticks: $TOTAL"
echo ""

# --- primário em segundo plano -------------------------------------------
# --huge-dir só é passado se a variável existir, para não quebrar máquinas em
# que /dev/hugepages já é gravável.
# Descobre o hugetlbfs em vez de exigir a variavel exportada a mao -- ver o
# porque em lib-hugetlbfs.sh. DPDK_ACADEMY_HUGE_DIR continua vencendo, quando
# definida, para permitir apontar uma montagem especifica.
# shellcheck source=lib-hugetlbfs.sh
. "$(dirname "$0")/lib-hugetlbfs.sh"
DPDK_ACADEMY_HUGE_DIR=$(descobrir_hugetlbfs)
export DPDK_ACADEMY_HUGE_DIR
EXTRA_EAL=${DPDK_ACADEMY_HUGE_DIR:+--huge-dir=$DPDK_ACADEMY_HUGE_DIR}
[ -n "$DPDK_ACADEMY_HUGE_DIR" ] && echo "  hugetlbfs: $DPDK_ACADEMY_HUGE_DIR"

# shellcheck disable=SC2086
timeout 90 "$PRIMARIO" -l "$LCORE_PRIMARIO" --file-prefix="$PREFIXO" --no-pci $EXTRA_EAL \
    -- "$TOTAL" cadencia >"$SAIDA_P" 2>&1 &
pid_primario=$!

# O secundário só pode subir depois de o primário ter criado os arquivos de
# runtime. Em vez de dormir um tempo fixo, espera o sinal no próprio log.
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
    wait "$pid_primario"
    rc=$?
    sed 's/^/    | /' "$SAIDA_P"
    [ $rc -ne 0 ] && pular "o primario encerrou antes de publicar (codigo $rc)"
fi

# --- secundário -----------------------------------------------------------
# Corelist distinta do primário: a documentação do DPDK exige que processos que
# compartilham memória não disputem os mesmos lcores.
# shellcheck disable=SC2086
timeout 90 "$SECUNDARIO" -l "$LCORE_SECUNDARIO" --file-prefix="$PREFIXO" --no-pci \
    --proc-type=secondary $EXTRA_EAL >"$SAIDA_S" 2>&1
rc_secundario=$?

wait "$pid_primario"
rc_primario=$?
pid_primario=""

if grep -q "EAL nao inicializou\|nao apareceu" "$SAIDA_S" 2>/dev/null && [ $rc_secundario -ne 0 ]; then
    sed 's/^/    | /' "$SAIDA_S"
    pular "o secundario nao conseguiu se anexar a memoria do primario"
fi

# --- verificações ---------------------------------------------------------
check "primario encerrou com codigo 0" "$([ $rc_primario -eq 0 ]; echo $?)"
check "secundario encerrou com codigo 0" "$([ $rc_secundario -eq 0 ]; echo $?)"

grep -q "tipo de processo\|processo secundario" "$SAIDA_S"
check "secundario se identificou como secundario" $?

# O mesmo endereço virtual dos dois lados é a propriedade central do modelo:
# é o que permite que estruturas em memória compartilhada sejam lidas como
# estruturas normais, sem tradução de offset.
end_p=$(grep -m1 "endereco virtual" "$SAIDA_P" | awk '{print $4}')
end_s=$(grep -m1 "endereco virtual" "$SAIDA_S" | awk '{print $4}')
[ -n "$end_p" ] && [ "$end_p" = "$end_s" ]
check "memzone no mesmo endereco virtual nos dois processos ($end_p / $end_s)" $?

grep -q "ticks aceitos ........... $TOTAL" "$SAIDA_S"
check "secundario aceitou os $TOTAL ticks publicados" $?

# O produtor injeta lacunas de sequência; o consumidor precisa contar as mesmas.
inj=$(grep -m1 "lacunas de sequencia injetadas" "$SAIDA_P" | grep -o '[0-9]\+' | head -1)
det=$(grep -m1 "lacunas detectadas" "$SAIDA_S" | grep -o '[0-9]\+' | head -1)
[ -n "$inj" ] && [ "$inj" = "$det" ]
check "lacunas detectadas ($det) batem com as injetadas ($inj)" $?

grep -q "publicacao -> observacao" "$SAIDA_S"
check "latencia de travessia entre processos foi medida" $?

# Livro cruzado (melhor compra >= melhor venda) e estado impossivel em mercado.
# Ja apareceu aqui, por misturar papeis num livro so: e uma trava contra a volta.
grep -q "livros cruzados ......... 0" "$SAIDA_S"
check "nenhum livro cruzado" $?

# Encerramento ordenado: o primario e dono da memoria e do socket de controle,
# entao sai por ultimo. Ruido de IPC no fim significa ordem errada.
! grep -qE "Fail to recv reply|Could not send sync request|Cannot send message to primary" \
    "$SAIDA_P" "$SAIDA_S"
check "encerramento sem erro de comunicacao entre processos" $?

echo ""
echo "  --- saida do secundario ---"
sed 's/^/    | /' "$SAIDA_S"

if [ $falhas -eq 0 ]; then
    echo "L2: todos os testes passaram"
else
    echo "L2: $falhas falha(s)"
    echo "  --- saida do primario ---"
    sed 's/^/    | /' "$SAIDA_P"
    exit 1
fi
