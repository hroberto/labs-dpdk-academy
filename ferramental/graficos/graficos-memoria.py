#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Gera os gráficos do capítulo 4 de `docs/01-fundamentos` a partir dos números
que os programas de medição imprimem.

POR QUE ISTO É UM GERADOR, E NÃO TRÊS ARQUIVOS SVG DESENHADOS À MÃO

A régua do projeto é que todo número publicado saia de um programa. Um gráfico
desenhado à mão quebra essa régua de um jeito pior que uma tabela errada: ele
parece autoridade e não tem origem. Aqui os valores vivem em `DADOS`, com a
procedência anotada linha a linha, e o desenho é consequência deles. Quando uma
medição for refeita, atualize `DADOS` e regenere — o diff mostra o que mudou.

    python3 ferramental/graficos/graficos-memoria.py

PALETA

Vem de um sistema de design validado (rampa ordinal azul para escala ordenada,
slots categóricos azul/laranja para séries distintas). As cores foram conferidas
por script nos dois temas — banda de luminosidade, piso de croma, separação sob
daltonismo (protanopia/deuteranopia) e contraste contra a superfície — e não por
inspeção visual. Ao trocar qualquer valor, revalide.

REGRAS DE MARCA APLICADAS

- marcas finas, ponta de dado arredondada em 4px, ancorada na linha zero
- linha de série em 2px, marcador de 9px com anel da cor da superfície
- grade e eixos em fio de cabelo, um tom acima da superfície; nunca tracejados
- tracejado reservado para LIMIAR (orçamento, line rate), que não é grade
- rótulos diretos seletivos; texto sempre em tinta, nunca na cor da série
- tema escuro é escolhido passo a passo, não é inversão automática do claro
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from svg import barra_h, documento, linha, poli, ponto, texto  # noqa: E402

SAIDA = pathlib.Path(__file__).resolve().parents[2] / "docs/01-fundamentos/imagens"
LARGURA = 880

# --------------------------------------------------------------------------
# DADOS — procedência de cada número
# --------------------------------------------------------------------------
ORCAMENTO_NS = 67.2          # secao 1: 10 GbE, quadros de 64 B
LINE_RATE_MPPS = 14.88       # secao 1: 14 880 952 pacotes/s

# efeito-cache.c, coluna "dependente (LATENCIA)"
ESCADA = [("L1d", "16 KB", 0.891), ("L2", "256 KB", 2.68),
          ("L3", "8 MB", 9.67), ("RAM", "256 MB", 86.59)]

# custo-paralelismo.c, coluna "mediana", rodada r1 de
# 2026-09-23-expo6000-canal-duplo -- a MESMA rodada das tabelas publicadas
PARALELISMO = [(1, 76.65), (2, 37.97), (4, 20.58), (8, 10.75),
               (12, 7.38), (16, 5.64), (32, 3.19), (64, 2.43)]

# efeito-cache.c, bloco RAM. Banda = bytes MOVIDOS pela memória: cada acesso
# traz uma linha de 64 B inteira, mesmo quando o programa usa 4 bytes dela.
# No caso sequencial os 16 uint32_t da linha são todos usados, então os 64 B
# custam 16 acessos.
BANDA = [("sequencial (o prefetcher enfileira sozinho)", 64.0 / (0.187 * 16)),
         ("aleatório, endereços independentes",          64.0 / 5.81),
         ("aleatório, endereços encadeados",             64.0 / 86.59)]

# custo-paralelismo.c, fase 2: N nucleos fisicos, 16 cadeias cada, mesma regiao.
# Coleta 2026-09-23-expo6000-canal-duplo. O canal e parte da procedencia: a
# curva de saturacao E a medida do teto de banda, e o teto depende de quantos
# pentes servem a requisicao.
NUCLEOS = [(1, 5.85), (2, 6.08), (4, 6.69), (8, 8.69), (12, 12.68)]

# --------------------------------------------------------------------------
# TEXTOS — um gráfico por idioma
#
# O documento em ingles referenciava os MESMOS arquivos SVG do portugues, e o
# leitor de ingles recebia um grafico escrito em portugues no meio da pagina.
# A paridade de um documento nao termina na prosa: o que esta dentro da imagem
# tambem e texto, e nao aparece em nenhuma busca por palavra.
#
# `dec` e o separador decimal: 0,89 em portugues, 0.89 em ingles.
# --------------------------------------------------------------------------
TEXTOS = {
    "pt": dict(
        sufixo="", dec=",",
        esc_titulo="Um acesso à memória contra o orçamento de um pacote",
        esc_sub="latência de um acesso dependente, por nível da hierarquia — efeito-cache.c",
        esc_eixo="nanossegundos", esc_orc="orçamento: 67,2 ns por pacote",
        esc_excede="excede o orçamento em {0:.0f} ns",
        esc_desc=("Gráfico de barras horizontais. A latência de um acesso dependente é de "
                  "0,89 ns na L1d, 2,68 ns na L2, 9,67 ns na L3 e 86,6 ns na RAM. O "
                  "orçamento de um pacote de 64 B em 10 GbE é 67,2 ns: só o acesso à RAM "
                  "já o excede."),
        con_titulo="Vazão se compra com concorrência — e se paga com latência",
        con_sub="K acessos independentes em voo sobre a mesma região — custo-paralelismo.c",
        con_p1="1 · quanto a máquina entrega", con_p2="2 · e o que isso custa em espera",
        con_y1="M acessos/s", con_y2="ns (escala log)", con_lr="line rate 10 GbE",
        con_leg1="custo amortizado por acesso", con_leg2="tempo até o lote de K ficar pronto",
        con_x="K — acessos em voo ao mesmo tempo (escala log)",
        con_nota1="até K = 16 a curva laranja é plana:", con_nota2="a concorrência sai de graça",
        con_desc=("Dois gráficos empilhados com o mesmo eixo horizontal K em escala "
                  "logarítmica, de 1 a 64 acessos em voo. No primeiro, a vazão sobe de 13,0 "
                  "para 411 M acessos/s e satura; uma linha tracejada marca o line rate de "
                  "10 GbE. No segundo, em escala log nos dois eixos, o custo amortizado por "
                  "acesso cai de 77 para 2,43 ns enquanto o tempo até o lote ficar pronto "
                  "permanece plano em torno de 80 ns até K = 16 e sobe para 156 ns em "
                  "K = 64. As duas curvas estão em nanossegundos; a segunda é a primeira "
                  "multiplicada por K."),
        ban_titulo="A banda que você usa é a que o seu padrão de acesso permite",
        ban_sub="um núcleo, a mesma região de 256 MB na mesma RAM — efeito-cache.c",
        ban_eixo="gigabytes por segundo", ban_un="GB/s",
        ban_rot=["sequencial (o prefetcher enfileira sozinho)",
                 "aleatório, endereços independentes",
                 "aleatório, endereços encadeados"],
        ban_fecho="{0:.0f}× de diferença — mesma máquina, mesma memória, mesmo núcleo.",
        ban_desc=("Gráfico de barras horizontais. Sobre a mesma RAM, um núcleo move 21,4 "
                  "GB/s em acesso sequencial, 11,0 GB/s em acesso aleatório com endereços "
                  "independentes e 0,7 GB/s quando cada endereço depende do anterior."),
        sca_titulo="A banda não se multiplica por núcleo — ela é dividida",
        sca_sub=("vazão agregada com N núcleos físicos empurrando a mesma região — "
                 "custo-paralelismo.c, fase 2"),
        sca_y="M acessos/s (soma de todos os núcleos)", sca_ideal="se escalasse por núcleo",
        sca_teto="{0:.0f} M/s — o teto", sca_ms="{0:.0f} M/s", sca_x="núcleos físicos ativos",
        sca_fecho="Com 12 ativos, cada núcleo faz 46% do que fazia sozinho.",
        sca_desc=("Gráfico de linha. A vazão agregada sobe de 171 M acessos/s com um núcleo "
                  "para 948 M com doze, e satura por volta de oito. A linha de referência "
                  "mostra onde ela estaria se escalasse por núcleo: 2 051 M com doze."),
    ),
    "en": dict(
        sufixo=".en", dec=".",
        esc_titulo="One memory access against a single packet's budget",
        esc_sub="latency of one dependent access, per level of the hierarchy — efeito-cache.c",
        esc_eixo="nanoseconds", esc_orc="budget: 67.2 ns per packet",
        esc_excede="exceeds the budget by {0:.0f} ns",
        esc_desc=("Horizontal bar chart. The latency of one dependent access is 0.89 ns in "
                  "L1d, 2.68 ns in L2, 9.67 ns in L3 and 86.6 ns in RAM. The budget for a "
                  "64 B packet on 10 GbE is 67.2 ns: the RAM access alone already exceeds it."),
        con_titulo="Throughput is bought with concurrency — and paid for in latency",
        con_sub="K independent accesses in flight over the same region — custo-paralelismo.c",
        con_p1="1 · what the machine delivers", con_p2="2 · and what it costs in waiting",
        con_y1="M accesses/s", con_y2="ns (log scale)", con_lr="10 GbE line rate",
        con_leg1="amortized cost per access", con_leg2="time until the batch of K is ready",
        con_x="K — accesses in flight at the same time (log scale)",
        con_nota1="up to K = 16 the orange curve is flat:", con_nota2="concurrency comes for free",
        con_desc=("Two stacked charts sharing the same horizontal axis K on a logarithmic "
                  "scale, from 1 to 64 accesses in flight. In the first, throughput rises "
                  "from 13.0 to 411 M accesses/s and saturates; a dashed line marks the "
                  "10 GbE line rate. In the second, on log scales on both axes, the "
                  "amortized cost per access falls from 77 to 2.43 ns while the time until "
                  "the batch is ready stays flat around 80 ns up to K = 16 and rises to "
                  "156 ns at K = 64. Both curves are in nanoseconds; the second is the "
                  "first multiplied by K."),
        ban_titulo="The bandwidth you get is the one your access pattern allows",
        ban_sub="one core, the same 256 MB region in the same RAM — efeito-cache.c",
        ban_eixo="gigabytes per second", ban_un="GB/s",
        ban_rot=["sequential (the prefetcher queues on its own)",
                 "random, independent addresses",
                 "random, chained addresses"],
        ban_fecho="{0:.0f}× difference — same machine, same memory, same core.",
        ban_desc=("Horizontal bar chart. Over the same RAM, one core moves 21.4 GB/s with "
                  "sequential access, 11.0 GB/s with random access using independent "
                  "addresses and 0.7 GB/s when each address depends on the previous one."),
        sca_titulo="Bandwidth does not multiply per core — it is divided",
        sca_sub=("aggregate throughput with N physical cores pushing the same region — "
                 "custo-paralelismo.c, phase 2"),
        sca_y="M accesses/s (sum of all cores)", sca_ideal="if it scaled per core",
        sca_teto="{0:.0f} M/s — the ceiling", sca_ms="{0:.0f} M/s", sca_x="active physical cores",
        sca_fecho="With 12 active, each core does 46% of what it did alone.",
        sca_desc=("Line chart. Aggregate throughput rises from 171 M accesses/s with one "
                  "core to 948 M with twelve, and saturates around eight. The reference "
                  "line shows where it would be if it scaled per core: 2,051 M with twelve."),
    ),
}


def num(v, L, casas=2):
    """Formata respeitando o separador decimal do idioma."""
    return f"{v:.{casas}f}".replace(".", L["dec"])


TEMAS = {
    "claro": dict(
        superficie="#fcfcfb", tinta="#0b0b0b", tinta2="#52514e", suave="#898781",
        grade="#e1e0d9", eixo="#c3c2b7",
        rampa=["#86b6ef", "#5598e7", "#2a78d6", "#1c5cab"],   # ordinal, cresce escurecendo
        serie1="#2a78d6", serie2="#eb6834"),
    "escuro": dict(
        superficie="#1a1a19", tinta="#ffffff", tinta2="#c3c2b7", suave="#898781",
        grade="#2c2c2a", eixo="#383835",
        rampa=["#184f95", "#256abf", "#3987e5", "#6da7ec"],   # ordinal, cresce clareando
        serie1="#3987e5", serie2="#d95926"),
}


def cabecalho(t, titulo, subtitulo, x=28, y=34):
    return [texto(x, y, titulo, t["tinta"], 17, 600),
            texto(x, y + 21, subtitulo, t["tinta2"], 13)]


# --------------------------------------------------------------------------
# 1. A escada da memória contra o orçamento por pacote
# --------------------------------------------------------------------------
def escada(t, L):
    E, D, TOPO, ALT_B, PASSO = 108, 188, 122, 26, 46
    max_ns, larg = 120.0, LARGURA - E - D
    px = larg / max_ns
    alt = TOPO + PASSO * len(ESCADA) + 62
    c = cabecalho(t, L["esc_titulo"], L["esc_sub"])

    for v in range(0, 121, 20):                       # grade em fio de cabelo
        x = E + v * px
        c.append(linha(x, TOPO - 10, x, TOPO + PASSO * len(ESCADA) - 14, t["grade"]))
        c.append(texto(x, TOPO + PASSO * len(ESCADA) + 6, v, t["suave"], 12,
                       ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, TOPO + PASSO * len(ESCADA) + 26,
                   L["esc_eixo"], t["suave"], 12, ancora="middle"))

    xo = E + ORCAMENTO_NS * px                        # limiar: o orçamento
    c.append(linha(xo, TOPO - 32, xo, TOPO + PASSO * len(ESCADA) - 12,
                   t["tinta2"], 2, "5 4"))
    c.append(texto(xo, TOPO - 40, L["esc_orc"], t["tinta2"], 12, 600, ancora="middle"))

    for i, (nome, tam, ns) in enumerate(ESCADA):
        y = TOPO + i * PASSO - 14
        c.append(texto(E - 14, y + 18, nome, t["tinta"], 14, 600, ancora="end"))
        c.append(texto(E - 14, y + 33, tam, t["suave"], 11, ancora="end"))
        c.append(barra_h(E, y, ns * px, ALT_B, t["rampa"][i]))
        rot = f"{num(ns, L)} ns" if ns < 10 else f"{ns:.0f} ns"
        c.append(texto(E + ns * px + 10, y + 18, rot, t["tinta"], 13, 600, tabular=True))
        if nome == "RAM":
            c.append(texto(E + ns * px + 10, y + 34,
                           L["esc_excede"].format(ns - ORCAMENTO_NS), t["tinta2"], 12))
    return documento(LARGURA, alt, t["superficie"], L["esc_titulo"], L["esc_desc"], c)


# --------------------------------------------------------------------------
# 2. O conflito: o que a máquina entrega, e o que isso custa em espera
#
# Painel 2 é log-log de propósito, e a razão é geométrica, não estética:
# `lote = K × ns/acesso`. Se a concorrência fosse de graça, o ns/acesso cairia
# exatamente com 1/K e a curva do lote seria uma HORIZONTAL. Onde ela deixa de
# ser horizontal é, ponto a ponto, onde a concorrência passa a custar. Num eixo
# linear essa leitura não existe — a curva sobe desde o começo e o joelho some.
# --------------------------------------------------------------------------
def conflito(t, L):
    import math
    E, D, ALT_P, GAP, TOPO = 100, 150, 168, 74, 124
    larg = LARGURA - E - D
    alt = TOPO + 2 * ALT_P + GAP + 78
    ks = [k for k, _ in PARALELISMO]
    ns = [v for _, v in PARALELISMO]
    vaz = [1000.0 / v for v in ns]
    lote = [v * k for k, v in PARALELISMO]

    def x(k):
        return E + larg * math.log(k) / math.log(max(ks))

    c = cabecalho(t, L["con_titulo"], L["con_sub"])

    # ---- painel 1: vazão, escala linear, com o limiar de line rate ----
    TOPO_V = 300.0
    c.append(texto(E, TOPO - 14, L["con_p1"], t["tinta"], 14, 600))
    c.append(texto(28, TOPO - 34, L["con_y1"], t["suave"], 11))
    for i in range(5):
        yy = TOPO + ALT_P - ALT_P * i / 4
        c.append(linha(E, yy, E + larg, yy, t["grade"]))
        c.append(texto(E - 12, yy + 4, f"{round(TOPO_V * i / 4)}", t["suave"], 11,
                       ancora="end", tabular=True))
    yl = TOPO + ALT_P - ALT_P * LINE_RATE_MPPS / TOPO_V
    c.append(linha(E, yl, E + larg, yl, t["tinta2"], 2, "5 4"))
    c.append(texto(E + larg + 12, yl + 4, L["con_lr"], t["tinta2"], 12, 600))
    p1 = [(x(k), TOPO + ALT_P - ALT_P * v / TOPO_V) for k, v in zip(ks, vaz)]
    c.append(poli(p1, t["serie1"]))
    for px_, py_ in p1:
        c.append(ponto(px_, py_, t["serie1"], t["superficie"]))
    c.append(texto(p1[-1][0] - 6, p1[-1][1] - 16, f"{vaz[-1]:.0f} M/s", t["tinta"],
                   12, 600, ancora="end", tabular=True))
    c.append(texto(p1[0][0] + 12, p1[0][1] - 12, f"{num(vaz[0], L, 1)} M/s",
                   t["tinta"], 12, 600, tabular=True))

    # ---- painel 2: as duas grandezas em ns, log-log ----
    y2 = TOPO + ALT_P + GAP
    BAIXO, ALTO = 2.5, 300.0

    def yln(v):
        return y2 + ALT_P - ALT_P * (math.log(v) - math.log(BAIXO)) / (
            math.log(ALTO) - math.log(BAIXO))

    c.append(texto(E, y2 - 14, L["con_p2"], t["tinta"], 14, 600))
    c.append(texto(28, y2 - 34, L["con_y2"], t["suave"], 11))
    for v in (3, 10, 30, 100, 300):
        c.append(linha(E, yln(v), E + larg, yln(v), t["grade"]))
        c.append(texto(E - 12, yln(v) + 4, v, t["suave"], 11, ancora="end", tabular=True))

    pl = [(x(k), yln(v)) for k, v in zip(ks, lote)]
    pn = [(x(k), yln(v)) for k, v in zip(ks, ns)]
    c.append(poli(pl, t["serie2"]))
    c.append(poli(pn, t["serie1"]))
    for pts, cor in ((pl, t["serie2"]), (pn, t["serie1"])):
        for px_, py_ in pts:
            c.append(ponto(px_, py_, cor, t["superficie"]))
    c.append(texto(pl[-1][0] - 6, pl[-1][1] - 16, f"{lote[-1]:.0f} ns", t["tinta"],
                   12, 600, ancora="end", tabular=True))
    c.append(texto(pn[-1][0] - 6, pn[-1][1] + 22, f"{num(ns[-1], L)} ns",
                   t["tinta"], 12, 600, ancora="end", tabular=True))
    c.append(texto(pn[0][0] + 12, pn[0][1] - 12, f"{ns[0]:.0f} ns", t["tinta"],
                   12, 600, tabular=True))

    # eixo K, compartilhado pelos dois painéis
    for k in ks:
        c.append(texto(x(k), y2 + ALT_P + 22, k, t["suave"], 12,
                       ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, y2 + ALT_P + 40, L["con_x"],
                   t["suave"], 12, ancora="middle"))

    # legenda do painel 2: com duas séries, a cor nunca carrega a identidade sozinha
    lx = E
    for cor, rot in ((t["serie1"], L["con_leg1"]), (t["serie2"], L["con_leg2"])):
        c.append(ponto(lx + 5, y2 + ALT_P + 62, cor, t["superficie"]))
        c.append(texto(lx + 18, y2 + ALT_P + 66, rot, t["tinta2"], 12))
        lx += 26 + len(rot) * 6.6

    xk = x(16)
    c.append(linha(xk, TOPO - 6, xk, y2 + ALT_P, t["suave"], 1))
    c.append(texto(xk + 8, TOPO - 52, L["con_nota1"], t["tinta"], 12, 600))
    c.append(texto(xk + 8, TOPO - 36, L["con_nota2"], t["tinta2"], 12))
    return documento(LARGURA, alt, t["superficie"], L["con_titulo"], L["con_desc"], c)


# --------------------------------------------------------------------------
# 3. A mesma RAM, três padrões de acesso
# --------------------------------------------------------------------------
def banda(t, L):
    E, D, TOPO, ALT_B, PASSO = 300, 128, 92, 28, 50
    larg = LARGURA - E - D
    topo_v = 21.0
    px = larg / topo_v
    alt = TOPO + PASSO * len(BANDA) + 58
    c = cabecalho(t, L["ban_titulo"], L["ban_sub"])
    for v in range(0, 22, 3):
        x = E + v * px
        c.append(linha(x, TOPO - 12, x, TOPO + PASSO * len(BANDA) - 20, t["grade"]))
        c.append(texto(x, TOPO + PASSO * len(BANDA), v, t["suave"], 12,
                       ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, TOPO + PASSO * len(BANDA) + 20,
                   L["ban_eixo"], t["suave"], 12, ancora="middle"))
    for i, ((_, gbs), nome) in enumerate(zip(BANDA, L["ban_rot"])):
        y = TOPO + i * PASSO - 20
        c.append(texto(E - 16, y + 19, nome, t["tinta"], 13, ancora="end"))
        c.append(barra_h(E, y, gbs * px, ALT_B, t["serie1"]))
        c.append(texto(E + gbs * px + 10, y + 19, f'{num(gbs, L, 1)} {L["ban_un"]}',
                       t["tinta"], 13, 600, tabular=True))
    c.append(texto(28, TOPO + PASSO * len(BANDA) + 40,
                   L["ban_fecho"].format(BANDA[0][1] / BANDA[2][1]),
                   t["tinta"], 13, 600))
    return documento(LARGURA, alt, t["superficie"], L["ban_titulo"], L["ban_desc"], c)


# --------------------------------------------------------------------------
# 4. O teto é compartilhado: escala com o número de núcleos
# --------------------------------------------------------------------------
def escala(t, L):
    E, D, ALT_P, TOPO = 104, 168, 214, 118
    larg = LARGURA - E - D
    alt = TOPO + ALT_P + 76
    ns = [(n, 1000.0 * n / v) for n, v in NUCLEOS]      # vazão agregada
    base = 1000.0 / NUCLEOS[0][1]
    topo_v = 1700.0
    c = cabecalho(t, L["sca_titulo"], L["sca_sub"])

    def x(n):
        return E + larg * (n - 1) / (NUCLEOS[-1][0] - 1)

    for i in range(5):
        yy = TOPO + ALT_P - ALT_P * i / 4
        c.append(linha(E, yy, E + larg, yy, t["grade"]))
        c.append(texto(E - 12, yy + 4, f"{round(topo_v * i / 4):,}".replace(",", " "),
                       t["suave"], 11, ancora="end", tabular=True))
    c.append(texto(28, TOPO - 20, L["sca_y"], t["suave"], 11))

    ideal = [(n, base * n) for n, _ in NUCLEOS]          # referência, não série
    pi = [(x(n), TOPO + ALT_P - ALT_P * min(v, topo_v) / topo_v) for n, v in ideal]
    c.append(poli(pi, t["suave"], 2))
    c.append(texto(pi[-1][0] - 4, pi[-1][1] - 12,
                   L["sca_ideal"], t["suave"], 12, 600, ancora="end"))

    pts = [(x(n), TOPO + ALT_P - ALT_P * v / topo_v) for n, v in ns]
    c.append(poli(pts, t["serie1"]))
    for px_, py_ in pts:
        c.append(ponto(px_, py_, t["serie1"], t["superficie"]))
    c.append(texto(pts[-1][0] - 6, pts[-1][1] + 26,
                   L["sca_teto"].format(ns[-1][1]), t["tinta"], 12, 600,
                   ancora="end", tabular=True))
    c.append(texto(pts[0][0] + 12, pts[0][1] - 14, L["sca_ms"].format(ns[0][1]),
                   t["tinta"], 12, 600, tabular=True))

    for n, _ in NUCLEOS:
        c.append(texto(x(n), TOPO + ALT_P + 22, n, t["suave"], 12,
                       ancora="middle", tabular=True))
    c.append(texto(E + larg / 2, TOPO + ALT_P + 40, L["sca_x"],
                   t["suave"], 12, ancora="middle"))
    c.append(texto(28, TOPO + ALT_P + 64, L["sca_fecho"], t["tinta"], 13, 600))
    return documento(LARGURA, alt, t["superficie"], L["sca_titulo"], L["sca_desc"], c)


if __name__ == "__main__":
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome, fn in (("escada", escada), ("conflito", conflito),
                     ("banda", banda), ("escala", escala)):
        for idioma, L in TEXTOS.items():
            for tema, t in TEMAS.items():
                alvo = SAIDA / f"4-{nome}-{tema}{L['sufixo']}.svg"
                alvo.write_text(fn(t, L), encoding="utf-8")
                print(f"  {alvo.relative_to(SAIDA.parents[2])}  ({alvo.stat().st_size} B)")
