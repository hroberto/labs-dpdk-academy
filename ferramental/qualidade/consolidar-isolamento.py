#!/usr/bin/env python3
"""Produz as tabelas da §6 do topico de isolamento a partir das coletas.

POR QUE ESTE ARQUIVO EXISTE

A §6 publicava a coleta `C`, de 23/09/2026 -- uma das dez removidas em
`1e925358` ao adotar o protocolo de modo texto. Aquele commit declarou o estado
que criava: *"os numeros publicados no topico descrevem coletas que nao estao
arquivadas aqui ate as quatro celulas serem medidas"*. As quatro celulas foram
medidas dez vezes desde entao, e a §6 continuou citando a coleta que ninguem
consegue abrir.

O desencontro nao era so de procedencia. A coleta C publicava maior parada de
752,9 us e cinco das vinte execucoes acima da janela de 512 descritores; nas
dez coletas arquivadas -- 200 execucoes -- a maior parada observada e de
55,7 us e a contagem acima da janela e de 0 a 3 em 20. O modo alto que a §6.1
descrevia como bimodalidade nao aparece em nenhuma delas, o que e exatamente o
que a §6.6 conclui: ele era a sessao grafica.

O QUE ELE DECIDE, E POR QUE

  - agrega TODAS as coletas de modo texto -- dez, hoje --, e nao uma. Aqui a
    agregacao e o resultado, nao uma conveniencia: uma coleta de cinco
    execucoes por celula nao separa medianas que distam 2 us, e foi essa falta
    de poder que deixou a §6.5 sem veredito. Com 50 execucoes por celula a
    comparacao passa a ter o que decidir. O numero de coletas NAO aparece em
    nenhuma constante: ele sai da contagem, e por isso esta frase e a unica
    coisa aqui que envelhece;
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
    continuidade, o que e adequado com 50 contra 50 e seria grosseiro com
    amostras pequenas -- e esta dito aqui porque e uma limitacao do numero,
    nao um detalhe de implementacao.

O QUE ELE NAO AUTORIZA

A comparacao entre celulas e POST HOC. As coletas foram desenhadas para medir
cada celula, nao para testar esta diferenca, e nenhum criterio de refutacao foi
registrado antes. O p serve para dizer que a diferenca nao e ruido de amostra;
nao serve como confirmacao de hipotese, e o texto que o publica precisa dizer
isso.

O MODO `--conferir` E O PORTAO

Ter o programa nao e o mesmo que o documento usar o programa. As quatro tabelas
consolidadas nao tem a forma de nenhum `printf` arquivado -- sao tabelas
Markdown --, e por isso caem fora do escopo do `verificar-blocos.py`, como o
cabecalho daquele verificador declara. `--conferir` regenera as quatro a partir
do historico e compara com o publicado, nos dois idiomas. Ele FALHA quando uma
coleta nova move a mediana sem que alguem republique: e o sinal, nao o defeito.

    uso:  consolidar-isolamento.py <dir> [--celulas|--estados|--tlb|--grafico|--escalares] [--en]
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


def _ler_cru(raiz, condicao="texto"):
    """-> {coleta: {celula: [execucao, ...]}}, cada execucao um dict de campos.

    `condicao` FILTRA, e o padrao e "texto" porque a §6 publica as coletas sem
    sessao grafica. Em 25/09/2026, com a primeira coleta grafica arquivada, a
    versao sem filtro passou a AGREGAR as duas condicoes numa tabela so -- oito
    coletas e 160 execucoes onde a §6 diz sete e 140. Mediana entre condicoes
    diferentes nao e mediana de nada.

    SAO TRES CONDICOES, e nao duas, porque a coleta pode nao declarar a sua:
    `e_texto` devolve None nesse caso. "texto" aceita o nao declarado -- o
    historico anterior ao campo e todo de modo texto e descartar em silencio
    faria a referencia saltar --, e "grafica" exige a declaracao, porque uma
    coleta que nao diz ter sessao grafica nao serve de braco grafico.
    """
    if condicao not in ("texto", "grafica", "todas"):
        raise SystemExit("condicao desconhecida: %r" % condicao)
    saida = {}
    for d in sorted(glob.glob(os.path.join(raiz, "*", "isolamento"))):
        coleta = os.path.basename(os.path.dirname(d))
        e_texto = condicao_coleta.e_texto(os.path.dirname(d))
        if condicao == "texto" and e_texto is False:
            continue
        if condicao == "grafica" and e_texto is not False:
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


def eras(raiz, condicao="texto"):
    """-> (dados da era mais recente, coletas fora dela, {coleta: impressao}).

    POR QUE AGREGAR POR CONDICAO NAO BASTA

    Ate 03/10/2026 o filtro era sessao grafica e nada mais. Naquele dia uma
    ConnectX-4 Lx entrou na maquina -- `mlx5` aparece zero vez no log do kernel
    dos sete boots de 27/09 e quinze vezes no de 03/10 --, e uma coleta nova
    entraria nas tabelas da §6 junto com as dez de setembro. Maquina com placa
    somada a maquina sem placa, numa mediana so.

    E a mesma classe do defeito que tirou nove coletas do historico em
    24/09/2026: "os diretorios colidiam no nome e um deles carregava a
    configuracao de memoria errada". O nome da configuracao descreve MEMORIA
    (`expo6000-canal-duplo`) e nao diz nada sobre o barramento.

    A ERA ESCOLHIDA E A DA COLETA MAIS RECENTE, e as outras ficam de fora com o
    motivo impresso. Nao e escolha silenciosa: quem consome e o `--conferir`,
    que vai acusar divergencia contra o documento publicado na hora em que a
    era mudar -- e a divergencia e a decisao humana sendo pedida, do mesmo jeito
    que uma coleta nova pede republicacao.

    AS DEZ DE SETEMBRO NAO DECLARAM, e None e uma era como outra: elas
    continuam agregando entre si, e nao regridem. O que elas nao fazem mais e
    agregar com uma coleta que declara.
    """
    dados = _ler_cru(raiz, condicao)
    impressoes = {c: condicao_coleta.impressao_hardware(os.path.join(raiz, c))
                  for c in dados}
    grupos = {}
    for c, imp in impressoes.items():
        grupos.setdefault(imp, []).append(c)
    if len(grupos) <= 1:
        return dados, [], impressoes
    # O nome da coleta comeca pelo carimbo de data, e por isso `max` sobre os
    # nomes e cronologico -- o mesmo criterio que a `referencia()` da rajada usa.
    era = impressoes[max(dados)]
    fora = sorted(c for c in dados if impressoes[c] != era)
    return {c: v for c, v in dados.items() if impressoes[c] == era}, fora, impressoes


def relato_de_eras(fora, impressoes):
    """As linhas que explicam o que ficou fora, ou nada se nada ficou."""
    if not fora:
        return []
    nome = lambda i: i if i else "nao declarada"
    era = nome(impressoes[max(set(impressoes) - set(fora))])
    linhas = ["  ERAS DE HARDWARE DIFERENTES no historico: agreguei so a era"
              " %s, da coleta mais recente," % era,
              "  e deixei %d coleta(s) fora. Mediana entre hardwares diferentes"
              " nao e mediana de nada." % len(fora)]
    for c in fora:
        linhas.append("    fora: %s  (era %s)" % (c, nome(impressoes[c])))
    return linhas


def ler(raiz, condicao="texto"):
    """A era mais recente, so. Quem precisa saber o que ficou fora chama `eras`."""
    return eras(raiz, condicao)[0]


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


def faixa_pct(vs):
    """A amplitude de `vs` como fracao do MENOR, que e como a §6.2 a publica.

    Sobre o menor, e nao sobre a media: a frase diz "1 335 contagens sobre
    38 mil", e os 38 mil sao o piso da faixa. Trocar o denominador em silencio
    mudaria o numero publicado sem mudar a medida.
    """
    if not vs:
        return None
    return 100.0 * (max(vs) - min(vs)) / min(vs)


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
    medianas_tlb = [mediana_irq(dados[c].get("P0+ipi-thread", []), "TLB")
                    for c in sorted(dados) if dados[c].get("P0+ipi-thread")]
    tlb_execucoes = [e["irq"].get("TLB", 0) for e in tr]
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
        # A FAIXA DO TLB ENTRE COLETAS era `1 335 contagens -- 3,5%`, calculado
        # a mao sobre as sete coletas de entao. Numero citado na prosa e sem
        # produtor envelhece calado: tres coletas entraram e ele nao se moveu.
        "tlb-thread-coletas-min": min(medianas_tlb) if medianas_tlb else None,
        "tlb-thread-coletas-max": max(medianas_tlb) if medianas_tlb else None,
        "tlb-thread-entre-coletas-pct": faixa_pct(medianas_tlb),
        "tlb-thread-entre-execucoes-pct": faixa_pct(tlb_execucoes),
        "tlb-proc-max": max(e["irq"].get("TLB", 0) for e in pr) if pr else None,
        "maior-parada-fator": v[-1] / v[0],
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


def virgula(v, en, casas=1):
    """21.9465 -> `21,9` em portugues, `21.9` em ingles."""
    t = "%.*f" % (casas, v)
    return t if en else t.replace(".", ",")


def bloco_grafico(dt, dg, en=False, raiz=None):
    """O modo texto contra cada coleta COM sessao grafica, como a §6.1.1 publica.

    POR QUE ELE VIROU PROGRAMA

    Esta tabela foi calculada A MAO uma vez, em 26/09/2026, e publicada com
    `140 (7 coletas)` do lado do texto e uma unica coluna grafica. Tres coletas
    de texto e uma segunda coleta grafica entraram no historico depois, e a
    tabela continuou dizendo sete e uma -- sem portao que acusasse, porque ela
    nao era gerada por nada.

    POR QUE UMA COLUNA POR COLETA GRAFICA, E NAO UMA COLUNA AGREGADA

    As duas coletas graficas arquivadas declaram a MESMA condicao -- modo
    grafico, dois processos, governor `performance` -- e discordam em 9 us na
    mediana: 26,4 us em 25/09-2346 e 17,3 us em 27/09-0853. A mediana das duas
    juntas da 20,4 us, que nao descreve nenhuma delas. Agregar aqui esconderia
    exatamente o que a tabela existe para mostrar.

    O que se repete nas duas e a CAUDA: 784,1 e 439,4 us, contra 55,7 us como
    maior parada em 200 execucoes de modo texto. Por isso o negrito esta nas
    duas ultimas linhas, e nao na mediana -- a mediana deixou de carregar
    argumento quando a segunda coleta entrou.

    E O UPTIME E UMA LINHA DA TABELA, porque e ele que explica a discordancia.
    As dez coletas de modo texto correm de 0 a 2 minutos depois do boot, menos
    uma de 48; a coleta grafica de mediana alta correu com 4 h 37 min de
    maquina ligada, e a de mediana baixa com 1 minuto -- o mesmo protocolo das
    de texto. O mecanismo que a §6.6 identifica e o *power gating* da GPU, que
    depende de a GPU ficar OCIOSA, e um minuto depois do boot ela nao esta.

    Sem a raiz do historico o uptime nao se le, e a tabela nao se monta: ela
    afirmaria comparabilidade que ninguem conferiu.
    """
    if raiz is None:
        raise SystemExit("bloco_grafico: sem a raiz do historico nao se le o uptime")
    # SEM BRACO NAO HA TABELA. Sem esta recusa a funcao emitia um cabecalho de
    # uma coluna e linhas de celula vazia -- tabela publicavel, sem dado
    # dentro. Quem decide o que fazer com a ausencia e `conferir`, que a reporta
    # como NAO APURAVEL; aqui ela nao pode virar saida.
    if not dg:
        raise SystemExit("bloco_grafico: nenhuma coleta com sessao grafica")
    jan = janela(dt)
    vt = sorted(e["maior"] / 1000 for e in execucoes(dt))
    cols = sorted(dg)
    vg = [sorted(e["maior"] / 1000 for e in execucoes({c: dg[c]})) for c in cols]
    acima = lambda v: len([x for x in v if x > jan])
    cole = "collections" if en else "coletas"
    gr = "graphical" if en else "gráfico"

    def ligada(coletas):
        """`up 4 hours, 37 minutes` -> `4 h 37 min`, ou a faixa de um conjunto.

        NAO APURAVEL quando alguma coleta nao declara: a faixa de um
        subconjunto apresentada como a do conjunto e pior que a ausencia.
        """
        vs = [condicao_coleta.uptime_minutos(os.path.join(raiz, c)) for c in coletas]
        if any(v is None for v in vs):
            return "nao declarado"
        def um(m):
            if m < 60:
                return "%d min" % m
            return "%d h %02d min" % (m // 60, m % 60)
        if min(vs) == max(vs):
            return um(min(vs))
        return "%s %s %s" % (um(min(vs)), "to" if en else "a", um(max(vs)))
    linhas = [
        "| | %s | %s |" % ("text mode" if en else "modo texto",
                           " | ".join("%s %s" % (rotulo_curto(c), gr) for c in cols)),
        "|---|---:|" + "---:|" * len(cols),
        "| %s | %d (%d %s) | %s |"
        % ("runs" if en else "execuções", len(vt), len(dt), cole,
           " | ".join(str(len(v)) for v in vg)),
        "| %s | %s µs | %s |"
        % ("max stall, median" if en else "maior parada, mediana",
           virgula(statistics.median(vt), en),
           " | ".join("%s µs" % virgula(statistics.median(v), en) for v in vg)),
        "| %s | %d/%d | %s |"
        % (("above the %s µs window" if en else "acima da janela de %s µs")
           % virgula(jan, en), acima(vt), len(vt),
           " | ".join("**%d/%d**" % (acima(v), len(v)) for v in vg)),
        "| %s | %s µs | %s |"
        % ("max observed" if en else "maior observada", virgula(vt[-1], en),
           " | ".join("**%s µs**" % virgula(v[-1], en) for v in vg)),
        "| %s | %s | %s |"
        % ("machine up for" if en else "máquina ligada há",
           ligada(sorted(dt)), " | ".join(ligada([c]) for c in cols)),
    ]
    return "\n".join(linhas)


def escalares_grafico(dt, dg):
    """Os numeros da §6.1.1 que a prosa cita fora da tabela.

    A comparacao AGREGADA continua saindo aqui, e nao na tabela, porque ela e
    o que REFUTA a diferenca de mediana que a §6.1.1 publicava: com as duas
    coletas graficas juntas o sinal inverte e o p nao decide. Numero que
    derruba afirmacao publicada precisa ter produtor tanto quanto o que a
    sustenta.
    """
    vt = [e["maior"] for e in execucoes(dt)]
    vg = [e["maior"] for e in execucoes(dg)]
    medianas = [statistics.median([e["maior"] / 1000 for e in execucoes({c: dg[c]})])
                for c in sorted(dg)]
    mt, mg = statistics.median(vt), statistics.median(vg)
    return {
        "grafico-coletas": len(dg),
        "grafico-execucoes": len(vg),
        "grafico-mediana-min": min(medianas),
        "grafico-mediana-max": max(medianas),
        "grafico-max": max(vg) / 1000,
        "grafico-vs-texto-pct": 100.0 * (mg - mt) / mt,
        "grafico-vs-texto-p": mann_whitney(vt, vg)[2],
    }


# Onde cada tabela consolidada e publicada. O bloco e localizado pelo proprio
# CABECALHO, e nao por numero de linha: numero de linha envelhece a cada
# paragrafo inserido, e um portao que envelhece deixa de ser portao.
PUBLICADOS = [((), "trilha/03-performance/03-isolamento-cpu/README.md"),
              (("--en",), "trilha/03-performance/03-isolamento-cpu/README.en.md"),
              (("--estados",), "trilha/03-performance/03-isolamento-cpu/README.md"),
              (("--estados", "--en"), "trilha/03-performance/03-isolamento-cpu/README.en.md"),
              (("--tlb",), "trilha/03-performance/03-isolamento-cpu/README.md"),
              (("--tlb", "--en"), "trilha/03-performance/03-isolamento-cpu/README.en.md"),
              (("--grafico",), "trilha/03-performance/03-isolamento-cpu/README.md"),
              (("--grafico", "--en"), "trilha/03-performance/03-isolamento-cpu/README.en.md")]


def linhas_a_mais(esperadas, publicadas):
    """As linhas regeneradas que o documento nao publica.

    ZIP NAO ACUSA O QUE FALTA -- ele para na sequencia mais curta. A tabela de
    coletas do topico de isolamento publicava SETE coletas com dez no
    historico; as sete batiam linha por linha e o portao passava calado sobre
    tres coletas inteiras. Comparar o prefixo responde "o que esta la esta
    certo?", e a pergunta do portao e "o documento publica a coleta?".

    O comprimento se compara sem as linhas vazias do fim, porque o recorte do
    bloco carrega uma: o corpo termina em `\n` antes da cerca.
    """
    def sem_vazias_no_fim(seq):
        fim = len(seq)
        while fim and not seq[fim - 1].strip():
            fim -= 1
        return seq[:fim]
    esperadas, publicadas = sem_vazias_no_fim(esperadas), sem_vazias_no_fim(publicadas)
    return esperadas[len(publicadas):]


def conferir(raiz):
    h = os.path.join(raiz, "trilha/03-performance/03-isolamento-cpu/historico")
    dados, fora, impressoes = eras(h)
    # O RELATO VAI PARA O STDOUT, e a razao e a que este repositorio pagou em
    # 27/09/2026: o `marcar_falha` escrevia o motivo no stderr, quem rodou viu
    # "NAO CONCLUIDO" sem razao nenhuma, e repetiu horas de campanha para
    # descobrir. Informacao de portao vive onde o portao fala.
    for l in relato_de_eras(fora, impressoes):
        print(l)
    if not dados:
        print("  nenhuma coleta com isolamento/ no historico do topico")
        return 1
    # A TABELA DO BRACO GRAFICO SO SE CONFERE SE HOUVER BRACO. Sem coleta
    # grafica arquivada nao ha o que regenerar, e tratar isso como "em dia"
    # seria dar por conferido o que nao foi olhado.
    graficas = ler(h, "grafica")
    problemas = 0
    for args, arquivo in PUBLICADOS:
        en = "--en" in args
        if "--grafico" in args and not graficas:
            print("  %s: NAO APURAVEL -- nenhuma coleta grafica no historico,"
                  " a tabela da secao 6.1.1 nao foi conferida" % arquivo)
            problemas += 1
            continue
        novo = (bloco_estados(dados, en) if "--estados" in args else
                bloco_tlb(dados, en) if "--tlb" in args else
                bloco_grafico(dados, graficas, en, h) if "--grafico" in args else
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
        else:
            faltando = linhas_a_mais(novo[1:], atual)
            if faltando:
                print("  %s: o historico da %d linha(s) que o documento nao"
                      " publica:" % (arquivo, len(faltando)))
                for l in faltando:
                    print("      %s" % l)
                problemas += 1
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
    caso(41, "milhar em ingles usa virgula", milhar(37940, True), "37,940")
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

    # ZIP NAO ACUSA O QUE FALTA, e o portao passava calado sobre uma tabela
    # que perdeu linhas: compare o prefixo e a resposta e "o que esta la esta
    # certo?", que nao e a pergunta.
    caso(36, "linha regenerada que o documento nao publica aparece",
         linhas_a_mais(["a", "b", "c"], ["a"]), ["b", "c"])
    caso(37, "e documento em dia nao acusa nada",
         linhas_a_mais(["a", "b"], ["a", "b"]), [])
    # A vazia do fim e do RECORTE, nao do bloco: o corpo termina em `\n` antes
    # da cerca. Contar com ela acusaria toda tabela em dia.
    caso(38, "vazia no fim do recorte nao conta como linha",
         linhas_a_mais(["a", "b"], ["a", "b", ""]), [])
    caso(39, "e nem no lado regenerado",
         linhas_a_mais(["a", "b", ""], ["a", "b"]), [])
    # Documento com MAIS linhas que o historico e outra coisa -- a comparacao
    # linha por linha ja acusa, e aqui nao se inventa linha negativa.
    caso(40, "documento mais longo nao devolve linha",
         linhas_a_mais(["a"], ["a", "b"]), [])

    # 22 a 28. O BRACO GRAFICO: UMA COLUNA POR COLETA, e nao uma agregada.
    #
    # A versao publicada ate 27/09/2026 tinha uma coluna grafica so, porque so
    # havia uma coleta grafica. Com duas, a mediana agregada -- 20,4 us -- nao
    # descreve nenhuma das duas, que dao 26,4 e 17,3. Agregar aqui esconderia
    # exatamente o que a tabela existe para mostrar.
    # NOMES FABRICADOS, e nao os reais: `uptime_minutos` cai na coleta IRMA do
    # isolamento pelo NOME do diretorio, e com os nomes reais a fixture lia
    # dado de verdade em vez de exercitar a ausencia.
    graf = {"2099-01-02-2346-expo6000-canal-duplo": {"P0": [ex(26000), ex(784000)]},
            "2099-01-03-0853-expo6000-canal-duplo": {"P0": [ex(17000), ex(439000)]}}
    # A RAIZ E ONDE O UPTIME VIVE. Sem coleta em disco ele sai como
    # `nao declarado`, que e o terceiro estado -- e e isso que os casos abaixo
    # exercitam, porque a tabela precisa dizer "nao sei" sem travar.
    gl = bloco_grafico(dados, graf, False, "/inexistente").splitlines()
    caso(22, "quatro celulas: o rotulo, o modo texto e as duas graficas",
         len(gl[0].split("|")) - 2, 4)
    caso(23, "e cada coluna traz a propria mediana",
         [c.strip() for c in gl[3].split("|")[2:5]],
         ["23,0 µs", "405,0 µs", "228,0 µs"])
    # A CAUDA E O QUE A TABELA DESTACA, e nao a mediana: a mediana deixou de
    # carregar argumento quando a segunda coleta entrou com sinal invertido.
    caso(24, "o negrito esta nas linhas da cauda, e nao na mediana",
         [gl[i].count("**") for i in (2, 3, 4, 5, 6)], [0, 0, 4, 4, 0])
    # O UPTIME E A LINHA QUE EXPLICA A DISCORDANCIA, e sem coleta em disco ele
    # e `nao declarado` -- nao zero, que afirmaria "acabou de ligar".
    caso(42, "sem o ambiente em disco, o uptime diz que nao sabe",
         [c.strip() for c in gl[6].split("|")[2:5]],
         ["nao declarado"] * 3)
    # E SEM A RAIZ A TABELA NAO SE MONTA: ela afirmaria comparabilidade que
    # ninguem conferiu.
    try:
        bloco_grafico(dados, graf)
        caso(43, "sem raiz a tabela nao se monta", "passou", "SystemExit")
    except SystemExit:
        caso(43, "sem raiz a tabela nao se monta", "SystemExit", "SystemExit")
    caso(25, "e a linha da janela conta por coleta, nao somada",
         [c.strip() for c in gl[4].split("|")[2:5]], ["1/6", "**1/2**", "**1/2**"])
    # SEM BRACO NAO HA TABELA, e a ausencia nao e "em dia". Antes desta
    # recusa a funcao devolvia cabecalho de uma coluna e celulas vazias: uma
    # tabela publicavel sem dado dentro, que e a forma de falso verde que este
    # repositorio passou o dia caçando.
    try:
        bloco_grafico(dados, {}, False, "/inexistente")
        caso(26, "braco vazio aborta em vez de emitir tabela vazia",
             "passou", "SystemExit")
    except SystemExit:
        caso(26, "braco vazio aborta em vez de emitir tabela vazia",
             "SystemExit", "SystemExit")
    # A COMPARACAO AGREGADA SAI NOS ESCALARES, porque e ela que REFUTA a
    # diferenca de mediana que a secao publicava.
    esc = escalares_grafico(dados, graf)
    caso(27, "os escalares separam a mediana menor da maior",
         (round(esc["grafico-mediana-min"], 1), round(esc["grafico-mediana-max"], 1)),
         (228.0, 405.0))
    caso(28, "e contam as coletas graficas", esc["grafico-coletas"], 2)

    # 29 a 31. A CONDICAO DE LEITURA TEM TRES VALORES, e a quarta e recusada.
    #
    # `so_texto=True/False` era binario e nao tinha onde dizer "so as
    # graficas". A quarta condicao nao cai em nenhum ramo em silencio.
    try:
        ler("/inexistente", "qualquer-coisa")
        caso(29, "condicao desconhecida aborta", "passou", "SystemExit")
    except SystemExit:
        caso(29, "condicao desconhecida aborta", "SystemExit", "SystemExit")
    caso(30, "e as tres conhecidas nao abortam",
         [ler("/inexistente", c) for c in ("texto", "grafica", "todas")], [{}, {}, {}])
    caso(31, "o padrao e modo texto", ler("/inexistente"), {})

    # 32 a 35. O FILTRO SOBRE AS TRES CONDICOES REAIS, com coleta em disco.
    #
    # "grafica" EXIGE A DECLARACAO. Com `e_texto is True` no lugar de
    # `is not False`, a coleta que nao declara entraria no braco grafico -- e
    # todo o historico anterior a 25/09/2026 nao declara. O braco mediria a
    # condicao errada e nada acusaria; os casos abaixo sao o que distingue as
    # duas versoes.
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        def coleta(nome, graficos):
            d = os.path.join(tmp, nome, "isolamento")
            os.makedirs(d)
            with open(os.path.join(d, "P0.r1.txt"), "w") as f:
                f.write("stall probe: threshold 2000 ns\nmax stall: 21000 ns\n"
                        "   512 descriptors: 34.4 us\n")
            if graficos is not None:
                with open(os.path.join(tmp, nome, "ambiente.txt"), "w") as f:
                    f.write("  sessao grafica ....... %d processo(s)\n" % graficos)
        # Nomes fora do historico real: `processos_graficos` cai na coleta IRMA
        # pelo NOME do diretorio, e um nome real traria a condicao de la.
        coleta("2099-01-01-0000-fixture-texto", 0)
        coleta("2099-01-02-0000-fixture-grafica", 2)
        coleta("2099-01-03-0000-fixture-sem-declaracao", None)
        caso(32, "texto leva a declarada sem sessao e a nao declarada",
             sorted(ler(tmp, "texto")),
             ["2099-01-01-0000-fixture-texto",
              "2099-01-03-0000-fixture-sem-declaracao"])
        caso(33, "grafica leva SO a que declara sessao",
             sorted(ler(tmp, "grafica")), ["2099-01-02-0000-fixture-grafica"])
        caso(34, "e a nao declarada nunca entra no braco grafico",
             "2099-01-03-0000-fixture-sem-declaracao" in ler(tmp, "grafica"), False)
        caso(35, "todas leva as tres", len(ler(tmp, "todas")), 3)

        # 44 a 51. AS ERAS DE HARDWARE.
        #
        # O caso que importa e o que AINDA NAO EXISTE no historico: uma coleta
        # feita depois de 03/10/2026, que declara a impressao PCI, ao lado das
        # dez de setembro, que nao declaram. Sem fixture nao ha como exercitar
        # isso -- e foi exatamente a agregacao silenciosa das duas que motivou
        # o portao.
        def com_hw(nome, impressao=None, maior=21000):
            d = os.path.join(tmp, "eras", nome, "isolamento")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "P0.r1.txt"), "w") as f:
                f.write("stall probe: threshold 2000 ns\nmax stall: %d ns\n"
                        "   512 descriptors: 34.4 us\n" % maior)
            linhas = ["  sessao grafica ....... 0 processo(s)\n"]
            if impressao:
                linhas.append("hardware pci     : %s (47 dispositivos)\n" % impressao)
            with open(os.path.join(tmp, "eras", nome, "ambiente.txt"), "w") as f:
                f.writelines(linhas)
        e = os.path.join(tmp, "eras")
        com_hw("2026-09-24-0955-setembro-a", None, 21000)
        com_hw("2026-09-25-1720-setembro-b", None, 22000)
        caso(44, "era unica (nao declarada) agrega tudo", len(ler(e)), 2)
        caso(45, "e nada fica fora", eras(e)[1], [])
        # A coleta NOVA declara, e nao pode ser somada as duas de setembro.
        com_hw("2026-10-05-1200-outubro-com-placa", "ce9d4ee16f03", 17000)
        dados_era, fora, imps = eras(e)
        caso(46, "a era escolhida e a da coleta mais recente",
             sorted(dados_era), ["2026-10-05-1200-outubro-com-placa"])
        caso(47, "e as duas de setembro ficam fora, nomeadas",
             fora, ["2026-09-24-0955-setembro-a", "2026-09-25-1720-setembro-b"])
        # O RELATO E A DECISAO SENDO PEDIDA. Sem ele a escolha de era seria
        # silenciosa, que e o defeito trocado de lugar.
        rel = "\n".join(relato_de_eras(fora, imps))
        caso(48, "o relato nomeia a era agregada", "ce9d4ee16f03" in rel, True)
        caso(49, "e diz quantas ficaram fora", "2 coleta(s) fora" in rel, True)
        caso(50, "e nomeia cada uma das que ficaram",
             all(c in rel for c in fora), True)
        caso(51, "sem exclusao nao ha relato",
             relato_de_eras([], imps), [])

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
    graficas = ler(args[0], "grafica")
    # Aqui o relato vai para o STDERR porque o stdout e a TABELA: nota no meio
    # de bloco publicavel vira linha de tabela na republicacao seguinte.
    for l in relato_de_eras(*eras(args[0])[1:]):
        print(l, file=sys.stderr)
    if "--estados" in sys.argv:
        print(bloco_estados(dados, en))
    elif "--tlb" in sys.argv:
        print(bloco_tlb(dados, en))
    elif "--grafico" in sys.argv:
        if not graficas:
            print("nenhuma coleta COM sessao grafica em %s" % args[0],
                  file=sys.stderr)
            sys.exit(1)
        print(bloco_grafico(dados, graficas, en, args[0]))
    elif "--escalares" in sys.argv:
        tudo = escalares(dados)
        # O braco grafico entra SE EXISTIR, e a ausencia dele aparece como tal:
        # escalar que falta calado faz a prosa citar o numero de outra amostra.
        tudo.update(escalares_grafico(dados, graficas) if graficas else
                    {"grafico-coletas": 0})
        for k, v in tudo.items():
            print("%-24s %s" % (k, ("%.4f" % v) if isinstance(v, float) else v))
    else:
        print(bloco_celulas(dados, en))
    print("\n  (%d coleta(s), %d execucao(oes))"
          % (len(dados), len(execucoes(dados))), file=sys.stderr)
