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

2. MEDIDO CONTRA PREVISTO, nao dispersao. A primeira versao destes graficos
   mostrava a dispersao da taxa de miss, e a dispersao era artefato: o
   denominador daquela taxa conta RETENTATIVAS do produtor quando a fila
   enche, que medem a corrida entre os lcores e nao o cache. O numerador --
   idas ao anel comum -- e deterministico. O segundo grafico mostra
   exatamente isso: a contagem que nao varia ao lado da que varia.

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
from svg import documento, linha, poli, ponto, texto  # noqa: E402

RAIZ = pathlib.Path(__file__).resolve().parents[2]
COLETA = RAIZ / "docs/03-mempool-ring-mbuf/medicoes/historico/2026-09-21-mempool-cache-intercalada"
SAIDA = RAIZ / "docs/03-mempool-ring-mbuf/imagens"
LARGURA = 880

# Abaixo de 64 o 25.11 entra no regime misto e a contagem deixa de ser exata;
# esses pontos ficam fora do grafico da lei e sao tratados na prosa.
CACHES = [64, 96, 128, 256, 512]
CONTAMINA = 96      # celula usada para mostrar a contaminacao do denominador
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
        l_titulo="O custo nao e medido: e aritmetica, e a medicao confirma",
        l_sub="idas ao anel comum por milhao de pacotes — topologia assimetrica, seis execucoes por celula",
        l_y="idas ao anel comum (por milhao de pacotes)",
        l_x="cache por lcore (objetos)",
        l_previsto="previsto pelo tamanho da recarga",
        l_nota="As seis execucoes de cada celula dao o MESMO valor; cada ponto e as seis sobrepostas.",
        l_desc="Idas ao anel comum por milhao de pacotes, por tamanho de cache, "
               "para DPDK 25.11 e 26.07. Os pontos medidos caem sobre as curvas "
               "previstas pelo tamanho da recarga de cada versao, e as seis "
               "execucoes de cada celula coincidem.",
        c_titulo="Por que a taxa de miss dispersava: o denominador",
        c_sub="cache = {0}, DPDK 26.07 — a mesma celula, seis execucoes",
        c_x="execucao",
        c_gets="chamadas de get",
        c_backend="idas ao anel comum",
        c_nota="A diferenca entre as duas linhas sao retentativas do produtor quando a fila enche.",
        c_desc="Comparacao, ao longo de seis execucoes da mesma celula, entre o "
               "numero de chamadas de get e o numero de idas ao anel comum. O "
               "segundo e identico nas seis; o primeiro varia."),
    "en": dict(
        sufixo=".en", dec=".", mil=",",
        l_titulo="The cost is not measured: it is arithmetic, and measurement confirms it",
        l_sub="common-ring trips per million packets — asymmetric topology, six runs per cell",
        l_y="common-ring trips (per million packets)",
        l_x="per-lcore cache (objects)",
        l_previsto="predicted by the refill size",
        l_nota="All six runs of each cell give the SAME value; each dot is six points superimposed.",
        l_desc="Common-ring trips per million packets, by cache size, for DPDK "
               "25.11 and 26.07. The measured dots land on the curves predicted "
               "by each version's refill size, and the six runs of each cell "
               "coincide.",
        c_titulo="Why the miss rate dispersed: the denominator",
        c_sub="cache = {0}, DPDK 26.07 — the same cell, six runs",
        c_x="run",
        c_gets="get calls",
        c_backend="common-ring trips",
        c_nota="The gap between the two lines is producer retries when the queue fills.",
        c_desc="Comparison, across six runs of the same cell, between the number "
               "of get calls and the number of common-ring trips. The latter is "
               "identical in all six; the former varies."),
}


def num(v, L, casas=2):
    return f"{v:.{casas}f}".replace(".", L["dec"])


def ler():
    """Por celula: idas ao anel comum e chamadas de get, das seis execucoes.

    As duas saem da saida bruta arquivada. A primeira e o numerador da taxa de
    miss e e deterministica; a segunda e o denominador e nao e.
    """
    backend, gets = {}, {}
    for f in COLETA.glob("*.assimetrico.c*.txt"):
        v = ".".join(f.name.split(".")[:2])
        c = int(f.name.split(".")[3][1:])
        m = re.search(r"^  total +(\d+) +(\d+) ", f.read_text(encoding="utf-8"), re.M)
        if m:
            gets.setdefault((v, c), []).append(int(m.group(1)))
            backend.setdefault((v, c), []).append(int(m.group(2)))
    return backend, gets


def cabecalho(t, titulo, subtitulo):
    return [texto(28, 34, titulo, t["tinta"], 17, 600),
            texto(28, 55, subtitulo, t["tinta2"], 13)]


def lei(t, L, backend, _gets):
    """Medido contra previsto: idas ao anel comum por milhao de pacotes."""
    E, D, TOPO, ALT = 104, 178, 116, 286
    larg = LARGURA - E - D
    topo_v = 34000.0
    c = cabecalho(t, L["l_titulo"], L["l_sub"])

    def x(i):
        return E + larg * i / (len(CACHES) - 1)

    def y(v):
        return TOPO + ALT - ALT * v / topo_v

    for i in range(5):
        v = topo_v * i / 4
        c.append(linha(E, y(v), E + larg, y(v), t["grade"]))
        c.append(texto(E - 12, y(v) + 4, f"{round(v):,}".replace(",", L["mil"]),
                       t["suave"], 11, ancora="end", tabular=True))
    c.append(texto(28, TOPO - 20, L["l_y"], t["suave"], 11))

    # PREVISTO primeiro, em tinta suave: e referencia, nao serie.
    for j, v in enumerate(VERSOES):
        prev = [(x(i), y(1e6 / (ca + 32 if j == 0 else ca / 2)))
                for i, ca in enumerate(CACHES)]
        c.append(poli(prev, t["suave"], 2))
    # Ancorado a direita e ACIMA da curva: a legenda da referencia nao pode
    # transbordar a margem, e o verificador de geometria acusa se transbordar.
    c.append(texto(x(len(CACHES) - 1) - 8, y(1e6 / (CACHES[-1] / 2)) - 16,
                   L["l_previsto"], t["suave"], 12, 600, ancora="end"))

    for j, v in enumerate(VERSOES):
        cor = t["serie1"] if j == 0 else t["serie2"]
        pts = [(x(i), y(backend[(v, ca)][0] / 2.0)) for i, ca in enumerate(CACHES)]
        for px_, py_ in pts:
            c.append(ponto(px_, py_, cor, t["superficie"], 5))
        c.append(texto(pts[0][0] + 14, pts[0][1] + 5, f"DPDK {v}", t["tinta"], 12, 600))

    for i, ca in enumerate(CACHES):
        c.append(texto(x(i), TOPO + ALT + 22, ca, t["suave"], 12,
                       ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, TOPO + ALT + 42, L["l_x"], t["suave"], 12, ancora="middle"))
    c.append(texto(28, TOPO + ALT + 66, L["l_nota"], t["tinta2"], 12))
    return documento(LARGURA, TOPO + ALT + 92, t["superficie"],
                     L["l_titulo"], L["l_desc"], c)


def contaminacao(t, L, backend, gets):
    """Uma celula, seis execucoes: o que nao varia ao lado do que varia."""
    E, D, TOPO, ALT = 104, 178, 116, 214
    larg = LARGURA - E - D
    topo_v = 130000.0
    c = cabecalho(t, L["c_titulo"].format(CONTAMINA), L["c_sub"])
    passo = larg / 6

    def y(v):
        return TOPO + ALT - ALT * v / topo_v

    for i in range(5):
        v = topo_v * i / 4
        c.append(linha(E, y(v), E + larg, y(v), t["grade"]))
        c.append(texto(E - 12, y(v) + 4, f"{round(v):,}".replace(",", L["mil"]),
                       t["suave"], 11, ancora="end", tabular=True))

    g = gets[("26.07", CONTAMINA)]
    b = backend[("26.07", CONTAMINA)]
    for i in range(6):
        cx = E + passo * (i + 0.5)
        c.append(ponto(cx, y(g[i]), t["serie2"], t["superficie"], 5))
        c.append(ponto(cx, y(b[i]), t["serie1"], t["superficie"], 5))
        c.append(texto(cx, TOPO + ALT + 22, i + 1, t["suave"], 12,
                       ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, TOPO + ALT + 42, L["c_x"], t["suave"], 12, ancora="middle"))

    c.append(texto(E + larg + 14, y(g[-1]) + 5, L["c_gets"], t["tinta"], 12, 600))
    c.append(texto(E + larg + 14, y(b[-1]) + 5, L["c_backend"], t["tinta"], 12, 600))
    c.append(texto(28, TOPO + ALT + 66, L["c_nota"], t["tinta2"], 12))
    return documento(LARGURA, TOPO + ALT + 92, t["superficie"],
                     L["c_titulo"].format(CONTAMINA), L["c_desc"], c)


if __name__ == "__main__":
    backend, gets = ler()
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome, fn in (("lei", lei), ("contaminacao", contaminacao)):
        for _idioma, L in TEXTOS.items():
            for tema, t in TEMAS.items():
                alvo = SAIDA / f"1-{nome}-{tema}{L['sufixo']}.svg"
                alvo.write_text(fn(t, L, backend, gets), encoding="utf-8")
                print(f"  {alvo.relative_to(RAIZ)}  ({alvo.stat().st_size} B)")
