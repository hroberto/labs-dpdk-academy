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
set -euo pipefail

ESPELHO=${DPDK_ESPELHO:-https://fast.dpdk.org/rel}
DIR_SRC=${DPDK_DIR_SRC:-$HOME/opt/src}

uso() {
    sed -n '/^# USO/,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'
    exit "${1:-1}"
}

# O teste que importa: a macro chega a QUEM CONSOME, nao so a biblioteca.
conferir_prefixo() { # <prefixo> <versao-esperada>
    local prefixo=$1 esperada=$2 pc
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
    if ! grep -q '^#define RTE_LIBRTE_MEMPOOL_STATS' "$prefixo/include/rte_config.h"; then
        echo "  FALHA: RTE_LIBRTE_MEMPOOL_STATS nao esta em $prefixo/include/rte_config.h"
        echo "         (a biblioteca pode ate contar; o consumidor nao vai saber)"
        return 1
    fi
    echo "  ok - $prefixo: libdpdk $versao, RTE_LIBRTE_MEMPOOL_STATS visivel ao consumidor"
}

modo=construir
case "${1:-}" in
    -h|--help) uso 0 ;;
    --conferir) modo=conferir; shift ;;
esac
VERSAO=${1:-}
[ -n "$VERSAO" ] || uso
PREFIXO=${2:-$HOME/opt/dpdk-$VERSAO}

if [ "$modo" = conferir ]; then
    conferir_prefixo "$PREFIXO" "$VERSAO"
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

echo "==> configurando (prefixo $PREFIXO)"
# OS DRIVERS FICAM. Desligar `*/*` parece economia e quebra o essencial: o
# handler padrao de mempool e `ring_mp_mc`, que vem de drivers/mempool/ring --
# sem ele `rte_mempool_create` nao tem como alocar, e o prefixo sai inutil para
# justamente o estudo que motivou este script. Os prefixos ja em uso foram
# construidos com os drivers, e mudar isso tornaria os bracos incomparaveis.
meson setup "$FONTE/build" "$FONTE" \
    --prefix="$PREFIXO" --buildtype=release -Dtests=false >/dev/null

echo "==> compilando"
ninja -C "$FONTE/build" >/dev/null
echo "==> instalando"
ninja -C "$FONTE/build" install >/dev/null

echo "==> conferindo o resultado"
conferir_prefixo "$PREFIXO" "$VERSAO"
