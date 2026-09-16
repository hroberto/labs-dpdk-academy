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
- afirmações do material sobre si que não sejam o censo da regra 3 nem a
  promessa de resumo da regra 5 (níveis de teste, cobertura de módulo, estado de
  uma etapa);
- se o resumo em inglês DIZ a mesma coisa que o documento em português. A regra
  5 confere que ele EXISTE e a regra 6 que ele não INVENTA números; se o conteúdo
  corresponde exige ler as duas línguas e comparar sentido, e disso nenhum
  programa dá conta;
- se um número do resumo está ATRIBUÍDO à grandeza certa. A regra 6 é vácua
  contra troca, e isso foi medido: pôr "rte_eal_init() at 0.63 ms" no resumo --
  afirmação grosseiramente falsa, porque 0,63 ms é o custo de ENCERRAR -- passa,
  já que o número existe no corpo. Ela fecha a classe "número que não está em
  lugar nenhum", não a classe "número trocado".

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

# Documento que declara o proprio nivel -- singular ou plural. E o marcador que
# distingue MODULO/TOPICO de indice nesta arvore: indices nao declaram nivel.
NIVEL = re.compile(r"^>\s*\*\*N[íi]ve(?:l|is)\s", re.MULTILINE)

# O resumo em ingles, pela convencao do projeto.
RESUMO_EN = re.compile(r"^>\s*\*\*In English\.\*\*", re.MULTILINE)

# O BLOCO inteiro do resumo, para a regra 6 poder separá-lo do corpo.
RESUMO_BLOCO = re.compile(r"^> \*\*In English\.\*\*(.*?)(?=\n\n)", re.S | re.M)

# Número com dois dígitos ou mais. Dígito solto ("2 fit in that budget") é ruído:
# aparece em qualquer texto e não identifica grandeza nenhuma.
NUMERO_RESUMO = re.compile(r"\d[\d.,\u202f]*\d")

# Linha de tabela que aponta um diretorio e opina sobre o estado dele:
#   | 6 -- RX/TX | -- | [02-pipeline/01-rx-tx-burst/](02-pipeline/01-rx-tx-burst/) | esqueleto |
LINHA_INDICE = re.compile(r"^\|.*\]\((?P<destino>[^)]+/)\).*\|", re.MULTILINE)


def arquivos(raiz, exts):
    for pasta, subpastas, nomes in os.walk(raiz):
        subpastas[:] = [d for d in subpastas if d not in IGNORAR and not d.startswith("build")]
        for nome in nomes:
            if os.path.splitext(nome)[1] in exts:
                yield os.path.join(pasta, nome)


def formas_do_numero(numero):
    """As grafias que um mesmo valor tem nas duas linguas.

    Portugues e ingles discordam em DOIS pontos ao mesmo tempo: o separador
    decimal (`2,18` contra `2.18`) e o de milhar (`1 023` -- com espaco estreito,
    U+202F -- contra `1,023`). Comparar sem normalizar acusaria as duas grafias
    do MESMO numero, e verificador ruidoso e verificador desligado.

    A funcao e deliberadamente generosa: gera mais formas do que qualquer
    documento usa. O custo de uma forma a mais e um falso negativo raro; o custo
    de uma forma a menos e ruido constante, que custa mais.
    """
    formas = {numero}
    for f in list(formas):
        formas |= {f.replace(".", ","), f.replace(",", "."),
                   f.replace(",", ""), f.replace(".", ""),
                   f.replace(",", "\u202f"), f.replace(",", " "),
                   f.replace(".", "\u202f"),
                   f.replace(" ", "\u202f"), f.replace("\u202f", " "),
                   f.replace("\u202f", ""), f.replace(" ", "")}
    return formas


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
        # O PAR EM INGLES NAO E UM DOCUMENTO A MAIS. Contá-lo inflava o censo a
        # cada tradução -- 21 viraram 23 na primeira leva --, e a frase do
        # ROADMAP passaria a falar de um total que não corresponde ao material,
        # só à contagem de arquivos. É o mesmo documento noutra língua.
        if doc.endswith(".en.md"):
            continue
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

    # --- Regra 5 -----------------------------------------------------------
    #
    # `README.en.md` promete, em texto: "English covers the surface that matters
    # for reading and reuse: code, file names, this page, and a short summary at
    # the top of each written module".
    #
    # Era promessa sem verificacao, e quebrou calada: seis modulos escritos em
    # 16/09/2026 sairam sem resumo nenhum, e a frase continuou publicada. Quem
    # nao le portugues abria o documento e nao encontrava o que a porta de
    # entrada prometia.
    #
    # O marcador de "modulo escrito" e a DECLARACAO DE NIVEL: nesta arvore,
    # topico e modulo declaram `> **Nivel N**`, indice nao declara. Isso torna a
    # regra decidivel sem julgar o que e conteudo suficiente -- o mesmo cuidado
    # da regra 1.
    for doc in sorted(arquivos(os.path.join(raiz, "docs"), {".md"})) + \
               sorted(arquivos(os.path.join(raiz, "trilha"), {".md"})):
        try:
            texto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        if doc.endswith(".en.md"):
            continue
        if not NIVEL.search(texto):
            continue
        if BANNER.search(texto):     # esqueleto declarado nao promete resumo
            continue
        conferidos += 1
        # DUAS FORMAS ACEITAS, e isto e transitorio. Ate 16/09/2026 a paridade
        # era um RESUMO embutido; a decisao passou a ser PARIDADE COMPLETA, com
        # um `.en.md` ao lado de cada documento. Enquanto a migracao acontece, as
        # duas contam -- senao a suite ficaria vermelha durante o trabalho, e
        # suite vermelha por obra em andamento treina a ignorar vermelho.
        #
        # QUANDO A MIGRACAO TERMINAR, esta condicao deve exigir SO o par: o
        # resumo embutido deixa de ser suficiente. O caso 30 do autoteste existe
        # para que essa transicao seja deliberada e nao esquecida.
        par = os.path.splitext(doc)[0] + ".en.md"
        if not RESUMO_EN.search(texto) and not os.path.exists(par):
            print(f"  {os.path.relpath(doc, raiz)}: declara nivel (e portanto e"
                  f" modulo escrito) e nao tem nem o resumo \"> **In English.**\""
                  f" nem o par completo {os.path.basename(par)}")
            problemas += 1

    # --- Regra 6 -----------------------------------------------------------
    #
    # Número que aparece no resumo em inglês e em lugar nenhum do corpo em
    # português. É a forma mais crua de divergência entre as duas línguas, e ela
    # ACONTECEU: `docs/02-runtime-dpdk` publicava 0,08 ms no corpo e 0.30 ms no
    # resumo -- duas afirmações diferentes sobre a mesma grandeza, no mesmo
    # arquivo, e nenhuma reproduzia.
    #
    # O QUE ELA NÃO PEGA, e está no cabeçalho: número trocado por outro que
    # também existe no documento. Medido -- "rte_eal_init() at 0.63 ms" passa,
    # porque 0,63 é o custo de encerrar e está lá. Fecha "inventado", não
    # "errado".
    for doc in sorted(arquivos(os.path.join(raiz, "docs"), {".md"})) + \
               sorted(arquivos(os.path.join(raiz, "trilha"), {".md"})):
        try:
            texto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        if doc.endswith(".en.md"):
            continue
        m = RESUMO_BLOCO.search(texto)
        if m is None:
            continue
        ingles = m.group(1)
        corpo = texto.replace(ingles, "")
        for numero in sorted(set(NUMERO_RESUMO.findall(ingles))):
            conferidos += 1
            # Vírgula e ponto decimal são a mesma grandeza em línguas diferentes;
            # comparar sem normalizar acusaria "2.18" contra "2,18" e o
            # verificador viraria ruído -- e verificador ruidoso é desligado.
            formas = formas_do_numero(numero)
            if not any(f in corpo for f in formas):
                print(f"  {os.path.relpath(doc, raiz)}: o resumo em ingles publica"
                      f" \"{numero}\" e esse valor nao aparece no corpo em portugues")
                problemas += 1

    # --- Regra 7 -----------------------------------------------------------
    #
    # A MESMA pergunta da regra 6, feita ao par COMPLETO em vez do resumo.
    #
    # Ela existe porque traduzir estava REMOVENDO verificação: enquanto a
    # paridade era um resumo embutido, a regra 6 conferia os números dele; ao
    # trocar o resumo pelo par `.en.md`, o bloco sai do arquivo português e
    # aqueles números deixam de ser conferidos por ninguém. Medido na primeira
    # leva -- 77 asserções caíram para 72 só por traduzir três índices.
    #
    # Aqui a cobertura fica MAIOR que antes, não menor: o par inteiro tem muito
    # mais números que o resumo tinha, e cada um precisa existir no original.
    #
    # O QUE ELA NÃO PEGA é o mesmo limite da regra 6, e vale repetir: número
    # trocado por outro que também aparece no documento passa. Fecha
    # "inventado na tradução", não "errado nas duas línguas" -- para esse, o
    # instrumento é reconferir contra o programa que produz o número.
    for par in sorted(arquivos(os.path.join(raiz, "docs"), {".md"})) + \
               sorted(arquivos(os.path.join(raiz, "trilha"), {".md"})):
        if not par.endswith(".en.md"):
            continue
        origem = par[: -len(".en.md")] + ".md"
        if not os.path.exists(origem):
            # Par órfão: inglês sem português. Não é divergência de número, é
            # um arquivo que não deveria existir -- e o silêncio seria pior.
            print(f"  {os.path.relpath(par, raiz)}: par em ingles sem o original"
                  f" {os.path.basename(origem)} correspondente")
            problemas += 1
            continue
        try:
            ingles = open(par, encoding="utf-8").read()
            corpo = open(origem, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for numero in sorted(set(NUMERO_RESUMO.findall(ingles))):
            conferidos += 1
            formas = formas_do_numero(numero)
            if not any(f in corpo for f in formas):
                print(f"  {os.path.relpath(par, raiz)}: a versao em ingles publica"
                      f" \"{numero}\" e esse valor nao aparece no original em portugues")
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

    # 21-23. REGRA 5: a promessa do README.en.md de um resumo em ingles no topo
    #        de cada modulo escrito. Quebrou calada em 16/09/2026 -- seis modulos
    #        novos sairam sem resumo e a frase continuou publicada.
    nivel = "> **Nível 8** do plano\n"
    resumo = "> **In English.** A short summary.\n"
    for numero, descricao, doc, espera_defeito in (
        (21, "modulo com nivel e resumo acusado",
         "# m\n\n" + nivel + "\n" + resumo + "\ntexto.\n", False),
        (22, "modulo com nivel e SEM resumo passou",
         "# m\n\n" + nivel + "\ntexto.\n", True),
        (23, "indice sem declaracao de nivel exigido a ter resumo",
         "# i\n\n| a | b |\n|---|---|\n\ntexto.\n", False),
        # PLURAL. `trilha/01-fundamentos/` declara "Niveis 3 e 4", e foi
        # exatamente essa forma que escapou de uma conferencia manual feita com
        # regex singular. A regra le as duas; o caso 25 impede que volte a ler
        # so uma.
        (25, "modulo com 'Niveis' no plural e SEM resumo passou",
         "# m\n\n> **Níveis 3 e 4** do plano\n\ntexto.\n", True),
        (26, "modulo com 'Niveis' no plural e COM resumo acusado",
         "# m\n\n> **Níveis 3 e 4** do plano\n\n" + resumo + "\ntexto.\n", False),
    ):
        rc, saida = rodar({"trilha/m.md": doc})
        ok = (rc >= 1) if espera_defeito else (rc == 0)
        if not ok:
            print(f"  AUTOTESTE {numero} FALHOU: {descricao} (rc={rc})")
            print("    " + saida.strip().replace("\n", "\n    "))
            falhas += 1

    # 30. PARIDADE POR ARQUIVO satisfaz a regra 5 sem resumo embutido. Este caso
    #     e o que permite a migracao acontecer sem a suite ficar vermelha, e e
    #     tambem o lembrete de que ela esta em curso: quando todo modulo tiver o
    #     seu `.en.md`, a regra deve passar a exigir SO o par, e este caso muda.
    with __import__("tempfile").TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "trilha"), exist_ok=True)
        open(os.path.join(d, "trilha", "m.md"), "w", encoding="utf-8").write(
            "# m\n\n> **Nível 8** do plano\n\ntexto.\n")
        open(os.path.join(d, "trilha", "m.en.md"), "w", encoding="utf-8").write(
            "# m\n\ntext.\n")
        buf = _io.StringIO()
        with redirect_stdout(buf):
            rc = verificar(d)
        if rc != 0:
            print(f"  AUTOTESTE 30 FALHOU: par .en.md nao satisfaz a regra 5 (rc={rc})")
            print("    " + buf.getvalue().strip().replace("\n", "\n    "))
            falhas += 1

    # 31-34. REGRA 7: a paridade do par completo.
    #
    #   31. numero inventado na traducao: acusa;
    #   32. o MESMO numero em grafia inglesa (1,023 contra 1 023): passa -- sem
    #       isto a regra acusaria toda tabela com milhar e seria desligada;
    #   33. par orfao, ingles sem portugues: acusa;
    #   34. o limite declarado -- numero TROCADO por outro que existe no
    #       documento passa. Fica registrado para nao se confundir esta regra
    #       com conferencia de valor.
    par_pt = "# m\n\ntexto com 1\u202f023 e 4,4 ns.\n"
    for rotulo, en, espera in (
            ("numero inventado", "# m\n\ntext with 9,876 and 4.4 ns.\n", 1),
            ("grafia inglesa do milhar", "# m\n\ntext with 1,023 and 4.4 ns.\n", 0),
            ("numero trocado por outro do documento", "# m\n\ntext with 4.4 and 4.4 ns.\n", 0)):
        rc, saida = rodar({"trilha/m.md": par_pt, "trilha/m.en.md": en})
        if rc != espera:
            print(f"  AUTOTESTE 31-34 FALHOU: {rotulo} deu rc={rc}, esperado {espera}")
            print("    " + saida.strip().replace("\n", "\n    "))
            falhas += 1
    rc, _ = rodar({"trilha/m.en.md": "# m\n\ntext.\n"})
    if rc != 1:
        print(f"  AUTOTESTE 33 FALHOU: par orfao sem original passou (rc={rc})")
        falhas += 1

    # 24. Esqueleto DECLARADO nao promete resumo: a promessa e sobre modulo
    #     ESCRITO. Sem esta isenca, todo esqueleto novo nasceria vermelho.
    rc, _ = rodar({"trilha/e.md": "# e\n\n" + nivel + "\n" + esqueleto + "## Objetivo\n"})
    if rc != 0:
        print(f"  AUTOTESTE 24 FALHOU: esqueleto declarado exigido a ter resumo (rc={rc})")
        falhas += 1

    # 27-29. REGRA 6, e o caso 29 registra o que ela NAO pega.
    #
    # A divergencia real que a motivou: `docs/02-runtime-dpdk` publicava 0,08 ms
    # no corpo e 0.30 ms no resumo -- duas afirmacoes sobre a mesma grandeza, no
    # mesmo arquivo, e nenhuma reproduzia.
    corpo = "# m\n\n> **Nível 8** do plano\n\n{res}\nA EAL sobe em 123 ms e encerra em 0,63 ms.\n"
    for numero, descricao, res, espera_defeito in (
        (27, "numero do resumo presente no corpo acusado",
         "> **In English.** The EAL starts in 123 ms and stops in 0.63 ms.\n", False),
        (28, "numero INVENTADO no resumo passou",
         "> **In English.** The EAL starts in 999 ms.\n", True),
        # O QUE ELA NAO PEGA, registrado como caso que PASSA de proposito: o
        # numero existe no corpo, esta atribuido a grandeza errada, e a regra nao
        # tem como saber. Se um dia alguem fizer a regra pegar isso, este caso
        # falha e obriga a reescrever o comentario -- que e o ponto.
        (29, "troca de atribuicao (0,63 e o custo de ENCERRAR) -- limite declarado",
         "> **In English.** The EAL starts in 0.63 ms.\n", False),
    ):
        rc, saida = rodar({"trilha/m.md": corpo.format(res=res)})
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
