#!/usr/bin/env python3
"""Confere se todo número afirmado como medição PRÓPRIA tem evidência publicada.

POR QUE ESTA SONDA NAO ESTAVA NO `auditar-fontes.py`

Aquele instrumento tem três sondas, e as três olham para FORA: fonte remota,
mecanismo nu e número órfão são todas sobre afirmação a respeito de terceiro --
hardware, kernel, literatura. Elas perguntam "quem disse isso?".

Esta pergunta é a outra metade, e ela é a que o repositório mais promete: "todo
número publicado aqui tem um programa que o produz". Um número afirmado na prosa
como medição deste projeto, sem aparecer em nenhum bloco de saída do mesmo
documento, é uma promessa não cumprida -- e nenhum portão anterior olhava para
ela.

O QUE CONTA COMO EVIDENCIA, E POR QUE NAO E SO `disp`/`IQR`

A régua NAO e "todo numero precisa de estatística". O `anatomia-mbuf` observa
`sizeof(rte_mbuf)` e headroom: propriedades DETERMINISTICAS, onde publicar
dispersão inventaria incerteza. O `pool-esgotado` verifica fronteira e conta
objetos.

Evidência aqui é mais fraca e mais geral: **o número aparece dentro de um bloco
cercado do mesmo documento**. Se aparece, quem lê pode confrontar prosa e saída;
se não, tem de confiar.

AS DUAS CAUSAS LEGITIMAS QUE SOBRAM, e por que nao vale "consertar"

Depois de tres correcoes de desenho -- tabela conta como evidencia, escopo e o
modulo e nao o arquivo, e numero dentro de bloco nao carrega unidade -- a sonda
caiu de 262 para 78 avisos em 235 numeros. Os que restam sao de duas familias:

  ARREDONDAMENTO NA PROSA. O bloco publica `0.981` e o texto diz `0,98`. Isso e
  correto -- prosa nao repete tres casas -- e `verificar-retratacoes.py` ja tem
  a sonda de arredondamento. Duplicar aqui criaria dois lugares para a mesma
  regra divergir.

  VALOR DISCUTIDO COMO NAO PUBLICADO. O modulo 03 cita 2,19 e 2,77 ns
  justamente para dizer que NAO sao o valor publicado -- sao a variacao entre
  execucoes que motiva publicar razoes. Um aviso ali aponta para o paragrafo
  mais rigoroso do documento.

Reduzir esses dois exigiria a sonda entender intencao, e ela nao entende. O
numero de 78 e o custo de nao inventar precisao.

POR QUE E AVISO, E NAO REPROVACAO

Número derivado -- uma razão, uma soma, um percentual do orçamento -- nao
aparece em bloco nenhum e esta CERTO assim. Reprovar por isso transformaria o
portao em ruido, e ruido se desliga. A sonda diz onde olhar.
"""
import pathlib
import re
import sys

# Número com unidade típica das medições deste projeto. Sem unidade a taxa de
# falso positivo explode: versões, datas, contagens e números de seção entram.
NUM = re.compile(r"(\d+[.,]?\d*)\s*(ns|µs|us|ms|s\b|GB/s|MB/s|Mpps|GHz|MT/s|ciclos|cycles)")
# DENTRO de bloco e de tabela o numero NAO carrega unidade: ela esta no
# cabecalho ("tempos em ns"). Exigir unidade dos dois lados fazia a sonda
# acusar `2,18` enquanto o bloco ao lado publicava `malloc/free  2.18` --
# terceiro defeito de desenho desta sonda, e o mais silencioso.
NUM_NU = re.compile(r"(?<![\w.])(\d+[.,]\d+|\d{2,})(?![\w.])")
# Parágrafo com referência de rodapé é afirmação sobre terceiro: e do auditor
# de fontes, nao desta sonda.
TEM_FONTE = re.compile(r"\]\[[^\]]+\]|\]\(https?:")


def blocos_e_prosa(texto):
    """Devolve (numeros com evidencia, [(numero, linha) sem]).

    EVIDENCIA NAO E SO BLOCO CERCADO, e a primeira versao desta sonda errou
    nisso: uma LINHA DE TABELA markdown tambem e resultado publicado. O modulo
    02 publica `| -l 0 --in-memory | 121,1 ms | 120,0-122,5 |` -- numero,
    condicao e faixa -- e a sonda acusava, porque so olhava para ```.
    """
    dentro, bloco, prosa = False, set(), []
    for ln in texto.split("\n"):
        s = ln.strip()
        if s.startswith("```"):
            dentro = not dentro
            continue
        achados = [m.group(1).replace(",", ".") for m in NUM.finditer(ln)]
        if dentro or (s.startswith("|") and s.endswith("|")):
            bloco.update(m.group(1).replace(",", ".") for m in NUM_NU.finditer(ln))
            bloco.update(achados)
        elif achados and not TEM_FONTE.search(ln):
            for a in achados:
                prosa.append((a, s))
    return bloco, prosa


def verificar(raiz="docs"):
    """O escopo e o MODULO, nao o arquivo.

    A segunda versao desta sonda acusava `metodologia.md` inteiro, porque ela
    discute numeros cujos blocos vivem no `README.md` ao lado. Separar desenho
    experimental de narrativa foi decisao deliberada do projeto, e uma sonda que
    pune essa separacao empurraria o conteudo de volta para um arquivo so.
    """
    total = sem = 0
    modulos = {}
    for p in sorted(pathlib.Path(raiz).rglob("*.md")):
        modulos.setdefault(p.parent, []).append(p)
    for pasta, arquivos in sorted(modulos.items()):
        evidencia = set()
        for p in arquivos:
            b, _ = blocos_e_prosa(p.read_text(encoding="utf-8"))
            evidencia |= b
    for p in sorted(pathlib.Path(raiz).rglob("*.md")):
        if p.name.endswith(".en.md"):
            continue   # o par em ingles repete os mesmos numeros
        evid = set()
        for irmao in modulos[p.parent]:
            b, _ = blocos_e_prosa(irmao.read_text(encoding="utf-8"))
            evid |= b
        _, prosa = blocos_e_prosa(p.read_text(encoding="utf-8"))
        bloco = evid
        orfaos = [(n, l) for n, l in prosa if n not in bloco]
        total += len(prosa)
        sem += len(orfaos)
        if orfaos:
            print(f"  {p}: {len(orfaos)} de {len(prosa)} numero(s) de prosa sem bloco")
            for n, l in orfaos[:3]:
                print(f"      {n}  em: {l[:64]}")
    print(f"\n  {total} numero(s) com unidade em prosa; {sem} sem bloco no mesmo documento")
    return sem


def autoteste():
    import io
    import tempfile
    from contextlib import redirect_stdout
    falhas = 0

    def caso(numero, descricao, texto, esperado):
        nonlocal falhas
        d = tempfile.mkdtemp()
        pathlib.Path(d, "a.md").write_text(texto, encoding="utf-8")
        buf = io.StringIO()
        with redirect_stdout(buf):
            n = verificar(d)
        ok = (n == 0) if esperado == 0 else (n >= 1)
        if not ok:
            print(f"  AUTOTESTE {numero} FALHOU: {descricao} (n={n})")
            print("    " + buf.getvalue().strip().replace("\n", "\n    "))
            falhas += 1

    # 1. O caso central: prosa afirma um numero que nenhum bloco publica.
    caso(1, "numero de prosa sem bloco passou", "A syscall custa 33.5 ns aqui.\n", 1)

    # 2. Mesmo numero dentro de bloco: a prosa pode ser confrontada.
    caso(2, "numero com bloco acusado",
         "A syscall custa 33.5 ns aqui.\n\n```\n  syscall  33.5 ns\n```\n", 0)

    # 3. PARAGRAFO COM FONTE e do auditor de fontes, nao desta sonda. Sem este
    #    caso a sonda duplicaria o outro instrumento e os dois brigariam pelo
    #    mesmo numero.
    caso(3, "numero de terceiro com fonte acusado",
         "Gregg mede 100 ns em [outra maquina][g].\n\n[g]: https://exemplo\n", 0)

    # 4. NUMERO SEM UNIDADE nao entra: versao, data e numero de secao
    #    produziriam ruido que faria alguem desligar a sonda.
    caso(4, "numero sem unidade acusado", "Ver a secao 4.1 do modulo 02.\n", 0)

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    verificar(sys.argv[1] if len(sys.argv) > 1 else "docs")
    sys.exit(0)  # AVISO, nunca reprovacao -- ver o cabecalho.
