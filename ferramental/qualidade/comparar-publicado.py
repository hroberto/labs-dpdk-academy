#!/usr/bin/env python3
"""Acha bloco publicado que envelheceu: bate com coleta ANTIGA, nao com a atual.

POR QUE ESTE ARQUIVO EXISTE, E O QUE ELE ACRESCENTA AO `verificar-blocos`

O `verificar-blocos.py` pergunta se cada linha publicada existe literalmente em
ALGUMA coleta arquivada. E a pergunta certa contra invencao: um numero que
nenhum programa imprimiu nao passa.

Mas ela nao pega envelhecimento. Depois de uma coleta nova, uma linha continua
existindo na coleta VELHA -- e o portao segue verde enquanto o documento publica
o que a maquina nao produz mais. Foi assim que, em 25/09/2026, a tabela do
`custo-alocacao` e a linha de razoes logo abaixo dela ficaram vindo de execucoes
DIFERENTES sem que nada acusasse: as duas existiam em arquivo.

Este verificador faz a pergunta complementar: para cada linha publicada, existe
na coleta ATUAL uma linha da mesma FORMA com numeros diferentes? Se existe, o
documento publica uma medicao que a coleta atual contradiz.

O QUE ELE NAO DECIDE

Se a coleta atual e a que deve valer. Uma coleta pode ser a de um braco de
controle -- canal unico, JEDEC 4800 -- e o documento publicar de proposito a da
configuracao de referencia. Por isso a coleta atual e ARGUMENTO, nao adivinhada:
quem roda diz qual e, e o relatorio e lista de trabalho, nao veredito.

Tambem nao acusa a linha que SUMIU de formato. Se o programa mudou o `printf`,
nenhuma forma casa e a linha sai do escopo -- mesma limitacao declarada pelo
`verificar-blocos`, e pela mesma razao.

    uso:  comparar-publicado.py <carimbo-da-coleta-atual> [...]
          comparar-publicado.py 2026-09-25-0046
          comparar-publicado.py --autoteste
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
CERCA = "```"
MIN_CHARS = 24


def forma(l):
    return re.sub(r"\d", "#", l.rstrip())


def blocos(path):
    L = path.read_text(errors="replace").split("\n")
    out, ab, info = [], None, None
    for i, l in enumerate(L):
        if l.lstrip().startswith(CERCA):
            if ab is None:
                ab, info = i, l.strip()[3:]
            else:
                if not info:
                    out.append((ab + 2, L[ab + 1:i]))
                ab = None
    return out


def candidatos(publicada, coletadas):
    """As linhas coletadas que pareiam com a publicada, pelo prefixo de campos.

    Devolve [] quando nenhuma compartilha ao menos um campo inicial: nesse caso
    a forma casou por acaso e nao ha comparacao a fazer."""
    pub = publicada.split()
    melhor, escore = [], 0
    for c in coletadas:
        col = c.split()
        n = 0
        for a, b in zip(pub, col):
            if a != b:
                break
            n += 1
        if n > escore:
            melhor, escore = [c], n
        elif n == escore and n > 0:
            melhor.append(c)
    return sorted(melhor) if escore else []


def classificar(publicada, coletada):
    """-> ('mediana'|'dispersao', indice do primeiro campo numerico divergente).

    A DISTINCAO E O QUE TORNA A LISTA UTILIZAVEL. Quase toda linha deste projeto
    publica mediana seguida de IQR, faixa e dispersao, e as tres ultimas mudam
    entre execucoes POR DEFINICAO -- sao a medida da variacao, nao o resultado.
    Uma lista que trata "IQR 0.7% virou 0.9%" como numero obsoleto tem centenas
    de itens e nenhuma prioridade.

    O criterio: se o PRIMEIRO campo numerico divergente e tambem o primeiro campo
    numerico da linha, mudou a mediana. Senao, mudou so a dispersao em volta
    dela."""
    pub, col = publicada.split(), coletada.split()
    numericos = [i for i, t in enumerate(pub) if re.fullmatch(r"-?[\d.]+[a-z%]*", t)]
    for i, (a, b) in enumerate(zip(pub, col)):
        if a != b:
            return ("mediana" if numericos and i == numericos[0] else "dispersao"), i
    return "dispersao", -1


def variacao(publicada, coletadas):
    """Menor variacao relativa do primeiro campo numerico, entre os candidatos.

    E o que ordena a lista. Uma mediana que foi de 10,24 para 10,25 e ruido de
    execucao; uma que foi de 3,42 para 3,99 e outra medicao. Sem a magnitude as
    duas aparecem com o mesmo peso, e quem le desiste na terceira tela."""
    def primeiro(l):
        for t in l.split():
            m = re.fullmatch(r"-?(\d+(?:\.\d+)?)[a-z%]*", t)
            if m:
                return float(m.group(1))
        return None
    a = primeiro(publicada)
    if a in (None, 0.0):
        return 0.0
    v = [abs(primeiro(c) / a - 1) for c in coletadas if primeiro(c) is not None]
    # O MINIMO, E NAO O MAXIMO. A pergunta e se ALGUMA linha da coleta atual
    # sustenta o valor publicado -- basta uma. Com o maximo, `rte_eal_cleanup()`
    # do `custo-init.in-memory` (0,083, presente na coleta) aparecia com +508%
    # porque a mesma forma existe no `custo-init.no-huge`, que mede outra
    # invocacao e da 0,505. Duas invocacoes diferentes do mesmo programa nao se
    # contradizem; comparar uma com a outra e que era o erro.
    return min(v) if v else 0.0


def linhas_de(dirs):
    """-> (literais, {forma: {literais com essa forma}})"""
    literais, por_forma = set(), {}
    for d in dirs:
        for f in sorted(d.glob("*.txt")):
            for l in f.read_text(errors="replace").split("\n"):
                l = l.rstrip()
                literais.add(l)
                por_forma.setdefault(forma(l), set()).add(l)
    return literais, por_forma


def dirs_de_coleta(carimbos):
    todas = sorted(set(RAIZ.glob("docs/*/medicoes/historico/*/")) |
                   set(RAIZ.glob("trilha/**/historico/*/")))
    atuais = [d for d in todas if any(c in d.name for c in carimbos)]
    return todas, atuais


def main(carimbos):
    todas, atuais = dirs_de_coleta(carimbos)
    if not atuais:
        print("  nenhuma coleta casa %s" % carimbos, file=sys.stderr)
        print("  disponiveis: %s" % sorted({d.name for d in todas}), file=sys.stderr)
        return 2

    _, forma_atual = linhas_de(atuais)
    lit_atual = set().union(*forma_atual.values()) if forma_atual else set()

    docs = sorted(RAIZ.glob("docs/**/*.md")) + sorted(RAIZ.glob("trilha/**/*.md"))
    achados = []
    for p in docs:
        if "/historico/" in str(p):
            continue                      # nota de coleta nao e documento publicado
        for ini, corpo in blocos(p):
            uteis = [l for l in corpo
                     if len(l.rstrip()) >= MIN_CHARS and re.search(r"\d", l)]
            if len(uteis) < 2:
                continue
            for l in uteis:
                l = l.rstrip()
                f = forma(l)
                if f not in forma_atual:
                    continue              # fora do escopo: a coleta atual nao tem essa forma
                if l in lit_atual:
                    continue              # bate com a coleta atual
                # PAREAR A LINHA CERTA, e nao qualquer linha da mesma forma.
                #
                # Numa tabela de varredura todas as linhas tem a MESMA forma --
                # `#  #  #  #` --, entao a forma sozinha casa a linha de 8738
                # entradas com a de 4096. O par certo e o que compartilha o
                # PREFIXO de campos, que e a chave da linha; sem isto o relatorio
                # acusa diferenca onde ha so outra linha da tabela.
                cands = candidatos(l, forma_atual[f])
                if not cands:
                    continue
                classe = min(classificar(l, c)[0] for c in cands)  # 'dispersao' < 'mediana'
                achados.append((p.relative_to(RAIZ), ini, l, cands, classe,
                                variacao(l, cands)))

    print("  coleta(s) atual(is): %s" % ", ".join(sorted(d.name for d in atuais)))
    print("  %d documento(s) varrido(s)" % len(docs))
    print()
    if not achados:
        print("  nenhuma linha publicada contradiz a coleta atual.")
        return 0

    so_med = "--so-mediana" in sys.argv
    mostrados = [a for a in achados if not so_med or a[4] == "mediana"]
    # Ordem por MAGNITUDE, nao por documento: a lista existe para dizer o que
    # olhar primeiro.
    mostrados.sort(key=lambda a: -a[5])
    atual_doc = None
    for p, ini, publicado, pares, classe, var in mostrados:
        if p != atual_doc:
            print("  %s" % p)
            atual_doc = p
        print("    :%-5d [%s %+5.1f%%] publicado  %s"
              % (ini, classe[:4], var * 100, publicado[:72]))
        def dist(c):
            return variacao(publicado, {c})
        for c in sorted(pares, key=dist)[:2]:
            print("                  coletado   %s" % c[:82])
        if len(pares) > 2:
            print("                  (e mais %d variante(s) na coleta atual)" % (len(pares) - 2))
    n_med = sum(1 for a in achados if a[4] == "mediana")
    print()
    print("  %d linha(s) publicada(s) que a coleta atual contradiz:" % len(achados))
    print("    %3d com MEDIANA diferente  <- e aqui que se olha primeiro" % n_med)
    print("    %3d so com dispersao/faixa diferente (variacao entre execucoes)"
          % (len(achados) - n_med))
    print("  Lista de TRABALHO, nao veredito: a coleta atual pode ser um braco de")
    print("  controle, e o documento publicar a de referencia de proposito.")
    return 0


def autoteste():
    falhas = 0

    def caso(n, desc, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s (esperado %r, obtido %r)"
                  % (n, desc, esperado, obtido))
            falhas += 1

    # 1. A forma ignora digitos e SO digitos: 1.28 e 2.11 tem a mesma forma,
    #    e e isso que permite parear publicado com coletado.
    caso(1, "mesma forma para valores diferentes",
         forma("  with cache   1.28  x") == forma("  with cache   2.11  x"), True)
    # 2. Texto diferente NAO pareia -- sem isto o verificador casaria a linha
    #    do mempool com a do malloc e reportaria diferenca onde nao ha.
    caso(2, "texto diferente tem forma diferente",
         forma("  with cache 1.28") == forma("  no cache   1.28"), False)
    # 3. O PAREAMENTO POR PREFIXO. Sem ele a linha de 8738 entradas casaria
    #    com a de 4096 -- mesma forma, linha diferente da mesma tabela.
    caso("2b", "pareia a linha de mesma chave",
         candidatos("  8738  1.17  x", {"  8738  1.99  x", "  4096  1.17  x"}),
         ["  8738  1.99  x"])
    # 2c. Sem campo inicial em comum, nao ha o que comparar.
    caso("2c", "forma casada por acaso nao vira achado",
         candidatos("  aaa  1.0  x", {"  bbb  2.0  x"}), [])

    # 3. A CLASSIFICACAO. Mediana igual e IQR diferente e variacao entre
    #    execucoes, nao numero obsoleto -- sem esta distincao a lista tem
    #    centenas de itens e nenhuma prioridade.
    caso(3, "so o IQR mudou -> dispersao",
         classificar("  x  1.28  1.27-1.28  0.1%", "  x  1.28  1.27-1.29  0.3%")[0],
         "dispersao")
    caso("3b", "a mediana mudou -> mediana",
         classificar("  x  1.28  1.27-1.28  0.1%", "  x  1.03  1.27-1.28  0.1%")[0],
         "mediana")

    # 3c. A MAGNITUDE. Sem ela 10,24 -> 10,25 aparece com o mesmo peso que
    #     3,42 -> 3,99, e a lista deixa de ordenar o trabalho.
    caso("3c", "variacao do primeiro campo numerico",
         round(variacao("  x  3.42  y", {"  x  3.99  y"}), 4), round(0.57 / 3.42, 4))
    # 3e. O MINIMO ENTRE CANDIDATOS. Uma linha que a coleta atual reproduz
    #     exatamente nao e obsoleta so porque outra invocacao do mesmo programa
    #     deu outro valor.
    caso("3e", "basta um candidato que sustente",
         variacao("  x  0.083  y", {"  x  0.083  z", "  x  0.505  z"}), 0.0)
    caso("3d", "sem campo numerico, variacao zero",
         variacao("  so texto aqui", {"  so texto ali"}), 0.0)

    # 4. A cerca COM informacao (```bash) nao e bloco de medicao.
    import tempfile, os
    d = tempfile.mkdtemp()
    f = Path(d) / "t.md"
    f.write_text("```bash\n  algo   1.23  aqui dentro tem largura\n```\n")
    caso(3, "cerca com linguagem nao entra", blocos(f), [])
    f.write_text("```\n  algo   1.23  aqui dentro tem largura suficiente\n"
                 "  outro  4.56  aqui dentro tem largura suficiente\n```\n")
    caso(4, "cerca nua entra com as duas linhas", len(blocos(f)[0][1]), 2)
    import shutil
    shutil.rmtree(d, ignore_errors=True)

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("uso: comparar-publicado.py <carimbo-da-coleta-atual> [...]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(args))
