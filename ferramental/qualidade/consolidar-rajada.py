#!/usr/bin/env python3
"""Produz os dois blocos consolidados do `rajada-nasdaq` que a §6.3 publica.

POR QUE ESTE ARQUIVO EXISTE

O `rajada-nasdaq` imprime cinco secoes longas, em ingles, com todas as
profundidades de anel e todas as colunas. A §6.3 do modulo de fundamentos nao
publica nenhuma delas: publica duas tabelas RECOMPOSTAS -- uma com cinco linhas
escolhidas entre as duas primeiras secoes, outra que junta a linha do anel de
8192 com as duas linhas de socket da terceira secao -- e as publica em
portugues, com cabecalho proprio.

Essas duas tabelas nunca tiveram programa. Eram montadas a mao, e por isso
caiam FORA do escopo do `verificar-blocos.py`: aquele verificador casa a FORMA
de cada linha contra as coletas arquivadas, e uma linha que nenhum `printf`
produz nao tem forma para casar. Os blocos atravessavam o portao por nao serem
vistos por ele -- a mesma limitacao declarada que motivou o
`consolidar-efeito-cache.py`.

O efeito pratico apareceu em 25/09/2026: as duas tabelas estavam paradas numa
execucao anterior a coleta de referencia, e discordavam dela em toda celula
medida. A tabela de socket ainda sustentava "drenagem 27% menor", que a coleta
atual mede em 12,6%.

O QUE ELE DECIDE, E POR QUE

  - descarta `r0`, que e a execucao de aquecimento da campanha;
  - escolhe UMA EXECUCAO e emite as celulas dela, em vez de tomar a mediana
    por celula como o `consolidar-efeito-cache.py`. A diferenca e deliberada e
    vem da §1 dos padroes: a §6.3 publica estas duas tabelas resumidas, a
    tabela COMPLETA no arquivo de aprofundamento e ainda tres escalares na
    prosa -- `mu`, o `delta Q` e o custo por pacote. Mediana por celula faria
    cada um desses vir de um arranjo diferente de execucoes, e o leitor que
    refizesse a subtracao acharia discordancia de duas unidades entre dois
    paragrafos do mesmo capitulo. Com uma execucao so, a aritmetica fecha em
    todo lugar;
  - a execucao escolhida e a MEDIANA por uma chave declarada: a perda com anel
    de 1024, que e a linha sobre a qual o argumento da secao se apoia. Em
    empate vence a de indice menor. A escolha e ordinal, nao interpolada, e
    por isso a linha existe literalmente na coleta -- o que permite ao
    `verificar-blocos.py` conferir a procedencia do bloco verbatim que o
    `6.3-aprofundamento.md` publica da MESMA execucao;
  - o separador de milhar da coluna de drenagem segue o idioma: espaco no
    portugues, virgula no ingles, como o documento ja publicava;
  - o LAIAUTE das colunas e derivado do bloco publicado, e nao inventado aqui:
    um bloco que so difere no espacamento obriga quem regenerar a conferir a
    olho se a diferenca e de valor ou de forma.

O MODO `--conferir` E O PORTAO

Ter o programa nao e o mesmo que o documento usar o programa. Enquanto ninguem
compara, o bloco pode envelhecer de novo exatamente como envelheceu -- e o
`verificar-blocos.py` continua sem ve-lo, porque a linha consolidada nao tem a
forma de nenhum `printf` arquivado, que e a condicao de escopo daquele portao.

`--conferir` fecha essa volta: regenera os quatro blocos a partir da coleta de
referencia (a mais recente no historico do modulo, pelo mesmo criterio da
`campanha.sh`) e compara com o que os documentos publicam. Ele FALHA quando uma
coleta nova move a mediana sem que alguem republique -- que e o sinal, nao o
defeito.

    uso:  consolidar-rajada.py <dir-da-coleta> [--en] [--socket] [--escalares]
          consolidar-rajada.py --conferir
          consolidar-rajada.py --autoteste
"""
import glob
import os
import re
import sys

# As profundidades que a tabela resumida publica, na ordem em que ela publica.
# A de 512 aparece DUAS VEZES -- cadenciada e em rajada -- e e justamente esse
# par que carrega o argumento da secao: mesmo trafego, mesma fila, so muda a
# distribuicao no tempo.
RESUMO = [("cadenciada", "cadenced", 1, 512),
          ("rajada", "burst", 2, 512),
          ("rajada", "burst", 2, 1024),
          ("rajada", "burst", 2, 4096),
          ("rajada", "burst", 2, 32768)]

SECAO = re.compile(r"^  (\d)\. ")
# `ring(n) offered dropped loss occ.max median(us) p99(us)`
LINHA = re.compile(r"^\s+(\d+)\s+\d+\s+\d+\s+([\d.]+)%\s+(\d+)\s+[\d.]+\s+([\d.]+)\s*$")
DRENAGEM = re.compile(r"^\s+sustained drain\s+:\s+(\d+)")
CUSTO = re.compile(r"^\s+per-packet cost MEASURED on this machine:\s+(\d+) ns")
EXCEDENTE = re.compile(r"^\s+descriptors ONE mean burst demands:.*=\s+(\d+)")
# `drain: 1191880 and 1196001 packets/s, against 1363015 for the pure ring`
SOCKET = re.compile(r"^\s+drain:\s+(\d+) and (\d+) packets/s")


def ler(diretorio):
    """-> ({execucao: {(secao, anel): {coluna: valor}}}, {execucao: {chave: valor}})."""
    tabs, escs = {}, {}
    arquivos = sorted(glob.glob(os.path.join(diretorio, "rajada-nasdaq.r[1-9]*.txt")))
    for f in arquivos:
        nome = os.path.basename(f)
        tab = tabs.setdefault(nome, {})
        esc = escs.setdefault(nome, {})
        secao = None
        # Na secao 3 as duas linhas de socket tem o MESMO anel (8738), e
        # distingui-las exige a ordem em que aparecem, nao a chave.
        ordem_socket = 0
        for l in open(f, encoding="utf-8", errors="replace"):
            m = SECAO.match(l)
            if m:
                secao = int(m.group(1))
                continue
            m = DRENAGEM.match(l)
            if m:
                esc["drenagem-anel"] = int(m.group(1))
                continue
            m = CUSTO.match(l)
            if m:
                esc["custo-pacote"] = int(m.group(1))
                continue
            m = EXCEDENTE.match(l)
            if m:
                esc["excedente"] = int(m.group(1))
                continue
            m = SOCKET.match(l)
            if m:
                esc["drenagem-recv"] = int(m.group(1))
                esc["drenagem-recvmmsg"] = int(m.group(2))
                continue
            m = LINHA.match(l)
            if m and secao in (1, 2, 3):
                chave = (secao, int(m.group(1)))
                if secao == 3:
                    ordem_socket += 1
                    chave = (3, ordem_socket)
                tab[chave] = {"perda": float(m.group(2)),
                              "ocupacao": int(m.group(3)),
                              "p99": float(m.group(4))}
    return tabs, escs, arquivos


# A CHAVE DA ESCOLHA, declarada: a perda com anel de 1024. E a linha que o
# capitulo cita para dizer que mil descritores nao bastam, e portanto a
# grandeza cuja execucao tipica interessa. Qualquer outra chave seria igualmente
# arbitraria; o que nao pode e nao estar escrita.
CHAVE = (2, 1024)


def mediana_execucao(tabs):
    """O nome da execucao MEDIANA pela chave declarada; empate vence o menor.

    O valor mediano sai por posicao ORDINAL, nunca por interpolacao: com numero
    par de execucoes toma-se a de baixo. Interpolar produziria uma celula que
    nao existe em coleta nenhuma -- o defeito que este programa existe para nao
    cometer. Sobre o valor escolhido, devolve-se a PRIMEIRA execucao que o
    tenha, para que duas coletas com o mesmo empate publiquem a mesma linha.
    """
    cand = sorted((tabs[k][CHAVE]["perda"], k) for k in tabs if CHAVE in tabs[k])
    if not cand:
        return None
    valor = cand[(len(cand) - 1) // 2][0]
    return min(k for v, k in cand if v == valor)


def milhar(v, en):
    """1363015 -> `1 363 015` em portugues, `1,363,015` em ingles."""
    return "{:,}".format(v).replace(",", "," if en else chr(32))


def bloco_resumo(tab, en=False):
    linhas = ["  arrival       ring(n)      loss  peak occ.   p99(us)",
              "  -----------   -------  --------  --------  --------"] if en else \
             ["  chegada       anel(n)     perda  ocup.max   p99(us)",
              "  -----------   -------  --------  --------  --------"]
    for pt, ingles, secao, anel in RESUMO:
        d = tab.get((secao, anel))
        if d is None:
            continue
        #   chegada  col 3-13, a esquerda     ocup.max  col 34-43, a direita
        #   anel(n)  col 14-23, a direita      p99(us)   col 44-53, a direita
        #   perda    col 24-33, a direita
        linhas.append("  %-11s%10d%9.3f%%%10d%10.1f"
                      % (ingles if en else pt, anel,
                         d["perda"], d["ocupacao"], d["p99"]))
    return "\n".join(linhas)


def bloco_socket(tab, esc, en=False):
    rotulos = [("anel de descritores", "descriptor ring", (2, 8192), "drenagem-anel"),
               ("socket UDP (recv um a um)", "UDP socket (recv one at a time)",
                (3, 1), "drenagem-recv"),
               ("socket UDP (recvmmsg em lote)", "UDP socket (recvmmsg batches)",
                (3, 2), "drenagem-recvmmsg")]
    linhas = ["  path                             queue     loss       drain",
              "  ------------------------------  ------  -------  ----------"] if en else \
             ["  caminho                          fila    perda    drenagem",
              "  ------------------------------  -----  -------  ----------"]
    for pt, ingles, chave, k in rotulos:
        d = tab.get(chave)
        if d is None or k not in esc:
            continue
        # A coluna `fila` da linha de socket e 8738 pela construcao do
        # programa (o buffer concedido de 8 MB), e nao vem da tabela: as duas
        # linhas de socket sao indexadas pela ordem, nao pelo anel.
        fila = 8192 if chave == (2, 8192) else 8738
        # AS COLUNAS SAO ABSOLUTAS, e nao larguras de campo encadeadas. O
        # rotulo mais longo do ingles -- `UDP socket (recv one at a time)` --
        # tem 31 caracteres e estoura um campo de 30; com larguras encadeadas
        # ele empurraria a linha inteira uma coluna a direita, e so essa linha.
        # O bloco publicado alinha os tres numeros na MESMA coluna, com a folga
        # do rotulo variavel, e e esse contrato que se reproduz aqui.
        col_fila, col_perda = (40, 49) if en else (39, 48)
        col_dren = col_perda + 12
        l = "  " + (ingles if en else pt)
        l += ("%d" % fila).rjust(col_fila - len(l))
        l += ("%.3f%%" % d["perda"]).rjust(col_perda - len(l))
        l += milhar(esc[k], en).rjust(col_dren - len(l))
        linhas.append(l + (" packets/s" if en else " pacotes/s"))
    return "\n".join(linhas)


# Onde cada bloco consolidado e publicado. A chave e o par de argumentos; o
# valor, o arquivo e a linha do CABECALHO do bloco -- a linha e procurada, nao
# fixada por numero, porque numero de linha envelhece a cada paragrafo inserido.
PUBLICADOS = [
    ((), "docs/01-fundamentos/README.md"),
    (("--en",), "docs/01-fundamentos/README.en.md"),
    (("--socket",), "docs/01-fundamentos/README.md"),
    (("--socket", "--en"), "docs/01-fundamentos/README.en.md"),
]


def referencia(raiz):
    """A coleta mais recente do modulo, pelo mesmo criterio da `campanha.sh`.

    O carimbo `AAAA-MM-DD-HHMM` na frente do nome faz a ordem lexicografica ser
    a ordem do tempo. Os sufixos `-ambiente` e `-sonda` sao coletas irmas, de
    outra natureza, e nao trazem `rajada-nasdaq`.
    """
    base = os.path.join(raiz, "docs/01-fundamentos/medicoes/historico")
    cand = [d for d in sorted(os.listdir(base))
            if re.match(r"^\d{4}-\d{2}-\d{2}-\d{4}", d)
            and not d.endswith(("-ambiente", "-sonda"))
            and glob.glob(os.path.join(base, d, "rajada-nasdaq.r[1-9]*.txt"))]
    return os.path.join(base, cand[-1]) if cand else None


def conferir(raiz):
    """Compara o publicado com o regenerado; devolve o numero de divergencias."""
    dir_ref = referencia(raiz)
    if dir_ref is None:
        print("  nenhuma coleta com rajada-nasdaq no historico do modulo 01")
        return 1
    tabs, escs, _ = ler(dir_ref)
    escolhida = mediana_execucao(tabs)
    tab, esc = tabs[escolhida], escs[escolhida]
    problemas = 0
    for args, arquivo in PUBLICADOS:
        en = "--en" in args
        novo = (bloco_socket(tab, esc, en) if "--socket" in args
                else bloco_resumo(tab, en)).split("\n")
        texto = open(os.path.join(raiz, arquivo), encoding="utf-8").read()
        if "\n".join(novo) in texto:
            continue
        # O cabecalho identifica O BLOCO; se ele nao esta la, o documento nao
        # publica esta tabela e o desencontro e de outra natureza.
        if novo[0] not in texto:
            print("  %s: nao encontrei o bloco de cabecalho %r"
                  % (arquivo, novo[0].strip()[:40]))
            problemas += 1
            continue
        atual = texto.split(novo[0] + "\n")[1].split("```")[0].split("\n")
        for esperada, tem in zip(novo[1:], atual):
            if esperada != tem:
                print("  %s: a coleta %s da\n      %s\n    e o documento publica"
                      "\n      %s" % (arquivo, os.path.basename(dir_ref),
                                      esperada, tem))
                problemas += 1
                break
    print("\n  %d bloco(s) consolidado(s) conferido(s) contra %s (%s);"
          " %d divergencia(s)"
          % (len(PUBLICADOS), os.path.basename(dir_ref), escolhida, problemas))
    return problemas


def autoteste():
    falhas = 0

    def caso(n, descricao, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    # 1. A ESCOLHA DA EXECUCAO e ordinal pela chave declarada, e em numero PAR
    #    de execucoes ela toma a de baixo -- nunca interpola. Interpolar
    #    produziria uma linha que nao existe em coleta nenhuma, que e
    #    exatamente o que este programa existe para nao fazer.
    def exec_com(perda):
        return {(2, 1024): {"perda": perda, "ocupacao": 1024, "p99": 7.0}}
    tabs = {"r1": exec_com(30.0), "r2": exec_com(10.0), "r3": exec_com(20.0)}
    caso(1, "escolhe a execucao mediana pela chave", mediana_execucao(tabs), "r3")
    caso(2, "com numero par, toma a de baixo -- nao interpola",
         mediana_execucao({"r1": exec_com(10.0), "r2": exec_com(20.0)}), "r1")
    caso(3, "empate vence o indice menor",
         mediana_execucao({"r1": exec_com(5.0), "r2": exec_com(5.0),
                           "r3": exec_com(9.0)}), "r1")
    caso(4, "coleta sem a chave nao escolhe nada", mediana_execucao({}), None)

    # 5. O anel de 512 aparece duas vezes, uma por secao, e as duas linhas NAO
    #    sao a mesma: e o par que sustenta o argumento da secao inteira.
    tab2 = {(1, 512): {"perda": 0.0, "ocupacao": 1, "p99": 0.7},
            (2, 512): {"perda": 26.5, "ocupacao": 512, "p99": 375.5}}
    r = bloco_resumo(tab2).splitlines()[2:]
    caso(5, "512 cadenciada e 512 em rajada sao linhas distintas",
         [r[0].split()[0], r[1].split()[0]], ["cadenciada", "rajada"])
    caso(6, "a linha cadenciada leva a ocupacao 1", r[0].split()[-2], "1")

    # 7/8. As duas linhas de socket tem o mesmo anel (8738) e so a ORDEM as
    #    separa. Uma versao anterior indexava por anel e publicava a segunda
    #    duas vezes.
    tab3 = {(2, 8192): {"perda": 1.089, "ocupacao": 8192, "p99": 5656.1},
            (3, 1): {"perda": 1.174, "ocupacao": 8738, "p99": 6836.8},
            (3, 2): {"perda": 1.166, "ocupacao": 8738, "p99": 6810.3}}
    esc = {"drenagem-anel": 1363015, "drenagem-recv": 1191880,
           "drenagem-recvmmsg": 1196001}
    s = bloco_socket(tab3, esc).splitlines()[2:]
    caso(7, "as duas linhas de socket diferem", s[1] != s[2], True)
    caso(8, "a perda do recv e a da primeira linha de socket",
         "1.174%" in s[1], True)

    # 9/10. O SEPARADOR DE MILHAR E COMPARADO POR CODIGO DE CARACTERE, e nao
    #    por literal: o NBSP (U+00A0) e o espaco estreito (U+202F) sao
    #    indistinguiveis a olho do espaco comum, e um deles ja entrou neste
    #    arquivo por copia. Um literal no teste herda o mesmo caractere errado
    #    do codigo e nao mata mutante nenhum. O que o bloco publicado usa, e o
    #    que o `verificar-autodescricao.py` sabe casar entre os dois idiomas,
    #    e o espaco comum.
    caso(9, "milhar em portugues usa o espaco comum, nao NBSP nem estreito",
         [ord(c) for c in milhar(1363015, False)],
         [49, 32, 51, 54, 51, 32, 48, 49, 53])
    caso(10, "milhar em ingles usa virgula", milhar(1363015, True), "1,363,015")

    # 11 a 14. O LAIAUTE e contrato com o documento: a coluna da direita tem de
    #    cair onde o cabecalho publicado a coloca, senao a proxima regeneracao
    #    move o bloco inteiro sem mover um numero.
    caso(11, "resumo: a linha termina na coluna 53",
         len(bloco_resumo(tab2).splitlines()[2]), 53)
    caso(12, "socket pt: a perda termina na coluna 48",
         bloco_socket(tab3, esc).splitlines()[2].index("1.089%") + 6, 48)
    caso(13, "socket en: a perda termina na coluna 49",
         bloco_socket(tab3, esc, True).splitlines()[2].index("1.089%") + 6, 49)
    # O rotulo de 31 caracteres do ingles -- `UDP socket (recv one at a time)`
    # -- estoura um campo de 30 e e o caso que quebrou a versao de largura
    # fixa: ela deslocava aquela linha, e so aquela, uma coluna a direita.
    en_s = bloco_socket(tab3, esc, True).splitlines()[2:]
    caso(14, "rotulo longo nao desloca a coluna da fila",
         [l.index("8738") + 4 for l in en_s[1:]], [40, 40])

    # 15. Coleta sem a secao pedida nao vira linha inventada.
    caso(15, "linha ausente nao aparece", len(bloco_resumo({}).splitlines()), 2)

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    if "--conferir" in sys.argv:
        raiz = os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))))
        sys.exit(1 if conferir(raiz) else 0)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("uso: consolidar-rajada.py <dir-da-coleta> [--en] [--socket]",
              file=sys.stderr)
        sys.exit(2)
    tabs, escs, arquivos = ler(args[0])
    escolhida = mediana_execucao(tabs)
    if escolhida is None:
        print("nenhum rajada-nasdaq.r<N>.txt utilizavel em %s" % args[0],
              file=sys.stderr)
        sys.exit(1)
    en = "--en" in sys.argv
    tab, esc = tabs[escolhida], escs[escolhida]
    if "--escalares" in sys.argv:
        for k in ("custo-pacote", "drenagem-anel", "excedente",
                  "drenagem-recv", "drenagem-recvmmsg"):
            if k in esc:
                print("%-18s %s" % (k, milhar(esc[k], en)))
    else:
        print(bloco_socket(tab, esc, en) if "--socket" in sys.argv
              else bloco_resumo(tab, en))
    print("\n  (%d execucoes; r0 de aquecimento descartado; publicada a mediana "
          "pela perda com anel de 1024: %s)" % (len(arquivos), escolhida),
          file=sys.stderr)
