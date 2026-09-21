#!/usr/bin/env python3
"""Confere os ponteiros que o codigo-fonte faz para secoes do seu README.

POR QUE ISTO EXISTE

Ate a v0.02.00 o melhor material didatico do repositorio vivia em comentario de
codigo-fonte. Medido no `pipeline_ring.c`: 210 linhas de comentario para 363 de
codigo, ensinando cinco armadilhas que o README do topico nao mencionava
nenhuma vez. Quem lia o Markdown nao via o raciocinio; quem lia o `.c` via um
tratado dentro de um arquivo que ninguem abre para aprender.

O raciocinio transferivel passou para o documento, e o fonte ficou com ponteiros
de uma linha -- "ver README.md secao 4.3". A troca resolve a legibilidade e
CRIA UM RISCO NOVO: o dia em que a secao 4.3 for renumerada, ou o trecho que ela
descreve for reescrito, o ponteiro continua sintaticamente valido e passa a
mentir. Ponteiro pendurado e pior que ausencia de ponteiro, porque tem a
aparencia de rastreabilidade.

O QUE ELE CONFERE

1. A secao apontada EXISTE no README.md vizinho, e tambem no par `.en.md`.
2. Se o ponteiro nomeia a secao -- `secao 4.3 "Contabilizacao do cache do
   mempool"` --, o titulo tem de bater com o titulo real. E isso que pega a
   renumeracao, que e a deriva provavel: a secao 4.3 passa a ser outra e o
   ponteiro continua sintaticamente valido.

COMO ESTE VERIFICADOR CHEGOU A ESTE FORMATO, que vale registrar

Tres versoes anteriores tentaram inferir do TEXTO se a secao apontada descrevia
codigo, para so entao exigir bidirecionalidade -- se a secao cita algum
identificador do fonte, o ponteiro esta vivo. As tres erraram na mesma secao: a
5.1.1 do modulo 01 explica SMT, nao descreve codigo, e cita `nice` e
`scaling_cur_freq` em crase. Inferir por diretorio desligava a verificacao em
`docs/*/medicoes/`; inferir por presenca de crase acusava a secao de SMT;
inferir por presenca do simbolo na arvore nao separava, porque os dois nomes
aparecem em fonte.

O defeito nao estava na heuristica, estava no FORMATO DO PONTEIRO: um numero
sozinho nao carrega informacao suficiente para que a deriva seja detectavel.
Nomear a secao resolve exatamente, sem heuristica e sem falso positivo. O custo
e o ponteiro ficar mais longo; continua cabendo em uma linha.

O QUE ELE DELIBERADAMENTE NAO FAZ, e vale declarar

Nao compara SENTIDO. Se a secao continuar citando `relatar_mempool` e descrever
errado o que a funcao faz, este verificador passa. A deriva semantica nao e
detectavel por programa, e prometer que seria tornaria o portao um alibi.

Nao exige que fonte e documento mudem no MESMO commit. Foi considerado e
recusado: um ajuste de espacamento no `.c` passaria a exigir edicao do texto, o
verificador viraria ruido, e verificador ruidoso e desligado -- que e a forma
mais comum de um controle morrer.

Nao exige ponteiro. Um fonte sem comentario nenhum passa. Este verificador
cuida dos ponteiros que existem, nao da decisao de cria-los.
"""
import pathlib
import re
import unicodedata
import sys

IGNORAR = {".git", "build", "builddir", "build-precommit", "subprojects",
           "temp", "__pycache__", "alternativas"}
FONTES = (".c", ".h", ".cpp", ".hpp")

# `secao 4.3 "Titulo"` -- o titulo e opcional, e e ele que torna a deriva
# detectavel; sem ele so a existencia da secao e conferida.
PONTEIRO = re.compile(
    r"(?:se[cç][aã]o|section)\s+(\d+(?:\.\d+)*)\s*(?:\"([^\"\n]+)\")?", re.I)
TITULO = re.compile(r"^#{2,6}\s+(\d+(?:\.\d+)*)[.\s]+(.*)$")


def _norm(t):
    """Compara titulos sem acento, caixa nem pontuacao -- o comentario do fonte
    e escrito sem acento por convencao do repositorio."""
    t = unicodedata.normalize("NFKD", t.strip().lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", "", t).strip()


def _raiz():
    return pathlib.Path(__file__).resolve().parents[2]


def _secoes(md):
    """Mapeia prefixo numerico -> titulo da secao."""
    out = {}
    for linha in md.splitlines():
        m = TITULO.match(linha)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def _comentarios(texto):
    """So o que esta dentro de comentario -- um ponteiro em string nao conta.

    As quebras de linha do bloco sao desfeitas antes de casar: um ponteiro
    longo quebra naturalmente entre o numero e o titulo, e sem isto ele seria
    lido como ponteiro SEM titulo -- um enfraquecimento silencioso, que e o
    modo de falha que este verificador existe para evitar.
    """
    blocos = re.findall(r"/\*.*?\*/", texto, re.S)
    blocos += re.findall(r"//[^\n]*", texto)
    junto = "\n".join(blocos)
    return re.sub(r"\n\s*(?:\*|//)?\s*", " ", junto)


def verificar(raiz):
    raiz = pathlib.Path(raiz)
    falhas, conferidos, sem_titulo = [], 0, 0
    for src in sorted(raiz.rglob("*")):
        if src.suffix not in FONTES or not src.is_file():
            continue
        if any(p in IGNORAR for p in src.parts):
            continue
        texto = src.read_text(encoding="utf-8", errors="replace")
        alvos = sorted(set(PONTEIRO.findall(_comentarios(texto))))
        if not alvos:
            continue
        # O README mais proximo subindo: em docs/ os fontes vivem em
        # `medicoes/` e o documento fica no diretorio do modulo.
        readme = None
        for d in [src.parent, *src.parent.parents]:
            if not str(d).startswith(str(raiz)):
                break
            if (d / "README.md").exists():
                readme = d / "README.md"
                break
        rel = src.relative_to(raiz)
        if readme is None:
            falhas.append(f"{rel}: aponta para secao"
                          f" {', '.join(a for a, _ in alvos)}"
                          " e nao ha README.md no diretorio nem acima")
            continue
        secoes = _secoes(readme.read_text(encoding="utf-8"))
        en = readme.parent / "README.en.md"
        secoes_en = _secoes(en.read_text(encoding="utf-8")) if en.exists() else None
        for alvo, titulo in alvos:
            conferidos += 1
            if alvo not in secoes:
                falhas.append(f"{rel}: aponta para a secao {alvo},"
                              f" que nao existe em {readme.name}")
                continue
            if secoes_en is not None and alvo not in secoes_en:
                falhas.append(f"{rel}: secao {alvo} existe no pt e nao no en")
            if not titulo:
                sem_titulo += 1
                continue
            if _norm(titulo) != _norm(secoes[alvo]):
                falhas.append(
                    f'{rel}: aponta para a secao {alvo} "{titulo}",'
                    f' e a secao {alvo} chama-se "{secoes[alvo]}"')
    for f in falhas:
        print(f"  {f}")
    print(f"  {conferidos} ponteiro(s) de fonte para secao conferido(s),"
          f" {conferidos - sem_titulo} com titulo; {len(falhas)} pendurado(s)")
    return bool(falhas)


def autoteste():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        r = pathlib.Path(d)
        pt = ("# T\n## 4. Impl\n### 4.1 Contabilizacao do cache\n"
              "A funcao `relatar_pool()` delimita o indice.\n"
              "### 4.2 Conceito\nSo prosa, com `nice` em crase.\n")
        en = ("# T\n## 4. Impl\n### 4.1 Cache accounting\n"
              "The `relatar_pool()` function bounds the index.\n"
              "### 4.2 Concept\nJust prose.\n")
        (r / "README.md").write_text(pt)
        (r / "README.en.md").write_text(en)
        (r / "a.c").write_text(
            '/* Ver README.md secao 4.1 "Contabilizacao do cache". */\n')
        if verificar(r):
            print("  AUTOTESTE FALHOU: ponteiro com titulo correto foi acusado")
            return True

        # RENUMERACAO: a secao 4.1 existe e passou a ser outra.
        (r / "README.md").write_text(pt.replace(
            "### 4.1 Contabilizacao do cache", "### 4.1 Outra coisa"))
        if not verificar(r):
            print("  AUTOTESTE FALHOU: secao renumerada passou despercebida")
            return True
        (r / "README.md").write_text(pt)

        # Acento e caixa nao contam: o comentario do fonte nao usa acento.
        (r / "README.md").write_text(pt.replace(
            "### 4.1 Contabilizacao do cache", "### 4.1 Contabilização do Cache"))
        if verificar(r):
            print("  AUTOTESTE FALHOU: diferenca de acento foi tratada como deriva")
            return True
        (r / "README.md").write_text(pt)

        # Secao conceitual apontada COM titulo: conferida igual, sem heuristica.
        (r / "a.c").write_text('/* Ver secao 4.2 "Conceito". */\n')
        if verificar(r):
            print("  AUTOTESTE FALHOU: secao sem identificador foi acusada")
            return True

        # Secao inexistente.
        (r / "a.c").write_text('/* Ver README.md secao 9.9 "Nada". */\n')
        if not verificar(r):
            print("  AUTOTESTE FALHOU: secao inexistente passou despercebida")
            return True

        # Ponteiro quebrado em duas linhas continua sendo COM titulo.
        (r / "a.c").write_text(
            '/* Ver README.md secao 4.1\n'
            ' * "Contabilizacao do cache". */\n')
        if verificar(r):
            print("  AUTOTESTE FALHOU: ponteiro quebrado em duas linhas"
                  " foi acusado")
            return True
        import io as _io
        _saida = _io.StringIO()
        _ant = sys.stdout
        sys.stdout = _saida
        verificar(r)
        sys.stdout = _ant
        if "1 com titulo" not in _saida.getvalue():
            print("  AUTOTESTE FALHOU: ponteiro quebrado foi contado"
                  " como sem titulo")
            return True

        # Ponteiro SEM titulo: aceito, e contado a parte.
        (r / "a.c").write_text("/* Ver README.md secao 4.1. */\n")
        if verificar(r):
            print("  AUTOTESTE FALHOU: ponteiro sem titulo foi acusado")
            return True

        # Ponteiro em string, nao em comentario: nao e ponteiro.
        (r / "a.c").write_text('const char *s = "secao 9.9";\n')
        if verificar(r):
            print("  AUTOTESTE FALHOU: texto fora de comentario foi lido"
                  " como ponteiro")
            return True
    print("  autoteste ok: acusa secao inexistente e renumerada, tolera acento"
          " e caixa, aceita ponteiro sem titulo e texto fora de comentario")
    return False


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else _raiz()) else 0)
