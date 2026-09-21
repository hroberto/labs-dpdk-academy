#!/usr/bin/env python3
"""Confere se cada bloco publicado ainda corresponde ao que os programas imprimem.

POR QUE ESTE ARQUIVO EXISTE

Em 20/09/2026, ao migrar a saída dos programas para inglês, três rodadas
sucessivas de regeneração deixaram blocos para trás. A causa foi sempre a
mesma: a lista de blocos a regenerar era montada **de memória**, procurando
marcadores que quem escrevia lembrava de ter visto. Primeiro faltou `medicao`;
depois faltaram os blocos que não têm linha de cabeçalho nenhuma.

O portão existente não podia pegar isso. O `verificar-autodescricao.py` compara
os números entre a versão pt e a en; um bloco desatualizado nos DOIS idiomas,
com os mesmos números antigos, bate consigo mesmo e passa. Não havia nenhuma
verificação de que um bloco publicado fosse igual ao que o programa imprime.

O QUE ESTE VERIFICADOR FAZ

Para cada bloco de cerca nua, classifica cada linha em DUAS etapas:

1. **Forma.** A linha com todo dígito trocado por `#`. Se essa forma aparece em
   alguma coleta arquivada, a linha veio de um `printf` de programa de medição
   — é o que separa uma tabela de resultado de um diagnóstico de NIC ou de uma
   tabela de prosa. Linha cuja forma não existe no arquivo sai do escopo.

2. **Literal.** Entre as que estão no escopo, a que NÃO aparece literalmente no
   arquivo é um bloco publicado que o programa não produz mais.

A primeira etapa é o que torna o relatório utilizável: sem ela, 101 dos 140
blocos do repositório apareciam como suspeitos. Com ela, 9.

O QUE ELE NÃO FAZ, E POR QUE ISSO IMPORTA

Ele não distingue bloco de saída literal de tabela montada à mão. Uma tabela
que combina linhas de duas execuções — como a de `custo-init`, que junta duas
configurações — aparece aqui, e isso é correto: ela TAMBÉM precisa ser
conferida, só que a conferência é linha a linha, não bloco a bloco.

Ele também não pega bloco cujo formato MUDOU inteiro: se nenhuma linha casa
forma, o bloco sai do escopo e some do relatorio. Esse caso precisa do olho
humano, e esta limitação é declarada em vez de escondida.

Ele também não roda os programas. Compara contra o que foi ARQUIVADO, que é o
que dá procedência ao bloco. Se o arquivo estiver velho, o verificador
silencia junto -- por isso o relatório imprime a data da coleta que usou.

USO
    ./ferramental/qualidade/verificar-blocos.py            # relatório
    ./ferramental/qualidade/verificar-blocos.py --lista    # só os caminhos
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]
CERCA = "`" * 3

# Linhas curtas ou sem dígito não distinguem nada: um "```" seguido de prosa
# curta produziria ruído. O corte é pelo que carrega informação de medição.
MIN_CHARS = 12


def forma(l):
    """A linha com todo número trocado por '#': a ASSINATURA do formato.

    É isto que identifica o programa de origem. Duas execuções do mesmo
    `printf` têm formas idênticas e literais diferentes; um bloco de
    diagnóstico de NIC não tem a forma de nenhum `printf` arquivado."""
    return re.sub(r"\d", "#", l.rstrip())


def coletas():
    """Linhas arquivadas: o conjunto literal e o conjunto de formas."""
    literais, formas = set(), set()
    # A trilha tambem arquiva: ela publica bloco de saida como qualquer
    # modulo, e enquanto esteve fora deste glob seus blocos apareciam
    # como "sem procedencia" sem que houvesse onde procurar.
    dirs = sorted(set(RAIZ.glob("docs/*/medicoes/historico/*/")) |
                  set(RAIZ.glob("trilha/**/historico/*/")))
    for d in dirs:
        for f in d.glob("*.txt"):
            for l in f.read_text(errors="replace").split("\n"):
                literais.add(l.rstrip())
                formas.add(forma(l))
    return literais, formas, sorted({d.name for d in dirs})


def blocos(path):
    """(inicio_1based, corpo) de cada bloco de cerca NUA."""
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


def main():
    literais, formas, dirs = coletas()
    if not literais:
        print("Nenhuma coleta em medicoes/historico/: nada a comparar.", file=sys.stderr)
        return 0
    docs = sorted(RAIZ.glob("docs/**/*.md")) + sorted(RAIZ.glob("trilha/**/*.md"))
    suspeitos, total = [], 0
    for p in docs:
        for ini, corpo in blocos(p):
            # Só interessa bloco que PARECE saída de medição: tem dígito e
            # largura. Diagrama, comando e trecho de configuração caem fora.
            uteis = [l for l in corpo
                     if len(l.rstrip()) >= MIN_CHARS and re.search(r"\d", l)]
            if len(uteis) < 2:
                continue
            total += 1
            # Em escopo: a linha tem a FORMA de algo que um programa imprime.
            # Fora de escopo: diagnostico de NIC, saida de script, tabela de
            # prosa -- nada disso casa forma com o que foi arquivado.
            no_escopo = [l for l in uteis if forma(l) in formas]
            if not no_escopo:
                continue
            orfas = [l for l in no_escopo if l.rstrip() not in literais]
            if orfas:
                suspeitos.append((p.relative_to(RAIZ), ini, len(no_escopo), orfas))
    if "--lista" in sys.argv:
        for p, ini, _, _ in suspeitos:
            print(f"{p}:{ini}")
        return 1 if suspeitos else 0
    for p, ini, n, orfas in suspeitos:
        print(f"  {p}:{ini}  {len(orfas)} de {n} linha(s) sem procedencia")
        for l in orfas[:3]:
            print(f"      {l.rstrip()[:96]}")
    print(f"\n  {total} bloco(s) numerico(s) conferidos contra {len(dirs)} coleta(s) "
          f"({', '.join(dirs)}); {len(suspeitos)} sem procedencia completa")
    return 1 if suspeitos else 0


if __name__ == "__main__":
    sys.exit(main())
