#!/usr/bin/env python3
"""Confere que toda linha de tabela tem a largura do cabecalho dela.

POR QUE ISTO EXISTE

Sete linhas de referencia bibliografica foram parar dentro da tabela
comparativa da 6.2 -- "maquina de referencia x servidor de market data" --
em vez da tabela do 13. Eram linhas de duas celulas numa tabela de tres
colunas.

O Markdown nao reclama. Ele preenche a celula que falta com vazio e renderiza
a tabela inteira sem aviso. Nenhum dos oito verificadores existentes pegava:
os links estavam validos, o idioma estava certo, a paridade de titulos estava
alinhada, os numeros conferiam. So a largura estava errada, e ninguem olhava
para a largura.

Pior: como o erro nao aparece no texto renderizado como erro, ele sobreviveu
a uma revisao de paridade pt/en inteira. O documento em ingles ficou com tres
referencias A MAIS na tabela errada e A MENOS na tabela certa.

POR QUE ESTE PODE SER PORTAO, E O AUDITOR DE FONTES NAO

Este e deterministico: ou a linha tem a largura do cabecalho, ou nao tem.
Zero falso positivo por construcao. O `auditar-fontes.py` levanta candidatos e
erra de proposito -- por isso ele fica de fora do pre-commit.
"""
import pathlib
import re
import sys

IGNORAR = {".git", "build", "builddir", "build-precommit", "subprojects",
           "temp", "__pycache__"}
SEPARADOR = re.compile(r"^\|[\s:|-]+\|$")


def celulas(linha):
    """Conta celulas de uma linha de tabela, ignorando pipes escapados."""
    return len(re.split(r"(?<!\\)\|", linha.strip())) - 2


def conferir(caminho):
    falhas = []
    largura = cabecalho = None
    codigo = False
    for n, linha in enumerate(caminho.read_text().split("\n"), 1):
        if linha.lstrip().startswith("```"):
            codigo = not codigo
            largura = None
            continue
        if codigo or not linha.startswith("|"):
            if not linha.startswith("|"):
                largura = None
            continue
        if SEPARADOR.match(linha):
            largura = celulas(linha)
            continue
        if largura is None:
            cabecalho = (n, celulas(linha))
            continue
        if celulas(linha) != largura:
            falhas.append((n, celulas(linha), largura, linha[:90]))
    return falhas


def autoteste():
    """Linha estreita TEM de ser acusada; tabela correta TEM de passar."""
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        alvo = pathlib.Path(d) / "t.md"
        boa = "| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n"
        alvo.write_text(boa + "| so duas |  |\n")
        if not conferir(alvo):
            print("  AUTOTESTE FALHOU: linha de 2 celulas passou em tabela de 3")
            return True
        alvo.write_text(boa)
        if conferir(alvo):
            print("  AUTOTESTE FALHOU: tabela correta foi acusada")
            return True
        # Pipe dentro de bloco de codigo nao e tabela.
        alvo.write_text("```\n| isto | nao | e | tabela |\n```\n" + boa)
        if conferir(alvo):
            print("  AUTOTESTE FALHOU: bloco de codigo tratado como tabela")
            return True
        # Pipe escapado nao abre celula nova.
        alvo.write_text("| a | b |\n|---|---|\n| x \\| y | z |\n")
        if conferir(alvo):
            print("  AUTOTESTE FALHOU: pipe escapado contado como celula")
            return True
    print("  autoteste ok: acusa linha estreita, aceita tabela correta,"
          " bloco de codigo e pipe escapado")
    return False


def main():
    if "--autoteste" in sys.argv:
        return 1 if autoteste() else 0
    raiz = pathlib.Path(__file__).resolve().parents[2]
    docs = sorted(p for p in raiz.rglob("*.md")
                  if not IGNORAR & set(p.relative_to(raiz).parts))
    total = falhas = 0
    for doc in docs:
        total += 1
        for n, tem, esperado, texto in conferir(doc):
            falhas += 1
            rel = doc.relative_to(raiz)
            print(f"{rel}:{n}: linha com {tem} celula(s), tabela tem "
                  f"{esperado}\n    {texto}")
    print(f"  {total} documento(s) conferidos; {falhas} linha(s) de tabela "
          f"com largura errada")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
