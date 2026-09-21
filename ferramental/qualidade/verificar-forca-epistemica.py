#!/usr/bin/env python3
"""Confere se a tradução preserva a FORÇA da afirmação científica.

POR QUE ESTE VERIFICADOR EXISTE

O `verificar-paridade.py` declara no próprio cabeçalho o que ele não alcança:

    O que a verificação NÃO cobre continua sendo o risco real: se o texto em
    inglês *diz a mesma coisa*. Isso é semântica, nenhum padrão sintático
    decide, e a garantia ali é humana, com data.

Isso continua verdadeiro para semântica em geral. Mas uma FATIA dela é
verificável, e é justamente a que mais importa num material experimental: os
marcadores de força epistêmica formam um vocabulário FECHADO e pequeno.

    compatível / consistent     demonstra / demonstrates
    sugere / suggests           mede / measures
    pode / may, can             nesta máquina / on this machine

O caso grave que isto pega: a §4.1 afirma que a explicação do custo de tradução
é "compatível, NÃO demonstrada" -- porque demonstrar exigiria contador de
hardware. Se a tradução disser `demonstrated`, um número muda de estatuto
científico na travessia, e nenhum portão anterior veria: a estrutura de títulos
bate, os números batem, a bibliografia bate.

O QUE ELE NÃO É

Não é tradutor nem avaliador de qualidade. Ele conta ocorrências por classe em
cada par pt/en e acusa DESEQUILÍBRIO. Uma divergência não é erro por si -- as
duas línguas distribuem estes termos de forma diferente, e `pode` cobre `may` e
`can`. Por isso a tolerância é generosa e a saída é AVISO, não reprovação: o
verificador aponta onde olhar, e quem decide é quem lê as duas frases.

Um portão que reprovasse aqui seria desligado na primeira semana, e o valor
dele é justamente sobreviver para apontar o caso raro.
"""
import os
import re
import sys

# Classes de força. Cada uma agrupa o que, para efeito de afirmação científica,
# vale o mesmo -- e o que NÃO vale está em outra classe de propósito.
CLASSES = {
    # `estabelece`/`establish` FICARAM DE FORA, e a razao vale registrar porque
    # ela apareceu na primeira execucao: o verbo e AMBIGUO. "Estabelece que X
    # causa Y" e afirmacao forte; "estabelece o ambiente de medicao" e registrar
    # um fato. O submodulo de benchmarking usa o segundo sentido seis vezes em
    # ingles (`establishes`) e o portugues usa `apura` -- traducao fiel, que o
    # verificador acusou como mudanca de estatuto.
    #
    # Uma classe com membro ambiguo produz falso positivo para sempre, e falso
    # positivo em portao e o que faz alguem desligar o portao.
    "forte (demonstra/prova)": (
        r"\b(demonstra|demonstram|demonstrad[ao]s?|prova|provam|provad[ao]s?)\b",
        r"\b(demonstrates?|demonstrated|proves?|proven)\b"),
    # `appears` FICOU DE FORA pelo mesmo motivo que `establish`: em ingles ele
    # quase sempre significa "aparece na saida", nao "parece". As 11 ocorrencias
    # do modulo 02 eram todas desse sentido, contra 3 `parece` em portugues --
    # e `appears` e `parece` nem sao pares: o par de `parece` e `seems`.
    #
    # A licao das duas exclusoes e a mesma, e ela vale mais que o vocabulario:
    # ESTE VOCABULARIO TEM DE SAIR DO CORPUS, NAO DA MEMORIA DE QUEM ESCREVE.
    # Montado de cabeca, ele errou duas vezes em dez achados na primeira volta.
    # `parece` saiu -- QUARTA ambiguidade. As tres ocorrencias do modulo 02 eram
    # todas dele, e nenhuma era hesitacao: "um piso fixo com essa dispersao nao
    # parece trabalho: parece espera" e "as descricoes se parecem". E
    # "assemelha-se a", nao "sugere". Com ele fora, o par `seems` tambem sai,
    # porque perde o correspondente.
    "fraca (sugere/indica)": (
        r"\b(sugere|sugerem|indica|indicam|aponta|apontam)\b",
        r"\b(suggests?|indicates?|points? to)\b"),
    "compatibilidade (nao prova)": (
        r"\b(compatív(el|eis)|coerente|coerentes|consistente|consistentes)\b",
        r"\b(consistent|compatible|coherent)\b"),
    # ESTE nao foi ambiguidade, foi PADRAO INCOMPLETO -- a mesma classe do
    # `limitac` que nao casava com `limitaç`. Faltavam as formas mais comuns do
    # portugues: `medir`, `medicao`, `medicoes`, `medimos`. Do lado ingles
    # faltava o substantivo `measurement`.
    "medicao": (
        r"\b(mede|medem|medir|medid[ao]s?|mensurad[ao]s?|mediç(ão|ões)|medimos)\b",
        r"\b(measures?|measured|measurable|measurements?|measuring)\b"),
    # `pode` FICOU DE FORA, e e a TERCEIRA ambiguidade que este vocabulario
    # encontrou -- depois de `establish` e `appears`, as duas no lado ingles.
    #
    # Em portugues `pode` cobre possibilidade E capacidade; o ingles separa em
    # `may` e `can`. Os 37 `pode/podem` do modulo 01 misturam os dois sentidos,
    # e os 20 ingleses contam so o primeiro. Incluir `can` no lado ingles
    # tornaria a classe inutil: ele e onipresente em texto tecnico.
    #
    # O padrao das tres exclusoes e o mesmo, e merece ser dito: NAO EXISTE
    # PAREAMENTO 1:1 entre vocabularios epistemicos de duas linguas. O que
    # sobrevive sao os marcadores SEM equivalente ambiguo -- e sao poucos, o
    # que e uma limitacao do instrumento, nao um defeito dele.
    "modal (talvez/possivelmente)": (
        r"\b(poderia|poderiam|talvez|possivelmente|eventualmente)\b",
        r"\b(might|perhaps|possibly)\b"),
    "escopo declarado": (
        r"(nesta máquina|neste hardware|nesta configuração|nesta coleta)",
        r"(on this machine|on this hardware|in this configuration|in this collection)"),
    "negacao de forca": (
        r"(não demonstra|não prova|não autoriza|não estabelece|não é demonstrad)",
        r"(does not demonstrate|do not demonstrate|does not prove|do not prove|"
        r"does not authorise|does not establish|is not demonstrated)"),
}

# Tolerância: a menor diferença que vale olhar. Abaixo disso a divergência é
# ruído de idioma, não mudança de afirmação.
MINIMO = 3
FRACAO = 0.4


def contar(texto, padrao):
    return len(re.findall(padrao, texto, re.I))


def pares(raiz):
    for base, dirs, nomes in os.walk(raiz):
        dirs[:] = [d for d in dirs if d not in (".git", "build", "subprojects", "temp")]
        for n in sorted(nomes):
            if n.endswith(".en.md"):
                pt = os.path.join(base, n[:-6] + ".md")
                if os.path.exists(pt):
                    yield pt, os.path.join(base, n)


def verificar(raiz="."):
    avisos = conferidos = 0
    for pt, en in pares(raiz):
        tp = open(pt, encoding="utf-8").read()
        te = open(en, encoding="utf-8").read()
        for nome, (rp, re_) in CLASSES.items():
            a, b = contar(tp, rp), contar(te, re_)
            conferidos += 1
            maior = max(a, b)
            if maior < MINIMO or abs(a - b) <= max(MINIMO - 1, maior * FRACAO):
                continue
            print(f"  {pt}: '{nome}' pt={a} en={b}")
            avisos += 1
    print(f"\n  {conferidos} contagem(ns) de força epistêmica em "
          f"{len(list(pares(raiz)))} par(es); {avisos} desequilíbrio(s) para olhar")
    return avisos


def autoteste():
    import io
    import tempfile
    from contextlib import redirect_stdout

    falhas = 0

    def caso(numero, descricao, ptxt, etxt, esperado):
        nonlocal falhas
        d = tempfile.mkdtemp()
        open(os.path.join(d, "a.md"), "w", encoding="utf-8").write(ptxt)
        open(os.path.join(d, "a.en.md"), "w", encoding="utf-8").write(etxt)
        buf = io.StringIO()
        with redirect_stdout(buf):
            n = verificar(d)
        ok = (n == 0) if esperado == 0 else (n >= 1)
        if not ok:
            print(f"  AUTOTESTE {numero} FALHOU: {descricao} (n={n})")
            print("    " + buf.getvalue().strip().replace("\n", "\n    "))
            falhas += 1

    # 1. O CASO QUE JUSTIFICA O ARQUIVO. O português diz que a explicação é
    #    compatível e NÃO demonstrada; o inglês diz que está demonstrada. A
    #    estrutura bate, os números batem, e um numero mudou de estatuto.
    caso(1, "downgrade epistemico na traducao passou",
         "É compatível. É compatível. É compatível. É compatível.",
         "It is demonstrated. It is demonstrated. It is demonstrated. It is demonstrated.", 1)

    # 2. Tradução fiel não pode acusar, senão o portão vira ruído.
    caso(2, "traducao fiel acusada",
         "É compatível. É compatível. É compatível. É compatível.",
         "It is consistent. It is consistent. It is consistent. It is consistent.", 0)

    # 3. Volume pequeno não acusa: com uma ocorrência de cada lado a diferença
    #    é indistinguível de escolha lexical.
    caso(3, "diferenca de uma ocorrencia acusada",
         "Isto demonstra o efeito.", "This suggests the effect.", 0)

    # 4. O escopo declarado é a classe mais fácil de perder na tradução, e a
    #    que mais muda a conclusão: sem ela, o número vira universal.
    caso(4, "escopo declarado perdido na traducao passou",
         "nesta máquina. nesta máquina. nesta máquina. nesta máquina. nesta máquina.",
         "The result holds. The result holds. The result holds.", 1)

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    verificar(sys.argv[1] if len(sys.argv) > 1 else ".")
    sys.exit(0)  # AVISO, nunca reprovação -- ver o cabeçalho.
