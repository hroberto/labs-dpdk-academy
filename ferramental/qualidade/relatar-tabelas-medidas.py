#!/usr/bin/env python3
"""Celula de tabela Markdown com unidade de medida tem de existir numa coleta.

`relatar-`, E NAO `verificar-`, E A DIFERENCA E DE CONTRATO. O laco do
`pre-commit.sh` roda todo `verificar-*.py` e marca `[ok]` quando ele sai com
zero. Este aqui sai com zero SEMPRE -- ver o comentario no fim de `main()` --,
entao apareceria como `[ok]` ao lado de "43 sem lastro", que le como "passou".
O nome diz o que ele e: relatorio, nao veredito.

POR QUE ESTE ARQUIVO EXISTE

O `verificar-blocos.py` confere bloco de cerca -- saida literal de programa. Uma
tabela Markdown nao e saida de programa: ela e MONTADA, transcrevendo valores da
saida para celulas, muitas vezes com virgula decimal e ordem diferente.

Por isso ela ficava fora de todo portao. Em 25/09/2026 havia 141 linhas de
tabela com numero medido em 10 documentos, sem quem as conferisse -- e a
consequencia apareceu no modulo 02: o bloco do `custo-init` publicava 117,8 ms
para `-l 0 --in-memory` e a tabela da §2.1 publicava 122,4 ms para a MESMA
configuracao, no mesmo documento. O `122,4` so existia em arquivo numa coleta de
JEDEC-4800 com `--no-huge`.

A REGRA, E POR QUE ELA E ESTA

Confere apenas celula com UNIDADE DE MEDIDA -- ns, us, ms, s, GHz, MT/s, GB/s,
MB/s, Mpps, pps. Uma celula assim e TRANSCRICAO: o numero saiu de um `printf` e
alguem o copiou. Se nao existe em coleta nenhuma, ou a coleta sumiu ou a copia
errou, e os dois casos importam.

Celula com `x`, `×` ou `%` fica FORA: e grandeza DERIVADA, calculada a partir de
outras duas, e cobrar dela presenca em arquivo produziria centenas de falsos
positivos -- o tipo de ruido que ensina a ignorar o portao. A aritmetica dessas
e problema do `verificar-aritmetica`.

O QUE ELE NAO DECIDE

De QUAL coleta a celula deveria vir. Uma tabela comparativa de hardware publica,
de proposito, valores de quatro configuracoes diferentes. Aqui basta que o valor
EXISTA em alguma coleta arquivada; o envelhecimento e pergunta do
`comparar-publicado.py`.

Tambem nao pega celula cujo valor colida por acaso com outro numero qualquer de
alguma coleta. Casar por valor nu e grosseiro, e esta limitacao fica declarada
em vez de escondida: o portao serve contra numero SEM lastro, nao como prova de
que a celula veio do lugar certo.

    uso:  relatar-tabelas-medidas.py [--listar]
          relatar-tabelas-medidas.py --autoteste
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
CERCA = "```"
UNIDADES = r"(?:ns|µs|us|ms|s|GHz|MHz|MT/s|GB/s|MB/s|Mpps|pps|KB|MB|GB)"
# `**1,627 ns**` ou `1.627 ns` -- numero com decimal, seguido de unidade.
CELULA = re.compile(r"\*{0,2}(\d+[.,]\d+)\*{0,2}\s*" + UNIDADES + r"\b")
DIRTY = re.compile(r"^\s*origin:.*-dirty\b", re.M)


def numeros_arquivados():
    """Todo numero com decimal que aparece em coleta arquivada, normalizado."""
    vistos = set()
    dirs = sorted(set(RAIZ.glob("docs/*/medicoes/historico/*/")) |
                  set(RAIZ.glob("trilha/**/historico/*/")))
    for d in dirs:
        for f in d.glob("*.txt"):
            if f.name.endswith(".r0.txt"):
                continue                      # aquecimento nao e procedencia
            texto = f.read_text(errors="replace")
            if DIRTY.search(texto):
                continue                      # arvore suja nao e procedencia
            for m in re.finditer(r"\d+\.\d+", texto):
                vistos.add(m.group(0))
    return vistos


def celulas(path):
    """(linha, valor_normalizado, texto) de cada celula com unidade."""
    out, dentro = [], False
    for i, l in enumerate(path.read_text(errors="replace").split("\n"), 1):
        if l.lstrip().startswith(CERCA):
            dentro = not dentro
            continue
        if dentro or not l.lstrip().startswith("|"):
            continue
        for m in CELULA.finditer(l):
            out.append((i, m.group(1).replace(",", "."), l.strip()))
    return out


def sustenta(valor, arquivados):
    """O valor existe em coleta? Tenta o literal e as vizinhancas de precisao.

    `1.63` publicado pode vir de `1.627` arquivado: a tabela arredonda. Aceitar
    o prefixo evitaria o falso positivo, mas tambem aceitaria qualquer coisa que
    COMECE igual -- `1.6` casaria com `1.699`. O criterio usado e mais estreito:
    o arquivado tem de arredondar, na precisao da celula, para o valor da celula.
    """
    if valor in arquivados:
        return True
    casas = len(valor.split(".")[1])
    try:
        alvo = float(valor)
    except ValueError:
        return False
    for a in arquivados:
        try:
            if round(float(a), casas) == alvo:
                return True
        except ValueError:
            continue
    return False


def main():
    arquivados = numeros_arquivados()
    if not arquivados:
        print("  nenhuma coleta arquivada: nada a conferir", file=sys.stderr)
        return 0
    docs = sorted(RAIZ.glob("docs/**/*.md")) + sorted(RAIZ.glob("trilha/**/*.md"))
    orfas, total = [], 0
    for p in docs:
        if "/historico/" in str(p):
            continue
        for linha, valor, texto in celulas(p):
            total += 1
            if not sustenta(valor, arquivados):
                orfas.append((p.relative_to(RAIZ), linha, valor, texto))

    if "--listar" in sys.argv:
        doc = None
        for p, linha, valor, texto in orfas:
            if p != doc:
                print("  %s" % p)
                doc = p
            print("    :%-5d %-10s %s" % (linha, valor, texto[:72]))
        print()
    print("  %d celula(s) de tabela com unidade conferida(s); %d sem lastro em coleta"
          % (total, len(orfas)))
    if orfas and "--listar" not in sys.argv:
        print("  detalhe: ./ferramental/qualidade/relatar-tabelas-medidas.py --listar")
    # RELATA, NAO BLOQUEIA -- e a decisao tem razao, nao comodidade.
    #
    # Das 43 celulas sem lastro em 25/09/2026, a maioria precisa de CAMPANHA
    # para resolver (a tabela envelheceu) ou de DECISAO editorial (o valor e
    # calculado da taxa de linha, ou citado de outra maquina). Um portao
    # vermelho que ninguem consegue limpar ensina a passar `--no-verify`, que e
    # pior que nao ter portao -- a mesma razao pela qual o relatorio de
    # arredondados e o Portao B tambem ficam fora do veredito.
    #
    # O que ele nao pode e ficar invisivel: a contagem sai na barra toda vez.
    return 0


def autoteste():
    falhas = 0

    def caso(n, desc, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s (esperado %r, obtido %r)"
                  % (n, desc, esperado, obtido))
            falhas += 1

    import tempfile, shutil
    d = Path(tempfile.mkdtemp())
    f = d / "t.md"

    # 1. Celula com unidade entra; com `x` ou `%` NAO -- sao derivadas.
    f.write_text("| 1 | 1,627 ns | 2,8× | 12,7% |\n")
    caso(1, "so a celula com unidade entra", [c[1] for c in celulas(f)], ["1.627"])

    # 2. Dentro de bloco de cerca nao entra: la o `verificar-blocos` ja manda.
    f.write_text("```\n| 1 | 1,627 ns |\n```\n")
    caso(2, "dentro de cerca nao entra", celulas(f), [])

    # 3. Linha que nao e tabela nao entra.
    f.write_text("O custo foi de 1,627 ns naquela execucao.\n")
    caso(3, "prosa nao entra", celulas(f), [])

    # 4. ARREDONDAMENTO. A tabela publica 1,63; a coleta tem 1.627. Sustenta.
    caso(4, "arredondamento sustenta", sustenta("1.63", {"1.627"}), True)
    # 5. E o inverso NAO vale: 1.6 nao pode casar com 1.699 so por comecar igual.
    caso(5, "prefixo nao sustenta", sustenta("1.6", {"1.699"}), False)
    # 6. Valor sem nada parecido em arquivo: sem lastro.
    caso(6, "valor ausente nao sustenta", sustenta("9.99", {"1.627"}), False)
    # 7. Negrito em volta do numero nao esconde a celula.
    f.write_text("| 128 | **0,372 ns** |\n")
    caso(7, "negrito nao esconde", [c[1] for c in celulas(f)], ["0.372"])

    shutil.rmtree(d, ignore_errors=True)
    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(main())
