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
  (2,08 no lugar de 2,078): a busca é textual. Isto DEIXOU de passar em
  silêncio -- ver "O RELATÓRIO DE ARREDONDADOS" abaixo --, mas continua fora
  do veredito, e a razão está medida;
- número retratado dentro de código-fonte que o documento não cita;
- retratação escrita sem nenhum dos marcadores conhecidos;
- valor cujos MESMOS DÍGITOS têm outro papel legítimo no texto. Um "120,0"
  retratado como mediana reaparece como extremo de amplitude "120,0-122,5", e a
  busca textual não separa os dois. Nesse caso o valor não deve entrar na marca
  -- declará-lo produziria acusação falsa, e verificador que acusa o correto é
  desligado;
- afirmação retratada que não é numérica (um rótulo, uma conclusão).

O RELATÓRIO DE ARREDONDADOS, e por que ele NÃO é um gate

Em 19/09/2026 três números retratados foram encontrados vivos, e os três tinham
escapado pela mesma porta: a busca é literal.

    18,2 retratado, e "11 a 18 ns" publicado em seis lugares
    17,50 e 82,99 retratados, e "17 ns / mais de 80" publicados na §4.2.1

A correção óbvia seria procurar também os arredondamentos. Ela foi medida antes
de ser escrita, e REPROVOU: `91,5` é um valor retratado do §4.2, o seu
arredondamento é `92`, e `92 ns` aparece **sete vezes** no módulo 01 -- todas
legítimas, porque a travessia entre domínios mede 91,75 ns. Um gate por
arredondamento acusaria sete vezes o texto correto no primeiro documento em que
rodasse.

E verificador que acusa o correto é desligado. É a forma mais comum de um
controle morrer, e este arquivo já diz isso em dois lugares.

A saída é a mesma de `auditar-fontes.py`: **inventário de trabalho, não
veredito**. O relatório lista os candidatos, exige que o número venha seguido de
unidade (sem isso, `18` casa em qualquer data e contagem) e deixa a decisão com
quem escreve. Ele não altera o código de saída. O que ele compra é que a classe
inteira deixe de ser invisível -- e invisibilidade era o defeito, não a
existência dos falsos positivos.

Só entram números com pelo menos TRÊS dígitos significativos. Sem esse corte,
valores como "5" ou "100" casariam em toda parte e o verificador viraria ruído
-- e verificador ruidoso é desligado, que é a forma mais comum de um controle
morrer.
"""
import os
import re
import sys

IGNORAR = {".git", "build", "subprojects", "__pycache__", "temp"}

# Marcadores de retratação, em minúsculas. Derivados dos blocos que o projeto
# já escreveu: "Esta tabela já publicou", "Este bloco publicava", "Uma versão
# anterior desta frase dizia", "o número era artefato", "estavam errados".
MARCADORES = (
    "publicava", "publicou", "ja publicou", "já publicou",
    "versao anterior", "versão anterior", "era artefato", "eram artefato",
    "estava errado", "estavam errados", "estavam erradas", "dizia",
    # As mesmas frases em ingles, pelos pares `.en.md`.
    #
    # SEM ELAS, NENHUM BLOCO DE RETRATACAO EM INGLES ERA RECONHECIDO -- e a
    # consequencia era pior que nao conferir: o proprio comentario
    # `<!-- retratado: ... -->` do par contava como texto VIVO, e o verificador
    # acusava o documento de republicar o que ele estava retratando. Foi assim
    # que apareceu, em vermelho, ao traduzir a alternativa em C++23.
    #
    # A lista e deliberadamente ESPECIFICA. "published" e "said" sozinhos
    # entrariam em prosa comum, e um falso positivo aqui REMOVE o bloco do texto
    # conferido -- ele afrouxa o verificador em silencio, que e a direcao
    # perigosa do erro.
    "used to publish", "once published", "previously published",
    "previous version", "used to say", "was an artefact", "was an artifact",
    "was wrong", "were wrong", "retraction",
)

# Número decimal qualquer; o corte por dígitos significativos vem depois, em
# `distintivo()`. A primeira versão fazia o corte NO REGEX, exigindo duas casas
# decimais -- e o cabeçalho prometia "três dígitos significativos", que não é a
# mesma coisa: `120,0` tem quatro significativos e uma casa, e escapava. O
# contrato dizia uma coisa e o código fazia outra, que é exatamente a classe de
# defeito que este verificador existe para pegar.
NUMERO_BRUTO = re.compile(r"\b\d+[.,]\d+\b")
MIN_SIGNIFICATIVOS = 3


def distintivo(n):
    """Dígitos suficientes para que casar no texto signifique algo.

    Sem este corte, valores como "5,0" apareceriam em toda parte e o
    verificador viraria ruído -- e verificador ruidoso é desligado, que é a
    forma mais comum de um controle morrer."""
    return len(n.replace(",", "").replace(".", "").lstrip("0")) >= MIN_SIGNIFICATIVOS


class _Numero:
    @staticmethod
    def findall(texto):
        return [n for n in NUMERO_BRUTO.findall(texto) if distintivo(n)]

    @staticmethod
    def search(texto):
        for n in NUMERO_BRUTO.finditer(texto):
            if distintivo(n.group(0)):
                return n
        return None


NUMERO = _Numero


def aparece(valor, linha):
    """O valor aparece na linha como NUMERO INTEIRO, não como pedaço de outro.

    A busca era `valor in linha`, substring pura, e isso acusava número que
    nunca foi retratado: `17.1` casava dentro de `17.197%`, e `65,3` dentro de
    `1,365,373`. O defeito já tinha cobrado antes -- `91.5` colidia com um
    `91,55 ns` legítimo, e a saída na época foi TIRAR o valor da marca de
    retratação, o que enfraquece o controle para resolver um problema que era
    do casamento, não do dado.

    A guarda é de fronteira de DÍGITO, não de palavra: `\b` não serve, porque
    ponto e vírgula não são caractere de palavra e `\b17.1\b` casaria em
    `17.197` do mesmo jeito. O que não pode haver, antes ou depois, é dígito ou
    separador."""
    return re.search(r"(?<![\d.,])" + re.escape(valor) + r"(?![\d.,])",
                     linha) is not None

# A marca que declara o que caiu. Comentário HTML: invisível na renderização.
MARCA = re.compile(r"<!--\s*retratado:\s*([^>]+?)\s*-->", re.IGNORECASE)

# A marca inversa: este documento CITA um valor retratado de propósito, porque
# fala sobre o defeito em vez de cometê-lo. Sem esta válvula, um laudo de
# auditoria ou um estudo sobre retratações seria impossível de escrever -- e a
# saída seria afrouxar a regra para todo mundo, que é pior. A válvula é
# explícita e aparece na contagem final, então ninguém a usa sem deixar rastro.
CITA = re.compile(r"<!--\s*cita-retratado:\s*([^>]+?)\s*-->", re.IGNORECASE)


def achatar(bloco):
    """O bloco em minusculas e numa linha so, sem os `>` da citacao.

    POR QUE ISTO EXISTE: os marcadores em ingles sao FRASES de duas e tres
    palavras -- "used to publish", "previous version" --, e a prosa quebra em
    80 colunas onde calhar. Um bloco que dizia "This table used to\n> publish
    0.924 ns" nao casava com "used to publish", e o efeito era o pior possivel:
    o bloco inteiro deixava de ser reconhecido como retratacao, a marca
    `<!-- retratado: ... -->` dele passava a contar como texto VIVO, e o
    verificador acusava o documento de republicar o que estava retratando.
    Medido em 19/09/2026, ao escrever a retratacao do custo-syscall.

    Os marcadores em portugues sao palavras unicas e nunca sofreram com isso --
    e por isso o defeito atravessou a traducao sem aparecer."""
    return " ".join(bloco.replace(">", " ").lower().split())


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
    """Onde o documento declara que um valor caiu.

    Duas formas valem, e a segunda existe por um motivo de LEITURA.

    A primeira e um bloco de citacao que se anuncia como retratacao. Ela serve
    quando o erro ensina alguma coisa e o bloco fica no texto de proposito.

    A segunda e a MARCA SOZINHA, sem bloco nenhum. Comentario HTML nao
    renderiza, entao ela some para quem le e continua valendo para o portao.
    Existe porque errata e ruido para quem estuda: o leitor quer o conteudo
    certo, nao o historico dos meus enganos. O que precisa sobreviver nao e a
    narrativa do erro -- e a GARANTIA de que o numero derrubado nao volta a
    aparecer publicado noutra pagina, e essa garantia e do verificador, nao do
    texto."""
    encontrados = [b for b in blocos_de_citacao(texto)
                   if any(m in achatar(b[2]) for m in MARCADORES)]
    cobertos = [(ini, fim) for ini, fim, _ in encontrados]
    for m in MARCA.finditer(texto):
        if not any(ini <= m.start() < fim for ini, fim in cobertos):
            encontrados.append((m.start(), m.end(), m.group(0)))
    return sorted(encontrados)


def fora_de_retratacao(texto):
    """O texto com os blocos de retratação removidos."""
    for ini, fim, _ in reversed(retratacoes(texto)):
        texto = texto[:ini] + texto[fim:]
    return texto


# Unidade logo depois do número. Sem esta exigência, o arredondado `18` casa em
# datas, contagens e números de seção, e o relatório vira ruído ilegível.
UNIDADE = r"\s*(?:ns|µs|us|ms|s|%|×|x|GB/s|MB/s|MB|KB|GB|GHz|MHz|ciclos|pacotes)\b"


# Quão perto uma grafia curta tem de estar para ser O MESMO número dito de
# outro jeito. O limiar foi escolhido pelos casos reais, e a escolha é o que
# separa relatório de ruído:
#
#    18,2  -> 18     1,10%   <- defeito real, tem de entrar
#    82,99 -> 83     0,01%   <- defeito real, tem de entrar
#    17,50 -> 17     2,86%   <- defeito real, tem de entrar
#    91,5  -> 92     0,55%   <- LEGITIMO (a travessia mede 91,75), entra e
#                                 e triado por quem le: e o preco do relatorio
#    10,93 -> 10     8,51%   <- fora: "10 us" nao e o 10,93 retratado
#     7,68 -> 8      4,17%   <- fora
#    0,193 -> 0,1   48,2%    <- fora
#
# Sem ele o relatorio saiu com 254 candidatos, quase todos prosa comum, e
# relatorio ilegivel nao e lido -- que e a mesma morte do verificador ruidoso,
# uma casa antes.
TOLERANCIA_ARREDONDAMENTO = 0.03
MIN_SIGNIFICATIVOS_ARREDONDADO = 2


def arredondamentos(valor):
    """As grafias mais curtas que ainda SÃO o mesmo número.

    Duas por precisão, porque quem escreve faz as duas coisas: arredonda
    (17,50 -> 18) e trunca (17,50 -> 17). A de partida não entra: ela já é
    conferida literalmente pelo veredito."""
    sep = "," if "," in valor else "."
    bruto = float(valor.replace(",", "."))
    if bruto == 0.0:
        return set()
    dec = valor.partition(sep)[2]
    saida = set()
    for casas in range(len(dec) - 1, -1, -1):
        fator = 10 ** casas
        for v in (f"{bruto:.{casas}f}", f"{int(bruto * fator) / fator:.{casas}f}"):
            if v.replace(".", sep) == valor:
                continue
            if abs(float(v) - bruto) / abs(bruto) > TOLERANCIA_ARREDONDAMENTO:
                continue
            if len(v.replace(".", "").lstrip("0")) < MIN_SIGNIFICATIVOS_ARREDONDADO:
                continue
            saida.add(v)
    fora = set()
    for v in saida:
        fora.update(grafias(v))
    return fora


def relatar_arredondados(docs, mortos, raiz):
    """Candidatos a sobrevivente por arredondamento. NÃO entra no veredito."""
    # Chave (documento, candidato, linha): o MESMO valor retratado entra no
    # dicionario nas duas grafias, e sem a deduplicacao cada candidato saia
    # duas vezes -- o relatorio dobrava de tamanho sem dobrar de conteudo.
    achados = {}
    for doc in docs:
        try:
            vivo = fora_de_retratacao(open(doc, encoding="utf-8").read())
        except (OSError, UnicodeDecodeError):
            continue
        for n in sorted(mortos):
            for a in sorted(arredondamentos(n)):
                for linha in vivo.splitlines():
                    if re.search(r"(?<![\d.,])" + re.escape(a) + UNIDADE, linha):
                        chave = (os.path.relpath(doc, raiz), a, linha.strip()[:80])
                        achados.setdefault(chave, set()).add(n.replace(".", ","))
                        break
    achados = [(d, sorted(orig), a, l)
               for (d, a, l), orig in sorted(achados.items())]
    if not achados:
        return
    print(f"\n  ARREDONDADOS: {len(achados)} candidato(s) -- inventário de"
          f" trabalho, NÃO veredito.")
    print("  Cada linha publica um número seguido de unidade que é o"
          " arredondamento de um valor retratado.")
    print("  A maioria é legítima (92 ns é 91,75 medido, não 91,5 retratado):"
          " confira, não corrija em massa.")
    for doc, origens, a, linha in achados[:25]:
        print(f"    {doc}: '{a}' ~ retratado {' / '.join(origens)}")
        print(f"        {linha}")
    if len(achados) > 25:
        print(f"    ... e mais {len(achados) - 25}")


def arquivos(raiz, exts):
    for pasta, subpastas, nomes in os.walk(raiz):
        subpastas[:] = [d for d in subpastas if d not in IGNORAR and not d.startswith("build")]
        for nome in nomes:
            if os.path.splitext(nome)[1] in exts:
                yield os.path.join(pasta, nome)


def grafias(numero):
    """O mesmo valor nas duas linguas do material.

    A PARIDADE pt/en ABRIU ESTE BURACO, e ele foi medido antes de ser fechado:
    `122,3` declarado retratado sobrevivia como `122.3` no par `.en.md`, e este
    verificador ficava VERDE. O numero seguia publicado, so que com ponto.

    E o defeito que o projeto inteiro combate -- ausencia de deteccao lida como
    ausencia de problema --, cometido pela propria decisao de traduzir.
    """
    return {numero, numero.replace(",", "."), numero.replace(".", ",")}


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
                # Cada grafia entra como chave propria: o laço abaixo procura
                # literal, e o par em ingles escreve o mesmo valor com ponto.
                for g in grafias(n):
                    mortos.setdefault(g, []).append(doc)

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
            # A isencao vale para as duas grafias: quem declara citar `2,078`
            # de proposito esta citando o mesmo valor que o ingles escreve
            # `2.078`, e exigir as duas marcas seria burocracia sem ganho.
            for n in NUMERO.findall(m.group(1)):
                citados.update(grafias(n))
        if citados:
            isentos[os.path.relpath(doc, raiz)] = sorted(citados)
        for n, origens in sorted(mortos.items()):
            if n in vivo and n not in citados:
                onde = ", ".join(sorted(set(os.path.relpath(o, raiz) for o in origens)))
                for i, linha in enumerate(vivo.splitlines(), 1):
                    if aparece(n, linha):
                        print(f"  {os.path.relpath(doc, raiz)}: '{n}' foi RETRATADO"
                              f" (em {onde}) e continua publicado")
                        print(f"      {linha.strip()[:110]}")
                        problemas += 1
                        break

    if "--arredondados" in sys.argv:
        relatar_arredondados(docs, mortos, raiz)

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

    # DISTINTIVO, e este caso nasceu de uma campanha de mutacao: trocando o
    # corte por `return True`, o autoteste continuava verde. O corte existe para
    # que "5,0" nao vire ruido -- e um verificador ruidoso e desligado, que e a
    # forma mais comum de um controle morrer. Sem caso proprio, ninguem
    # perceberia se ele deixasse de cortar.
    #
    # Dois numeros no mesmo bloco: "120,0" tem tres significativos e E rastreado;
    # "5,0" tem um so e NAO deve ser. Se o corte cair, o "5,0" vivo la fora vira
    # sobrevivente e o caso acusa.
    # A marca declara "5,0", que tem UM significativo, e "5,0" aparece vivo fora
    # do bloco. Com o corte, ele nao e rastreado e nada acontece. Sem o corte,
    # vira sobrevivente e o verificador acusa -- entao este caso, que espera
    # SILENCIO, e quem morre quando o corte cai.
    bloco = ("# d\n\n> **Este bloco publicava 5,0 ns, e estava errado.** O medido\n"
             "> e 1,234 ns.\n> <!-- retratado: 5,0 -->\n\nA folga segue em 5,0 ns.\n")
    rc, saida = rodar({"d.md": bloco})
    if rc != 0:
        print(f"  AUTOTESTE (distintivo) FALHOU: numero de 1 significativo"
              f" tratado como rastreavel (rc={rc})")
        print("    " + saida.strip().replace("\n", "\n    "))
        falhas += 1

    # O corte tambem governa o AVISO de cobertura parcial: um bloco sem marca so
    # merece aviso se tiver numero rastreavel. Com "5,0" sozinho, avisar seria
    # ruido -- e verificador ruidoso e desligado. Este caso trava esse ramo, que
    # e de RELATO e nao muda o veredito; sem ele, a mutacao passava despercebida.
    rc, saida = rodar({"baixo.md":
        "# b\n\n> **Este bloco publicava 5,0 ns, e estava errado.** Agora e outro.\n"})
    if "COBERTURA PARCIAL" in saida:
        print("  AUTOTESTE FALHOU: bloco sem marca, com numero de 1 significativo,"
              " gerou aviso de cobertura parcial")
        falhas += 1

    # PARIDADE pt/en: o mesmo valor, a outra grafia.
    #
    # Este caso registra um buraco que existiu de verdade. Enquanto a paridade
    # era um resumo embutido em portugues, so havia uma grafia no material. Com
    # os pares `.en.md`, `122,3` retratado passou a poder sobreviver como
    # `122.3`, e o verificador ficava verde -- medido antes de ser fechado.
    rc, saida = rodar({"a.md": "# a\n\n> **Publicava 122,3 ms, e estava errado.**\n"
                               "> <!-- retratado: 122,3 -->\n",
                       "a.en.md": "# a\n\nThe cost is 122.3 ms, measured.\n"})
    if rc != 1:
        print(f"  AUTOTESTE (paridade) FALHOU: valor retratado sobreviveu na"
              f" grafia inglesa sem ser acusado (rc={rc})")
        print("    " + saida.strip().replace("\n", "\n    "))
        falhas += 1

    # E a isencao declarada tambem atravessa a lingua: quem cita de proposito
    # nao deve precisar de uma marca por grafia.
    rc, saida = rodar({"b.md": "# b\n\n> **Publicava 122,3 ms, e estava errado.**\n"
                               "> <!-- retratado: 122,3 -->\n",
                       "b.en.md": "# b\n\n<!-- cita-retratado: 122,3 -->\n"
                                  "The old figure was 122.3 ms.\n"})
    if rc != 0:
        print(f"  AUTOTESTE (paridade/isencao) FALHOU: citacao declarada em"
              f" portugues nao isentou a grafia inglesa (rc={rc})")
        print("    " + saida.strip().replace("\n", "\n    "))
        falhas += 1

    # Bloco de retratacao EM INGLES precisa ser reconhecido como bloco.
    #
    # Sem isto o par `.en.md` nao so deixava de ser conferido: a propria marca
    # `<!-- retratado: ... -->` dele contava como texto vivo, e o verificador
    # acusava o documento de republicar aquilo que estava retratando.
    rc, saida = rodar({"a.en.md":
        "# a\n\n> **This column used to publish 2.078 ns, and it does not"
        " reproduce.**\n> The measured value is 1.628 ns.\n"
        "> <!-- retratado: 2,078 -->\n\nThe ring costs 1.628 ns.\n"})
    if rc != 0:
        print(f"  AUTOTESTE (retratacao em ingles) FALHOU: bloco nao reconhecido"
              f" (rc={rc})")
        print("    " + saida.strip().replace("\n", "\n    "))
        falhas += 1

    # E o reconhecimento nao pode virar porta dos fundos: o valor retratado que
    # sobrevive FORA do bloco continua sendo acusado, em qualquer das grafias.
    rc, _ = rodar({"b.en.md":
        "# b\n\n> **This column used to publish 2.078 ns.**\n"
        "> <!-- retratado: 2,078 -->\n\nThe ring costs 2.078 ns.\n"})
    if rc != 1:
        print(f"  AUTOTESTE (retratacao em ingles) FALHOU: sobrevivente fora do"
              f" bloco passou (rc={rc})")
        falhas += 1

    # A DIRECAO PERIGOSA: marcador frouxo afrouxa o verificador em silencio.
    #
    # Um bloco de citacao que apenas MENCIONA o valor, sem se anunciar como
    # retratacao, tem de continuar sendo acusado. Sem este caso, acrescentar
    # uma frase comum a MARCADORES -- "ring costs", "the cost is" -- isentaria
    # prosa normal e nada falharia. Medido: o mutante sobrevivia.
    rc, _ = rodar({"r.md": "# r\n\n> **This column used to publish 2.078 ns.**\n"
                           "> <!-- retratado: 2,078 -->\n",
                   "c.en.md": "# c\n\n> The ring costs 2.078 ns per hand-off.\n"})
    if rc != 1:
        print(f"  AUTOTESTE (marcador frouxo) FALHOU: citacao comum tratada como"
              f" retratacao, e o valor retratado passou (rc={rc})")
        falhas += 1

    # N. O valor retratado como PEDAÇO de outro número maior NAO e o valor.
    #    Este caso reproduz a colisao real: `17.1` dentro de `17.197%` e
    #    `65,3` dentro de `1 365 373`. Com a busca por substring pura, os dois
    #    acusavam -- e a saida na epoca foi tirar o valor da marca, o que
    #    enfraquece o controle em vez de consertar o casamento.
    rc, _ = rodar({
        "retrata.md": "# r\n\n> **Este bloco publicava 17,197 ns.**\n"
                      "> <!-- retratado: 17,197 -->\n",
        "vizinho.md": "# v\n\n| perda | 17,1975 % |\n| taxa | 117,197 |\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: numero maior que CONTEM o retratado acusou")
        falhas += 1

    #    E o inverso continua valendo: o valor exato tem de ser pego.
    rc, _ = rodar({
        "retrata.md": "# r\n\n> **Este bloco publicava 17,197 ns.**\n"
                      "> <!-- retratado: 17,197 -->\n",
        "sobrevive.md": "# s\n\n| custo | 17,197 ns |\n"})
    if rc != 1:
        print("  AUTOTESTE FALHOU: o valor exato deixou de ser pego"); falhas += 1

    # MARCADOR QUEBRADO EM DUAS LINHAS. Sem o achatamento, este bloco nao e
    # reconhecido, a marca dele conta como texto vivo, e o verificador acusa o
    # documento de republicar o valor que ele esta retratando -- rc vira 1.
    rc, saida = rodar({"q.en.md":
        "# q\n\n> **This table used to\n> publish 0.924 ns, and it was wrong.**\n"
        "> The measured value is 0.717 ns.\n> <!-- retratado: 0,924 -->\n\n"
        "The call costs 0.717 ns.\n"})
    if rc != 0:
        print(f"  AUTOTESTE (marcador quebrado) FALHOU: frase-marcador partida"
              f" em duas linhas nao foi reconhecida (rc={rc})")
        print("    " + saida.strip().replace("\n", "\n    "))
        falhas += 1

    # ARREDONDAMENTO: a funcao que decide o que entra no relatorio.
    #
    # Ela nao muda veredito, e por isso e a primeira candidata a apodrecer sem
    # ninguem notar. Os casos abaixo sao os numeros REAIS que motivaram o
    # relatorio, dos dois lados do limiar.
    for valor, esperado, motivo in [
        ("18,2",  "18",   "o defeito de 19/09: '11 a 18 ns' publicado seis vezes"),
        ("82,99", "83",   "o §4.2.1 publicava 'mais de 80'"),
        ("17,50", "17",   "o §4.2.1 publicava '17 ns'"),
    ]:
        if esperado not in arredondamentos(valor):
            print(f"  AUTOTESTE (arredondamento) FALHOU: {valor} -> {esperado}"
                  f" nao entrou, e {motivo}")
            falhas += 1
    for valor, proibido, motivo in [
        ("10,93", "10",  "8,5% de distancia: '10 us' e outro numero"),
        ("7,68",  "8",   "4,2% de distancia"),
        ("0,193", "0,1", "48% de distancia, e um significativo so"),
    ]:
        if proibido in arredondamentos(valor):
            print(f"  AUTOTESTE (arredondamento) FALHOU: {valor} -> {proibido}"
                  f" entrou, e nao devia -- {motivo}")
            falhas += 1
    # E o relatorio NAO pode mexer no veredito: esta e a propriedade que o
    # separa de um gate, e a que alguem quebraria ao "melhorar" o verificador.
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "a.md"), "w", encoding="utf-8").write(
            "# a\n\n> **Publicava 18,2 ns, e estava errado.**\n"
            "> <!-- retratado: 18,2 -->\n\nO ganho vai de 11 a 18 ns por acesso.\n")
        buf = _io.StringIO()
        sys.argv.append("--arredondados")
        try:
            with redirect_stdout(buf):
                rc = verificar(d)
        finally:
            sys.argv.remove("--arredondados")
    if rc != 0:
        print(f"  AUTOTESTE (arredondamento) FALHOU: o relatorio mudou o"
              f" veredito (rc={rc}) -- ele e inventario, nao gate")
        falhas += 1
    if "ARREDONDADOS" not in buf.getvalue() or "'18'" not in buf.getvalue():
        print("  AUTOTESTE (arredondamento) FALHOU: o caso real de 19/09"
              " nao apareceu no relatorio")
        falhas += 1

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    # As flags nao sao caminho. Sem este filtro, `--arredondados` virava o alvo
    # do os.walk, a arvore saia vazia e o relatorio imprimia "0 documentos" --
    # um verde por nao ter procurado, que e o defeito que este arquivo combate.
    posicionais = [a for a in sys.argv[1:] if not a.startswith("-")]
    alvo = posicionais[0] if posicionais else "."
    sys.exit(1 if verificar(alvo) else 0)
