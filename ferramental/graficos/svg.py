# SPDX-License-Identifier: MIT
"""Primitivas de SVG para os gráficos do projeto.

POR QUE ESCREVER SVG À MÃO, EM VEZ DE USAR UMA BIBLIOTECA

Três razões, nesta ordem:

1. **O SVG é texto, e texto entra no diff.** Quando uma medição é refeita, o
   diff do gráfico mostra o que mudou — do mesmo jeito que o diff da tabela. Um
   PNG não mostra, e a saída de biblioteca é verbosa demais para que o diff
   signifique alguma coisa.
2. **Sem dependência de build.** Qualquer pessoa regenera com o Python da
   distribuição, sem instalar nada.
3. **Controle total do contraste.** Os gráficos precisam passar nos mesmos
   limiares de acessibilidade nos dois temas, e isso exige escolher cada cor,
   não aceitar a paleta padrão de uma biblioteca.

A paleta e as regras de marca vêm de um sistema de design validado; ver
`graficos-memoria.py`.
"""

TIPOGRAFIA = "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"


def escapar(t):
    return (str(t).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def texto(x, y, s, cor, tam=13, peso=400, ancora="start", tabular=False, opacidade=None):
    extra = ' font-variant-numeric="tabular-nums"' if tabular else ""
    op = f' opacity="{opacidade}"' if opacidade is not None else ""
    return (f'<text x="{x:.1f}" y="{y:.1f}" fill="{cor}" font-size="{tam}" '
            f'font-weight="{peso}" text-anchor="{ancora}" '
            f'font-family="{TIPOGRAFIA}"{extra}{op}>{escapar(s)}</text>')


def barra_h(x, y, larg, alt, cor, raio=4):
    """Barra horizontal com a PONTA DE DADO arredondada e a base reta.

    A base reta ancora a barra na linha zero; a ponta arredondada é a marca fina
    do sistema de design. Arredondar os dois lados faria a barra flutuar."""
    larg = max(larg, 0.6)
    r = min(raio, larg, alt / 2)
    return (f'<path d="M{x:.1f},{y:.1f} H{x + larg - r:.1f} '
            f'Q{x + larg:.1f},{y:.1f} {x + larg:.1f},{y + r:.1f} '
            f'V{y + alt - r:.1f} Q{x + larg:.1f},{y + alt:.1f} '
            f'{x + larg - r:.1f},{y + alt:.1f} H{x:.1f} Z" fill="{cor}"/>')


def linha(x1, y1, x2, y2, cor, larg=1, tracejado=None):
    d = f' stroke-dasharray="{tracejado}"' if tracejado else ""
    return (f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{cor}" stroke-width="{larg}"{d}/>')


def poli(pontos, cor, larg=2):
    p = " ".join(f"{x:.1f},{y:.1f}" for x, y in pontos)
    return (f'<polyline points="{p}" fill="none" stroke="{cor}" '
            f'stroke-width="{larg}" stroke-linejoin="round" stroke-linecap="round"/>')


def ponto(x, y, cor, anel, r=4.5):
    """Marcador com anel da cor da superfície: separa marcas que se sobrepõem
    sem desenhar borda em volta delas."""
    return (f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{cor}" '
            f'stroke="{anel}" stroke-width="2"/>')


def documento(larg, alt, superficie, titulo, descricao, corpo):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {larg} {alt}" '
        f'width="{larg}" height="{alt}" role="img" '
        f'aria-labelledby="t d" font-family="{TIPOGRAFIA}">\n'
        f'<title id="t">{escapar(titulo)}</title>\n'
        f'<desc id="d">{escapar(descricao)}</desc>\n'
        f'<rect width="{larg}" height="{alt}" fill="{superficie}"/>\n'
        + "\n".join(corpo) + "\n</svg>\n")
