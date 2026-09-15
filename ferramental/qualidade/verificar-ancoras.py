#!/usr/bin/env python3
"""Confere se âncoras de linha nos documentos ainda apontam para o alvo certo.

POR QUE ESTE SCRIPT EXISTE

Links do tipo `arquivo.c#L227` levam o leitor direto ao código que produziu um
número — leitura muito mais fluida que "procure a função no arquivo". O preço é
que números de linha mudam quando o código muda, e um link desatualizado não
quebra: ele aponta em silêncio para o trecho errado, que é pior que apontar para
lugar nenhum.

Este verificador elimina esse risco. A convenção que ele exige é simples: o
**texto do link** deve ser o nome do símbolo, e a linha apontada deve conter
esse nome. Assim:

    [`m_spinlock`](medicoes/custo-espera.c#L227)

Se `m_spinlock` deixar de estar na linha 227, o script acusa e diz onde ela foi
parar — basta corrigir o número.
"""
import os
import re
import sys

IGNORAR = {".git", "build", "subprojects"}
# [`simbolo`](caminho#L123)  ou  [texto](caminho#L123-L130)
PADRAO = re.compile(r"\[`?([^\]`]+)`?\]\(([^)#]+)#L(\d+)(?:-L\d+)?\)")


def verificar(raiz="."):
    problemas = 0
    total = 0
    for base, dirs, arquivos in os.walk(raiz):
        dirs[:] = [d for d in dirs if d not in IGNORAR]
        for nome in sorted(arquivos):
            if not nome.endswith(".md"):
                continue
            doc = os.path.join(base, nome)
            texto = open(doc, encoding="utf-8").read()
            for simbolo, caminho, linha in PADRAO.findall(texto):
                alvo = os.path.normpath(os.path.join(base, caminho))
                total += 1
                if not os.path.exists(alvo):
                    print(f"  {doc}: alvo inexistente -> {caminho}")
                    problemas += 1
                    continue
                linhas = open(alvo, encoding="utf-8").read().split("\n")
                n = int(linha)
                if n < 1 or n > len(linhas):
                    print(f"  {doc}: linha {n} fora de {caminho} ({len(linhas)} linhas)")
                    problemas += 1
                    continue
                if simbolo not in linhas[n - 1]:
                    # onde o símbolo está de fato, para facilitar a correção
                    onde = [i + 1 for i, l in enumerate(linhas) if simbolo in l]
                    sugestao = f" (está na linha {onde[0]})" if onde else " (não encontrado no arquivo)"
                    print(f"  {doc}: '{simbolo}' NAO esta em {caminho}:{n}{sugestao}")
                    print(f"      linha {n} contem: {linhas[n - 1].strip()[:60]}")
                    problemas += 1
    print(f"\n  {total} âncoras de linha verificadas, {problemas} desatualizadas")
    return problemas


if __name__ == "__main__":
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else ".") else 0)
