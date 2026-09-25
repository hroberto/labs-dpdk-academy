#!/usr/bin/env python3
"""Produz o bloco consolidado do `efeito-cache` que a §4.2 publica.

POR QUE ESTE ARQUIVO EXISTE

O `efeito-cache` imprime uma tabela POR REGIAO, com mediana, IQR, faixa e
dispersao. A §4.2 publica outra coisa: uma tabela de quatro linhas, uma por
nivel, com uma coluna derivada -- `acessos em voo`, que e a razao entre
`dependente` e `aleatorio`.

Essa tabela nunca teve programa. Ela era montada a mao a partir das saidas, e
por isso caia FORA do escopo do `verificar-blocos.py`: aquele verificador casa a
FORMA de cada linha contra as coletas arquivadas, e uma linha que nenhum
`printf` produz nao tem forma para casar. O bloco atravessava o portao por nao
ser visto por ele -- que e a limitacao declarada no cabecalho do proprio
verificador, e nao um defeito dele.

O efeito pratico apareceu em 25/09/2026: ao corrigir o acumulador do
`efeito-cache`, as quatro linhas mudaram, e nada no projeto sabia recalcula-las.

AGORA O BLOCO TEM PROGRAMA. Ele le uma coleta, toma a mediana ENTRE EXECUCOES de
cada celula e emite as linhas exatamente como o documento as publica.

O QUE ELE DECIDE, E POR QUE

  - descarta `r0`, que e a execucao de aquecimento da campanha;
  - toma a MEDIANA entre execucoes, e nao a media: a distribuicao entre
    execucoes tem cauda, e a campanha ja publica dispersao;
  - `acessos em voo` e `dependente / aleatorio` ARREDONDADO, e sai com `~`
    porque e razao entre duas medianas, nao medida;
  - a dispersao publicada e a do `dependente`, que e a coluna que sustenta o
    argumento da secao.

    uso:  consolidar-efeito-cache.py <dir-da-coleta> [--en]
          consolidar-efeito-cache.py --autoteste
"""
import glob
import os
import re
import statistics
import sys

REGIOES = [("L1d", "16"), ("L2", "256"), ("L3", "8192"), ("RAM", "262144")]

# Copiados do documento, e nao redigitados: e o cabecalho que fixa as colunas.
CABECALHO_PT = (
    "  cabe em    tamanho   sequencial    aleatorio    dependente   acessos   disp do",
    "                       (amortizado)  (amortizado) (LATENCIA)   em voo    dependente",
)
CABECALHO_EN = (
    "  fits in       size   sequential     random      dependent    accesses   disp of",
    "                       (amortised)   (amortised)  (LATENCY)    in flight  dependent",
)
CABECA = re.compile(r"\s+(L1d|L2|L3|RAM)\s+\((\d+) KB\)")
CELULA = re.compile(
    r"\s+(sequential|random|dependent)\s+\(\S+\)\s+([\d.]+)\s+\S+\s+\S+\s+([\d.]+)%")


def ler(diretorio):
    """-> {(nivel, kb): {coluna: [valores]}}, e a dispersao do dependente."""
    dados, disp = {}, {}
    arquivos = sorted(glob.glob(os.path.join(diretorio, "efeito-cache.r[1-9]*.txt")))
    for f in arquivos:
        regiao = None
        for l in open(f, encoding="utf-8", errors="replace"):
            m = CABECA.match(l)
            if m:
                regiao = (m.group(1), m.group(2))
                continue
            m = CELULA.match(l)
            if m and regiao:
                dados.setdefault(regiao, {}).setdefault(m.group(1), []).append(
                    float(m.group(2)))
                if m.group(1) == "dependent":
                    disp.setdefault(regiao, []).append(float(m.group(3)))
    return dados, disp, len(arquivos)


def ns(v):
    """A precisao que o documento usa: 3 casas abaixo de 1 ns, 2 acima."""
    return ("%.3f ns" % v) if v < 1 else ("%.2f ns" % v)


def bloco(dados, disp, en=False):
    linhas = list(CABECALHO_EN if en else CABECALHO_PT)
    for k in REGIOES:
        if k not in dados:
            continue
        s = statistics.median(dados[k]["sequential"])
        a = statistics.median(dados[k]["random"])
        p = statistics.median(dados[k]["dependent"])
        d = statistics.median(disp[k])
        # O LAIAUTE E DERIVADO DO BLOCO PUBLICADO, coluna a coluna, e nao
        # inventado aqui: um bloco que so difere no espacamento obriga quem
        # regenerar a conferir a olho se a diferenca e de valor ou de forma.
        #
        #   nivel     col 2, a esquerda        dependente  col 53-60, a direita
        #   tamanho   col 5-16, a direita      em voo      col 61-67, a direita
        #   sequencial col 20-32, a direita    dispersao   col 68-79, a direita
        #   aleatorio col 39-52, a ESQUERDA -- e a unica, e e assim no original
        linhas.append("  %-3s%12s KB%13s      %-14s%8s%7s%12s"
                      % (k[0], k[1], ns(s), ns(a), ns(p),
                         "~%d" % round(p / a), "%.1f%%" % d))
    return "\n".join(linhas)


def autoteste():
    falhas = 0

    def caso(n, descricao, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    # 1/2. A precisao muda em 1 ns, e o documento depende disso.
    caso(1, "abaixo de 1 ns leva 3 casas", ns(0.1804), "0.180 ns")
    caso(2, "acima de 1 ns leva 2 casas", ns(87.181), "87.18 ns")
    # 3. MEDIANA, NAO MEDIA. Com [1, 1, 10] a media e 4 e a mediana e 1; a
    #    diferenca e o motivo da escolha, e um teste que usasse dados simetricos
    #    nao distinguiria as duas.
    dados = {("RAM", "262144"): {"sequential": [1.0, 1.0, 10.0],
                                 "random": [2.0, 2.0, 2.0],
                                 "dependent": [4.0, 4.0, 4.0]}}
    disp = {("RAM", "262144"): [0.5, 0.5, 0.5]}
    linha = bloco(dados, disp).splitlines()[-1]
    caso(3, "usa mediana, nao media", "1.00 ns" in linha, True)
    # 4. `acessos em voo` e a razao arredondada: 4/2 = 2.
    caso(4, "acessos em voo = dependente/aleatorio", "~2" in linha, True)
    # 5. Regiao ausente na coleta nao vira linha inventada.
    caso(5, "regiao ausente nao aparece", len(bloco(dados, disp).splitlines()), 3)

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("uso: consolidar-efeito-cache.py <dir-da-coleta> [--en]", file=sys.stderr)
        sys.exit(2)
    dados, disp, n = ler(args[0])
    if not dados:
        print("nenhum efeito-cache.r<N>.txt em %s" % args[0], file=sys.stderr)
        sys.exit(1)
    print(bloco(dados, disp, en="--en" in sys.argv))
    print("\n  (n = %d execucoes; r0 de aquecimento descartado)" % n, file=sys.stderr)
