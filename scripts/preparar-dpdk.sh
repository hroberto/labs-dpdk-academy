#!/usr/bin/env bash
# Constroi um DPDK num prefixo proprio, com as estatisticas de mempool ligadas.
#
# POR QUE ISTO EXISTE
#
# O estudo do cache do mempool compara duas versoes do DPDK. Ate agora os dois
# prefixos existiam apenas em `~/opt` desta maquina, construidos a mao: o
# resultado era publicavel e NAO era reproduzivel, que e a metade do problema
# que este repositorio existe para nao ter.
#
# A ARMADILHA QUE CUSTOU UMA COLETA
#
# `RTE_LIBRTE_MEMPOOL_STATS` nao tem opcao de meson. A tentativa obvia --
# `meson setup -Dc_args=-DRTE_LIBRTE_MEMPOOL_STATS` -- compila a biblioteca com
# o contador e NAO o expoe a quem consome: o `libdpdk.pc` publica apenas
# `-I${includedir}`, entao o define nao chega ao programa, o
# `#ifdef RTE_LIBRTE_MEMPOOL_STATS` do cabecalho sai falso, e o programa relata
# "UNAVAILABLE" contra uma biblioteca que estava contando.
#
# O define precisa entrar em `config/rte_config.h`, que e instalado junto com
# os cabecalhos e portanto vale para a biblioteca E para o consumidor. E ali
# que o DPDK deixa a linha `/* RTE_LIBRTE_MEMPOOL_STATS is not set */`.
#
# CUSTO DE MEDICAO, e ele nao e zero
#
# O contador e atualizado no caminho quente. Um prefixo construido por este
# script serve para medir TAXA DE ACERTO, nao tempo. Ver
# temp/plano-pendencias.md, secao 1.1.
#
# USO
#
#   scripts/preparar-dpdk.sh 25.11            # constroi e instala em ~/opt
#   scripts/preparar-dpdk.sh 26.07 /caminho   # prefixo alternativo
#   scripts/preparar-dpdk.sh --conferir 25.11 # so confere um prefixo existente
#   scripts/preparar-dpdk.sh --minimo 25.11   # so os drivers que o estudo usa
#   scripts/preparar-dpdk.sh --sem-stats --minimo 25.11   # para medir TEMPO
#   scripts/preparar-dpdk.sh --portatil --minimo 26.07   # para CI, NAO para medir
#
# O MODO --minimo EXISTE PARA REPRODUZIR O QUE FOI PUBLICADO
#
# Sem ele o script instala o conjunto completo -- 154 drivers, 61 PMDs de rede
# --, que e o que serve para RX/TX. Os prefixos que produziram a tabela da §1.4
# do modulo 03 tem tres: bus_pci, bus_vdev e mempool_ring. Sao builds
# diferentes, e oferecer um chamando-o de reproducao do outro seria oferecer
# reprodutibilidade e entregar outra coisa.
#
# O MODO --sem-stats EXISTE PORQUE O CONTADOR CUSTA TEMPO
#
# `RTE_LIBRTE_MEMPOOL_STATS` incrementa contadores no CAMINHO QUENTE de get e
# put. Isso nao altera a CONTAGEM de idas ao anel comum -- que e a metrica do
# estudo B4 --, mas altera o TEMPO: o programa medido deixa de ser o de
# producao. Ligar o estudo de miss ao de tempo exige um par de prefixos sem a
# macro, e por isso ela virou opcao em vez de constante.
#
# O prefixo padrao ganha o sufixo `-sem-stats`. Dois prefixos da mesma versao
# que diferem so num #define nao se distinguem pelo pkg-config; compartilhar o
# caminho faria a segunda construcao apagar a primeira, e a campanha publicada
# deixaria de ser reproduzivel sem que nada avisasse.
set -euo pipefail

ESPELHO=${DPDK_ESPELHO:-https://fast.dpdk.org/rel}
DIR_SRC=${DPDK_DIR_SRC:-$HOME/opt/src}

uso() {
    sed -n '/^# USO/,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'
    exit "${1:-1}"
}

# O teste que importa: a macro chega a QUEM CONSOME, nao so a biblioteca.
# O TERCEIRO ARGUMENTO INVERTE O SENTIDO DA CONFERENCIA, e existe por simetria.
#
# Um prefixo COM estatisticas serve ao estudo de taxa de miss; um SEM serve ao
# estudo de TEMPO, porque o contador e atualizado no caminho quente e o
# programa medido deixa de ser o de producao. Os dois precisam ser conferidos,
# e conferir so um lado deixaria o outro nascer errado em silencio -- que e o
# defeito que este arquivo inteiro existe para impedir.
conferir_prefixo() { # <prefixo> <versao-esperada> [sem-stats]
    local prefixo=$1 esperada=$2 querSem=${3:-0} pc
    pc=$(find "$prefixo/lib" -name pkgconfig -type d 2>/dev/null | head -1)
    if [ -z "$pc" ]; then
        echo "  FALHA: nao achei o diretorio pkgconfig em $prefixo/lib"
        return 1
    fi
    local versao
    versao=$(PKG_CONFIG_PATH="$pc" pkg-config --modversion libdpdk 2>/dev/null) || {
        echo "  FALHA: pkg-config nao encontrou libdpdk em $pc"
        return 1
    }
    case "$versao" in
        "$esperada"*) ;;
        *) echo "  FALHA: $prefixo tem $versao, esperado $esperada"; return 1 ;;
    esac
    if grep -q '^#define RTE_LIBRTE_MEMPOOL_STATS' "$prefixo/include/rte_config.h"; then
        tem=1
    else
        tem=0
    fi
    if [ "$querSem" -eq 1 ] && [ "$tem" -eq 1 ]; then
        echo "  FALHA: $prefixo TEM RTE_LIBRTE_MEMPOOL_STATS, e foi pedido sem"
        echo "         (o contador roda no caminho quente e contamina a medicao de tempo)"
        return 1
    fi
    if [ "$querSem" -eq 0 ] && [ "$tem" -eq 0 ]; then
        echo "  FALHA: RTE_LIBRTE_MEMPOOL_STATS nao esta em $prefixo/include/rte_config.h"
        echo "         (a biblioteca pode ate contar; o consumidor nao vai saber)"
        return 1
    fi
    if [ "$querSem" -eq 1 ]; then
        echo "  ok - $prefixo: libdpdk $versao, SEM RTE_LIBRTE_MEMPOOL_STATS"
    else
        echo "  ok - $prefixo: libdpdk $versao, RTE_LIBRTE_MEMPOOL_STATS visivel ao consumidor"
    fi
}

modo=construir
MINIMO=0
SEM_STATS=0
PORTATIL=0
while true; do
    case "${1:-}" in
        -h|--help) uso 0 ;;
        --conferir) modo=conferir; shift ;;
        --minimo) MINIMO=1; shift ;;
        --sem-stats) SEM_STATS=1; shift ;;
        --portatil) PORTATIL=1; shift ;;
        *) break ;;
    esac
done
VERSAO=${1:-}
[ -n "$VERSAO" ] || uso
# O SUFIXO NO PREFIXO PADRAO NAO E COSMETICO. Dois prefixos da mesma versao que
# diferem so num #define sao indistinguiveis pelo pkg-config e pelo nome; se
# ocupassem o mesmo caminho, a segunda construcao sobrescreveria a primeira e a
# campanha anterior deixaria de ser reproduzivel sem aviso.
if [ "$SEM_STATS" -eq 1 ]; then
    PREFIXO=${2:-$HOME/opt/dpdk-$VERSAO-sem-stats}
else
    PREFIXO=${2:-$HOME/opt/dpdk-$VERSAO}
fi

if [ "$modo" = conferir ]; then
    conferir_prefixo "$PREFIXO" "$VERSAO" "$SEM_STATS"
    exit $?
fi

for f in meson ninja tar; do
    command -v "$f" >/dev/null || { echo "ausente: $f"; exit 1; }
done

mkdir -p "$DIR_SRC"
TAR="$DIR_SRC/dpdk-$VERSAO.tar.xz"
if [ ! -f "$TAR" ]; then
    echo "==> baixando dpdk-$VERSAO"
    curl -fsSL -o "$TAR.parcial" "$ESPELHO/dpdk-$VERSAO.tar.xz"
    mv "$TAR.parcial" "$TAR"
fi

TRAB=$(mktemp -d)
trap 'rm -rf "$TRAB"' EXIT
echo "==> extraindo"
tar xf "$TAR" -C "$TRAB"
FONTE=$(find "$TRAB" -maxdepth 1 -mindepth 1 -type d | head -1)

# A linha-marcador existe em todas as versoes conferidas (25.11 e 26.07). Se um
# dia nao existir, e melhor falhar aqui do que instalar um prefixo silenciosamente
# sem o contador -- que e o defeito original, com outra roupa.
MARCADOR='/* RTE_LIBRTE_MEMPOOL_STATS is not set */'
if ! grep -qF "$MARCADOR" "$FONTE/config/rte_config.h"; then
    echo "FALHA: nao achei a linha-marcador em config/rte_config.h desta versao."
    echo "       Confira como ela declara RTE_LIBRTE_MEMPOOL_STATS antes de seguir."
    exit 1
fi

if [ "$SEM_STATS" -eq 1 ]; then
    # NAO EDITAR E UMA ESCOLHA, E ELA PRECISA SER CONFERIDA COMO QUALQUER OUTRA.
    #
    # "Deixei como estava" e indistinguivel de "esqueci de editar" quando nada
    # confere. A linha-marcador ja foi exigida acima; aqui so se declara que ela
    # permanece, e `conferir_prefixo` recusa o prefixo se a macro aparecer.
    echo "==> MANTENDO RTE_LIBRTE_MEMPOOL_STATS desligado (--sem-stats)"
else
    echo "==> ligando RTE_LIBRTE_MEMPOOL_STATS em config/rte_config.h"
    # NAO com `sed`: o marcador contem `/*`, que em expressao regular significa
    # "zero ou mais barras", entao o padrao nao casa a linha literal -- e `sed -i`
    # nao reclama quando nada casa. A primeira versao deste script fazia isso e
    # instalava um prefixo sem o contador, anunciando que o tinha ligado.
    python3 - "$FONTE/config/rte_config.h" <<'PATCH'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
marcador = "/* RTE_LIBRTE_MEMPOOL_STATS is not set */"
assert marcador in s, "linha-marcador ausente"
p.write_text(s.replace(marcador, "#define RTE_LIBRTE_MEMPOOL_STATS 1", 1))
PATCH

    # A edicao e CONFERIDA, nao presumida.
    grep -q '^#define RTE_LIBRTE_MEMPOOL_STATS' "$FONTE/config/rte_config.h" || {
        echo "FALHA: a edicao de config/rte_config.h nao pegou; abortando antes de compilar."
        exit 1
    }
fi

echo "==> configurando (prefixo $PREFIXO)"
# OS DRIVERS FICAM. Desligar `*/*` parece economia e quebra o essencial: o
# handler padrao de mempool e `ring_mp_mc`, que vem de drivers/mempool/ring --
# sem ele `rte_mempool_create` nao tem como alocar, e o prefixo sai inutil para
# justamente o estudo que motivou este script. Os prefixos ja em uso foram
# construidos com os drivers, e mudar isso tornaria os bracos incomparaveis.
OPCOES=(--prefix="$PREFIXO" --buildtype=release -Dtests=false)
if [ "$PORTATIL" -eq 1 ]; then
    # `-Dplatform=generic` NAO E O PADRAO, E NAO DEVE SER.
    #
    # O padrao do DPDK e `native`, que assa no binario a ISA da maquina que
    # compilou. Para reproduzir o que este repositorio publicou isso e o
    # correto: os numeros saem da maquina de referencia, com as instrucoes que
    # ela tem.
    #
    # Em CI e o oposto. Os runners do GitHub sao heterogeneos -- uns Intel com
    # AVX-512, outros AMD sem --, e o prefixo construido num deles fica em
    # CACHE e e restaurado noutro. Quando as ISAs nao batem, toda
    # `rte_eal_init` morre com "unsupported cpu type", e a falha e por sorteio
    # de maquina: verde de manha, dez falhas de L2 a tarde, sem nada ter
    # mudado na arvore.
    #
    # Medido em 26/09/2026: `releases-dpdk (26.07)` passou na main as 06:28 e
    # falhou no mesmo codigo as 14:59, com "This system does not support
    # AVX512BW" em dez testes de EAL. A 25.11 passou nas duas -- outro sorteio.
    #
    # Quem usa esta opcao aceita a troca: o binario roda em qualquer runner, e
    # NAO serve para medir tempo.
    OPCOES+=(-Dplatform=generic)
fi
if [ "$MINIMO" -eq 1 ]; then
    # `mempool/ring` e obrigatorio: e o handler padrao (`ring_mp_mc`), e sem ele
    # `rte_mempool_create` nao aloca. `bus/pci` e `bus/vdev` entram porque a EAL
    # os exige para enumerar.
    OPCOES+=(-Denable_drivers='bus/pci,bus/vdev,mempool/ring')
fi
meson setup "$FONTE/build" "$FONTE" "${OPCOES[@]}" >/dev/null

echo "==> compilando"
ninja -C "$FONTE/build" >/dev/null
echo "==> instalando"
ninja -C "$FONTE/build" install >/dev/null

echo "==> conferindo o resultado"
conferir_prefixo "$PREFIXO" "$VERSAO" "$SEM_STATS"
