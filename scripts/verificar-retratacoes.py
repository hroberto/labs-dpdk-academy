#!/usr/bin/env python3
"""Confere que um número retratado não sobreviveu fora do bloco que o retrata.

POR QUE ISTO EXISTE

Este projeto retrata em público: quando um número publicado não se sustenta, o
documento ganha um bloco que diz qual era o valor, por que caiu e qual é o
certo. A régua editorial premia essa prática -- mas só quando a retratação
corrige o **texto inteiro**, e não quando ela para no primeiro arquivo.

E ela para. A auditoria adversarial do projeto isolou isso como causa-raiz,
presente em oito dimensões:

    "A retratação corrige o DOCUMENTO e não alcança o ARTEFATO que produz o
     número -- o programa, a tabela, o script irmão, o índice pai."

O caso que motivou este verificador é o mais direto possível: em 15/09/2026 a
coluna `rte_ring` de uma tabela foi retratada (2,078 ns não reproduzia; dez
execuções devolveram 1,622). A retratação foi escrita, o documento de origem foi
corrigido -- e os 2,078 continuaram publicados como resultado válido em duas
linhas da página de síntese. No mesmo dia, uma retratação de "22 ns e 117 ns"
afirmou que o 22 "não saía de lugar nenhum" enquanto o MESMO documento publicava
o 22 em outros dois pontos.

Nos dois casos quem escreveu a retratação sabia da regra, tinha acabado de
enunciá-la, e ainda assim deixou o valor derrubado circulando. É por isso que
esta regra é um teste e não uma recomendação: correção manual não escala para
"nenhum número retratado sobrevive".

COMO FUNCIONA

O bloco de retratação declara, numa marca invisível na renderização, QUAIS
valores ele está derrubando:

    > **Este bloco publicava 2,078 ns.** O valor medido é 1,622 ns.
    > <!-- retratado: 2,078 0,368 -->

A declaração é obrigatória e não podia ser evitada. A primeira versão deste
verificador tentava adivinhar, extraindo todos os números do bloco -- e acusou
o valor CORRIGIDO de estar retratado, porque ele também aparece ali. Não há
sinal textual confiável que separe "o número que caiu" de "o número que o
substitui"; quem escreve a retratação sabe, o analisador não.

1. Acha blocos de citação (`>`) que se anunciam como retratação.
2. Lê a marca `<!-- retratado: ... -->` de cada um.
3. Procura cada valor declarado no resto da árvore, FORA de blocos de retratação.
4. Cada sobrevivente é uma falha.
5. Reporta quantos blocos de retratação ainda NÃO têm a marca.

O passo 5 não é enfeite: sem ele, um repositório com uma retratação marcada e
vinte sem marca sairia verde, e o verde diria "consistente" quando ninguém
conferiu dezenove. Cobertura parcial só é honesta quando é contada em voz alta.

O QUE ELE DELIBERADAMENTE NÃO PEGA, e vale declarar para que o verde não prometa
demais:

- número retratado que reaparece **arredondado** ou com outra formatação
  (2,08 no lugar de 2,078): a busca é textual;
- número retratado dentro de código-fonte que o documento não cita;
- retratação escrita sem nenhum dos marcadores conhecidos;
- afirmação retratada que não é numérica (um rótulo, uma conclusão).

Só entram números com pelo menos TRÊS dígitos significativos. Sem esse corte,
valores como "5" ou "100" casariam em toda parte e o verificador viraria ruído
-- e verificador ruidoso é desligado, que é a forma mais comum de um controle
morrer.
"""
import os
import re
import sys

IGNORAR = {".git", "build", "subprojects", "__pycache__"}

# Marcadores de retratação, em minúsculas. Derivados dos blocos que o projeto
# já escreveu: "Esta tabela já publicou", "Este bloco publicava", "Uma versão
# anterior desta frase dizia", "o número era artefato", "estavam errados".
MARCADORES = (
    "publicava", "publicou", "ja publicou", "já publicou",
    "versao anterior", "versão anterior", "era artefato", "eram artefato",
    "estava errado", "estavam errados", "estavam erradas", "dizia",
)

# Número com >= 3 dígitos significativos: 2,078 / 1.539 / 0,115 / 22,5 não entra.
NUMERO = re.compile(r"\b\d+[.,]\d{2,}\b")

# A marca que declara o que caiu. Comentário HTML: invisível na renderização.
MARCA = re.compile(r"<!--\s*retratado:\s*([^>]+?)\s*-->", re.IGNORECASE)

# A marca inversa: este documento CITA um valor retratado de propósito, porque
# fala sobre o defeito em vez de cometê-lo. Sem esta válvula, um laudo de
# auditoria ou um estudo sobre retratações seria impossível de escrever -- e a
# saída seria afrouxar a regra para todo mundo, que é pior. A válvula é
# explícita e aparece na contagem final, então ninguém a usa sem deixar rastro.
CITA = re.compile(r"<!--\s*cita-retratado:\s*([^>]+?)\s*-->", re.IGNORECASE)


def blocos_de_citacao(texto):
    """Devolve [(inicio, fim, conteudo)] de cada bloco '>' contíguo."""
    blocos, atual, ini = [], [], None
    pos = 0
    for linha in texto.splitlines(keepends=True):
        if linha.lstrip().startswith(">"):
            if ini is None:
                ini = pos
            atual.append(linha)
        else:
            if atual:
                blocos.append((ini, pos, "".join(atual)))
                atual, ini = [], None
        pos += len(linha)
    if atual:
        blocos.append((ini, pos, "".join(atual)))
    return blocos


def retratacoes(texto):
    """Blocos de citação que se anunciam como retratação."""
    return [b for b in blocos_de_citacao(texto)
            if any(m in b[2].lower() for m in MARCADORES)]


def fora_de_retratacao(texto):
    """O texto com os blocos de retratação removidos."""
    for ini, fim, _ in reversed(retratacoes(texto)):
        texto = texto[:ini] + texto[fim:]
    return texto


def arquivos(raiz, exts):
    for pasta, subpastas, nomes in os.walk(raiz):
        subpastas[:] = [d for d in subpastas if d not in IGNORAR and not d.startswith("build")]
        for nome in nomes:
            if os.path.splitext(nome)[1] in exts:
                yield os.path.join(pasta, nome)


def verificar(raiz="."):
    docs = sorted(arquivos(raiz, {".md"}))
    # Onde cada número retratado foi declarado morto.
    mortos = {}
    sem_marca = []
    for doc in docs:
        try:
            texto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for _, _, bloco in retratacoes(texto):
            marca = MARCA.search(bloco)
            if not marca:
                if NUMERO.search(bloco):
                    sem_marca.append((os.path.relpath(doc, raiz), bloco.strip()[:70]))
                continue
            for n in NUMERO.findall(marca.group(1)):
                mortos.setdefault(n, []).append(doc)

    problemas = 0
    isentos = {}
    for doc in docs:
        try:
            texto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        vivo = fora_de_retratacao(texto)
        citados = set()
        for m in CITA.finditer(texto):
            citados.update(NUMERO.findall(m.group(1)))
        if citados:
            isentos[os.path.relpath(doc, raiz)] = sorted(citados)
        for n, origens in sorted(mortos.items()):
            if n in vivo and n not in citados:
                onde = ", ".join(sorted(set(os.path.relpath(o, raiz) for o in origens)))
                for i, linha in enumerate(vivo.splitlines(), 1):
                    if n in linha:
                        print(f"  {os.path.relpath(doc, raiz)}: '{n}' foi RETRATADO"
                              f" (em {onde}) e continua publicado")
                        print(f"      {linha.strip()[:110]}")
                        problemas += 1
                        break

    print(f"\n  {len(mortos)} valor(es) declarado(s) retratado(s) em {len(docs)}"
          f" documento(s); {problemas} sobrevivente(s) fora do bloco de retratação")
    if isentos:
        total = sum(len(v) for v in isentos.values())
        print(f"\n  {total} citação(ões) deliberada(s) de valor retratado, declaradas"
              f" com `<!-- cita-retratado: ... -->` em {len(isentos)} documento(s):")
        for doc, vals in sorted(isentos.items()):
            print(f"    {doc}: {' '.join(vals)}")
    if sem_marca:
        print(f"\n  COBERTURA PARCIAL: {len(sem_marca)} bloco(s) de retratação com"
              f" número e SEM a marca `<!-- retratado: ... -->`.")
        print("  Eles NAO foram conferidos. Verde aqui não cobre estes blocos:")
        for doc, trecho in sem_marca[:10]:
            print(f"    {doc}: {trecho}...")
        if len(sem_marca) > 10:
            print(f"    ... e mais {len(sem_marca) - 10}")
    return problemas


def autoteste():
    """Três casos: limpo, sobrevivente, e retratação sem marca.

    O terceiro é o que impede o verificador de mentir por omissão: sem ele,
    um repositório inteiro de retratações não marcadas sairia verde.
    """
    import io as _io
    import tempfile
    from contextlib import redirect_stdout

    def rodar(arquivos):
        with tempfile.TemporaryDirectory() as d:
            for nome, conteudo in arquivos.items():
                open(os.path.join(d, nome), "w", encoding="utf-8").write(conteudo)
            buf = _io.StringIO()
            with redirect_stdout(buf):
                rc = verificar(d)
            return rc, buf.getvalue()

    falhas = 0

    # 1. Retratação marcada, valor derrubado NÃO republicado: deve passar.
    rc, saida = rodar({"ok.md":
        "# ok\n\n> **Este bloco publicava 9,876 ns, e estava errado.** O medido\n"
        "> é 1,234 ns.\n> <!-- retratado: 9,876 -->\n\nO custo é 1,234 ns.\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: caso limpo acusou sobrevivente"); falhas += 1
    if "COBERTURA PARCIAL" in saida:
        print("  AUTOTESTE FALHOU: bloco marcado contado como sem marca"); falhas += 1

    # 2. Valor declarado morto continua publicado noutro arquivo: deve falhar.
    rc, _ = rodar({
        "retrata.md": "# r\n\n> **Este bloco publicava 9,876 ns.**\n"
                      "> <!-- retratado: 9,876 -->\n",
        "sobrevive.md": "# s\n\n| custo | 9,876 ns |\n"})
    if rc != 1:
        print(f"  AUTOTESTE FALHOU: sobrevivente não detectado (rc={rc})"); falhas += 1

    # 3. Retratação COM número e SEM marca: não é falha, mas tem de ser contada.
    #    Se esta assercao cair, o verde do verificador deixou de significar algo.
    rc, saida = rodar({"muda.md":
        "# m\n\n> **Este bloco publicava 9,876 ns, e estava errado.**\n"})
    if "COBERTURA PARCIAL" not in saida:
        print("  AUTOTESTE FALHOU: retratação sem marca passou silenciosa"); falhas += 1

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    alvo = sys.argv[1] if len(sys.argv) > 1 else "."
    sys.exit(1 if verificar(alvo) else 0)
