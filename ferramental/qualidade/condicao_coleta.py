#!/usr/bin/env python3
"""Diz se uma coleta arquivada correu COM ou SEM sessao grafica.

POR QUE ESTE ARQUIVO EXISTE

Ate 25/09/2026 todas as coletas arquivadas eram de modo texto, e "a coleta mais
recente" era um criterio suficiente para escolher a referencia. Naquela noite
entrou a primeira coleta GRAFICA de controle -- a que o pre-registro da §7.1 da
metodologia do modulo 01 pediu -- e o criterio quebrou na hora:

  - `comparar-publicado.py` passou a confrontar o material contra ela, e o
    aviso de envelhecimento saltou de 27 para 47 linhas;
  - `consolidar-rajada.py --conferir` acusou quatro divergencias que eram a
    diferenca de condicao, nao envelhecimento;
  - `consolidar-isolamento.py --conferir` foi pior: AGREGOU a coleta grafica
    com as sete de texto, publicando uma tabela que mistura duas condicoes --
    exatamente o que a §6 daquele topico existe para nao fazer.

Nenhum dos tres estava errado no que fazia; os tres estavam lendo um arquivo
que nao dizia a condicao. Agora diz, e este modulo e onde a leitura mora, para
que os tres respondam a mesma pergunta do mesmo jeito.

DE ONDE SAI A RESPOSTA, EM ORDEM

  1. `ambiente.txt` da propria coleta, campo `sessao grafica`. E o campo que o
     `scripts/ambiente.sh` passou a gravar em 25/09/2026.

  2. `ambiente.txt` da coleta IRMA do topico de isolamento, mesmo carimbo,
     campo `processos grafico`. A `campanha.sh` ja o gravava antes disso, e e
     por ele que as coletas anteriores a 25/09 continuam classificaveis.

  3. Nao achou nenhum dos dois: devolve None. NAO devolve "texto" por ser o que
     todas as coletas antigas eram -- inferir a condicao e exatamente o defeito
     que este modulo corrige. Quem chama decide o que fazer com o None, e o que
     nao pode e fingir que sabe.
"""
import os
import pathlib
import re

RAIZ = pathlib.Path(__file__).resolve().parents[2]
ISOLAMENTO = RAIZ / "trilha/03-performance/03-isolamento-cpu/historico"

# `sessao grafica ......... 2 processo(s); graphical.target active; ...`
CAMPO_FUND = re.compile(r"^\s*sessao grafica\s*\.*\s*(\d+) processo", re.M)
# `processos grafico: 0`
CAMPO_ISO = re.compile(r"^processos grafico:\s*(\d+)\s*$", re.M)


def _ler(caminho, padrao):
    try:
        m = padrao.search(pathlib.Path(caminho).read_text(errors="replace"))
    except OSError:
        return None
    return int(m.group(1)) if m else None


def processos_graficos(diretorio):
    """Quantos processos graficos estavam vivos, ou None se nao esta declarado."""
    d = pathlib.Path(diretorio)
    n = _ler(d / "ambiente.txt", CAMPO_FUND)
    if n is not None:
        return n
    # A IRMA DO ISOLAMENTO tem o mesmo nome de diretorio, porque a `campanha.sh`
    # carimba as duas com o mesmo `<data>-<hora>-<configuracao>`.
    return _ler(ISOLAMENTO / d.name / "ambiente.txt", CAMPO_ISO)


# `uptime           : up 4 hours, 37 minutes`
CAMPO_UPTIME = re.compile(r"^\s*uptime\s*:?\s*\.*\s*up (.+?)\s*$", re.M)
_UNIDADES = (("day", 1440), ("hour", 60), ("minute", 1), ("week", 10080))


def uptime_minutos(diretorio):
    """Quantos minutos a maquina estava ligada, ou None se nao esta declarado.

    POR QUE O UPTIME E CONDICAO, E NAO CURIOSIDADE

    Em 03/10/2026, ao dar programa a tabela do braco grafico do topico de
    isolamento, as duas coletas graficas discordaram em 9 us na mediana
    declarando a MESMA condicao. O `ambiente.txt` guardava a diferenca que a
    declaracao nao captura: `up 4 hours, 37 minutes` numa, `up 1 minute` na
    outra -- e TODAS as dez coletas de modo texto correm de 0 a 2 minutos
    depois do boot.

    Isso importa porque o mecanismo que a §6.6 identifica e o *power gating* da
    GPU, que depende de a GPU ficar OCIOSA. Um minuto depois do boot, com a
    area de trabalho subindo, ela nao esta. A coleta de uptime alto nao e
    comparavel as de texto pelo protocolo de coleta; a de uptime baixo e.

    DEVOLVE None, E NAO ZERO, quando nao acha. Zero seria "acabou de ligar",
    que e uma afirmacao -- e inferir condicao e o defeito que este modulo
    corrige.
    """
    import pathlib as _p
    for caminho in (_p.Path(diretorio) / "ambiente.txt",
                    ISOLAMENTO / _p.Path(diretorio).name / "ambiente.txt"):
        try:
            texto = _p.Path(caminho).read_text(errors="replace")
        except OSError:
            continue
        m = CAMPO_UPTIME.search(texto)
        if m is None:
            continue
        total, achou = 0, False
        for n, peso in _UNIDADES:
            u = re.search(r"(\d+)\s+" + n, m.group(1))
            if u:
                total += int(u.group(1)) * peso
                achou = True
        if achou:
            return total
    return None


def e_texto(diretorio):
    """True (sem sessao grafica), False (com), ou None (nao declarado)."""
    n = processos_graficos(diretorio)
    return None if n is None else n == 0


def so_texto(diretorios, incluir_nao_declarados=True):
    """Filtra para as coletas SEM sessao grafica.

    `incluir_nao_declarados` existe porque a alternativa e pior: descartar em
    silencio toda coleta anterior ao campo faria a referencia saltar para uma
    coleta recente sem ninguem notar, que e a mesma classe de defeito. Quem
    precisar de rigor passa False e recebe so o que esta declarado.
    """
    fora = []
    for d in diretorios:
        t = e_texto(d)
        if t is True or (t is None and incluir_nao_declarados):
            fora.append(d)
    return fora


def autoteste():
    import tempfile
    falhas = 0

    def caso(n, descricao, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)

        def coleta(nome, texto=None):
            d = base / nome
            d.mkdir()
            if texto is not None:
                (d / "ambiente.txt").write_text(texto)
            return d

        # 1/2. O campo do modulo 01, nas duas formas que o `ambiente.sh` emite.
        g = coleta("grafica", "  sessao grafica ......... 2 processo(s); "
                              "graphical.target active; alvo padrao graphical.target\n")
        t = coleta("texto", "  sessao grafica ......... 0 processo(s); "
                            "graphical.target inactive; alvo padrao multi-user.target\n")
        caso(1, "duas sessoes graficas -> nao e texto", e_texto(g), False)
        caso(2, "zero processos -> e texto", e_texto(t), True)

        # 3. SEM DECLARACAO NENHUMA E None, e nao True. Devolver True aqui faria
        #    uma coleta grafica antiga passar por texto, que e pior que nao
        #    saber: o erro fica invisivel e contamina a agregacao.
        v = coleta("sem-campo", "  governor ............... performance\n")
        caso(3, "ambiente sem o campo -> None", e_texto(v), None)
        caso(4, "diretorio sem ambiente.txt -> None",
             e_texto(base / "nao-existe"), None)

        # 5/6. O filtro, e a escolha sobre o nao declarado.
        caso(5, "so_texto inclui o nao declarado por padrao",
             sorted(x.name for x in so_texto([g, t, v])), ["sem-campo", "texto"])
        caso(6, "com incluir_nao_declarados=False, so o declarado",
             [x.name for x in so_texto([g, t, v], False)], ["texto"])

        # 7/8. UM CAMPO PARECIDO NAO PODE CASAR. `processos grafico` e do
        #    arquivo do isolamento e tem outro formato; se o padrao do modulo 01
        #    casasse com ele, a ordem de precedencia deixaria de valer.
        p = coleta("outro-campo", "processos grafico: 2\n")
        caso(7, "o padrao do modulo 01 nao casa o campo do isolamento",
             _ler(p / "ambiente.txt", CAMPO_FUND), None)
        caso(8, "o padrao do isolamento casa o campo do isolamento",
             _ler(p / "ambiente.txt", CAMPO_ISO), 2)

        # 9. O PADRAO PRECISA DA ANCORA `sessao grafica`, e este caso e o que
        #    prova. Um padrao solto como `(\d+) processo` casaria a PRIMEIRA
        #    linha do arquivo que falasse em processo -- e o `ambiente.sh`
        #    imprime varias antes dela.
        a = coleta("ancora", "  outra coisa ............ 4 processos concorrentes\n"
                             "  sessao grafica ......... 0 processo(s); "
                             "graphical.target inactive; alvo padrao multi-user.target\n")
        caso(9, "le a linha da sessao, nao a primeira que diz processo",
             e_texto(a), True)

        # 10/11. O RECUO PARA A COLETA IRMA do isolamento e o que classifica
        #    tudo que foi arquivado antes de 25/09. Sem ele, oito coletas
        #    viravam "nao declarado" e a referencia passava a depender do que
        #    `incluir_nao_declarados` fizesse.
        global ISOLAMENTO
        antes = ISOLAMENTO
        try:
            irmaos = base / "irmaos"
            irmaos.mkdir()
            (irmaos / "so-irma").mkdir()
            (irmaos / "so-irma" / "ambiente.txt").write_text(
                "modo declarado   : grafico\nprocessos grafico: 3\n")
            ISOLAMENTO = irmaos
            orfa = coleta("so-irma-2", None)
            os.rename(orfa, base / "so-irma")
            caso(10, "sem ambiente proprio, le o da coleta irma",
                 processos_graficos(base / "so-irma"), 3)
            caso(11, "e classifica como grafico por ela",
                 e_texto(base / "so-irma"), False)
        finally:
            ISOLAMENTO = antes

        # 12 a 18. O UPTIME, nas formas que o `uptime -p` emite.
        #
        # Ele e condicao: as duas coletas graficas do topico de isolamento
        # discordam em 9 us na mediana declarando a MESMA condicao, e o que
        # difere entre elas e `up 4 hours, 37 minutes` contra `up 1 minute`.
        up = lambda t: uptime_minutos(coleta("up-" + t.replace(" ", "-")
                                             .replace(",", ""),
                                             "uptime           : up %s\n" % t))
        caso(12, "horas e minutos somam", up("4 hours, 37 minutes"), 277)
        caso(13, "minuto no singular", up("1 minute"), 1)
        caso(14, "zero minuto e zero, nao None", up("0 minutes"), 0)
        caso(15, "dia entra na conta", up("1 day, 2 hours, 3 minutes"), 1563)
        caso(16, "hora sozinha", up("2 hours"), 120)
        # SEM O CAMPO E None, E NAO ZERO. Zero seria "acabou de ligar", que e
        # uma afirmacao; e foi inferir condicao ausente que este modulo veio
        # corrigir.
        caso(17, "ambiente sem uptime -> None",
             uptime_minutos(coleta("sem-uptime", "governor: performance\n")), None)
        caso(18, "unidade desconhecida -> None",
             up("3 fortnights"), None)

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    import sys
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    alvos = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not alvos:
        alvos = sorted(str(p) for p in
                       (RAIZ / "docs/01-fundamentos/medicoes/historico").glob("*/")
                       if not p.name.endswith(("-ambiente", "-sonda")))
    for a in alvos:
        n = processos_graficos(a)
        print("%-52s %s" % (os.path.basename(str(a).rstrip("/")),
                            "nao declarado" if n is None else
                            ("texto" if n == 0 else "grafico (%d processo(s))" % n)))
