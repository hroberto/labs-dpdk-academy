#!/usr/bin/env python3
"""Confere se o número da prosa CONCORDA com o bloco, e não só se ele aparece.

POR QUE ESTE VERIFICADOR EXISTE, E POR QUE O `verificar-evidencia.py` NAO BASTA

Aquela sonda pergunta se o número da prosa APARECE em algum bloco do módulo.
É a pergunta certa para a promessa "todo número publicado tem um programa que o
produz", e ela fecha a classe do número órfão -- o que nunca teve saída nenhuma.

Ela não alcança a classe que mais apareceu na revisão externa: o número que JÁ
TEVE bloco, e ficou para trás quando a coleta foi refeita. A prosa diz `1,04×`,
o bloco ao lado publica `1.03`, e a sonda de evidência não acusa nada -- porque
`1.04` de fato não está no bloco, e ela só sabe dizer "sem evidência", que é uma
frase que o revisor humano lê como "número derivado, normal".

O relatório externo chamou essa classe de **Portão B -- número com dono único**,
e contou 46 ocorrências só nos módulos 02 e 03. Não é erro de digitação: é o
rastro de cada recoleta que moveu o bloco e não moveu o texto.

O PROBLEMA DE DESENHO, DECLARADO

Número igual não prova correferência. Se a prosa diz `1,04` e um bloco do
módulo tem `1.03`, nada no texto garante que as duas grandezas são a mesma --
podem ser razões de coisas diferentes que calharam de ficar perto.

Por isso este programa **não emite veredito**: ele gera lista de trabalho
ordenada por suspeita. Quem decide é quem lê o parágrafo. A alternativa seria a
sonda inventar uma correferência que ela não pode observar, e um portão que
inventa é pior que portão nenhum -- a lição já está registrada na §6.7 do módulo
de isolamento de CPU, sobre compatibilidade de escala não estabelecer causa.

AS DUAS REGRAS QUE FAZEM O SINAL VALER

  VIZINHANCA. Só entra o par cuja distância relativa é pequena. Números longe
  um do outro falam de grandezas diferentes; números a 1% de distância, num
  documento que publica três casas, quase sempre são o mesmo valor em dois
  estados de atualização.

  ARREDONDAMENTO E LEGITIMO. A prosa não repete três casas, e não deve. Se o
  bloco publica `0.981` e o texto diz `0,98`, isso está CERTO: `round(0.981, 2)`
  é `0.98`. O par só vira suspeita quando o valor do bloco, arredondado na
  precisão que a prosa escolheu, dá outra coisa. `round(1.03, 2)` é `1.03`, e a
  prosa diz `1,04`: um dos dois está velho.

Essa segunda regra é o que separa este verificador de um detector de ruído. Sem
ela a lista teria centenas de linhas e seria desligada na primeira semana.

O QUE ELE NAO COBRE

Número derivado -- razão, soma, percentual de orçamento -- não vive em bloco
nenhum e está certo assim. Se o derivado calhar de cair perto de um valor de
bloco, ele entra na lista como falso positivo. É o custo aceito: a lista é para
ler, não para aplicar em massa.
"""
import pathlib
import re
import sys

# A unidade e o que separa medicao de numero de secao, versao ou contagem. O
# `verificar-evidencia.py` ja pagou o preco de nao exigir unidade; aqui a lista
# alem disso inclui `×`, `x` e `%`, porque a classe que este programa persegue
# e dominada por RAZAO e PERCENTUAL -- foi onde a revisao externa achou mais.
UNI = r"(?:ns|µs|us|ms|s|GB/s|MB/s|Mpps|GHz|MT/s|ciclos|cycles|×|x|%)"
NUM = re.compile(rf"(\d+(?:[.,]\d+)?)\s*{UNI}(?![\w/])")
# Dentro de bloco e de tabela a unidade vive no cabecalho, nao no numero.
NUM_NU = re.compile(r"(?<![\w.,])(\d+(?:[.,]\d+)?)(?![\w.,])")
TEM_FONTE = re.compile(r"\]\[[^\]]+\]|\]\(https?:")
# URL e definicao de referencia nao sao prosa: o `9950` de
# `chipsandcheese.com/p/amds-ryzen-9950x-zen-5-on-desktop` e nome de produto, e
# a vizinhanca de 2% o casava com um `10000` de bloco sem relacao nenhuma. Uma
# linha que E um endereco sai inteira do escopo.
SO_URL = re.compile(r"^\s*(\[[^\]]+\]:\s*)?(https?|ftp)://\S+\s*$")
# Valor que o documento JA declara retratado e cita de proposito. Sem isto, o
# paragrafo mais honesto do material -- aquele que diz "esta tabela publicava
# 0,924 ns e o valor nao reproduz" -- e o que mais aparece na lista, porque o
# valor antigo esta perto do novo por construcao. Acusar ali e pedir que o
# documento apague a propria correcao.
RETRATADO = re.compile(r"<!--\s*(?:cita-)?retratado:\s*([^>]*?)\s*-->")

# Distancia relativa maxima para dois numeros serem candidatos a "mesma
# grandeza em dois estados". 2% foi escolhido olhando a lista do Apendice A:
# `1,04` contra `1.03` e 0,97%; `26,6` contra `26,5` e 0,38%; `8,51` contra
# `8,48` e 0,35%. Acima de 2% a lista enche de par sem relacao.
VIZINHANCA = 0.02


def casas(s):
    """Quantas casas decimais a PROSA escolheu publicar."""
    return len(s.split(".")[1]) if "." in s else 0


def numeros(texto):
    """Devolve (valores de bloco, [(texto do numero, valor, linha) da prosa])."""
    retratados = set()
    for m in RETRATADO.finditer(texto):
        retratados.update(v.replace(",", ".") for v in m.group(1).split())
    dentro, bloco, prosa = False, set(), []
    for ln in texto.split("\n"):
        s = ln.strip()
        if s.startswith("```"):
            dentro = not dentro
            continue
        if dentro or (s.startswith("|") and s.endswith("|")):
            for m in NUM_NU.finditer(ln):
                bloco.add(m.group(1).replace(",", "."))
            for m in NUM.finditer(ln):
                bloco.add(m.group(1).replace(",", "."))
        elif not TEM_FONTE.search(ln) and not SO_URL.match(ln):
            for m in NUM.finditer(ln):
                t = m.group(1).replace(",", ".")
                if t in retratados:
                    continue          # citacao deliberada do valor corrigido
                prosa.append((t, float(t), s))
    return bloco, prosa


def divergencias(bloco, prosa):
    """Para cada numero da prosa, o valor de bloco mais proximo que NAO o explica.

    Um valor de bloco explica a prosa quando arredonda para ela na precisao que
    a prosa escolheu. Se ALGUM valor do bloco explica, o numero esta em ordem e
    nao entra na lista -- mesmo que outros valores proximos nao expliquem.
    """
    saida = []
    vals = sorted({(float(b), b) for b in bloco})
    for txt, v, linha in prosa:
        d = casas(txt)
        if any(round(bv, d) == round(v, d) for bv, _ in vals):
            continue                      # ha bloco que explica: em ordem
        perto = [(abs(bv - v) / v, bv, bs) for bv, bs in vals
                 if v and abs(bv - v) / v <= VIZINHANCA]
        if perto:
            dist, bv, bs = min(perto)
            saida.append((dist, txt, bs, linha))
    return sorted(saida)


def verificar(raizes=("docs", "trilha"), limite=None):
    """Agrupa por PAR (prosa, bloco), e ordena por numero de ocorrencias.

    A primeira versao listava ocorrencia por ocorrencia, e 70 linhas soltas nao
    sao lista de trabalho: sao ruido com indice. O agrupamento troca a pergunta
    "este numero diverge?" -- que exige julgar o paragrafo -- pela pergunta
    "este VALOR esta velho no documento inteiro?", que se responde uma vez e
    corrige em N lugares.

    A contagem tambem e o melhor discriminador de falso positivo que este
    programa tem. Um par que aparece cinco vezes e recoleta que nao alcancou a
    prosa; um par que aparece uma vez costuma ser numero derivado que calhou de
    cair perto de um valor sem relacao com ele.
    """
    modulos = {}
    for raiz in raizes:
        for p in sorted(pathlib.Path(raiz).rglob("*.md")):
            modulos.setdefault(p.parent, []).append(p)
    total = 0
    for p in sorted(x for v in modulos.values() for x in v):
        if p.name.endswith(".en.md"):
            continue                      # o par repete os mesmos numeros
        bloco = set()
        for irmao in modulos[p.parent]:
            b, _ = numeros(irmao.read_text(encoding="utf-8"))
            bloco |= b
        _, prosa = numeros(p.read_text(encoding="utf-8"))
        achados = divergencias(bloco, prosa)
        if not achados:
            continue
        pares = {}
        for dist, txt, bs, linha in achados:
            pares.setdefault((txt, bs, dist), []).append(linha)
        total += len(achados)
        print(f"  {p}")
        ordem = sorted(pares.items(), key=lambda kv: (-len(kv[1]), kv[0][2]))
        for (txt, bs, dist), linhas in ordem[:limite]:
            marca = "<<<" if len(linhas) > 1 else "   "
            print(f"    {marca} prosa {txt:>8}  bloco {bs:>8}"
                  f"  ({dist*100:.2f}%)  {len(linhas)}x")
            for l in linhas[:1]:
                print(f"            {l[:76]}")
    print(f"\n  {total} ocorrencia(s) -- lista de trabalho, NAO veredito."
          f"  `<<<` = repetido, suspeita alta.")
    return total


def autoteste():
    falhas = 0

    def caso(desc, bloco, prosa_txt, esperado):
        nonlocal falhas
        b, pr = numeros(bloco + "\n" + prosa_txt)
        got = len(divergencias(b, pr))
        ok = got == esperado
        print(f"  [{'ok' if ok else 'FALHA'}] {desc}: {got} (esperado {esperado})")
        if not ok:
            falhas += 1

    print("== autoteste do verificador de concordancia ==")
    caso("arredondamento legitimo nao acusa",
         "```\nrazao  0.981\n```", "A razao foi de 0,98×.", 0)
    caso("prosa velha contra bloco novo acusa",
         "```\nrazao  1.03\n```", "A razao foi de 1,04×.", 1)
    caso("numero distante nao entra na lista",
         "```\nrazao  5.00\n```", "A razao foi de 1,04×.", 0)
    caso("valor exato nao acusa",
         "```\nrazao  1.04\n```", "A razao foi de 1,04×.", 0)
    caso("percentual velho acusa",
         "```\nuso  26.5\n```", "Ficou em 26,6%.", 1)
    caso("sem unidade a prosa nao e medicao",
         "```\nrazao  1.03\n```", "Veja a secao 1,04 adiante.", 0)
    caso("URL nao e prosa",
         "```\nrazao  10000\n```",
         "[cc]: https://chipsandcheese.com/p/amds-ryzen-9950x-zen-5", 0)
    caso("valor declarado retratado nao entra na lista",
         "```\nrazao  1.03\n```\n<!-- retratado: 1,04 1.04 -->",
         "A tabela publicava 1,04× e o valor nao reproduz.", 0)
    caso("um bloco que explica basta, com outro perto",
         "```\na 1.03\nb 1.041\n```", "A razao foi de 1,04×.", 0)
    print(f"\n  {falhas} falha(s)")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    lim = None if "--tudo" in sys.argv else 3
    verificar(limite=lim)
    sys.exit(0)                           # lista de trabalho: nunca reprova
