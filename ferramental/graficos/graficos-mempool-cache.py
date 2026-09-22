#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Graficos do estudo B4 — cache do mempool, 25.11 contra 26.07.

DE ONDE VEM CADA PONTO

Nada aqui e digitado. O script le a coleta arquivada em
`docs/03-mempool-ring-mbuf/medicoes/historico/2026-09-21-mempool-cache-intercalada/`:
a taxa de miss sai do CSV, e o numero de eventos de fila cheia sai da saida
bruta de cada execucao, porque essa coluna nao entrou no CSV. Regerar o grafico
depois de uma coleta nova e uma linha de comando, e o diff do SVG mostra o que
mudou -- que e a razao de os graficos deste projeto serem SVG escrito a mao.

POR QUE ESTAS DUAS FORMAS

1. TIRAS DE PONTOS, nao barras de mediana. A dispersao E a historia: em
   `cache=64` as seis repeticoes do 26.07 varrem 32 pontos percentuais. Uma
   barra de mediana esconderia exatamente o que se quer mostrar, e um box plot
   com n=6 afirmaria sobre a forma da distribuicao mais do que seis pontos
   sustentam. Mostrar os seis pontos nao afirma nada alem do que foi medido.

2. AMPLITUDE DO EVENTO, nao correlacao. A relacao inversa entre miss e fila
   cheia vale em quase toda a faixa e nas duas versoes -- plota-la sugeriria
   que e assinatura do `cache=64`, e nao e. O que E exclusivo dali e a
   amplitude do proprio evento: 3,9x entre repeticoes, contra ~1,3x nas
   vizinhas. O segundo grafico mostra isso e so isso.

O QUE ESTES GRAFICOS DELIBERADAMENTE NAO TEM

Camada de interacao. O SVG e renderizado pelo GitHub dentro do Markdown, que
remove script: uma dica de contexto ao passar o mouse nunca apareceria. A
leitura fina fica nas tabelas da secao 1.4, que sao a versao tabular destes
mesmos dados.
"""
import csv
import pathlib
import re
import statistics
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from svg import documento, linha, ponto, texto  # noqa: E402

RAIZ = pathlib.Path(__file__).resolve().parents[2]
COLETA = RAIZ / "docs/03-mempool-ring-mbuf/medicoes/historico/2026-09-21-mempool-cache-intercalada"
SAIDA = RAIZ / "docs/03-mempool-ring-mbuf/imagens"
LARGURA = 880

# `0` e `16` ficam de fora: as duas versoes saturam em 100% e as tiras seriam
# doze pontos empilhados sem informacao. A prosa da secao cobre o caso.
CACHES = [24, 32, 48, 64, 96, 128, 256, 512]
VERSOES = ["25.11", "26.07"]

TEMAS = {
    "claro": dict(
        superficie="#fcfcfb", tinta="#0b0b0b", tinta2="#52514e", suave="#898781",
        grade="#e1e0d9", eixo="#c3c2b7", serie1="#2a78d6", serie2="#eb6834"),
    "escuro": dict(
        superficie="#1a1a19", tinta="#ffffff", tinta2="#c3c2b7", suave="#898781",
        grade="#2c2c2a", eixo="#383835", serie1="#3987e5", serie2="#d95926"),
}

TEXTOS = {
    "pt": dict(
        sufixo="", dec=",", mil=" ",
        d_titulo="A dispersao separa as versoes mais que a mediana",
        d_sub="taxa de miss do cache do mempool, seis repeticoes por celula — topologia assimetrica",
        d_y="miss do cache (%)", d_x="cache por lcore (objetos)",
        d_nota="Cada ponto e uma execucao. O traco e a mediana.",
        d_marca="em cache = 64 o 26.07 varre 32 pontos",
        d_desc="Tiras de pontos comparando a taxa de miss do cache do mempool "
               "entre DPDK 25.11 e 26.07 para varios tamanhos de cache. O 26.07 "
               "fica acima em toda a faixa, e em cache 64 suas repeticoes se "
               "espalham muito mais que as das celulas vizinhas.",
        a_titulo="O que varia em cache = 64 e a propria frequencia de fila cheia",
        a_sub="eventos de fila cheia por execucao, DPDK 26.07 — minimo, mediana e maximo de seis repeticoes",
        a_y="cache por lcore (objetos)", a_x="objetos que nao couberam na fila (milhoes)",
        a_nota="A barra e o intervalo entre a menor e a maior das seis execucoes.",
        a_marca="amplitude de {0}x",
        a_vizinha="vizinhas: ~{0}x",
        a_desc="Intervalos entre minimo e maximo do numero de eventos de fila "
               "cheia por tamanho de cache no DPDK 26.07. O intervalo de cache "
               "64 e varias vezes mais largo que o das celulas vizinhas."),
    "en": dict(
        sufixo=".en", dec=".", mil=",",
        d_titulo="Dispersion separates the versions more than the median does",
        d_sub="mempool cache miss rate, six repetitions per cell — asymmetric topology",
        d_y="cache miss (%)", d_x="per-lcore cache (objects)",
        d_nota="Each dot is one run. The tick is the median.",
        d_marca="at cache = 64, 26.07 spans 32 points",
        d_desc="Dot strips comparing the mempool cache miss rate between DPDK "
               "25.11 and 26.07 across cache sizes. 26.07 sits higher across the "
               "range, and at cache 64 its repetitions scatter far more than "
               "those of neighbouring cells.",
        a_titulo="What varies at cache = 64 is the ring-full frequency itself",
        a_sub="ring-full events per run, DPDK 26.07 — minimum, median and maximum of six repetitions",
        a_y="per-lcore cache (objects)", a_x="objects that did not fit in the queue (millions)",
        a_nota="The bar is the interval between the lowest and highest of the six runs.",
        a_marca="{0}x range",
        a_vizinha="neighbours: ~{0}x",
        a_desc="Intervals between minimum and maximum ring-full event counts per "
               "cache size on DPDK 26.07. The cache-64 interval is several times "
               "wider than those of neighbouring cells."),
}


def num(v, L, casas=2):
    return f"{v:.{casas}f}".replace(".", L["dec"])


def ler():
    """miss% do CSV; eventos de fila cheia da saida bruta de cada execucao."""
    miss = {}
    with open(COLETA / "mempool-cache.csv", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["topologia"] != "assimetrico":
                continue
            miss.setdefault((r["versao"], int(r["cache"])), []).append(float(r["miss_pct"]))
    fila = {}
    for f in COLETA.glob("*.assimetrico.*.txt"):
        v, _, c, rep = f.name.split(".")[0] + "." + f.name.split(".")[1], *f.name.split(".")[2:5]
        m = re.search(r"did not fit in the queue: (\d+)", f.read_text(encoding="utf-8"))
        if m:
            fila.setdefault((v, int(c[1:])), []).append(int(m.group(1)))
    return miss, fila


def cabecalho(t, titulo, subtitulo):
    return [texto(28, 34, titulo, t["tinta"], 17, 600),
            texto(28, 55, subtitulo, t["tinta2"], 13)]


def dispersao(t, L, miss, _fila):
    E, D, TOPO, ALT = 96, 150, 116, 300
    larg = LARGURA - E - D
    passo = larg / len(CACHES)
    c = cabecalho(t, L["d_titulo"], L["d_sub"])

    def y(v):
        return TOPO + ALT - ALT * v / 100.0

    for i in range(6):
        v = 20 * i
        c.append(linha(E, y(v), E + larg, y(v), t["grade"]))
        c.append(texto(E - 12, y(v) + 4, v, t["suave"], 11, ancora="end", tabular=True))
    c.append(texto(28, TOPO - 20, L["d_y"], t["suave"], 11))

    for i, cache in enumerate(CACHES):
        cx = E + passo * (i + 0.5)
        for j, v in enumerate(VERSOES):
            cor = t["serie1"] if j == 0 else t["serie2"]
            ox = -11 if j == 0 else 11
            vals = miss[(v, cache)]
            for p in vals:
                c.append(ponto(cx + ox, y(p), cor, t["superficie"], 4))
            md = statistics.median(vals)
            c.append(linha(cx + ox - 13, y(md), cx + ox + 13, y(md), t["tinta"], 2))
        c.append(texto(cx, TOPO + ALT + 22, cache, t["suave"], 12,
                       ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, TOPO + ALT + 42, L["d_x"], t["suave"], 12, ancora="middle"))

    # Legenda: duas series exigem legenda, e ela nao pode ser so a cor.
    lx = E + larg + 22
    for j, v in enumerate(VERSOES):
        cor = t["serie1"] if j == 0 else t["serie2"]
        c.append(ponto(lx + 6, TOPO + 6 + j * 24, cor, t["superficie"], 4))
        c.append(texto(lx + 18, TOPO + 10 + j * 24, f"DPDK {v}", t["tinta"], 12, 600))

    # Rotulo direto, seletivo: so na celula que a secao discute.
    i64 = CACHES.index(64)
    c.append(texto(E + passo * (i64 + 0.5) + 26, y(max(miss[("26.07", 64)])) - 12,
                   L["d_marca"], t["tinta"], 12, 600))
    c.append(texto(28, TOPO + ALT + 66, L["d_nota"], t["tinta2"], 12))
    return documento(LARGURA, TOPO + ALT + 92, t["superficie"],
                     L["d_titulo"], L["d_desc"], c)


def amplitude(t, L, _miss, fila):
    E, D, TOPO, PASSO = 96, 210, 116, 34
    larg = LARGURA - E - D
    caches = [c for c in CACHES if c >= 32]
    topo_v = 3.5e6
    c = cabecalho(t, L["a_titulo"], L["a_sub"])

    def x(v):
        return E + larg * v / topo_v

    for i in range(8):
        v = topo_v * i / 7
        c.append(linha(x(v), TOPO - 12, x(v), TOPO + PASSO * len(caches), t["grade"]))
        c.append(texto(x(v), TOPO + PASSO * len(caches) + 20, num(v / 1e6, L, 1),
                       t["suave"], 11, ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, TOPO + PASSO * len(caches) + 40, L["a_x"],
                   t["suave"], 12, ancora="middle"))
    c.append(texto(28, TOPO - 26, L["a_y"], t["suave"], 11))

    razoes = {}
    for i, cache in enumerate(caches):
        vals = fila[("26.07", cache)]
        lo, hi, md = min(vals), max(vals), statistics.median(vals)
        razoes[cache] = hi / lo
        yy = TOPO + PASSO * i + 10
        c.append(texto(E - 14, yy + 4, cache, t["suave"], 12, ancora="end", tabular=True))
        c.append(linha(x(lo), yy, x(hi), yy, t["serie1"], 3))
        c.append(ponto(x(md), yy, t["serie1"], t["superficie"], 4.5))

    i64 = caches.index(64)
    c.append(texto(x(max(fila[("26.07", 64)])) + 16, TOPO + PASSO * i64 + 14,
                   L["a_marca"].format(num(razoes[64], L, 1)), t["tinta"], 12, 600))
    vizinhas = statistics.median([razoes[k] for k in caches if k != 64])
    c.append(texto(x(max(fila[("26.07", 96)])) + 16, TOPO + PASSO * caches.index(96) + 14,
                   L["a_vizinha"].format(num(vizinhas, L, 1)), t["tinta2"], 12))
    c.append(texto(28, TOPO + PASSO * len(caches) + 64, L["a_nota"], t["tinta2"], 12))
    return documento(LARGURA, TOPO + PASSO * len(caches) + 90, t["superficie"],
                     L["a_titulo"], L["a_desc"], c)


if __name__ == "__main__":
    miss, fila = ler()
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome, fn in (("dispersao", dispersao), ("amplitude", amplitude)):
        for _idioma, L in TEXTOS.items():
            for tema, t in TEMAS.items():
                alvo = SAIDA / f"1-{nome}-{tema}{L['sufixo']}.svg"
                alvo.write_text(fn(t, L, miss, fila), encoding="utf-8")
                print(f"  {alvo.relative_to(RAIZ)}  ({alvo.stat().st_size} B)")
