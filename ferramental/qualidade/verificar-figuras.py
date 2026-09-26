#!/usr/bin/env python3
"""Confere que o `alt=` de cada figura e o `<desc>` do SVG dizem a MESMA coisa.

POR QUE ESTE PORTAO EXISTE

O texto alternativo de uma figura carrega numeros -- "a vazao sobe de 171 para
948 milhoes" -- e esses numeros nao aparecem em lugar nenhum que os portoes
anteriores olhem. O `verificar-blocos.py` confere blocos cercados; o
`verificar-evidencia.py` procura o numero da prosa num bloco. Nenhum dos dois
enxerga dentro de um atributo HTML.

O efeito e que o `alt=` envelhece em silencio. Uma revisao externa encontrou
alt de figura descrevendo uma coleta de duas configuracoes de hardware atras,
ao lado do SVG ja regenerado -- a imagem dizia uma coisa e o texto para quem
usa leitor de tela dizia outra.

A CONFERENCIA POSSIVEL, E POR QUE ESTA

Nao da para conferir o `alt=` contra a medicao: ele e prosa. Mas o gerador de
graficos escreve o `<desc>` DENTRO do SVG a partir da mesma string, entao os
dois tem de ser identicos. Regenerar o grafico atualiza o `<desc>`; se o `alt=`
do Markdown nao acompanhar, a divergencia aparece aqui.

Isso transforma "lembrar de atualizar o alt" em erro de portao -- que e a
unica forma que funciona.

LIMITE DECLARADO

O portao nao sabe se o `<desc>` esta certo; sabe que os dois concordam. Um
numero errado escrito nos dois lugares passa. O que ele impede e a DERIVA entre
eles, que e o defeito observado.
"""
import html
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]


def normalizar(s: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(s)).strip()


def autoteste() -> int:
    """O portao conferido contra casos construidos.

    O PRIMEIRO CASO EXISTE POR UM DEFEITO DESTE ARQUIVO.

    A primeira versao procurava `<desc>` com a expressao `<desc>(.*?)</desc>`,
    e o gerador emite `<desc id="d">`. Nenhum SVG casava, e a sonda relatava
    "0 divergencias" sobre doze figuras que nao tinha lido -- o mesmo falso
    verde que ela existe para impedir, dentro dela mesma.
    """
    import tempfile

    falhas = 0
    casos = [
        ("desc com atributo, igual ao alt", '<desc id="d">um grafico</desc>', "um grafico", 0),
        ("desc sem atributo, igual ao alt", "<desc>um grafico</desc>", "um grafico", 0),
        ("divergentes", '<desc id="d">um grafico</desc>', "outro grafico", 1),
        ("espaco e quebra de linha nao contam", '<desc id="d">um\n  grafico</desc>', "um grafico", 0),
        ("entidade HTML no alt", '<desc id="d">a &amp; b</desc>', "a &amp; b", 0),
        ("svg sem desc nenhum", "<title>so titulo</title>", "um grafico", 1),
    ]
    for rotulo, desc, alt, espera in casos:
        with tempfile.TemporaryDirectory() as d:
            raiz = pathlib.Path(d)
            (raiz / "docs" / "m" / "imagens").mkdir(parents=True)
            (raiz / "docs" / "m" / "imagens" / "g.svg").write_text(f"<svg>{desc}</svg>")
            (raiz / "docs" / "m" / "README.md").write_text(
                f'# m\n\n<img alt="{alt}" src="imagens/g.svg">\n')
            global RAIZ
            antes, RAIZ = RAIZ, raiz
            try:
                import io
                import contextlib
                with contextlib.redirect_stdout(io.StringIO()):
                    rc = main()
            finally:
                RAIZ = antes
            if rc != espera:
                print(f"  AUTOTESTE FALHOU: {rotulo} deu rc={rc}, esperado {espera}")
                falhas += 1
    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return 1 if falhas else 0


def main() -> int:
    pares = 0
    falhas = []
    sem_desc = []
    for md in sorted(list(RAIZ.glob("docs/**/*.md")) + list(RAIZ.glob("trilha/**/*.md"))):
        texto = md.read_text(encoding="utf-8")
        for m in re.finditer(r'<img\s+alt="([^"]*)"\s+src="([^"]+)"', texto):
            alt, src = m.group(1), m.group(2)
            svg = (md.parent / src).resolve()
            if not svg.exists():
                continue          # verificar-links.py ja cobre caminho quebrado
            pares += 1
            d = re.search(r"<desc[^>]*>(.*?)</desc>", svg.read_text(encoding="utf-8"), re.S)
            rel = md.relative_to(RAIZ)
            if d is None:
                sem_desc.append(f"{rel}: {src} nao tem <desc>")
                continue
            if normalizar(alt) != normalizar(d.group(1)):
                falhas.append((rel, src, normalizar(alt), normalizar(d.group(1))))

    for rel, src, alt, desc in falhas:
        print(f"  {rel}: alt= e <desc> de {src} divergem")
        print(f"      alt : {alt}")
        print(f"      desc: {desc}")
    for s in sem_desc:
        print(f"  {s}")

    n = len(falhas) + len(sem_desc)
    print(f"\n  {pares} figura(s) conferida(s); {n} divergencia(s) entre alt= e <desc>")
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(autoteste() if "--autoteste" in sys.argv else main())
