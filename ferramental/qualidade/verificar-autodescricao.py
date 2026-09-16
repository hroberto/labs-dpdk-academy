#!/usr/bin/env python3
"""Confere afirmações que o material faz SOBRE SI MESMO.

POR QUE ISTO EXISTE

As duas afirmações mais fáceis de deixar envelhecer são as que o projeto faz a
respeito do próprio projeto. Elas não saem de medição nenhuma, ninguém as
reexecuta, e o texto continua dizendo o que era verdade no dia em que foi
escrito. Dois casos reais, encontrados em 15/09/2026:

- `trilha/02-pipeline/01-rx-tx-burst/README.md` carregava o banner "**Esqueleto.**
  Registra escopo e compromissos; o conteúdo ainda não foi escrito" -- em 268
  linhas, das quais cerca de 200 eram verificação de ambiente e capacidades de
  NIC medidas com ferramenta real. O documento mentia sobre si para menos;

- `README.md` declarava como requisito "Linux x86_64 **ou arm64**", enquanto
  quatro programas de medição chamavam `__builtin_ia32_pause()` em doze pontos
  sem nenhuma guarda de arquitetura. Em arm64 não compilam. O documento
  prometia uma plataforma que o código não sustentava.

Nenhum dos dois é detectável por quem lê o documento: o primeiro exige contar
linhas, o segundo exige cruzar a porta de entrada com o código. As duas contas
são triviais para um programa e improváveis para uma pessoa.

REGRA 1 -- banner de esqueleto contra conteúdo real

Um documento que se declara esqueleto e tem mais que LIMITE_ESQUELETO linhas de
conteúdo (fora banner, navegação e linhas vazias) falha. O limite é folgado de
propósito: um esqueleto legítimo registra objetivo, escopo e entregáveis, e isso
cabe com sobra.

REGRA 2 -- plataforma prometida contra guarda no código

Arquivo de código que usa construto específico de arquitetura precisa conter
guarda de arquitetura. A guarda pode ser direta (`__x86_64__`, `__aarch64__`) ou
vir do cabeçalho do projeto que encapsula a escolha (`cpu_pause.h`).

O QUE ELE DELIBERADAMENTE NÃO PEGA:

- promessa de plataforma em outros documentos que não o `README.md`;
- construto específico de arquitetura que o compilador aceite em ambas mas se
  comporte diferente (não é sobre compilar, é sobre semântica);
- banner de esqueleto ausente em documento que DEVERIA tê-lo -- o inverso desta
  regra, que exige julgar o que é conteúdo suficiente;
- afirmações do material sobre si que não sejam o censo da regra 3 (níveis de
  teste, cobertura de módulo, estado de uma etapa).

REGRA 3 -- o censo de esqueletos que o ROADMAP publica

O `ROADMAP.md` declara, em uma frase, QUANTOS documentos ainda são esqueletos,
de um TOTAL, e entre que TAMANHOS. São quatro números derivados do disco, e o
disco muda toda semana enquanto o texto não muda nunca.

Em 15/09/2026 essa frase dizia "7 dos 19 documentos ainda são esqueletos, de 62
a 98 linhas". O disco dizia 6, 21, 62 e 132: os quatro números estavam errados
ao mesmo tempo. E o defeito é mais feio do que parece -- quatro linhas abaixo, o
próprio parágrafo oferece os comandos para reconferir, com o aviso de que
"contagens envelhecem em silêncio, e estas já envelheceram uma vez". Havia
ceticismo declarado e nenhuma verificação executando: a intenção certa sem o
mecanismo, que é como a contagem envelheceu a segunda vez.

A regra roda os mesmos comandos que o parágrafo publica e compara com o que ele
afirma. A partir daqui a frase não pode envelhecer sem a suíte ficar vermelha.
"""
import os
import re
import sys

IGNORAR = {".git", "build", "subprojects", "__pycache__", "temp"}

LIMITE_ESQUELETO = 80

BANNER = re.compile(r"^>\s*\*\*Esqueleto\.\*\*", re.MULTILINE)

# Construtos que só existem em x86. Se a lista crescer, o teste cresce junto.
SO_X86 = ("__builtin_ia32_", "_mm_", "__rdtsc")
GUARDAS = ("__x86_64__", "__i386__", "__aarch64__", "cpu_pause.h", "ACADEMY_CPU_PAUSE_H")

# "Linux x86_64 ou arm64" na porta de entrada.
PROMESSA_ARM = re.compile(r"arm64|aarch64", re.IGNORECASE)

# "7 dos 19 documentos ainda são esqueletos, de 62 a 98 linhas".
#
# Os quatro numeros sao capturados por grupo nomeado para que a mensagem de erro
# diga QUAL deles divergiu -- "a contagem esta errada" manda o leitor recontar os
# quatro; "esqueletos: o texto diz 7, o disco tem 6" aponta o dedo.
CENSO = {
    # A faixa de tamanhos e OPCIONAL, e deixou de ser publicada por decisao, nao
    # por esquecimento: ela acoplava o texto do ROADMAP a contagem exata de
    # linhas de seis arquivos, de modo que QUALQUER edicao legitima num esqueleto
    # deixava a suite vermelha ate alguem atualizar uma frase que nao informava
    # nada. Um portao que dispara em trabalho correto treina o leitor a ignora-lo.
    #
    # O que restou e o que interessa e nao gera atrito: quantos esqueletos, de
    # quantos documentos. O tamanho maximo continua travado -- pela regra 1, que
    # recusa banner de esqueleto acima de LIMITE_ESQUELETO linhas de conteudo.
    # SINGULAR E PLURAL, e isto nao e purismo: quando a contagem caiu para 1, a
    # frase precisou virar "1 dos 21 documentos ainda E esqueleto", e o padrao
    # que exigia "sao esqueletos" deixou de casar. `censo is None` fazia a regra
    # PULAR EM SILENCIO -- a afirmacao continuava publicada e ninguem mais a
    # conferia. Um verificador que se desliga sozinho ao reescreverem a frase e
    # pior que nenhum, porque o verde continua saindo.
    #
    # Dai as duas defesas: o padrao aceita as duas flexoes, e QUASE_CENSO abaixo
    # acusa o arquivo que parece publicar um censo e nao casa com nada.
    # ZERO tem forma propria, e precisa ter. Quando o ultimo esqueleto virou
    # conteudo, "0 dos 21 documentos ainda e esqueleto" seria portugues torto, e
    # apagar a frase deixaria o ROADMAP sem afirmacao nenhuma para conferir --
    # de modo que o proximo esqueleto a aparecer nao teria quem o contasse. Por
    # isso "Nenhum dos 21 documentos" e lido como n=0 e continua verificado.
    "ROADMAP.md": re.compile(
        r"(?:(?P<n>\d+)|(?P<zero>[Nn]enhum))\s+d[oe]s\s+(?P<total>\d+)\s+documentos?\s+"
        r"(?:ainda\s+)?(?:s[ãa]o\s+esqueletos?|[ée]\s+esqueleto|permanece\s+esqueleto)"
        r"(?:,\s*de\s+(?P<min>\d+)\s+a\s+(?P<max>\d+)\s+linhas)?"),
    # A traducao repete a contagem e NAO repete a faixa de tamanhos. Conferir so
    # os grupos que o padrao tem e o que mantem as duas linguas sob a mesma
    # regra: a versao em ingles carregava "7 of 19" tres semanas depois de o
    # numero mudar, porque a regra lia um arquivo so.
    "README.en.md": re.compile(
        r"(?:(?P<n>\d+)|(?P<zero>[Nn]one))\s+of\s+(?P<total>\d+)\s+documents?\s+"
        r"(?:are|is)\s+(?:still\s+)?(?:a\s+)?scope\s+skeletons?"),
}

# Frase que PARECE um censo e nao casa com o padrao do arquivo. Existe para que
# uma reescrita nao desligue a regra 3 sem avisar: o erro passa a ser "o padrao
# nao reconheceu esta frase", que e acionavel, em vez de silencio.
QUASE_CENSO = re.compile(
    r"\d+\s+(?:d[oe]s|of)\s+\d+\s+documentos?[^.\n]{0,40}(?:esqueleto|skeleton)"
    r"|\d+\s+(?:d[oe]s|of)\s+\d+\s+documents?[^.\n]{0,40}(?:esqueleto|skeleton)",
    re.IGNORECASE)

# Linha de tabela que aponta um diretorio e opina sobre o estado dele:
#   | 6 -- RX/TX | -- | [02-pipeline/01-rx-tx-burst/](02-pipeline/01-rx-tx-burst/) | esqueleto |
LINHA_INDICE = re.compile(r"^\|.*\]\((?P<destino>[^)]+/)\).*\|", re.MULTILINE)


def arquivos(raiz, exts):
    for pasta, subpastas, nomes in os.walk(raiz):
        subpastas[:] = [d for d in subpastas if d not in IGNORAR and not d.startswith("build")]
        for nome in nomes:
            if os.path.splitext(nome)[1] in exts:
                yield os.path.join(pasta, nome)


def linhas_de_conteudo(texto):
    """Linhas que não são vazias, banner, citação de cabeçalho nem navegação."""
    dentro_nav = False
    n = 0
    for linha in texto.splitlines():
        s = linha.strip()
        if s.startswith("## Navegação"):
            dentro_nav = True
            continue
        if dentro_nav:
            continue
        if not s or s.startswith(">") or s.startswith("#"):
            continue
        if set(s) <= set("|-: "):
            continue
        n += 1
    return n


def verificar(raiz="."):
    problemas = 0
    conferidos = 0

    # --- Regra 1 -----------------------------------------------------------
    for doc in sorted(arquivos(raiz, {".md"})):
        try:
            texto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        if not BANNER.search(texto):
            continue
        conferidos += 1
        n = linhas_de_conteudo(texto)
        if n > LIMITE_ESQUELETO:
            print(f"  {os.path.relpath(doc, raiz)}: declara-se ESQUELETO"
                  f" ('o conteúdo ainda não foi escrito') e tem {n} linhas de conteúdo"
                  f" (limite: {LIMITE_ESQUELETO})")
            problemas += 1

    # --- Regra 2 -----------------------------------------------------------
    readme = os.path.join(raiz, "README.md")
    promete_arm = False
    if os.path.exists(readme):
        try:
            promete_arm = bool(PROMESSA_ARM.search(open(readme, encoding="utf-8").read()))
        except (OSError, UnicodeDecodeError):
            pass

    if promete_arm:
        for src in sorted(arquivos(raiz, {".c", ".h", ".cpp", ".hpp"})):
            try:
                texto = open(src, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            usados = [t for t in SO_X86 if t in texto]
            if not usados:
                continue
            conferidos += 1
            if not any(g in texto for g in GUARDAS):
                print(f"  {os.path.relpath(src, raiz)}: usa {', '.join(usados)}"
                      f" (só x86) sem guarda de arquitetura, e o README.md promete arm64")
                problemas += 1

    # --- Regra 3 -----------------------------------------------------------
    esqueletos, docs, banner_de = [], 0, {}
    for doc in sorted(arquivos(os.path.join(raiz, "docs"), {".md"})) + \
               sorted(arquivos(os.path.join(raiz, "trilha"), {".md"})):
        docs += 1
        try:
            texto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        tem = bool(BANNER.search(texto))
        banner_de[os.path.realpath(doc)] = tem
        if tem:
            esqueletos.append(len(texto.splitlines()))

    real = {"n": len(esqueletos), "total": docs,
            "min": min(esqueletos) if esqueletos else None,
            "max": max(esqueletos) if esqueletos else None}
    rotulo = {"n": "esqueletos", "total": "documentos",
              "min": "menor esqueleto (linhas)", "max": "maior esqueleto (linhas)"}

    for nome, padrao in CENSO.items():
        caminho = os.path.join(raiz, nome)
        if not os.path.exists(caminho):
            continue
        try:
            censo = padrao.search(open(caminho, encoding="utf-8").read())
        except (OSError, UnicodeDecodeError):
            continue
        if censo is None:
            # FAIL-CLOSED: o arquivo tem cara de publicar um censo e o padrao nao
            # reconheceu. Pode ser reescrita legitima ou erro de digitacao; as
            # duas exigem alguem olhar, e nenhuma delas e "nada a conferir".
            try:
                bruto = open(caminho, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            if QUASE_CENSO.search(bruto):
                conferidos += 1
                print(f"  {nome}: ha uma frase que parece um censo de esqueletos e o"
                      f" padrao nao a reconhece -- a regra 3 deixaria de conferi-la")
                problemas += 1
            continue
        conferidos += 1
        # Sem esqueleto nenhum, min/max nao existem: comparar seria inventar
        # numero. A CONTAGEM, essa continua conferivel -- e e o caso "Nenhum".
        if not esqueletos and (censo.groupdict().get("min") is not None):
            print(f"  {nome}: publica faixa de tamanhos de esqueleto e nao ha"
                  " esqueleto em docs/ nem trilha/; a faixa perdeu o referente")
            problemas += 1
            continue
        for chave in censo.groupdict():
            if chave == "zero":
                continue
            if censo.group(chave) is None:
                # "Nenhum dos 21" -> o grupo `n` nao casou; a afirmacao e zero.
                if chave == "n" and censo.groupdict().get("zero"):
                    if real["n"] != 0:
                        print(f"  {nome}: {rotulo['n']} -- o texto diz nenhum,"
                              f" o disco tem {real['n']}")
                        problemas += 1
                continue
            if int(censo.group(chave)) != real[chave]:
                print(f"  {nome}: {rotulo[chave]} -- o texto diz"
                      f" {censo.group(chave)}, o disco tem {real[chave]}")
                problemas += 1

    # --- Regra 4 -----------------------------------------------------------
    #
    # Um indice que rotula diretorio por diretorio envelhece pior que o censo: o
    # total pode continuar certo enquanto UMA linha passou a mentir. Foi o que
    # houve com `trilha/02-pipeline/01-rx-tx-burst/`, marcado "esqueleto" no
    # indice depois de o banner sair do documento -- 325 linhas de escopo,
    # restricoes de ambiente e capacidades de NIC medidas, anunciadas como
    # promessa vazia.
    #
    # A REGRA VALE NUMA DIRECAO SO, e isto foi aprendido errando: a primeira
    # versao conferia tambem o inverso -- diretorio com banner que o indice NAO
    # chama de esqueleto -- e acusou 13 defeitos inexistentes, todos linhas de
    # tabela de NAVEGACAO ("| Proximo | [02 -- Batching](../02-batching/) |").
    # Uma linha dessas aponta um diretorio e nao afirma nada sobre o estado
    # dele; exigir que afirme e inventar um defeito.
    #
    # Distinguir "linha de status" de "linha de navegacao" por sintaxe e o mesmo
    # problema indecidivel que a regra 1 evita. Entao a regra confere so o que e
    # decidivel: QUEM CHAMA de esqueleto precisa estar certo. O inverso -- o
    # documento que virou conteudo e ninguem atualizou o indice -- continua
    # fora, e isto esta declarado em vez de disfarcado.
    for indice in sorted(arquivos(os.path.join(raiz, "trilha"), {".md"})) + \
                  sorted(arquivos(os.path.join(raiz, "docs"), {".md"})):
        try:
            texto = open(indice, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for linha in texto.splitlines():
            if not linha.startswith("|") or "esqueleto" not in linha.lower():
                continue
            m = LINHA_INDICE.match(linha + "\n")
            if m is None:
                continue
            destino = os.path.realpath(
                os.path.join(os.path.dirname(indice), m.group("destino"), "README.md"))
            if destino not in banner_de:
                continue
            conferidos += 1
            if not banner_de[destino]:
                print(f"  {os.path.relpath(indice, raiz)}: chama"
                      f" {m.group('destino')} de esqueleto e o README.md de la"
                      f" NAO tem o banner -- o documento tem conteudo")
                problemas += 1

    print(f"\n  {conferidos} afirmação(ões) sobre o próprio material conferida(s);"
          f" {problemas} não se sustenta(m)")
    if not promete_arm:
        print("  (o README.md não promete arm64: a regra 2 não foi aplicada)")
    return problemas


def autoteste():
    import io as _io
    import tempfile
    from contextlib import redirect_stdout

    def rodar(arqs):
        with tempfile.TemporaryDirectory() as d:
            for nome, conteudo in arqs.items():
                caminho = os.path.join(d, nome)
                os.makedirs(os.path.dirname(caminho), exist_ok=True)
                open(caminho, "w", encoding="utf-8").write(conteudo)
            buf = _io.StringIO()
            with redirect_stdout(buf):
                rc = verificar(d)
            return rc, buf.getvalue()

    falhas = 0
    esqueleto = "# t\n\n> **Esqueleto.** O conteúdo ainda não foi escrito.\n\n"

    # 1. Esqueleto de verdade: passa.
    rc, _ = rodar({"e.md": esqueleto + "## Objetivo\n\nRegistrar escopo.\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: esqueleto legítimo acusado"); falhas += 1

    # 2. Banner mentindo sobre 200 linhas de conteúdo: falha.
    rc, _ = rodar({"e.md": esqueleto + "\n".join(f"linha {i} de conteudo real."
                                                 for i in range(200))})
    if rc != 1:
        print(f"  AUTOTESTE FALHOU: banner falso passou (rc={rc})"); falhas += 1

    # 3. Promessa de arm64 com builtin x86 sem guarda: falha.
    rc, _ = rodar({"README.md": "# p\n\n- Linux x86_64 ou arm64\n",
                   "src/a.c": "void f(void){ __builtin_ia32_pause(); }\n"})
    if rc != 1:
        print(f"  AUTOTESTE FALHOU: promessa arm64 sem guarda passou (rc={rc})"); falhas += 1

    # 4. O mesmo builtin COM guarda: passa.
    rc, _ = rodar({"README.md": "# p\n\n- Linux x86_64 ou arm64\n",
                   "src/a.c": "#if defined(__x86_64__)\nvoid f(void){ __builtin_ia32_pause(); }\n#endif\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: guarda de arquitetura não reconhecida"); falhas += 1

    # 5. Sem promessa de arm64, o mesmo código não é defeito: a regra não se aplica.
    rc, _ = rodar({"README.md": "# p\n\n- Linux x86_64\n",
                   "src/a.c": "void f(void){ __builtin_ia32_pause(); }\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: regra 2 aplicada sem a promessa"); falhas += 1

    # 6. Censo do ROADMAP batendo com o disco: passa.
    censo_ok = "# r\n\n1 dos 2 documentos ainda são esqueletos, de 5 a 5 linhas.\n"
    rc, _ = rodar({"ROADMAP.md": censo_ok,
                   "docs/a.md": esqueleto + "## Objetivo\n",
                   "trilha/b.md": "# b\n\nconteudo real.\n"})
    if rc != 0:
        print(f"  AUTOTESTE FALHOU: censo correto acusado (rc={rc})"); falhas += 1

    # 7. Cada um dos quatro numeros, errado sozinho: falha. Um por vez, porque um
    #    unico caso com os quatro errados passaria mesmo se a regra so conferisse
    #    um deles -- e foi assim que a frase real envelheceu sem ninguem ver.
    for rotulo, alvo_str, troca in (("contagem", "1 dos 2", "2 dos 2"),
                                    ("total", "1 dos 2", "1 dos 9"),
                                    ("minimo", "de 5 a 5", "de 3 a 5"),
                                    ("maximo", "a 5 linhas", "a 9 linhas")):
        rc, _ = rodar({"ROADMAP.md": censo_ok.replace(alvo_str, troca),
                       "docs/a.md": esqueleto + "## Objetivo\n",
                       "trilha/b.md": "# b\n\nconteudo real.\n"})
        if rc < 1:
            print(f"  AUTOTESTE FALHOU: censo com {rotulo} errado passou (rc={rc})"); falhas += 1

    # 8. Censo publicado sem esqueleto nenhum no disco: falha em vez de comparar
    #    min/max de lista vazia.
    rc, _ = rodar({"ROADMAP.md": censo_ok, "docs/a.md": "# a\n\nconteudo.\n"})
    if rc < 1:
        print(f"  AUTOTESTE FALHOU: censo sem referente passou (rc={rc})"); falhas += 1

    # 9. O censo em INGLES, que nao tem faixa de tamanhos: confere so os dois
    #    numeros que o padrao dele captura.
    en_ok = "# p\n\n1 of 2 documents are still scope skeletons, and each says so.\n"
    base = {"docs/a.md": esqueleto + "## Objetivo\n", "trilha/b.md": "# b\n\nconteudo.\n"}
    rc, _ = rodar({"README.en.md": en_ok, **base})
    if rc != 0:
        print(f"  AUTOTESTE FALHOU: censo em ingles correto acusado (rc={rc})"); falhas += 1
    rc, _ = rodar({"README.en.md": en_ok.replace("1 of 2", "9 of 2"), **base})
    if rc < 1:
        print(f"  AUTOTESTE FALHOU: censo em ingles errado passou (rc={rc})"); falhas += 1

    # 10. Indice que chama de esqueleto um diretorio que E esqueleto: passa.
    linha_ok = "| 5 | [d/](d/) | esqueleto |\n"
    rc, _ = rodar({"trilha/README.md": "# i\n\n" + linha_ok,
                   "trilha/d/README.md": esqueleto + "## Objetivo\n"})
    if rc != 0:
        print(f"  AUTOTESTE FALHOU: rotulo de esqueleto correto acusado (rc={rc})"); falhas += 1

    # 11. Indice que chama de esqueleto um diretorio com CONTEUDO: falha.
    rc, _ = rodar({"trilha/README.md": "# i\n\n" + linha_ok,
                   "trilha/d/README.md": "# d\n\n" + "\n".join(f"linha {i}." for i in range(50))})
    if rc < 1:
        print(f"  AUTOTESTE FALHOU: rotulo de esqueleto mentiroso passou (rc={rc})"); falhas += 1

    # 12. REGRESSAO. Linha de NAVEGACAO apontando um esqueleto, sem dizer
    #     "esqueleto": passa. A primeira versao da regra 4 acusava 13 defeitos
    #     inexistentes exatamente aqui -- toda tabela "| Proximo | [x](x/) |" da
    #     arvore. O caso existe para que a direcao inversa nao volte por engano.
    rc, _ = rodar({"trilha/README.md": "# i\n\n| **Proximo** | [d/](d/) |\n",
                   "trilha/d/README.md": esqueleto + "## Objetivo\n"})
    if rc != 0:
        print(f"  AUTOTESTE FALHOU: linha de navegacao acusada como rotulo (rc={rc})"); falhas += 1

    # 13-17. As duas defesas que a contagem chegar a 1 obrigou a criar.
    #
    # Quando o censo virou "1 dos 2 documentos ainda E esqueleto", o padrao que
    # exigia plural parou de casar -- e a regra 3 se DESLIGAVA SOZINHA, sem
    # avisar. A afirmacao seguia publicada e ninguem mais a conferia. Daqui em
    # diante, flexao reconhecida (13-15) e reescrita acusada (16), com o caso 17
    # garantindo que arquivo sem censo nenhum nao vire falso positivo.
    base13 = {"docs/a.md": esqueleto + "## Objetivo\n", "trilha/b.md": "# b\n\nconteudo.\n"}
    for numero, descricao, arqs, espera_defeito in (
        (13, "censo no singular nao reconhecido",
         {"ROADMAP.md": "# r\n\n1 dos 2 documentos ainda \u00e9 esqueleto.\n"}, False),
        (14, "censo no singular com numero errado passou",
         {"ROADMAP.md": "# r\n\n9 dos 2 documentos ainda \u00e9 esqueleto.\n"}, True),
        (15, "censo em ingles no singular nao reconhecido",
         {"README.en.md": "# r\n\n1 of 2 documents is still a scope skeleton.\n"}, False),
        (16, "frase de censo reescrita fora do padrao passou em silencio",
         {"ROADMAP.md": "# r\n\n1 dos 2 documentos permanece como esqueleto.\n"}, True),
        (17, "arquivo sem censo nenhum acusado",
         {"ROADMAP.md": "# r\n\nEste arquivo nao publica censo algum.\n"}, False),
    ):
        rc, saida = rodar({**arqs, **base13})
        ok = (rc >= 1) if espera_defeito else (rc == 0)
        if not ok:
            print(f"  AUTOTESTE {numero} FALHOU: {descricao} (rc={rc})")
            print("    " + saida.strip().replace("\n", "\n    "))
            falhas += 1

    # 18-20. ZERO. Quando o ultimo esqueleto virou conteudo, "0 dos 21" seria
    #        portugues torto e apagar a frase deixaria o ROADMAP sem afirmacao
    #        nenhuma -- o proximo esqueleto a aparecer nao teria quem o contasse.
    #        "Nenhum dos N" e lido como zero e SEGUE conferido.
    sem_esqueleto = {"docs/a.md": "# a\n\nconteudo.\n", "trilha/b.md": "# b\n\nconteudo.\n"}
    for numero, descricao, arqs, base, espera_defeito in (
        (18, "'Nenhum dos N' nao reconhecido como zero",
         {"ROADMAP.md": "# r\n\nNenhum dos 2 documentos e esqueleto.\n"}, sem_esqueleto, False),
        (19, "'Nenhum' afirmado com esqueleto no disco passou",
         {"ROADMAP.md": "# r\n\nNenhum dos 2 documentos e esqueleto.\n"}, base13, True),
        (20, "'None of the N' em ingles nao reconhecido",
         {"README.en.md": "# r\n\nNone of the 2 documents is a scope skeleton.\n"},
         sem_esqueleto, False),
    ):
        rc, saida = rodar({**arqs, **base})
        ok = (rc >= 1) if espera_defeito else (rc == 0)
        if not ok:
            print(f"  AUTOTESTE {numero} FALHOU: {descricao} (rc={rc})")
            print("    " + saida.strip().replace("\n", "\n    "))
            falhas += 1

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else ".") else 0)
