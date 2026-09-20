#!/usr/bin/env python3
"""Impede que endereço de e-mail pessoal entre na história do repositório.

POR QUE ESTE ARQUIVO EXISTE

A regra "commits usam o endereço `noreply` do GitHub, nunca o pessoal" já tinha
sido decidida e já tinha sido aplicada a uma correção anterior. Mesmo assim,
**quatro commits de merge e duas tags anotadas voltaram a carregar o endereço
real** -- e ficaram publicados em `origin/main` por dias, até uma auditoria de
exposição tropeçar neles.

A causa diz tudo sobre por que a regra escrita não bastava:

    autor:     <endereco-pessoal-redigido>
    committer: noreply@github.com          <- GitHub, não a máquina local

O `git config` local estava CORRETO o tempo todo. Os quatro commits não nasceram
aqui: nasceram no botão "Merge pull request" da interface web, que usa o
endereço do **perfil da conta**, não o do `git config`. Uma regra que só existe
na cabeça de quem digita `git commit` não alcança o caminho que não passa por
`git commit`.

As duas tags escaparam por um segundo caminho: `git tag -a` grava o campo
`tagger`, que nenhuma revisão de código jamais olha.

O QUE ESTE VERIFICADOR COBRE, E O QUE NÃO

Cobre os três campos de identidade que o git grava e que ninguém lê: `author`,
`committer` e `tagger`, em **toda** a história alcançável -- não só nos commits
recentes, porque o incidente foi descoberto meses depois do fato.

NÃO cobre a origem: ele acusa depois que o objeto existe. A prevenção real é a
configuração da conta (*Keep my email addresses private* + *Block command line
pushes that expose my email*), que vive no GitHub e fora do alcance de qualquer
script daqui. Este verificador é a rede embaixo dela, não o substituto -- e a
distinção importa, porque um objeto já empurrado não se apaga sozinho: hash
órfão continua acessível por SHA no GitHub até a limpeza ser pedida ao suporte.

A LISTA DE PERMITIDOS É POSITIVA, DE PROPÓSITO

Procurar "o endereço pessoal conhecido" só acha o endereço que já se conhece. A
lista é do que PODE aparecer, e qualquer outra coisa acusa -- inclusive um
endereço pessoal novo, que é exatamente o caso que uma lista negativa perde.
"""
import os
import re
import subprocess
import sys

PERMITIDOS = re.compile(r"^(?:[\w.+-]+@users\.noreply\.github\.com|noreply@github\.com)$")
# `tagger`/`author`/`committer` gravam `Nome <email> timestamp fuso`.
CAMPO = re.compile(r"^(author|committer|tagger) .*<([^>]*)>", re.M)

# O SEGUNDO ALCANCE, e ele nasceu de um erro deste mesmo verificador.
#
# A primeira versao conferia so os CAMPOS de identidade. Ela passou verde sobre
# o commit que documentava o incidente -- porque a mensagem desse commit citava
# o endereco vazado no corpo do texto, e o docstring deste arquivo tambem. O
# endereco foi republicado dentro da explicacao de como ele tinha sido
# removido, e quem achou foi uma varredura bruta por string, nao o portao.
#
# Dai a regra: em CORPO de mensagem e em CONTEUDO de arquivo, qualquer coisa
# com forma de e-mail acusa, salvo os dominios reservados para exemplo.
EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
# RFC 2606 reserva example.*/.invalid/.test justamente para texto e teste. A
# lista e SEPARADA da de campos de proposito: um `alguem@example.com` PRECISA
# ser recusado como autoria e PRECISA ser aceito como exemplo escrito.
# A primeira versão desta lista acusou 138 ocorrências, das quais 136 eram
# legítimas: `noreply@anthropic.com` é o trailer de atribuição de TODO commit,
# e `git@github.com` é a forma de URL SSH, não endereço de ninguém. Um portão
# que grita 136 vezes por engano é um portão que se desliga na segunda vez.
NAO_PESSOAL = re.compile(
    r"^(?:noreply|no-reply)@"            # qualquer noreply é, por definição, de ninguém
    r"|^git@"                            # `git@host:dono/repo` -- URL SSH
    r"|@[\w.-]*\bnoreply\.[\w.-]+$"    # users.noreply.github.com e parentes
    r"|@(?:example|exemplo)\.(?:com|org|net)$"   # RFC 2606: reservados para texto
    r"|@[\w-]+\.(?:invalid|test|localhost)$")


def git(args, repo):
    return subprocess.run(["git", "-C", repo] + args,
                          capture_output=True, text=True).stdout


def verificar(repo="."):
    # `--branches --tags`, NÃO `--all`. A diferença são os refs de rastreamento
    # `origin/*`, e ela é a diferença entre um portão usável e um inútil:
    # enquanto o remoto ainda está sujo, `--all` reprova o próprio commit que
    # o conserta, e a saída é desligar o portão -- que é o desfecho que todo
    # verificador barulhento tem.
    #
    # O escopo certo é o que ESTA máquina vai empurrar. O remoto é consequência
    # disso, e aparece abaixo como aviso que não bloqueia.
    objetos = []
    for c in git(["rev-list", "--branches", "--tags"], repo).split():
        objetos.append(("commit " + c[:9], git(["cat-file", "-p", c], repo)))
    for t in git(["tag"], repo).split():
        if git(["cat-file", "-t", t], repo).strip() == "tag":
            objetos.append(("tag " + t, git(["cat-file", "-p", t], repo)))

    problemas = 0
    for onde, bruto in objetos:
        # O corpo da mensagem pode conter a palavra "author"; só o cabeçalho
        # conta, e ele termina na primeira linha em branco.
        cabecalho = bruto.split("\n\n", 1)[0]
        for campo, email in CAMPO.findall(cabecalho):
            if not PERMITIDOS.match(email):
                print(f"  {onde}: {campo} expõe <{email}>")
                problemas += 1

        # Corpo da mensagem: o caminho que escapou da primeira versao.
        corpo = bruto.split("\n\n", 1)[1] if "\n\n" in bruto else ""
        for email in dict.fromkeys(EMAIL.findall(corpo)):
            if not NAO_PESSOAL.search(email):
                print(f"  {onde}: mensagem cita <{email}>")
                problemas += 1

    # Conteúdo versionado. Só a árvore de HEAD: para PREVENIR basta o estado
    # atual, e varrer toda a história a cada commit custaria o que ninguém
    # paga todo dia -- um portão caro é um portão que alguém desliga.
    # ÁRVORE DE TRABALHO, não HEAD. Um portão que lê HEAD relata o estado
    # ANTERIOR: ele reprova a correção que ainda não foi commitada e aprova o
    # defeito que acabou de ser escrito. Para PREVENIR, o que vale é o que está
    # prestes a entrar. Em repositório bare não há árvore, e aí HEAD é o que há.
    padrao = r"[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}"
    bare = git(["rev-parse", "--is-bare-repository"], repo).strip() == "true"
    saida = git(["grep", "-I", "-n", "-E", padrao] + (["HEAD"] if bare else []), repo)
    vistos = set()
    for linha in saida.splitlines():
        for email in EMAIL.findall(linha):
            if not NAO_PESSOAL.search(email) and email not in vistos:
                vistos.add(email)
                print(f"  {linha.split(':')[1] if ':' in linha else '?'}: conteúdo cita <{email}>")
                problemas += 1

    # O remoto, como aviso: saber que ele está sujo importa, bloquear por causa
    # dele impede a correção.
    sujos = 0
    for c in git(["rev-list", "--remotes"], repo).split():
        bruto = git(["cat-file", "-p", c], repo)
        cab = bruto.split("\n\n", 1)[0]
        corpo = bruto.split("\n\n", 1)[1] if "\n\n" in bruto else ""
        achados = [e for _, e in CAMPO.findall(cab)] + EMAIL.findall(corpo)
        if any(not NAO_PESSOAL.search(e) and not PERMITIDOS.match(e) for e in achados):
            sujos += 1
    if sujos:
        print(f"  aviso: {sujos} commit(s) em refs de rastreamento (origin/*) "
              f"ainda expõem endereço -- o remoto precisa ser reescrito")

    print(f"\n  {len(objetos)} objeto(s) de história e a árvore versionada conferidos, "
          f"{problemas} ocorrência(s) de endereço pessoal")
    return problemas


def autoteste():
    import tempfile
    falhas = 0

    def repo_com(email, tag_email=None):
        d = tempfile.mkdtemp()
        amb = dict(os.environ, GIT_AUTHOR_NAME="T", GIT_COMMITTER_NAME="T",
                   GIT_AUTHOR_EMAIL=email, GIT_COMMITTER_EMAIL=email)
        for cmd in (["init", "-q", "-b", "m"], ["commit", "-q", "--allow-empty", "-m", "x"]):
            subprocess.run(["git", "-C", d] + cmd, env=amb, capture_output=True)
        if tag_email:
            amb2 = dict(amb, GIT_COMMITTER_EMAIL=tag_email)
            subprocess.run(["git", "-C", d, "tag", "-a", "v1", "-m", "t"],
                           env=amb2, capture_output=True)
        return d

    def caso(numero, descricao, repo, esperado):
        nonlocal falhas
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with redirect_stdout(buf):
            n = verificar(repo)
        ok = (n == 0) if esperado == 0 else (n >= 1)
        if not ok:
            print(f"  AUTOTESTE {numero} FALHOU: {descricao} (n={n})")
            print("    " + buf.getvalue().strip().replace("\n", "\n    "))
            falhas += 1

    NOREPLY = "9491372+hroberto@users.noreply.github.com"
    # Endereço "pessoal" de teste montado em PEDAÇOS de propósito: escrito
    # inteiro, a varredura de conteúdo deste próprio arquivo o acusaria --
    # a mesma armadilha auto-referente que já mordeu este repositório,
    # quando um autoteste procurava uma string no fonte e casava com o
    # literal da própria busca.
    PESSOAL = "vazou" + "@" + "provedor" + "." + "net"

    # 1/2. O caso central: endereço pessoal em author/committer.
    caso(1, "endereço noreply acusado", repo_com(NOREPLY), 0)
    caso(2, "endereço pessoal passou", repo_com("alguem@example.com"), 1)

    # 3. O SEGUNDO CAMINHO DE FUGA. As duas tags do incidente escaparam pelo
    #    campo `tagger`, que nenhuma revisão de código olha. Sem este caso, um
    #    verificador que cheque só commits fica verde com a tag suja.
    caso(3, "tagger com endereço pessoal passou",
         repo_com(NOREPLY, tag_email="alguem@example.com"), 1)

    # 4. O committer do GitHub é legítimo: os merges pela interface web gravam
    #    `noreply@github.com` aqui, e acusá-lo tornaria o portão inútil na
    #    prática -- ninguém mantém um verificador que acusa o caminho normal.
    caso(4, "committer noreply@github.com acusado", repo_com("noreply@github.com"), 0)

    # 5. LISTA POSITIVA, e este caso é o que prova a escolha: um endereço
    #    pessoal NOVO, que nenhuma lista negativa conteria, precisa acusar.
    caso(5, "endereço pessoal desconhecido passou", repo_com("outro@example.org"), 1)

    # 6/7. OS DOIS CAMINHOS QUE A PRIMEIRA VERSÃO NÃO VIA, e que não são
    #      hipotéticos: foi assim que o endereço voltou a ser publicado, dentro
    #      do commit que explicava como ele tinha sido removido.
    d = repo_com(NOREPLY)
    subprocess.run(["git", "-C", d, "commit", "-q", "--allow-empty", "-m",
                    "doc\n\n    autor: " + PESSOAL + "\n"],
                   env=dict(os.environ, GIT_AUTHOR_NAME="T", GIT_COMMITTER_NAME="T",
                            GIT_AUTHOR_EMAIL=NOREPLY, GIT_COMMITTER_EMAIL=NOREPLY),
                   capture_output=True)
    caso(6, "endereço no CORPO da mensagem passou", d, 1)

    d = repo_com(NOREPLY)
    open(os.path.join(d, "doc.md"), "w").write("contato: " + PESSOAL + "\n")
    amb = dict(os.environ, GIT_AUTHOR_NAME="T", GIT_COMMITTER_NAME="T",
               GIT_AUTHOR_EMAIL=NOREPLY, GIT_COMMITTER_EMAIL=NOREPLY)
    subprocess.run(["git", "-C", d, "add", "-A"], capture_output=True)
    subprocess.run(["git", "-C", d, "commit", "-q", "-m", "x"], env=amb, capture_output=True)
    caso(7, "endereço em ARQUIVO versionado passou", d, 1)

    # 8. E o contrapeso, sem o qual o portão vira ritual: os autotestes DESTE
    #    arquivo escrevem endereços de propósito, e um portão que se acusa
    #    sozinho é desligado na primeira semana. Domínio reservado passa.
    d = repo_com(NOREPLY)
    open(os.path.join(d, "doc.md"), "w").write("veja alguem@example.com\n")
    subprocess.run(["git", "-C", d, "add", "-A"], capture_output=True)
    subprocess.run(["git", "-C", d, "commit", "-q", "-m", "x"], env=amb, capture_output=True)
    caso(8, "endereço de exemplo (RFC 2606) acusado", d, 0)

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else ".") else 0)
