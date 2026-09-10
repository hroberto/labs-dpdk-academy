#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Prepara um hugetlbfs gravável pelo usuário, para os exercícios de
# MULTIPROCESSO do módulo 02.
#
# POR QUE ISTO É NECESSÁRIO
#
# Quase todo o projeto roda sem privilégio, com --in-memory ou --no-huge. O
# modelo primário/secundário é a exceção, e a razão é estrutural: um processo
# secundário se anexa às MESMAS páginas físicas que o primário reservou, e o
# mecanismo que permite isso são arquivos em hugetlbfs. Sem eles não há o que
# mapear:
#
#   --in-memory  usa memória anônima com memfd e DESLIGA o suporte a secundário
#                (a própria ajuda da EAL diz isso).
#   --no-huge    usa memória anônima comum, que o outro processo não mapeia:
#                o secundário falha com "Cannot init memory".
#
# Em muitas distribuições /dev/hugepages pertence a root com modo 0755, e um
# usuário comum não consegue criar arquivo lá. Rodar tudo como root resolveria,
# e é o que a maior parte do material da web recomenda — mas dar root a um
# processo de plano de dados por causa de uma permissão de diretório é trocar um
# problema pequeno por um grande.
#
# Este script faz o mínimo: monta UM hugetlbfs adicional, com dono definido, sem
# alterar /dev/hugepages e sem tocar em nada do sistema. Para desfazer, basta
# desmontar — nenhuma alteração é persistente.
#
# QUEM É O "USUÁRIO", QUANDO O SCRIPT RODA COMO ROOT
#
# Este ponto já causou uma execução inútil e merece estar explícito. Rodado com
# sudo ou como root, perguntar "eu consigo escrever em /dev/hugepages?" responde
# a pergunta ERRADA: root sempre consegue, e o script concluiria que não há nada
# a fazer — deixando o usuário comum exatamente como estava. O alvo é sempre
# quem vai EXECUTAR os exercícios, não quem executa este script.
#
# Uso:
#   ./scripts/preparar-hugepages.sh              # monta para você
#   sudo ./scripts/preparar-hugepages.sh         # monta para $SUDO_USER
#   DPDK_ACADEMY_USUARIO=fulano sudo ./scripts/preparar-hugepages.sh
#   ./scripts/preparar-hugepages.sh --desfazer   # desmonta
set -u

PONTO=${DPDK_ACADEMY_HUGE_DIR:-/mnt/huge-academia}
TAMANHO_PAGINA=${TAMANHO_PAGINA:-2M}

# Usuário-alvo: quem vai rodar os exercícios.
#   1. DPDK_ACADEMY_USUARIO, se declarado
#   2. SUDO_USER, quando o script foi chamado por sudo
#   3. o usuário atual
ALVO=${DPDK_ACADEMY_USUARIO:-${SUDO_USER:-$(id -un)}}

if ! id "$ALVO" >/dev/null 2>&1; then
    echo "Usuario alvo '$ALVO' nao existe. Informe com DPDK_ACADEMY_USUARIO=<usuario>." >&2
    exit 1
fi
ALVO_UID=$(id -u "$ALVO")
ALVO_GID=$(id -g "$ALVO")

if [ "$ALVO_UID" = "0" ]; then
    echo "AVISO: o usuario alvo e o root." >&2
    echo "  Este script existe para EVITAR rodar plano de dados como root." >&2
    echo "  Informe o usuario real: DPDK_ACADEMY_USUARIO=<usuario> $0" >&2
    exit 1
fi

# Executa um comando COMO O ALVO. É assim que se testa a permissão dele, e não
# a de quem chamou o script.
como_alvo() {
    if [ "$(id -u)" = "$ALVO_UID" ]; then
        "$@"
    elif command -v runuser >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
        runuser -u "$ALVO" -- "$@"
    else
        sudo -n -u "$ALVO" "$@" 2>/dev/null || sudo -u "$ALVO" "$@"
    fi
}

# sudo só é necessário quando ainda não somos root.
elevar() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

if [ "${1:-}" = "--desfazer" ]; then
    if mountpoint -q "$PONTO" 2>/dev/null; then
        echo "Desmontando $PONTO..."
        elevar umount "$PONTO" && elevar rmdir "$PONTO" 2>/dev/null
        echo "Feito. Nada permanente foi alterado no sistema."
    else
        echo "$PONTO nao esta montado. Nada a fazer."
    fi
    exit 0
fi

echo "== Preparacao de hugepages para os exercicios de multiprocesso =="
echo ""
echo "  executando como ....... $(id -un)"
echo "  usuario alvo .......... $ALVO (uid $ALVO_UID)"
echo ""

# 1. Existem hugepages reservadas no kernel?
total=$(awk '/^HugePages_Total:/{print $2}' /proc/meminfo)
livres=$(awk '/^HugePages_Free:/{print $2}' /proc/meminfo)
tamanho=$(awk '/^Hugepagesize:/{print $2}' /proc/meminfo)
echo "  hugepages reservadas .. $total (livres: $livres, de $tamanho kB cada)"

if [ "${total:-0}" -eq 0 ]; then
    echo ""
    echo "  Nenhuma hugepage reservada. Reserve antes de continuar, por exemplo:"
    echo "    sudo sysctl -w vm.nr_hugepages=1024      # 1024 x 2 MB = 2 GiB"
    echo ""
    echo "  Para tornar permanente, veja 'vm.nr_hugepages' em /etc/sysctl.conf,"
    echo "  ou reserve na linha de comando do kernel (hugepages=1024)."
    exit 1
fi

# 2. /dev/hugepages ja serve PARA O ALVO? Note o "para o alvo": testar com
#    [ -w ] enquanto root responderia sempre que sim.
if como_alvo test -w /dev/hugepages 2>/dev/null; then
    echo "  /dev/hugepages ........ gravavel por $ALVO"
    echo ""
    echo "  Nenhuma montagem adicional e necessaria: rode os exercicios direto,"
    echo "  como $ALVO e sem --huge-dir."
    exit 0
fi

echo "  /dev/hugepages ........ NAO gravavel por $ALVO ($(stat -c '%A %U:%G' /dev/hugepages))"
echo ""

if mountpoint -q "$PONTO" 2>/dev/null && como_alvo test -w "$PONTO" 2>/dev/null; then
    echo "  $PONTO ja esta montado e gravavel por $ALVO."
else
    echo "  Vou montar um hugetlbfs proprio em $PONTO, com dono $ALVO."
    echo "  Isto NAO e permanente: some no proximo reinicio."
    echo ""
    elevar mkdir -p "$PONTO" || exit 1
    elevar mount -t hugetlbfs \
        -o "pagesize=$TAMANHO_PAGINA,uid=$ALVO_UID,gid=$ALVO_GID,mode=0700" \
        nodev "$PONTO" || {
        echo "  Falha ao montar. Verifique se o kernel tem suporte a hugetlbfs."
        exit 1
    }
    echo "  Montado."

    if ! como_alvo test -w "$PONTO" 2>/dev/null; then
        echo ""
        echo "  ATENCAO: montado, mas $ALVO ainda nao escreve em $PONTO."
        echo "  Confira: $(stat -c '%A %U:%G' "$PONTO")"
        exit 1
    fi
fi

echo ""
echo "== Pronto =="
echo ""
echo "  Como $ALVO, exporte a variavel e rode os testes:"
echo ""
echo "    export DPDK_ACADEMY_HUGE_DIR=$PONTO"
echo "    ./scripts/test-all.sh l2"
echo ""
echo "  Ou execute o exemplo de market data a mao, em dois terminais:"
echo ""
echo "    # terminal 1 — feed handler (primario)"
echo "    ./build/docs/02-runtime-dpdk/medicoes/feed-primario \\"
echo "        -l 0 --file-prefix=academia --no-pci --huge-dir=$PONTO -- 200000 cadencia"
echo ""
echo "    # terminal 2 — assinante (secundario)"
echo "    ./build/docs/02-runtime-dpdk/medicoes/feed-secundario \\"
echo "        -l 1 --file-prefix=academia --no-pci --huge-dir=$PONTO --proc-type=secondary"
echo ""
echo "  Para desfazer: ./scripts/preparar-hugepages.sh --desfazer"
echo ""
