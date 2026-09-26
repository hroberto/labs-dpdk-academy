#!/usr/bin/env python3
"""Produz as tabelas da §6 do topico de isolamento a partir das coletas.

POR QUE ESTE ARQUIVO EXISTE

A §6 publicava a coleta `C`, de 23/09/2026 -- uma das dez removidas em
`1e925358` ao adotar o protocolo de modo texto. Aquele commit declarou o estado
que criava: *"os numeros publicados no topico descrevem coletas que nao estao
arquivadas aqui ate as quatro celulas serem medidas"*. As quatro celulas foram
medidas sete vezes desde entao, e a §6 continuou citando a coleta que ninguem
consegue abrir.

O desencontro nao era so de procedencia. A coleta C publicava maior parada de
752,9 us e cinco das vinte execucoes acima da janela de 512 descritores; nas
sete coletas arquivadas -- 140 execucoes -- a maior parada observada e de
55,7 us e a contagem acima da janela e de 1 a 2 em 20. O modo alto que a §6.1
descrevia como bimodalidade nao aparece em nenhuma delas, o que e exatamente o
que a §6.6 conclui: ele era a sessao grafica.

O QUE ELE DECIDE, E POR QUE

  - agrega as SETE coletas de modo texto, e nao uma. Aqui a agregacao e o
    resultado, nao uma conveniencia: uma coleta de cinco execucoes por celula
    nao separa medianas que distam 2 us, e foi essa falta de poder que deixou a
    §6.5 sem veredito. Com 35 execucoes por celula a comparacao passa a ter o
    que decidir;
  - descarta nada por aquecimento: a campanha de isolamento nao tem `r0`, e as
    cinco repeticoes de cada celula correm em ordem permutada, que e o desenho
    que dispensa o descarte;
  - o LIMIAR DA SONDA DIFERE POR CELULA -- 1 us na celula do provocador em
    thread, 2 us nas outras -- e por isso a coluna de contagem de paradas NAO e
    comparavel entre celulas. O programa emite o limiar de cada linha, o que a
    tabela publicada anterior omitia enquanto chamava a coluna de "paradas
    > 2 us";
  - a correlacao entre preempcoes e maior parada sai por POSTO (Spearman),
    porque a maior parada tem cauda e a correlacao linear a deixaria dominada
    por uma execucao;
  - a comparacao entre celulas sai por POSTO tambem (Mann-Whitney), e pela
    mesma razao. O p que ele devolve e por aproximacao normal SEM correcao de
    continuidade, o que e adequado com 35 contra 35 e seria grosseiro com
    amostras pequenas -- e esta dito aqui porque e uma limitacao do numero,
    nao um detalhe de implementacao.

O QUE ELE NAO AUTORIZA

A comparacao entre celulas e POST HOC. As coletas foram desenhadas para medir
cada celula, nao para testar esta diferenca, e nenhum criterio de refutacao foi
registrado antes. O p serve para dizer que a diferenca nao e ruido de amostra;
nao serve como confirmacao de hipotese, e o texto que o publica precisa dizer
isso.

O MODO `--conferir` E O PORTAO

Ter o programa nao e o mesmo que o documento usar o programa. As tres tabelas
consolidadas nao tem a forma de nenhum `printf` arquivado -- sao tabelas
Markdown --, e por isso caem fora do escopo do `verificar-blocos.py`, como o
cabecalho daquele verificador declara. `--conferir` regenera as tres a partir
do historico e compara com o publicado, nos dois idiomas. Ele FALHA quando uma
coleta nova move a mediana sem que alguem republique: e o sinal, nao o defeito.

    uso:  consolidar-isolamento.py <dir-do-historico> [--celulas|--estados|--tlb|--escalares] [--en]
          consolidar-isolamento.py --conferir
          consolidar-isolamento.py --autoteste
"""
import glob
import os
import re
import statistics
import sys

import condicao_coleta

# A ordem em que a §6 publica as celulas, com o rotulo de cada idioma.
CELULAS = [("P0", "P0 — só afinidade", "P0 — affinity only"),
           ("P0+ipi-thread", "P0 + provocador **thread**", "P0 + **thread** provoker"),
           ("P0+ipi-proc", "P0 + provocador **processo**", "P0 + **process** provoker"),
           ("P5-irmao", "P5 — irmão SMT carregado", "P5 — busy SMT sibling")]

CAMPOS = {
    "limiar": re.compile(r"^stall probe:.*threshold (\d+) ns"),
    "amostras": re.compile(r"^samples: (\d+)"),
    "paradas": re.compile(r"^stalls above threshold: (\d+)"),
    "maior": re.compile(r"^max stall: (\d+) ns"),
    "preempcoes": re.compile(r"^involuntary context switches: (\d+)"),
}
IRQ = re.compile(r"^  ([A-Z]{3})\s+(\d+)\s*$")
# A janela de 512 descritores a 10 GbE com quadro de 64 B. O programa a imprime
# em cada execucao, e le-la de la evita que a constante envelheca aqui.
JANELA = re.compile(r"^   512 descriptors: ([\d.]+) us")


def ler(raiz, so_texto=True):
    """-> {coleta: {celula: [execucao, ...]}}, cada execucao um dict de campos.

    `so_texto` FILTRA POR CONDICAO, e o padrao e True porque a §6 publica as
    coletas sem sessao grafica. Em 25/09/2026, com a primeira coleta grafica
    arquivada, a versao sem filtro passou a AGREGAR as duas condicoes numa
    tabela so -- oito coletas e 160 execucoes onde a §6 diz sete e 140. Mediana
    entre condicoes diferentes nao e mediana de nada.
    """
    saida = {}
    for d in sorted(glob.glob(os.path.join(raiz, "*", "isolamento"))):
        coleta = os.path.basename(os.path.dirname(d))
        if so_texto and condicao_coleta.e_texto(os.path.dirname(d)) is False:
            continue
        for chave, _, _ in CELULAS:
            for f in sorted(glob.glob(os.path.join(d, chave + ".r[1-9]*.txt"))):
                e = {"irq": {}}
                for l in open(f, encoding="utf-8", errors="replace"):
                    for nome, pat in CAMPOS.items():
                        m = pat.match(l)
                        if m:
                            e[nome] = int(m.group(1))
                    m = IRQ.match(l)
                    if m:
                        e["irq"][m.group(1)] = int(m.group(2))
                    m = JANELA.match(l)
                    if m:
                        e["janela"] = float(m.group(1))
                if "maior" in e:
                    saida.setdefault(coleta, {}).setdefault(chave, []).append(e)
    return saida


def execucoes(dados, celula=None):
    """Todas as execucoes, de todas as coletas, opcionalmente de uma celula."""
    return [e for c in dados.values() for k, v in c.items()
            if celula is None or k == celula for e in v]


def janela(dados):
    """A janela de 512 descritores, como as coletas a declaram."""
    vals = {e.get("janela") for e in execucoes(dados)} - {None}
    if len(vals) != 1:
        raise SystemExit("coletas discordam da janela de 512 descritores: %r" % vals)
    return vals.pop()


def milhar(v, en):
    """37940 -> `37 940` em portugues, `37,940` em ingles, como o topico publica."""
    return "{:,}".format(int(v)).replace(",", "," if en else chr(32))


def mediana_irq(execs, nome):
    v = [e["irq"].get(nome, 0) for e in execs]
    return round(statistics.median(v)) if v else 0


def bloco_celulas(dados, en=False):
    """A tabela por celula: mediana de cada grandeza sobre TODAS as coletas."""
    cab = ("| Célula | limiar | maior parada | paradas ≥ limiar | preempções |"
           " `TLB` | `CAL` | `LOC` |\n|---|---:|---:|---:|---:|---:|---:|---:|")
    if en:
        cab = ("| Cell | threshold | max stall | stalls ≥ threshold | preemptions |"
               " `TLB` | `CAL` | `LOC` |\n|---|---:|---:|---:|---:|---:|---:|---:|")
    linhas = [cab]
    for chave, pt, ingles in CELULAS:
        ex = execucoes(dados, chave)
        if not ex:
            continue
        lim = {e["limiar"] for e in ex}
        # Limiar diferente dentro da MESMA celula tornaria a contagem
        # incomparavel tambem entre execucoes, e ai nao ha mediana que salve.
        if len(lim) != 1:
            raise SystemExit("celula %s tem limiares diferentes: %r" % (chave, lim))
        dec = "." if en else ","
        linhas.append("| %s | %d µs | %s µs | %s | %s | %s | %s | %s |" % (
            ingles if en else pt, lim.pop() // 1000,
            ("%.1f" % (statistics.median([e["maior"] for e in ex]) / 1000)).replace(".", dec),
            milhar(round(statistics.median([e["paradas"] for e in ex])), en),
            milhar(round(statistics.median([e["preempcoes"] for e in ex])), en),
            milhar(mediana_irq(ex, "TLB"), en), milhar(mediana_irq(ex, "CAL"), en),
            milhar(mediana_irq(ex, "LOC"), en)))
    return "\n".join(linhas)


def bloco_estados(dados, en=False):
    """Uma linha por coleta: mediana das 20 execucoes e contagem acima da janela."""
    jan = janela(dados)
    cab = ("| Coleta | maior parada, mediana | acima de %s µs | maior observada |\n"
           "|---|---:|---:|---:|") % ("%.1f" % jan).replace(".", ",")
    if en:
        cab = ("| Collection | max stall, median | above %.1f µs | largest seen |\n"
               "|---|---:|---:|---:|") % jan
    dec = "." if en else ","
    linhas = [cab]
    for coleta in sorted(dados):
        ex = execucoes({coleta: dados[coleta]})
        v = [e["maior"] / 1000 for e in ex]
        linhas.append("| `%s` | %s µs | %d/%d | %s µs |" % (
            coleta, ("%.1f" % statistics.median(v)).replace(".", dec),
            sum(1 for x in v if x > jan), len(v),
            ("%.1f" % max(v)).replace(".", dec)))
    return "\n".join(linhas)


def rotulo_curto(coleta):
    """`2026-09-24-0955-jedec4800-canal-unico-texto` -> `0955 4800 1c`.

    O nome de diretorio inteiro nao cabe num cabecalho de sete colunas, e uma
    tabela que estoura a largura deixa de ser lida. O rotulo guarda o que
    distingue as coletas entre si: a hora, a memoria e o numero de canais.
    """
    partes = coleta.split("-")
    hora = partes[3]
    mem = "4800" if "jedec4800" in coleta else "6000" if "expo6000" in coleta else "?"
    canais = "1c" if "canal-unico" in coleta else "2c" if "canal-duplo" in coleta else "?"
    return "%s %s %s" % (hora, mem, canais)


def bloco_tlb(dados, en=False):
    """O contraste de `TLB` entre as duas celulas de provocador, por coleta."""
    colunas = sorted(dados)
    cab = "| | " + " | ".join(rotulo_curto(c) for c in colunas) + " |"
    sep = "|---|" + "---:|" * len(colunas)
    rot = ("**thread** provoker", "**process** provoker") if en else \
          ("provocador **thread**", "provocador **processo**")
    linhas = [cab, sep]
    for chave, rotulo in (("P0+ipi-thread", rot[0]), ("P0+ipi-proc", rot[1])):
        v = []
        for c in colunas:
            ex = dados[c].get(chave, [])
            v.append(milhar(mediana_irq(ex, "TLB"), en) if ex else "—")
        linhas.append("| %s | %s |" % (rotulo, " | ".join(v)))
    return "\n".join(linhas)


def spearman(xs, ys):
    """Correlacao de posto. Empates recebem o posto MEDIO, como manda a definicao.

    Sem o tratamento de empate a contagem de preempcoes -- que repete valores --
    produziria um rho inflado, e este programa existe para nao publicar numero
    que so parece certo.
    """
    def postos(v):
        ordem = sorted(range(len(v)), key=lambda i: v[i])
        p = [0.0] * len(v)
        i = 0
        while i < len(ordem):
            j = i
            while j + 1 < len(ordem) and v[ordem[j + 1]] == v[ordem[i]]:
                j += 1
            medio = (i + j) / 2 + 1
            for k in range(i, j + 1):
                p[ordem[k]] = medio
            i = j + 1
        return p
    a, b = postos(xs), postos(ys)
    n = len(a)
    ma, mb = sum(a) / n, sum(b) / n
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    den = (sum((x - ma) ** 2 for x in a) * sum((y - mb) ** 2 for y in b)) ** 0.5
    return num / den if den else 0.0


def mann_whitney(a, b):
    """(U, z, p bilateral, P(b > a)) por posto, com empate valendo meio.

    Sem correcao de continuidade: com 35 contra 35 a aproximacao normal ja e
    boa, e a correcao mudaria a terceira casa. Com amostra pequena o numero
    daqui seria otimista, e e por isso que esta escrito.

    COM CORRECAO DE VARIANCIA POR EMPATES. O `0.5` acima trata o empate no U, e
    so nele: a variancia usada para o `z` presumia que nao ha valores repetidos.

    A DIRECAO DO ERRO E UMA SO, e a primeira versao deste comentario dizia que
    dependia do sinal -- estava errado. Empate REDUZ a variancia verdadeira;
    ignora-lo usa um `sd` maior que o correto, o que encolhe `|z|` e, como o
    `p` daqui e BILATERAL (`erfc(|z|/sqrt(2))`), aumenta o `p` sempre. Nao e
    otimista em direcao nenhuma: e conservador quanto a rejeitar a hipotese
    nula, o que e mais seguro e ainda assim errado.

    O proprio numero medido ja dizia isso: no conjunto com empates do
    autoteste, `p` sem correcao da 0,0845 e com correcao da 0,0746.

    MEDIDO ANTES DE ESCREVER: sobre as coletas de 26/09/2026, P0 contra
    P0+ipi-thread, sao 70 observacoes com 70 valores DISTINTOS -- zero grupos de
    empate, zero pares cruzados empatados. A correcao e no-op ali: `sd` de
    85.134697 nos dois casos, e `p` de 0.368879 nos dois. Ela entra porque o
    proximo conjunto de dados pode empatar, e porque uma formula certa nao
    depende de os dados serem gentis; nao entra porque mudou algum numero
    publicado, e dizer isso e melhor que deixar supor que mudou.
    """
    import math
    import collections
    n1, n2 = len(a), len(b)
    if not n1 or not n2:
        return 0.0, 0.0, 1.0, 0.5
    U = sum(1 for x in a for y in b if x < y) + \
        0.5 * sum(1 for x in a for y in b if x == y)
    mu = n1 * n2 / 2
    n = n1 + n2
    # sum(t^3 - t) sobre os grupos de empate das DUAS amostras juntas, que e a
    # forma padrao da correcao. Sem empates a soma e zero e o termo desaparece.
    contagem = collections.Counter(list(a) + list(b))
    soma_t = sum(t ** 3 - t for t in contagem.values())
    variancia = (n1 * n2 / 12.0) * ((n + 1) - soma_t / (n * (n - 1))) if n > 1 else 0.0
    sd = variancia ** 0.5 if variancia > 0 else 0.0
    z = (U - mu) / sd if sd else 0.0
    return U, z, math.erfc(abs(z) / math.sqrt(2)), U / (n1 * n2)


def escalares(dados):
    """Os numeros que a prosa da §6 cita, cada um com o nome do que ele e."""
    todas = execucoes(dados)
    jan = janela(dados)
    v = sorted(e["maior"] / 1000 for e in todas)
    acima = [x for x in v if x > jan]
    p0 = execucoes(dados, "P0")
    tr = execucoes(dados, "P0+ipi-thread")
    pr = execucoes(dados, "P0+ipi-proc")
    p5 = execucoes(dados, "P5-irmao")
    # As trocas involuntarias por segundo: a sonda corre 30 s em cada execucao.
    taxa = sorted(e["preempcoes"] / 30.0 for e in todas)
    return {
        "coletas": len(dados),
        "execucoes": len(todas),
        "janela-512": jan,
        "maior-parada-min": v[0],
        "maior-parada-mediana": statistics.median(v),
        "maior-parada-max": v[-1],
        "acima-da-janela": len(acima),
        "acima-da-janela-menor": min(acima) if acima else None,
        "razao-maior-por-janela": v[-1] / jan,
        "p0-mediana": statistics.median([e["maior"] / 1000 for e in p0]),
        "thread-mediana": statistics.median([e["maior"] / 1000 for e in tr]),
        "proc-mediana": statistics.median([e["maior"] / 1000 for e in pr]),
        "p5-mediana": statistics.median([e["maior"] / 1000 for e in p5]),
        "paradas-p0": round(statistics.median([e["paradas"] for e in p0])),
        "paradas-thread": round(statistics.median([e["paradas"] for e in tr])),
        "tlb-thread": mediana_irq(tr, "TLB"),
        "tlb-proc": mediana_irq(pr, "TLB"),
        "preempcoes-por-s-min": taxa[0],
        "preempcoes-por-s-max": taxa[-1],
        "rho-preempcao-parada": spearman([e["preempcoes"] for e in todas],
                                         [e["maior"] for e in todas]),
        "p5-vs-p0-p": mann_whitney([e["maior"] for e in p0],
                                   [e["maior"] for e in p5])[2],
        "p5-vs-p0-prob": mann_whitney([e["maior"] for e in p0],
                                      [e["maior"] for e in p5])[3],
        "thread-vs-p0-p": mann_whitney([e["maior"] for e in p0],
                                       [e["maior"] for e in tr])[2],
        "proc-vs-p0-p": mann_whitney([e["maior"] for e in p0],
                                     [e["maior"] for e in pr])[2],
    }


# Onde cada tabela consolidada e publicada. O bloco e localizado pelo proprio
# CABECALHO, e nao por numero de linha: numero de linha envelhece a cada
# paragrafo inserido, e um portao que envelhece deixa de ser portao.
PUBLICADOS = [((), "trilha/03-performance/03-isolamento-cpu/README.md"),
              (("--en",), "trilha/03-performance/03-isolamento-cpu/README.en.md"),
              (("--estados",), "trilha/03-performance/03-isolamento-cpu/README.md"),
              (("--estados", "--en"), "trilha/03-performance/03-isolamento-cpu/README.en.md"),
              (("--tlb",), "trilha/03-performance/03-isolamento-cpu/README.md"),
              (("--tlb", "--en"), "trilha/03-performance/03-isolamento-cpu/README.en.md")]


def conferir(raiz):
    dados = ler(os.path.join(raiz, "trilha/03-performance/03-isolamento-cpu/historico"))
    if not dados:
        print("  nenhuma coleta com isolamento/ no historico do topico")
        return 1
    problemas = 0
    for args, arquivo in PUBLICADOS:
        en = "--en" in args
        novo = (bloco_estados(dados, en) if "--estados" in args else
                bloco_tlb(dados, en) if "--tlb" in args else
                bloco_celulas(dados, en)).split("\n")
        texto = open(os.path.join(raiz, arquivo), encoding="utf-8").read()
        if "\n".join(novo) in texto:
            continue
        if novo[0] not in texto:
            print("  %s: nao encontrei a tabela de cabecalho %r"
                  % (arquivo, novo[0][:56]))
            problemas += 1
            continue
        atual = texto.split(novo[0] + "\n")[1].split("\n\n")[0].split("\n")
        for esperada, tem in zip(novo[1:], atual):
            if esperada != tem:
                print("  %s: o historico da\n      %s\n    e o documento publica"
                      "\n      %s" % (arquivo, esperada, tem))
                problemas += 1
                break
    print("\n  %d tabela(s) consolidada(s) conferida(s) contra %d coleta(s)"
          " / %d execucao(oes); %d divergencia(s)"
          % (len(PUBLICADOS), len(dados), len(execucoes(dados)), problemas))
    return problemas


def autoteste():
    falhas = 0

    def caso(n, descricao, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    # 1 a 3. SPEARMAN COM EMPATE. Uma implementacao que ignorasse o empate daria
    #    1.0 no caso 2, porque a ordem de desempate seria a mesma nas duas
    #    listas por acidente de indice.
    caso(1, "spearman monotonico da 1", round(spearman([1, 2, 3], [10, 20, 30]), 6), 1.0)
    # O EMPATE PRECISA DE TRES VALORES DISTINTOS PARA TESTAR ALGUMA COISA. Com
    # `[1, 1, 3]` o posto medio `[1.5, 1.5, 3]` e transformacao AFIM de
    # `[1, 1, 3]`, e Pearson -- de que Spearman e um caso -- e invariante a
    # afim: os dois dao 0,866, e um mutante que trocasse o posto medio pelo
    # menor sobreviveria ao teste. Com `[1, 1, 2, 3]` a relacao deixa de ser
    # afim e o teste passa a distinguir.
    caso(2, "spearman com empate usa posto medio",
         round(spearman([1, 1, 2, 3], [10, 20, 30, 40]), 4), round(0.9486833, 4))
    caso(3, "spearman invertido da -1",
         round(spearman([1, 2, 3], [30, 20, 10]), 6), -1.0)
    # 4. Monotonico NAO linear tem de dar 1: e a razao de usar posto.
    caso(4, "spearman ignora a escala", round(spearman([1, 2, 3], [1, 2, 1000]), 6), 1.0)

    # 13 a 16. MANN-WHITNEY. O caso separado da p pequeno; o caso sobreposto,
    #    p grande. E o empate vale meio: duas amostras identicas tem de dar
    #    exatamente 0,5 de probabilidade, e uma versao que contasse empate
    #    como vitoria daria 1,0.
    U, z, pv, prob = mann_whitney([1, 2, 3, 4, 5], [11, 12, 13, 14, 15])
    caso(13, "amostras separadas: probabilidade 1", prob, 1.0)
    caso(14, "amostras separadas: p pequeno", pv < 0.01, True)
    _, _, pv2, prob2 = mann_whitney([1, 2, 3], [1, 2, 3])
    caso(15, "amostras identicas: probabilidade 0,5", prob2, 0.5)

    # A CORRECAO POR EMPATES AGE, e este caso e o que prova.
    #
    # Sobre os dados reais ela e no-op: 70 observacoes, 70 valores distintos.
    # Um teste so com eles nao distinguiria a formula certa da anterior -- e
    # uma correcao que nunca dispara e indistinguivel de uma que nao existe.
    # Aqui os empates sao construidos, e o `p` corrigido fica MENOR: empate
    # reduz a variancia, o `z` cresce em modulo, e ignorar isso era otimista.
    _, _, p_emp, _ = mann_whitney([1, 2, 2, 3, 3, 3, 4], [2, 3, 3, 4, 4, 5, 5])
    n1 = n2 = 7
    sd_sem = (n1 * n2 * (n1 + n2 + 1) / 12) ** 0.5
    u_emp = sum(1 for x in [1, 2, 2, 3, 3, 3, 4] for y in [2, 3, 3, 4, 4, 5, 5] if x < y) \
            + 0.5 * sum(1 for x in [1, 2, 2, 3, 3, 3, 4] for y in [2, 3, 3, 4, 4, 5, 5] if x == y)
    import math as _m
    p_sem = _m.erfc(abs((u_emp - n1 * n2 / 2) / sd_sem) / _m.sqrt(2))
    caso(20, "com empates, o p corrigido e menor que o sem correcao",
         p_emp < p_sem, True)
    caso(21, "e a diferenca nao e ruido de arredondamento",
         round(p_sem - p_emp, 4), 0.0099)
    caso(17, "rotulo curto guarda hora, memoria e canais",
         rotulo_curto("2026-09-24-0955-jedec4800-canal-unico-texto"), "0955 4800 1c")
    caso(18, "rotulo curto do canal duplo em 6000",
         rotulo_curto("2026-09-25-1720-expo6000-canal-duplo"), "1720 6000 2c")
    caso(16, "amostras identicas: p igual a 1", round(pv2, 6), 1.0)

    def ex(maior, limiar=2000, paradas=10, preemp=200, irq=None, jan=34.4):
        return {"maior": maior, "limiar": limiar, "paradas": paradas,
                "preempcoes": preemp, "irq": irq or {}, "janela": jan,
                "amostras": 1}
    dados = {"c1": {"P0": [ex(20000), ex(30000)],
                    "P0+ipi-thread": [ex(21000, limiar=1000, paradas=15000,
                                         irq={"TLB": 38000})],
                    "P0+ipi-proc": [ex(22000, irq={"TLB": 0})],
                    "P5-irmao": [ex(90000)]},
             "c2": {"P0": [ex(24000)]}}

    # 5. O LIMIAR VAI NA TABELA. A celula do provocador em thread conta paradas
    #    acima de 1 us, e a tabela anterior chamava a coluna de "paradas > 2 us"
    #    para as quatro -- somando o que nao se soma.
    linhas = bloco_celulas(dados).splitlines()
    caso(5, "cada linha publica o proprio limiar",
         [l.split("|")[2].strip() for l in linhas[2:]],
         ["2 µs", "1 µs", "2 µs", "2 µs"])

    # 6. A mediana e sobre TODAS as coletas, nao sobre a primeira.
    caso(6, "P0 agrega as duas coletas (20, 24, 30 -> 24)",
         linhas[2].split("|")[3].strip(), "24,0 µs")
    # O separador de milhar do portugues e o espaco COMUM, comparado por codigo
    # de caractere: NBSP e espaco estreito sao indistinguiveis a olho, e um
    # deles ja entrou num consolidador deste projeto por copia.
    caso(19, "milhar em portugues usa o espaco comum",
         [ord(c) for c in milhar(37940, False)], [51, 55, 32, 57, 52, 48])
    caso(20, "milhar em ingles usa virgula", milhar(37940, True), "37,940")
    caso(7, "o ingles usa ponto decimal",
         bloco_celulas(dados, True).splitlines()[2].split("|")[3].strip(), "24.0 µs")

    # 8/9. A contagem acima da janela e por execucao, e a janela vem da coleta.
    e = escalares(dados)
    caso(8, "janela lida da coleta", e["janela-512"], 34.4)
    caso(9, "so a execucao de 90 us passa da janela", e["acima-da-janela"], 1)
    caso(10, "as 6 execucoes entram no total", e["execucoes"], 6)

    # 11. Limiar inconsistente DENTRO de uma celula aborta, em vez de publicar
    #     uma mediana entre contagens que medem coisas diferentes.
    ruim = {"c1": {"P0": [ex(20000, limiar=2000), ex(20000, limiar=1000)]}}
    try:
        bloco_celulas(ruim)
        caso(11, "limiar misto na mesma celula aborta", "passou", "SystemExit")
    except SystemExit:
        caso(11, "limiar misto na mesma celula aborta", "SystemExit", "SystemExit")

    # 12. Janela divergente entre coletas tambem aborta: comparar contagens
    #     acima de janelas diferentes seria somar duas perguntas.
    ruim2 = {"c1": {"P0": [ex(20000, jan=34.4)]}, "c2": {"P0": [ex(20000, jan=68.8)]}}
    try:
        janela(ruim2)
        caso(12, "janela divergente aborta", "passou", "SystemExit")
    except SystemExit:
        caso(12, "janela divergente aborta", "SystemExit", "SystemExit")

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    if "--conferir" in sys.argv:
        sys.exit(1 if conferir(os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))))) else 0)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__.rstrip().rsplit("uso:", 1)[-1], file=sys.stderr)
        sys.exit(2)
    dados = ler(args[0])
    if not dados:
        print("nenhuma coleta com isolamento/ em %s" % args[0], file=sys.stderr)
        sys.exit(1)
    en = "--en" in sys.argv
    if "--estados" in sys.argv:
        print(bloco_estados(dados, en))
    elif "--tlb" in sys.argv:
        print(bloco_tlb(dados, en))
    elif "--escalares" in sys.argv:
        for k, v in escalares(dados).items():
            print("%-24s %s" % (k, ("%.4f" % v) if isinstance(v, float) else v))
    else:
        print(bloco_celulas(dados, en))
    print("\n  (%d coleta(s), %d execucao(oes))"
          % (len(dados), len(execucoes(dados))), file=sys.stderr)
