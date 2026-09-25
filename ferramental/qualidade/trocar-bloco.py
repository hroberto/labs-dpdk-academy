#!/usr/bin/env python3
"""Troca linhas de bloco publicado pelas da coleta, casando pela chave.

POR QUE SO DENTRO DE CERCA, E POR QUE ISSO FOI APRENDIDO DOENDO

A versao anterior casava `lstrip().startswith(chave)` em QUALQUER linha do
documento. Em 25/09/2026 isso destruiu duas coisas no README em ingles:

  1. a tabela de COBERTURA da TLB (`4 KB pages   96   4 096   16 MB`), que tem
     a mesma chave da tabela de LATENCIA e mede outra coisa;
  2. uma linha de PROSA -- "...it fails because, with\\n4 KB pages, **each entry
     covers far too little**." -- cuja continuacao comeca com a chave.

As duas viraram linha de medicao. A segunda e a pior: prosa substituida por
numero nao parece defeito nenhum ao passar o olho.

A correcao e restringir o alvo ao interior de uma cerca ``` -- que e onde saida
de programa vive -- e exigir que a linha ja contenha numero. Prosa dentro de
cerca e rara; prosa com numero na posicao certa, mais rara ainda.

    uso:  trocar_bloco.py <doc.md> <coleta.txt> <chave> [<chave> ...]
"""
import io
import re
import sys

doc, origem = sys.argv[1], sys.argv[2]
chaves = sys.argv[3:]
col = [l.rstrip() for l in io.open(origem, encoding="utf-8", errors="replace")]
linhas = io.open(doc, encoding="utf-8").read().split("\n")

# Marca quais linhas estao dentro de cerca nua (``` sem linguagem).
dentro, cercas = False, [False] * len(linhas)
for i, l in enumerate(linhas):
    if l.lstrip().startswith("```"):
        dentro = not dentro
        continue
    cercas[i] = dentro

trocas, recusas = 0, 0
for chave in chaves:
    alvo = [l for l in col if l.lstrip().startswith(chave)]
    if len(alvo) != 1:
        print("  RECUSADO: '%s' aparece %d vez(es) em %s" % (chave, len(alvo), origem))
        sys.exit(1)
    # A linha da coleta tem de ter numero -- se nao tem, a chave esta pegando
    # cabecalho ou texto, e trocar por ela nao faz sentido.
    if not re.search(r"\d", alvo[0]):
        print("  RECUSADO: a linha de '%s' na coleta nao tem numero" % chave)
        sys.exit(1)
    # A FORMA DECIDE, e nao o prefixo.
    #
    # Dentro de cerca a chave `4 KB pages` casa DUAS tabelas: a de cobertura da
    # TLB (`4 KB pages   96   4 096   16 MB`) e a de latencia
    # (`4 KB pages   90.75   90.18-90.86  ...`). As duas medem coisas
    # diferentes, e so a segunda vem deste arquivo de coleta.
    #
    # Trocar todo digito por `#` da a assinatura do `printf` que produziu a
    # linha -- o mesmo criterio do `verificar-blocos.py`. Duas execucoes do
    # mesmo programa tem formas identicas; duas tabelas diferentes, nao.
    #
    # Se um valor cruzar fronteira de digito (9,99 para 10,01) a forma muda e a
    # troca e RECUSADA. Falhar avisando e melhor que acertar em silencio.
    forma_alvo = re.sub(r"\d", "#", alvo[0])
    pub = [i for i, l in enumerate(linhas)
           if cercas[i] and l.lstrip().startswith(chave)
           and re.sub(r"\d", "#", l.rstrip()) == forma_alvo]
    fora = [i for i, l in enumerate(linhas)
            if not cercas[i] and l.lstrip().startswith(chave)]
    if fora:
        recusas += len(fora)
        print("  IGNORADAS fora de cerca: %s (linhas %s)"
              % (chave, ", ".join(str(i + 1) for i in fora[:4])))
    if not pub:
        print("  RECUSADO: '%s' nao encontrada dentro de cerca em %s" % (chave, doc))
        sys.exit(1)
    for i in pub:
        if linhas[i].rstrip() != alvo[0]:
            linhas[i] = alvo[0]
            trocas += 1

io.open(doc, "w", encoding="utf-8").write("\n".join(linhas))
print("  %s: %d trocada(s)%s" % (doc, trocas,
      ", %d ignorada(s) fora de cerca" % recusas if recusas else ""))
