#!/usr/bin/env python3
"""Classifica cada rotulo por sensibilidade ao leiaute, a partir de uma coleta
do `caracterizar-leiaute.sh`.

    classificar-leiaute.py <dir-da-caracterizacao> [--tsv]
    classificar-leiaute.py --autoteste

DUAS PERGUNTAS, E ELAS SAO SOBRE COISAS DIFERENTES

    reprodutibilidade  a faixa entre execucoes do MESMO artefato
    envelope           a variacao das medianas ENTRE alinhamentos

Um rotulo so e classificavel quando a segunda se separa da primeira. Quando a
reprodutibilidade engole o envelope, a resposta honesta nao e "invariavel" --
e "nao consegui distinguir", e o rotulo NAO entra na tabela.

AUSENCIA E UM ESTADO, e e por isso que ela nao precisa de nome aqui. Rotulo
fora da tabela e `identificabilidade nao estabelecida` para o
`comparar-hardware.py`: nem permissao, nem proibicao. Escrever uma terceira
classe para dizer isso duplicaria o estado que ja existe.

POR QUE IQR, E NAO A FAIXA

O criterio do `meson.build` e faixas disjuntas entre execucoes. Ele e o certo
sob protocolo; sob perturbacao ele quebra, e quebra para o lado errado: em
27/09/2026 UMA execucao de dez levou a faixa de `lock, best case` a 84% -- um
valor de 3,79 entre nove de 2,04 --, e a faixa passou a dizer mais sobre a
sessao que sobre o binario. O IQR sobrevive a isso; a faixa vai impressa ao
lado para quem quiser aplicar o criterio original.

O ENVELOPE E UM PISO, NUNCA UMA INCERTEZA. `-falign-loops` e UMA coordenada do
leiaute. Quatro valores dela nao amostram o espaco de leiautes possiveis, e o
que se afirma e "sensibilidade observada >= X", jamais "incerteza = +-X".
"""
import io
import os
import re
import statistics as st
import sys

PISO_PCT = 1.0      # o mesmo piso de materialidade do `comparar-hardware.py`
LINHA = [
    re.compile(r'^\s{2}(\S.*?)\s{2,}([0-9]+\.[0-9]+)\s+[0-9.]+-[0-9.]+\s+'
               r'[0-9.]+-[0-9.]+\s+[0-9.]+%\s+[0-9.]+%'),
    re.compile(r'^\s{2}(\S.*?)\s{2,}([0-9]+\.[0-9]+)\s+[0-9.]+-[0-9.]+\s+\d+\s+[0-9.]+%'),
]
NOME = re.compile(r'^r(\d+)-al(\d+)-(.+)\.txt$')


def ler(diretorio):
    """{(programa, rotulo): {alinhamento: [medianas por execucao]}}"""
    saidas = os.path.join(diretorio, "saidas")
    fora = {}
    for arq in sorted(os.listdir(saidas)):
        m = NOME.match(arq)
        if not m:
            continue
        al, prog = m.group(2), m.group(3)
        with io.open(os.path.join(saidas, arq), encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                for padrao in LINHA:
                    g = padrao.match(linha.rstrip())
                    if g:
                        chave = (prog, "%s: %s" % (prog, g.group(1)))
                        fora.setdefault(chave, {}).setdefault(al, []).append(float(g.group(2)))
                        break
    return fora


def quartis(v):
    s = sorted(v)
    return s[len(s) // 4], s[(3 * len(s)) // 4]


def dispersao_iqr(v):
    """(p75 - p25) / mediana, em %. Ordinal, e nao supoe distribuicao."""
    med = st.median(v)
    if med <= 0:
        return None
    a, b = quartis(v)
    return 100.0 * (b - a) / med


def classificar(por_alinhamento):
    """-> (classe|None, reprodutibilidade%, envelope%, faixa%)"""
    als = sorted(por_alinhamento, key=int)
    if len(als) < 2 or any(len(por_alinhamento[a]) < 4 for a in als):
        return None, None, None, None
    repro = max(dispersao_iqr(por_alinhamento[a]) or 0.0 for a in als)
    medianas = [st.median(por_alinhamento[a]) for a in als]
    centro = st.median(medianas)
    if centro <= 0:
        return None, repro, None, None
    envelope = 100.0 * (max(medianas) - min(medianas)) / centro
    todos = [x for a in als for x in por_alinhamento[a]]
    faixa = 100.0 * (max(todos) - min(todos)) / st.median(todos)
    # A REPRODUTIBILIDADE PRECISA CABER DENTRO DO ENVELOPE para que o envelope
    # signifique leiaute. Quando ela o engole, o que se mediu foi a sessao.
    if envelope >= PISO_PCT and envelope > repro:
        return "SENSIVEL", repro, envelope, faixa
    if envelope < PISO_PCT and repro < PISO_PCT:
        return "INVARIAVEL", repro, envelope, faixa
    return None, repro, envelope, faixa


def ancoras(diretorio, build):
    """{programa: text_sha256 do instrumento ancorado}, ou {} se nao der.

    A CLASSIFICACAO VALE PARA UM INSTRUMENTO, E NAO PARA UM COMMIT. A mudanca
    do `statistics.h` em 27/09/2026 alterou o `.text` de todos os programas sem
    tocar em nenhum `.c`: uma classificacao presa ao commit do fonte
    continuaria autorizando comparacao entre dois binarios diferentes.

    A autoridade e o `text_sha256` da variante que reproduziu byte a byte o
    binario de producao -- a ancora. Duas fontes, nesta ordem:

      1. o bloco `# ANCORA` do manifesto, gravado no momento da medicao;
      2. o casamento contra o binario de producao ainda presente no build.

    A segunda existe para coletas anteriores ao registro. Ela NAO adivinha:
    procura o artefato cujo `.text` e identico ao de producao, e exige
    exatamente um. Zero ou mais de um, devolve vazio e a classificacao e
    recusada -- porque sem ancora a linha do TSV nao diz a que instrumento ela
    se refere.
    """
    man = os.path.join(str(diretorio).rstrip("/"), "manifesto.txt")
    fora, atual = {}, None
    try:
        with io.open(man, encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                m = re.match(r"^#\s*ANCORA\s+(\S+)", linha)
                if m:
                    atual = m.group(1)
                    continue
                m = re.match(r"^#\s+text_sha256=([0-9a-f]{64})\s*$", linha)
                if m and atual:
                    fora[atual] = m.group(1)
                    atual = None
    except OSError:
        pass
    if fora:
        return fora
    # Sem registro: casar contra o binario de producao, se ele ainda existir.
    artefatos = {}
    atual = None
    try:
        with io.open(man, encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                m = re.match(r"^#\s*ARTIFACT\s+(\S+)", linha)
                if m:
                    atual = m.group(1)
                    continue
                m = re.match(r"^#\s+text_sha256=([0-9a-f]{64})\s*$", linha)
                if m and atual:
                    artefatos[atual] = m.group(1)
                    atual = None
    except OSError:
        return {}
    for nome, sha in list(artefatos.items()):
        prog = nome.rsplit(".al", 1)[0]
        alvo = os.path.join(build, "docs")
        achados = []
        for raiz, _, arqs in os.walk(build):
            if prog in arqs:
                achados.append(os.path.join(raiz, prog))
        if len(achados) != 1:
            continue
        if _sha_texto(achados[0]) == sha:
            fora[prog] = sha
    return fora


def _sha_texto(binario):
    """sha256 da secao `.text`, lida pelos bytes. Vazio se nao der."""
    import subprocess
    import tempfile
    with tempfile.NamedTemporaryFile() as t:
        r = subprocess.run(["objcopy", "--dump-section", ".text=" + t.name, binario,
                            os.devnull], capture_output=True)
        if r.returncode != 0:
            return ""
        dados = io.open(t.name, "rb").read()
    if not dados:
        return ""
    import hashlib
    return hashlib.sha256(dados).hexdigest()


def fontes(diretorio):
    """{programa: commit} dos blocos `# FONTE` do manifesto."""
    man = os.path.join(diretorio, "manifesto.txt")
    fora, atual = {}, None
    try:
        with io.open(man, encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                m = re.match(r"^#\s*FONTE\s+(\S+)", linha)
                if m:
                    atual = m.group(1)
                    continue
                m = re.match(r"^#\s+commit=(\S+)", linha)
                if m and atual:
                    fora[atual] = m.group(1)
    except OSError:
        pass
    return fora


def principal(diretorio, tsv, build):
    dados = ler(diretorio)
    if not dados:
        print("  nada reconhecido em %s/saidas" % diretorio)
        return 1
    fnt = fontes(diretorio)
    anc = ancoras(diretorio, build)
    evidencia = os.path.basename(str(diretorio).rstrip("/"))
    # SEM ANCORA NAO HA LINHA. A classificacao autoriza ou proibe comparacao
    # entre INSTRUMENTOS; uma linha que nao diz a qual instrumento se refere
    # autorizaria qualquer um.
    faltando = sorted({p for (p, _) in dados} - set(anc))
    if faltando:
        print("  SEM ANCORA para: %s" % ", ".join(faltando))
        print("  A classificacao amarra rotulo a INSTRUMENTO, e a ancora e o")
        print("  `text_sha256` da variante que reproduziu o binario de producao.")
        print("  Sem ela a linha do TSV nao diz a que binario se refere.")
        return 1
    linhas, indeterminados = [], 0
    if not tsv:
        print("  %-46s %8s %8s %8s  %s" % ("rotulo", "repro%", "envel%", "faixa%", "classe"))
        print("  " + "-" * 92)
    for (prog, rotulo) in sorted(dados):
        classe, repro, env, faixa = classificar(dados[(prog, rotulo)])
        if not tsv:
            fmt = lambda x: ("%7.2f%%" % x) if x is not None else "      -"
            print("  %-46s %s %s %s  %s" % (rotulo[:46], fmt(repro), fmt(env), fmt(faixa),
                                            classe or "(indeterminado)"))
        if classe:
            # A ANCORA E A AUTORIDADE OPERACIONAL; o `source_origin` fica como
            # procedencia humana, para quem le.
            linhas.append("%s\t%s\t%s\t%s\t%s" % (rotulo, classe, evidencia,
                                                  anc[prog],
                                                  fnt.get(prog, "desconhecido")))
        else:
            indeterminados += 1
    if tsv:
        for l in linhas:
            print(l)
    else:
        print("\n  %d rotulo(s) classificado(s), %d indeterminado(s)" % (len(linhas), indeterminados))
        print("  piso de materialidade: %.0f%% (o mesmo do comparar-hardware.py)" % PISO_PCT)
        print("  o envelope e PISO de sensibilidade: `-falign-loops` e UMA coordenada do leiaute")
        print("\n  Para gravar a classificacao:")
        print("    %s %s --tsv >> ferramental/qualidade/sensibilidade-leiaute.tsv" % (sys.argv[0], diretorio))
    return 0


def autoteste():
    falhas = 0

    def caso(n, descricao, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    # Quatro alinhamentos, dez execucoes cada. O ruido interno e o mesmo; o que
    # muda e o quanto as MEDIANAS se afastam entre alinhamentos.
    def amostra(medias, ruido):
        return {str(al): [m + (i % 2) * ruido for i in range(10)]
                for al, m in zip((16, 32, 64, 128), medias)}

    caso(1, "medianas iguais e ruido pequeno -> invariavel",
         classificar(amostra([100.0] * 4, 0.05))[0], "INVARIAVEL")
    caso(2, "medianas afastadas com ruido pequeno -> sensivel",
         classificar(amostra([100.0, 100.0, 110.0, 100.0], 0.05))[0], "SENSIVEL")
    # O CASO QUE SEPARA ESTE CLASSIFICADOR DE UM QUE SO OLHA O ENVELOPE: se a
    # reprodutibilidade engole o envelope, o que se mediu foi a sessao.
    # O CASO QUE DISTINGUE este classificador de um que so olha o envelope: o
    # envelope esta ACIMA do piso (1,74%) e mesmo assim nao classifica, porque
    # a variacao entre execucoes do mesmo artefato e de 26% -- quinze vezes
    # maior. Sem esta comparacao, ele chamaria de sensibilidade ao leiaute o
    # que foi perturbacao de sessao, que e o erro de 27/09/2026 em forma de
    # codigo.
    envelope_acima = amostra([100.0, 100.0, 102.0, 100.0], 30.0)
    _, repro3, env3, _ = classificar(envelope_acima)
    caso(3, "envelope acima do piso, mas engolido pelo ruido -> indeterminado",
         classificar(envelope_acima)[0], None)
    caso(31, "e o caso e mesmo o que se descreve: envelope > piso",
         env3 > PISO_PCT, True)
    caso(32, "com o ruido maior que ele",
         repro3 > env3, True)
    caso(4, "ruido grande com medianas iguais tambem e indeterminado",
         classificar(amostra([100.0] * 4, 30.0))[0], None)
    caso(5, "poucas execucoes nao classificam",
         classificar({"16": [1.0, 1.0], "64": [2.0, 2.0]})[0], None)
    caso(6, "um alinhamento so nao classifica",
         classificar({"64": [1.0] * 10})[0], None)
    env = classificar(amostra([100.0, 100.0, 110.0, 100.0], 0.05))[2]
    caso(7, "o envelope e (max-min)/mediana entre alinhamentos",
         round(env, 1), 10.0)
    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        sys.exit(2)
    build = os.environ.get("DPDK_ACADEMY_BUILD", "build-precommit")
    sys.exit(principal(args[0], "--tsv" in sys.argv, build))
