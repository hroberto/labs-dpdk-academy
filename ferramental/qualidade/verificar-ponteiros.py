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
2. Para o ponteiro LOCAL -- aquele cujo README esta no mesmo diretorio do fonte
   -- a secao apontada tem de CITAR pelo menos um identificador que existe
   nesse fonte. E o teste de bidirecionalidade, e e ele que pega a renumeracao:
   uma secao 4.3 que virou outra coisa nao fala mais de `relatar_mempool`.

   O ponteiro CONCEITUAL -- o que sobe para o documento do modulo, como o
   `custo-paralelismo.c` apontando para a secao de SMT -- so e conferido quanto
   a existencia. A primeira versao deste verificador exigia identificador
   tambem nesse caso e acusou dois ponteiros corretos: secoes que explicam
   orcamento por pacote e SMT nao citam identificador nenhum porque nao
   descrevem codigo. Exigir bidirecionalidade delas seria pedir que o documento
   conceitual falasse de implementacao para satisfazer o portao.

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
import sys

IGNORAR = {".git", "build", "builddir", "build-precommit", "subprojects",
           "temp", "__pycache__", "alternativas"}
FONTES = (".c", ".h", ".cpp", ".hpp")

# "README.md secao 4.3", "ver secao 6.5", "secao 5.1"
PONTEIRO = re.compile(r"(?:se[cç][aã]o|section)\s+(\d+(?:\.\d+)*)", re.I)
TITULO = re.compile(r"^#{2,6}\s+(\d+(?:\.\d+)*)[.\s]")
IDENT = re.compile(r"`([A-Za-z_][A-Za-z0-9_]{2,}(?:\(\))?)`")


def _raiz():
    return pathlib.Path(__file__).resolve().parents[2]


def _secoes(md):
    """Mapeia prefixo numerico -> corpo da secao, ate o proximo titulo."""
    out, atual, corpo = {}, None, []
    for linha in md.splitlines():
        m = TITULO.match(linha)
        if m:
            if atual:
                out[atual] = "\n".join(corpo)
            atual, corpo = m.group(1), []
        elif atual:
            corpo.append(linha)
    if atual:
        out[atual] = "\n".join(corpo)
    return out


def _comentarios(texto):
    """So o que esta dentro de comentario -- um ponteiro em string nao conta."""
    blocos = re.findall(r"/\*.*?\*/", texto, re.S)
    blocos += re.findall(r"//[^\n]*", texto)
    return "\n".join(blocos)


def verificar(raiz):
    raiz = pathlib.Path(raiz)
    falhas, conferidos = [], 0
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
            falhas.append(f"{rel}: aponta para secao {', '.join(alvos)}"
                          " e nao ha README.md no diretorio nem acima")
            continue
        secoes = _secoes(readme.read_text(encoding="utf-8"))
        en = readme.parent / "README.en.md"
        secoes_en = _secoes(en.read_text(encoding="utf-8")) if en.exists() else None
        for alvo in alvos:
            conferidos += 1
            if alvo not in secoes:
                falhas.append(f"{rel}: aponta para a secao {alvo},"
                              f" que nao existe em {readme.name}")
                continue
            if secoes_en is not None and alvo not in secoes_en:
                falhas.append(f"{rel}: secao {alvo} existe no pt e nao no en")
            if readme.parent != src.parent:
                continue  # ponteiro conceitual: so existencia
            idents = set(IDENT.findall(secoes[alvo]))
            if not any(i.rstrip("()") in texto for i in idents):
                falhas.append(
                    f"{rel}: a secao {alvo} nao cita nenhum identificador"
                    f" deste fonte -- ponteiro provavelmente pendurado")
    for f in falhas:
        print(f"  {f}")
    print(f"  {conferidos} ponteiro(s) de fonte para secao conferido(s);"
          f" {len(falhas)} pendurado(s)")
    return bool(falhas)


def autoteste():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        r = pathlib.Path(d)
        (r / "README.md").write_text(
            "# T\n## 4. Impl\n### 4.1 Campos\n"
            "A funcao `relatar_pool()` delimita o indice.\n")
        (r / "README.en.md").write_text(
            "# T\n## 4. Impl\n### 4.1 Fields\n"
            "The `relatar_pool()` function bounds the index.\n")
        (r / "a.c").write_text(
            "/* Ver README.md secao 4.1. */\nvoid relatar_pool(void) {}\n")
        if verificar(r):
            print("  AUTOTESTE FALHOU: ponteiro correto foi acusado")
            return True

        # Renumeracao: a secao existe, e passou a falar de outra coisa.
        (r / "README.md").write_text(
            "# T\n## 4. Impl\n### 4.1 Outra coisa\n"
            "Nada a ver, fala de `outra_funcao()`.\n")
        if not verificar(r):
            print("  AUTOTESTE FALHOU: secao renumerada passou despercebida")
            return True

        # Secao inexistente.
        (r / "a.c").write_text("/* Ver README.md secao 9.9. */\n")
        if not verificar(r):
            print("  AUTOTESTE FALHOU: secao inexistente passou despercebida")
            return True

        # Ponteiro conceitual (README acima do fonte): so existencia.
        # O `a.c` volta ao estado bom para que a falha, se houver, seja do b.c.
        (r / "a.c").write_text(
            "/* Ver README.md secao 4.1. */\nvoid relatar_pool(void) {}\n")
        (r / "README.md").write_text(
            "# T\n## 4. Impl\n### 4.1 Campos\n"
            "A funcao `relatar_pool()` delimita o indice.\n")
        (r / "sub").mkdir()
        (r / "sub" / "b.c").write_text("/* Ver secao 4.1 do modulo. */\n")
        if verificar(r):
            print("  AUTOTESTE FALHOU: ponteiro conceitual exigiu identificador")
            return True
        (r / "sub" / "b.c").unlink()
        (r / "sub").rmdir()

        # Ponteiro em string, nao em comentario: nao e ponteiro.
        (r / "a.c").write_text('const char *s = "secao 9.9";\n')
        if verificar(r):
            print("  AUTOTESTE FALHOU: texto fora de comentario foi lido"
                  " como ponteiro")
            return True
    print("  autoteste ok: acusa secao inexistente e renumerada, aceita"
          " ponteiro correto e conceitual, ignora texto fora de comentario")
    return False


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else _raiz()) else 0)
