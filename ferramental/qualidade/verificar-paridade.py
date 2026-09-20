#!/usr/bin/env python3
"""Confere que cada documento e o seu par em ingles tem a MESMA ESTRUTURA.

POR QUE ISTO EXISTE

A v1.01.00 deu a cada documento um par `.en.md`. A v1.02.00 repontou 165
referencias que, dentro dos documentos em ingles, apontavam para o par em
portugues -- e a traducao da ancora foi feita POR POSICAO: o n-esimo titulo do
`.md` corresponde ao n-esimo do `.en.md`.

Essa premissa nunca tinha sido verificada. Se um par tivesse titulos em ordem
diferente, o link apontaria para uma secao VALIDA E ERRADA, e o
`verificar-links.py` nao acusaria nada: a ancora existe. O leitor clicaria em
"veja a secao 4.2" e cairia na 4.3.

Este verificador fecha esse buraco. Ele compara, posicao a posicao, o NIVEL do
titulo (`##`, `###`) e o PREFIXO NUMERICO (`4.1`, `4.2.1`). Nao compara o texto,
que e traduzido de proposito.

O QUE ELE DELIBERADAMENTE NAO FAZ, e vale declarar

Nao compara os NUMEROS dos dois documentos. Foi tentado, em tres formatos de
normalizacao, e o resultado ficou entre 5 e 13 pares limpos de 23 -- ruido
demais. As causas sao legitimas: prosa usa numerais em quantidades diferentes
entre idiomas ("um nucleo" x "one core"), numeros de versao usam ponto nos dois,
e o separador de milhar varia entre espaco e virgula dentro do proprio
repositorio.

Um verificador ruidoso e desligado, e essa e a forma mais comum de um controle
morrer. A comparacao numerica continua util, mas com ESCOPO DE SECAO e conduzida
a mao durante uma edicao -- foi assim que ela pegou, nesta sessao, numeros
desatualizados no texto alternativo de um grafico. Ferramenta de quem edita, nao
barra de quem commita.
"""
import pathlib
import re
import sys

IGNORAR = {".git", "build", "builddir", "build-precommit", "subprojects", "temp", "__pycache__"}
TITULO = re.compile(r"^(#{1,6})\s+(.*)$")
PREFIXO = re.compile(r"^([\d.]+)\s")


def _raiz():
    for d in pathlib.Path(__file__).resolve().parents:
        if (d / "meson.build").is_file() and (d / "docs").is_dir():
            return d
    raise SystemExit("nao achei a raiz do repositorio a partir de " + __file__)


def titulos(caminho):
    """(nivel, prefixo numerico) de cada titulo, fora de blocos de codigo."""
    saida, dentro = [], False
    for linha in caminho.read_text(encoding="utf-8").split("\n"):
        if linha.lstrip().startswith("```"):
            dentro = not dentro
            continue
        if dentro:
            continue
        m = TITULO.match(linha)
        if m:
            p = PREFIXO.match(m.group(2) + " ")
            saida.append((len(m.group(1)), p.group(1) if p else None, m.group(2)[:52]))
    return saida


def fontes(caminho):
    """Os rotulos de referencia DEFINIDOS no rodape do documento.

    POR QUE ISTO ENTROU, em 19/09/2026.

    O par de titulos ja acusava estrutura divergente, e acusou: o §9.1 entrou
    so no portugues e a contagem caiu para 24 de 25. Mas a divergencia
    BIBLIOGRAFICA e independente da estrutural -- um paragrafo novo com
    citacao nova cabe dentro de um titulo que ja existe nos dois lados, e ai
    nada acusa.

    A consequencia e de integridade, nao de traducao: o leitor em ingles
    recebe os mesmos numeros e NAO recebe as mesmas fontes para julga-los.
    Este teste e barato e deterministico -- compara conjuntos de rotulos, nao
    tenta provar equivalencia semantica de traducao, que exigiria heuristica
    perigosa."""
    return {m.group(1).lower() for m in
            re.finditer(r"(?m)^\[([^\]^]+)\]:\s*\S+",
                        caminho.read_text(encoding="utf-8"))}


def verificar(raiz):
    raiz = pathlib.Path(raiz)
    pares = falhas = 0
    for pt in sorted(raiz.rglob("*.md")):
        if any(p in IGNORAR for p in pt.parts) or pt.name.endswith(".en.md"):
            continue
        en = pt.with_name(pt.name[:-3] + ".en.md")
        if not en.exists():
            continue
        pares += 1
        a, b = titulos(pt), titulos(en)
        rel = pt.relative_to(raiz)
        if len(a) != len(b):
            falhas += 1
            print(f"  {rel}: {len(a)} titulos no pt contra {len(b)} no en")
            continue
        div = [(i, x, y) for i, (x, y) in enumerate(zip(a, b)) if x[:2] != y[:2]]
        if div:
            falhas += 1
            print(f"  {rel}: {len(div)} titulo(s) fora de ordem ou de nivel")
            for i, x, y in div[:4]:
                print(f"      posicao {i}: pt nivel {x[0]} num {x[1]} ({x[2]})")
                print(f"                  en nivel {y[0]} num {y[1]} ({y[2]})")
            continue

        # A BIBLIOGRAFIA, que e independente da estrutura de titulos.
        fa, fb = fontes(pt), fontes(en)
        so_pt, so_en = sorted(fa - fb), sorted(fb - fa)
        if so_pt or so_en:
            falhas += 1
            print(f"  {rel}: bibliografia divergente entre o par")
            if so_pt:
                print(f"      so no pt: {' '.join(so_pt)}")
            if so_en:
                print(f"      so no en: {' '.join(so_en)}")
    print(f"\n  {pares - falhas} de {pares} pares com estrutura de titulos e"
          " bibliografia alinhadas")
    return falhas > 0


def autoteste():
    """Um par com titulos trocados de ordem TEM de ser acusado."""
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        r = pathlib.Path(d)
        (r / "meson.build").write_text("")
        (r / "docs").mkdir()
        (r / "a.md").write_text("# T\n## 1. um\n## 2. dois\n")
        (r / "a.en.md").write_text("# T\n## 2. two\n## 1. one\n")
        if not verificar(r):
            print("  AUTOTESTE FALHOU: ordem trocada passou despercebida")
            return True
        (r / "a.en.md").write_text("# T\n## 1. one\n## 2. two\n")
        if verificar(r):
            print("  AUTOTESTE FALHOU: par correto foi acusado")
            return True

        # BIBLIOGRAFIA DIVERGENTE COM TITULOS IDENTICOS.
        #
        # Este e o caso que o teste de titulos NAO pega, e e por ele que a
        # sonda de fontes existe: um paragrafo com citacao nova cabe dentro de
        # um titulo que ja existe nos dois lados. Os titulos continuam
        # alinhados, e o leitor em ingles recebe o mesmo numero SEM a fonte
        # que o sustenta.
        (r / "a.md").write_text("# T\n## 1. um\n## 2. dois\n\n"
                                "veja [isto][novo].\n\n[novo]: https://x\n")
        (r / "a.en.md").write_text("# T\n## 1. one\n## 2. two\n\n"
                                   "see this.\n")
        if not verificar(r):
            print("  AUTOTESTE FALHOU: fonte presente so no pt, com titulos"
                  " alinhados, passou despercebida")
            return True

        # E o simetrico, porque a traducao tambem ganha fonte sozinha.
        (r / "a.en.md").write_text("# T\n## 1. one\n## 2. two\n\n"
                                   "see [this][novo] and [that][extra].\n\n"
                                   "[novo]: https://x\n[extra]: https://y\n")
        if not verificar(r):
            print("  AUTOTESTE FALHOU: fonte presente so no en passou"
                  " despercebida")
            return True

        # Com as duas bibliografias iguais, o par volta a passar.
        (r / "a.en.md").write_text("# T\n## 1. one\n## 2. two\n\n"
                                   "see [this][novo].\n\n[novo]: https://x\n")
        if verificar(r):
            print("  AUTOTESTE FALHOU: par com bibliografia IGUAL foi acusado")
            return True
    print("  autoteste ok: acusa ordem trocada, bibliografia divergente nos dois"
          " sentidos, e aceita par correto")
    return False


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else _raiz()) else 0)
