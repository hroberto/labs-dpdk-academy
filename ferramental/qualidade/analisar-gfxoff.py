#!/usr/bin/env python3
"""Apura as coletas da intervencao sobre o GFXOFF.

POR QUE O RESUMO IMPRESSO PELO PROPRIO EXPERIMENTO NAO BASTA

O script de coleta imprime medianas e uma contagem de pares favoraveis. Isso
serve para ler o desfecho na hora; nao serve para publicar, por duas razoes que
as duas coletas de 25/09 deixaram visiveis.

A PRIMEIRA: `Max Single` numa janela de 30 s NAO E UMA GRANDEZA ESTAVEL.

A reativacao do power gating e um evento RARO e GRANDE, nao uma carga continua.
Se nenhuma transicao acontecer na janela, o `Max Single` daquela celula mede
outro ruido qualquer -- e foi o que ocorreu em tres das cinco celulas ligadas
da coleta das 00:27, que deram 38, 25 e 117 us. A celula nao falhou; o evento
nao aconteceu nela.

Comparar medianas de `Max Single` entre os dois bracos, portanto, dilui o efeito
com as janelas em que nada havia para suprimir. O desfecho que corresponde ao
mecanismo e DICOTOMICO: a janela teve, ou nao teve, um evento da ordem das
centenas de microssegundos.

A SEGUNDA: uma coleta so nao decide.

As 00:15 o resultado foi 3 de 3 com separacao de trinta vezes; as 00:27 foi 4 de
5, com sobreposicao entre os bracos. Publicar a primeira seria escolher a
coleta que confirma. As duas entram, e o programa e o mesmo.

O QUE ELE CALCULA

  - a tabela pareada, celula a celula, com a coleta de origem;
  - o teste do sinal sobre os pares (usa so a direcao, nao a magnitude);
  - o teste exato de Fisher sobre a dicotomia "a janela teve evento >= LIMIAR",
    que e o desfecho ligado ao mecanismo.

Ambos os testes sao exatos e calculados aqui, sem scipy: o projeto nao adiciona
dependencia para tres coeficientes binomiais.

O QUE ELE NAO FAZ

Nao junta janelas de duracoes diferentes. Se as coletas passadas tiverem
`JANELA` distinta, ele recusa -- somar uma janela de 30 s com uma de 60 s
compara "maior evento em 30 s" com "maior evento em 60 s", e a segunda tem mais
chance de conter o evento so por ser mais longa.

    uso:  analisar-gfxoff.py <dir-coleta> [<dir-coleta> ...] [--limiar 300]
          analisar-gfxoff.py --autoteste
"""
import glob
import os
import re
import sys
from math import comb


def max_single(caminho, cpu="2"):
    """-> us do campo `Max Single` (campo 7), ou None."""
    try:
        for l in open(caminho, encoding="utf-8", errors="replace"):
            c = l.split()
            if c and c[0] == cpu:
                return float(c[6])
    except OSError:
        return None
    return None


def janela_de(diretorio):
    """-> segundos por celula, lido do ambiente.txt da propria coleta."""
    amb = os.path.join(diretorio, "ambiente.txt")
    try:
        texto = open(amb, encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(r"ciclos\s*:\s*\d+\s*pares de\s*(\d+)s", texto)
    return int(m.group(1)) if m else None


def pares(diretorio, cpu="2"):
    """-> [(ciclo, ligado_us, desligado_us)] da coleta."""
    saida = []
    for f in sorted(glob.glob(os.path.join(diretorio, "osnoise-c[0-9]*-ligado.txt"))):
        n = re.search(r"osnoise-c(\d+)-ligado", os.path.basename(f)).group(1)
        d = os.path.join(diretorio, "osnoise-c%s-desligado.txt" % n)
        a, b = max_single(f, cpu), max_single(d, cpu)
        if a is not None and b is not None:
            saida.append((int(n), a, b))
    return saida


def teste_do_sinal(ps):
    """Bilateral exato. Empates sao descartados, como manda o teste."""
    naoempate = [(a, b) for a, b in ps if a != b]
    n = len(naoempate)
    k = sum(1 for a, b in naoempate if b < a)   # desligado menor = a favor
    if n == 0:
        return n, k, 1.0
    cauda = sum(comb(n, i) for i in range(max(k, n - k), n + 1))
    return n, k, min(1.0, 2.0 * cauda / 2 ** n)


def fisher(a, b, c, d):
    """Bilateral exato para a tabela [[a,b],[c,d]], por soma das tabelas
    tao ou menos provaveis que a observada."""
    n = a + b + c + d
    lin1, col1 = a + b, a + c
    def p(x):
        return (comb(lin1, x) * comb(n - lin1, col1 - x)) / comb(n, col1)
    obs = p(a)
    lo = max(0, col1 - (n - lin1))
    hi = min(lin1, col1)
    return min(1.0, sum(p(x) for x in range(lo, hi + 1) if p(x) <= obs * (1 + 1e-9)))


def autoteste():
    falhas = 0

    def caso(n, descricao, obtido, esperado, tol=1e-6):
        nonlocal falhas
        ok = abs(obtido - esperado) < tol if isinstance(esperado, float) else obtido == esperado
        if not ok:
            print("  AUTOTESTE %s FALHOU: %s (esperado %r, obtido %r)"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    # 1. Sinal com 8 pares, 7 a favor: 2 * (C(8,7)+C(8,8)) / 256 = 18/256.
    _, k, p = teste_do_sinal([(10, 1)] * 7 + [(1, 10)])
    caso(1, "sinal 7 de 8 -> k", k, 7)
    caso(2, "sinal 7 de 8 -> p", p, 18 / 256)
    # 3. Simetria perfeita tem de dar p = 1.
    _, _, p = teste_do_sinal([(10, 1)] * 4 + [(1, 10)] * 4)
    caso(3, "sinal 4 de 8 -> p = 1", p, 1.0)
    # 4. EMPATE E DESCARTADO, nao contado a favor. Sem isto o teste inflaria.
    n, k, _ = teste_do_sinal([(10, 1), (5, 5), (5, 5)])
    caso(4, "empates descartados -> n", n, 1)
    # 5. Fisher numa tabela conhecida: [[5,3],[0,8]].
    #
    #    P(X=5) = C(8,5)C(8,0)/C(16,5) = 56/4368. A PRIMEIRA VERSAO DESTA
    #    ASSERCAO ESPERAVA esse valor como bilateral, e estava errada: com as
    #    duas linhas de tamanho 8, a tabela oposta [[0,8],[8,0]] tem
    #    P(X=0) = C(8,0)C(8,5)/C(16,5) = 56/4368 -- exatamente a mesma
    #    probabilidade. Um bilateral por soma das tabelas tao improvaveis
    #    quanto a observada tem de incluir as duas caudas.
    #
    #    Ficou registrado porque foi o codigo que corrigiu o teste, e nao o
    #    contrario. A simetria e consequencia das margens, nao dos dados.
    caso(5, "fisher [[5,3],[0,8]] soma as duas caudas", fisher(5, 3, 0, 8), 2 * 56 / 4368)
    # 6. Tabela sem associacao nenhuma -> p = 1.
    caso(6, "fisher [[4,4],[4,4]]", fisher(4, 4, 4, 4), 1.0)

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


def main(dirs, limiar):
    todos, janelas = [], set()
    for d in dirs:
        j = janela_de(d)
        if j is None:
            print("  AVISO: %s sem `ciclos: N pares de Ns` no ambiente.txt" % d)
        janelas.add(j)
        for ciclo, lig, des in pares(d):
            todos.append((os.path.basename(d), ciclo, lig, des))

    if len(janelas) > 1:
        print("  RECUSADO: as coletas usam janelas diferentes -> %s" % sorted(janelas))
        print("  'Maior evento em 30 s' e 'maior evento em 60 s' nao sao a mesma")
        print("  grandeza: a janela mais longa tem mais chance de conter o evento.")
        return 1
    if not todos:
        print("  nenhuma janela pareada encontrada")
        return 1

    janela = janelas.pop()
    print("  Intervencao sobre o GFXOFF -- %d par(es), janela de %ss por celula"
          % (len(todos), janela))
    print()
    print("  %-34s %5s %12s %12s" % ("coleta", "ciclo", "ligado us", "deslig. us"))
    print("  %-34s %5s %12s %12s" % ("-" * 34, "-----", "-----------", "-----------"))
    for nome, ciclo, lig, des in todos:
        marca = " <-" if des < lig else "   "
        print("  %-34s %5d %12.0f %12.0f%s" % (nome, ciclo, lig, des, marca))

    ps = [(l, d) for _, _, l, d in todos]
    n, k, p_sinal = teste_do_sinal(ps)
    print()
    print("  TESTE DO SINAL (usa so a direcao de cada par)")
    print("    %d de %d pares com o desligado menor; p = %.4f (bilateral, exato)"
          % (k, n, p_sinal))

    a = sum(1 for l, _ in ps if l >= limiar)          # ligado, com evento
    b = len(ps) - a
    c = sum(1 for _, d in ps if d >= limiar)          # desligado, com evento
    d_ = len(ps) - c
    p_f = fisher(a, b, c, d_)
    print()
    print("  DESFECHO DICOTOMICO: a janela teve evento >= %d us?" % limiar)
    print("    ligado     %d de %d" % (a, a + b))
    print("    DESLIGADO  %d de %d" % (c, c + d_))
    print("    Fisher exato bilateral: p = %.4f" % p_f)
    print()
    print("    Este e o desfecho ligado ao mecanismo. A reativacao do power")
    print("    gating e evento raro e grande: janela sem transicao nao tem o que")
    print("    suprimir, e o `Max Single` dela mede outro ruido qualquer.")
    print()
    print("  MAIORES OBSERVADOS")
    print("    ligado     %.0f us" % max(l for l, _ in ps))
    print("    DESLIGADO  %.0f us" % max(d for _, d in ps))
    return 0


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    limiar = 300
    if "--limiar" in sys.argv:
        limiar = int(sys.argv[sys.argv.index("--limiar") + 1])
        args = [a for a in args if a != str(limiar)]
    if not args:
        print(__doc__.strip().splitlines()[-2].strip(), file=sys.stderr)
        sys.exit(2)
    sys.exit(main(args, limiar))
