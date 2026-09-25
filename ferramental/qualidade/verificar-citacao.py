#!/usr/bin/env python3
"""Confere que o `CITATION.cff` ainda descreve o repositório que ele afirma descrever.

POR QUE ESTE VERIFICADOR NASCEU JUNTO COM O ARQUIVO

O `CITATION.cff` foi criado depois de um argumento contra ele: metadado
estruturado é mais um lugar onde um fato é DIGITADO, e este repositório já
pagou duas vezes por fato duplicado -- a paridade pt/en precisou de portão, e a
divergência de rótulos bibliográficos precisou de outro.

A evidência que fechou a questão era fresca. A §4.1 publica 10,40 ns para a
diferença de tradução; a execução seguinte, em máquina ociosa, deu 10,90 --
dentro da faixa, e ainda assim um YAML congelado teria envelhecido em silêncio.

Então o arquivo só entrou com a regra que o confere junto. As quatro
conferências abaixo são as afirmações que o `.cff` faz sobre o repositório e
que MUDAM sozinhas, sem que ninguém reabra o arquivo:

    version         <- a tag mais recente muda a cada release
    date-released   <- idem
    license         <- o SPDX declarado precisa bater com o LICENSE de fato
    repository-code <- a URL muda se o repositório for renomeado ou recriado

A QUINTA ENTROU DEPOIS, PORQUE A DIVERGÊNCIA SOBREVIVEU A DUAS RELEASES

    meson.build     <- a `version` do projeto Meson, que aparece no banner do
                       build e é o número que o leitor vê ao compilar

O `meson.build` declarava `1.02.01` enquanto o `.cff` e a tag diziam `0.0x`.
Ninguém consome `meson.project_version()` no projeto, então nada quebrava -- e é
justamente por isso que a divergência atravessou a 0.06.00 e a 0.07.00 sem ser
notada. Um número que só é lido por humanos não tem quem o confira, a menos que
alguém escreva a conferência.

A QUARTA É A QUE JUSTIFICA O ARQUIVO INTEIRO

Um metadado de citação com URL errada é pior que a ausência dele: ele manda o
leitor, com autoridade de arquivo padronizado, para um endereço que não existe.
E o caso não é hipotético -- este repositório foi apagado e republicado para
remover endereços de e-mail pessoais da história, e renomear era uma das
mudanças em discussão no mesmo dia.

A ORDEM DAS OPERAÇÕES NUMA TAG NOVA, e ela não é a intuitiva

Este verificador compara `version` com a TAG DE MAIOR VERSÃO já existente.
Enquanto a tag não existe, ele acusa divergência -- e a tag não pode existir
antes do commit que ela aponta. A sequência que funciona é:

    1. bumpar `version` e `date-released` no CITATION.cff
    2. commitar (o portão acusa a divergência; é esperado)
    3. criar a tag assinada sobre esse commit
    4. rodar o portão de novo: agora passa

O passo 2 é o único do projeto em que o portão fica vermelho por construção.
Quem não souber disso desiste do bump ou edita o verificador -- e as duas
saídas são piores que a espera de um comando.

O QUE ELE NÃO CONFERE

Se o texto do `abstract` continua verdadeiro. Isso é semântica, nenhum padrão
sintático decide, e a garantia ali é humana -- a mesma ressalva que o
verificador de paridade já declara no próprio cabeçalho.

Nem a grafia do nome do autor contra o registro ORCID. O identificador resolve
independentemente da grafia, e conferi-lo exigiria rede -- o que um portão de
pre-commit não deve exigir. O alinhamento foi feito a mão em 2026-09-23, com o
registro público como referência, e está declarado no próprio CITATION.cff.
"""
import os
import re
import subprocess
import sys

OBRIGATORIOS = ("cff-version", "message", "title", "authors", "type",
                "repository-code", "license", "version", "date-released")


def git(args, repo):
    r = subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True)
    return r.stdout.strip()


def tag_mais_recente(repo):
    """A tag de maior versão, não a mais recente no tempo.

    `--sort=-creatordate` erra quando uma tag antiga é recriada -- foi
    exatamente o que aconteceu aqui: v0.01.00 e v1.00.00 foram refeitas para
    limpar o campo `tagger`, e passaram a ser as MAIS NOVAS do repositório.
    """
    tags = git(["tag"], repo).split()
    if not tags:
        return None
    def chave(t):
        return [int(p) for p in re.findall(r"\d+", t)] or [0]
    return max(tags, key=chave)


def verificar(raiz="."):
    caminho = os.path.join(raiz, "CITATION.cff")
    if not os.path.exists(caminho):
        print("  CITATION.cff ausente")
        return 1
    try:
        import yaml
    except ImportError:
        print("  CITATION.cff: PyYAML ausente, conferência pulada")
        return 0

    try:
        d = yaml.safe_load(open(caminho, encoding="utf-8"))
    except Exception as e:
        print(f"  CITATION.cff: YAML inválido -- {e}")
        return 1

    problemas = 0
    for campo in OBRIGATORIOS:
        if not d.get(campo):
            print(f"  CITATION.cff: campo obrigatório ausente -> {campo}")
            problemas += 1
    if problemas:
        return problemas

    tag = tag_mais_recente(raiz)
    if tag:
        esperada = tag.lstrip("v")
        if str(d["version"]) != esperada:
            print(f"  CITATION.cff: version '{d['version']}' != tag mais recente '{tag}'")
            problemas += 1
        data = git(["log", "-1", "--format=%ad", "--date=short", tag], raiz)
        if data and str(d["date-released"]) != data:
            print(f"  CITATION.cff: date-released '{d['date-released']}' != data de {tag} ({data})")
            problemas += 1

    # A `version` do Meson contra a mesma fonte de verdade. Ela é comparada com o
    # `.cff`, e não com a tag: numa release em andamento os dois já estão à
    # frente da tag, e cobrar a tag aqui produziria a MESMA divergência esperada
    # duas vezes, o que ensina a ignorar o portão.
    mb = os.path.join(raiz, "meson.build")
    if os.path.exists(mb):
        texto = open(mb, encoding="utf-8").read()
        m = re.search(r"^\s*version\s*:\s*['\"]([^'\"]+)['\"]", texto, re.M)
        if m is None:
            print("  meson.build: não achei a `version` do projeto")
            problemas += 1
        elif m.group(1) != str(d["version"]):
            print(f"  meson.build: version '{m.group(1)}' != CITATION.cff "
                  f"('{d['version']}')")
            problemas += 1

    spdx = None
    lic = os.path.join(raiz, "LICENSE")
    if os.path.exists(lic):
        primeira = open(lic, encoding="utf-8").readline().strip()
        spdx = {"MIT License": "MIT"}.get(primeira, primeira)
        if spdx and d["license"] != spdx:
            print(f"  CITATION.cff: license '{d['license']}' != LICENSE ('{primeira}')")
            problemas += 1

    url = git(["remote", "get-url", "origin"], raiz)
    if url:
        # git@host:dono/nome.git  e  https://host/dono/nome.git  -> dono/nome
        slug = re.sub(r"\.git$", "", re.sub(r"^(?:git@[^:]+:|https?://[^/]+/)", "", url))
        if slug and slug not in d["repository-code"]:
            print(f"  CITATION.cff: repository-code '{d['repository-code']}' "
                  f"não corresponde ao remoto '{slug}'")
            problemas += 1

    print(f"\n  CITATION.cff: {len(OBRIGATORIOS)} campo(s) obrigatório(s), "
          f"versão/data/licença/URL/meson conferidas, {problemas} divergência(s)")
    return problemas


def autoteste():
    import io
    import shutil
    import tempfile
    from contextlib import redirect_stdout

    BASE = """cff-version: 1.2.0
message: cite
title: t
type: software
authors:
  - given-names: A
    family-names: B
repository-code: "https://github.com/dono/nome"
license: MIT
version: 1.02.01
date-released: "%s"
"""
    falhas = 0

    def repo(cff, tag="v1.02.01", licenca="MIT License\n", remoto="git@github.com:dono/nome.git",
             meson=None):
        d = tempfile.mkdtemp()
        amb = dict(os.environ, GIT_AUTHOR_NAME="T", GIT_COMMITTER_NAME="T",
                   GIT_AUTHOR_EMAIL="t@x", GIT_COMMITTER_EMAIL="t@x")
        subprocess.run(["git", "-C", d, "init", "-q", "-b", "m"], capture_output=True)
        open(os.path.join(d, "LICENSE"), "w").write(licenca)
        if cff is not None:
            open(os.path.join(d, "CITATION.cff"), "w").write(cff)
        if meson is not None:
            open(os.path.join(d, "meson.build"), "w").write(
                "project('t', 'c',\n  version : '%s',\n)\n" % meson)
        subprocess.run(["git", "-C", d, "add", "-A"], capture_output=True)
        subprocess.run(["git", "-C", d, "commit", "-q", "-m", "x"], env=amb, capture_output=True)
        if tag:
            # `-a -m`: com `tag.gpgsign` ligado no ambiente, `git tag <nome>` sem
            # mensagem falha com "no tag message?" -- e a tag simplesmente NÃO
            # nasce. Os casos 1 e 3 passavam a vazio por causa disso: o
            # verificador pulava a conferência de versão por não achar tag
            # nenhuma, e o verde era indistinguível do verde legítimo.
            subprocess.run(["git", "-C", d, "tag", "-a", "-m", "t", tag],
                           env=amb, capture_output=True)
        subprocess.run(["git", "-C", d, "remote", "add", "origin", remoto], capture_output=True)
        return d

    def data_do_commit(d):
        return git(["log", "-1", "--format=%ad", "--date=short"], d)

    def caso(numero, descricao, d, esperado):
        nonlocal falhas
        buf = io.StringIO()
        with redirect_stdout(buf):
            n = verificar(d)
        ok = (n == 0) if esperado == 0 else (n >= 1)
        if not ok:
            print(f"  AUTOTESTE {numero} FALHOU: {descricao} (n={n})")
            print("    " + buf.getvalue().strip().replace("\n", "\n    "))
            falhas += 1
        shutil.rmtree(d, ignore_errors=True)

    d0 = repo(None); hoje = data_do_commit(d0); shutil.rmtree(d0, ignore_errors=True)
    bom = BASE % hoje

    # 1/2. O arquivo precisa existir e ser YAML.
    caso(1, "CITATION.cff correto acusado", repo(bom), 0)
    caso(2, "CITATION.cff ausente passou", repo(None), 1)

    # 3. O caso mais provável no dia a dia: taggeou e esqueceu de subir a versão.
    caso(3, "version defasada em relação à tag passou",
         repo(bom, tag="v1.03.00"), 1)

    # 4. Licença: o `.cff` afirmando MIT sobre um LICENSE que não é MIT manda
    #    quem reutiliza o material confiar num termo errado.
    caso(4, "license divergente do LICENSE passou",
         repo(bom, licenca="Apache License\n"), 1)

    # 5. O CASO QUE JUSTIFICA O ARQUIVO. URL apontando para outro repositório:
    #    o leitor é mandado, com autoridade de metadado padronizado, para um
    #    endereço que não é este. Renomear ou recriar o repositório produz
    #    exatamente isso, e foi discutido no mesmo dia em que o arquivo nasceu.
    caso(5, "repository-code apontando para outro repositório passou",
         repo(bom, remoto="git@github.com:outro/projeto.git"), 1)

    # 6. Campo obrigatório ausente: sem `authors` o arquivo não responde a
    #    pergunta para a qual ele existe.
    caso(6, "CITATION.cff sem authors passou",
         repo(re.sub(r"authors:\n  - given-names: A\n    family-names: B\n", "", bom)), 1)

    # 6b/6c. A `version` do Meson. A do `.cff` no BASE é 1.02.01, então um
    #        meson.build com outro número tem de acusar, e com o mesmo tem de
    #        passar. Sem o segundo caso, um verificador que acusasse SEMPRE
    #        passaria no primeiro.
    caso("6b", "meson.build com version divergente passou",
         repo(bom, meson="9.99.99"), 1)
    caso("6c", "meson.build alinhado acusado",
         repo(bom, meson="1.02.01"), 0)

    # 7. A ORDENAÇÃO DAS TAGS. `--sort=-creatordate` daria v1.00.00 aqui, porque
    #    ela foi RECRIADA depois -- e foi o que de fato aconteceu neste
    #    repositório, ao limpar o campo `tagger`. A tag mais nova no tempo não é
    #    a maior versão, e confundir as duas acusa um arquivo correto.
    d = repo(bom, tag="v1.02.01")
    subprocess.run(["git", "-C", d, "tag", "-a", "-m", "t", "v1.00.00"],
                   env=dict(os.environ, GIT_COMMITTER_NAME="T", GIT_COMMITTER_EMAIL="t@x"),
                   capture_output=True)
    caso(7, "tag recriada tratada como a mais recente", d, 0)

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else ".") else 0)
