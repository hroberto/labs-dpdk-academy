#!/usr/bin/env python3
"""Verifica links relativos e âncoras de título nos documentos Markdown.

POR QUE A REGRA DE SLUG IMPORTA

O GitHub gera o identificador de uma seção com o github-slugger, cujo núcleo é:

    value.toLowerCase().replace(regex, '').replace(/ /g, '-')

O detalhe que engana: o último passo troca **cada espaço por um hífen**, sem
colapsar sequências. Um título como

    ### Nível 4 — Mempool, mbuf, ring e ciclo de dados

perde o travessão na remoção de pontuação e fica com **dois espaços seguidos**,
que viram **dois hífens**:

    nível-4--mempool-mbuf-ring-e-ciclo-de-dados
            ^^

Um validador que colapse espaços (`\\s+` -> `-`) produz um hífen só, considera o
link válido e deixa passar uma âncora morta. Este script reproduz a regra real.
"""
import os
import re
import sys

IGNORAR = {".git", "build", "subprojects"}
# Pontuação removida pelo github-slugger (aproximação suficiente: tudo que não é
# letra, dígito, sublinhado, espaço ou hífen). Acentos são PRESERVADOS.
PONTUACAO = re.compile(r"[^\w\s-]", re.UNICODE)


def slug(titulo):
    """Reproduz github-slugger: minúsculas, remove pontuação, cada espaço -> '-'."""
    return PONTUACAO.sub("", titulo.strip().lower()).replace(" ", "-")


def coletar_ancoras(caminho):
    vistos = {}
    ancoras = []
    for titulo in re.findall(r"^#{1,6}\s+(.+?)\s*$", open(caminho, encoding="utf-8").read(), re.M):
        # títulos podem conter links; o slug usa o texto visível
        texto = re.sub(r"\[([^\]]*)\]\[[^\]]*\]", r"\1", titulo)
        texto = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", texto)
        base = slug(texto)
        # github-slugger desambigua repetições com sufixo -1, -2...
        n = vistos.get(base, 0)
        vistos[base] = n + 1
        ancoras.append(base if n == 0 else f"{base}-{n}")
    return ancoras


def verificar(raiz="."):
    ancoras = {}
    for base, dirs, arquivos in os.walk(raiz):
        dirs[:] = [d for d in dirs if d not in IGNORAR]
        for nome in arquivos:
            if nome.endswith(".md"):
                p = os.path.normpath(os.path.join(base, nome))
                ancoras[p] = coletar_ancoras(p)

    problemas = total = orfas = 0
    for base, dirs, arquivos in os.walk(raiz):
        dirs[:] = [d for d in dirs if d not in IGNORAR]
        for nome in sorted(arquivos):
            if not nome.endswith(".md"):
                continue
            doc = os.path.join(base, nome)
            bruto = open(doc, encoding="utf-8").read()

            # Referência órfã: `[texto][rotulo]` sem a definição `[rotulo]: url`
            # no rodapé. O GitHub não avisa — renderiza os colchetes literais no
            # meio do parágrafo, e quem escreveu só descobre relendo a página.
            # Não conta como "link quebrado" porque não chega a ser um link.
            definidas = {m.group(1).lower() for m in re.finditer(r"^\[([^\]^]+)\]:\s*\S+", bruto, re.M)}
            for rotulo in sorted({m.group(1).lower() for m in re.finditer(r"\]\[([^\]]+)\]", bruto)}):
                if rotulo not in definidas:
                    print(f"  {doc}: referência sem definição -> [{rotulo}]")
                    orfas += 1

            texto = re.sub(r"^\[[^\]]+\]:.*$", "", bruto, flags=re.M)
            for alvo in re.findall(r"\]\((?!https?:|mailto:)([^)]+)\)", texto):
                total += 1
                arquivo, _, frag = alvo.partition("#")
                destino = os.path.normpath(os.path.join(base, arquivo)) if arquivo else os.path.normpath(doc)
                if not os.path.exists(destino):
                    print(f"  {doc}: arquivo inexistente -> {alvo}")
                    problemas += 1
                elif frag and not frag.startswith("L") and destino in ancoras:
                    if frag not in ancoras[destino]:
                        parecidos = [a for a in ancoras[destino] if a.replace("--", "-") == frag.replace("--", "-")]
                        dica = f" (você quis dizer '{parecidos[0]}'?)" if parecidos else ""
                        print(f"  {doc}: âncora inexistente -> #{frag}{dica}")
                        problemas += 1
    print(f"\n  {total} links relativos verificados, {problemas} quebrados"
          f"; {orfas} referência(s) sem definição")
    return problemas + orfas


if __name__ == "__main__":
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else ".") else 0)
