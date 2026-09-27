#!/usr/bin/env python3
"""Compara coletas da MESMA máquina sob configurações de hardware diferentes.

POR QUE ESTE ARQUIVO EXISTE

Em 20/09/2026 o EXPO 6000 foi ligado na placa e a latência de RAM caiu 12%. Em
três dias um segundo pente entra no slot B2 e a máquina passa de canal único a
duplo. Os números publicados até aqui descrevem uma configuração que deixou de
existir -- e o repositório não registrava qual era, porque `ambiente.sh` não
tinha o campo.

A lição não é "faltou um campo". É que **hardware é variável experimental**, e
este projeto vinha tratando a máquina como constante. Uma medição sem a
configuração declarada não é reproduzível; é anedota com selo.

POR QUE GERADO, E NÃO DIGITADO

A tabela comparativa poderia ser escrita à mão. Seria o terceiro lugar onde um
número é digitado neste repositório, e os dois primeiros já custaram um portão
cada: a paridade pt/en e a divergência de rótulos bibliográficos. Um número
digitado envelhece em silêncio; um número extraído da saída do programa
envelhece junto com ela, que é o comportamento certo.

A ENTRADA

Um diretório por configuração, contendo a saída bruta dos programas, uma por
execução:  <programa>.r<N>.txt

A execução `r0` é descartada: ela é o aquecimento, e a campanha anterior provou
que isso importa -- em `custo-mckenney`, quatro linhas foram acusadas como dois
regimes e nas quatro o destoante era a primeira execução.
"""
import io
import os
import pathlib
import re
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import condicao_coleta  # noqa: E402
from rotulos import normalizar  # noqa: E402

# O LIMIAR DE MOVIMENTO E RELATIVO A DISPERSAO DO PROPRIO ROTULO, e nao um
# numero fixo. A razao esta medida.
#
# Ate 26/09/2026 a marca era `abs(delta) > 5%` para todos. Medido sobre as
# coletas arquivadas de mesma configuracao e mesma condicao: das 95 grandezas
# com cinco coletas ou mais, QUARENTA -- 42% -- ja variam mais de 5% entre
# coletas em que nada mudou. A mediana varia 2,0%; a cauda chega a 159%.
#
# O efeito pratico era duplo e nos dois sentidos errados. Entre dois pares de
# texto do mesmo hardware a marca acusava 8 rotulos na mediana, todos ruido --
# e por isso a previsao do passo 6 da campanha saia "REFUTADA" sempre. E na
# unica comparacao em que havia efeito real para achar -- texto contra sessao
# grafica, 26/09 -- ela NAO marcou as duas grandezas que o teste de postos
# identificou, `mutex + condvar` e `POSIX semaphore`, porque as duas se movem
# 3,3% e 3,8%: abaixo do corte fixo.
#
# A regra nova marca quando o passo excede DUAS VEZES a amplitude historica do
# rotulo. Calibrada nos dez pares de coletas expo6000 de modo texto, ela da
# mediana de 1 marca (faixa 0 a 2), contra 8 da regra fixa; e contra a coleta
# grafica ela marca as duas que dormem.
#
# O PISO DE 1% existe porque amplitude historica pequena nao autoriza
# sensibilidade infinita: um rotulo que variou 0,05% entre coletas nao torna
# um passo de 0,3% um achado -- torna-o um digito.
FATOR_AMPLITUDE = 2.0
PISO_PCT = 1.0

# Duas formas de tabela convivem no repositório, e um parser que só entenda a
# primeira falha em SILÊNCIO sobre a segunda -- foi assim que `custo-mckenney`
# passou despercebido numa campanha inteira.
LINHA = re.compile(r"^\s{2,}(\S.*?)\s{2,}(\d+\.\d+)\s")
NIVEL = re.compile(r"^  (L1d|L2|L3|RAM) ")
SUB = re.compile(r"^    (sequencial|aleatorio|dependente|sequential|random|dependent)\s+\S*\s+(\d+\.\d+)\s")
SUB_EN = {"sequencial": "sequential", "aleatorio": "random", "dependente": "dependent"}


def coletar(diretorio):
    """{rótulo: [medianas, uma por execução]}, descartando a r0.

    ERRO EXPLICADO, E NAO RASTREIO DE PILHA

    A primeira vez que este comando foi usado de verdade, foi chamado ANTES da
    campanha que produz os dados -- que e a ordem natural de quem acabou de
    trocar um ajuste na BIOS e quer ver a diferenca. A resposta foi um
    `FileNotFoundError` com dez linhas de pilha.

    O usuario tinha feito a coisa certa e a ferramenta o tratou como defeito.
    Ferramenta de analise que responde assim treina quem a usa a desconfiar do
    proprio raciocinio em vez do proprio comando.
    """
    if not os.path.isdir(diretorio):
        print(f"  diretorio nao existe: {diretorio}")
        print(f"  a coleta precisa ser feita antes da comparacao:")
        print(f"    ./ferramental/qualidade/campanha-hardware.sh {os.path.basename(diretorio.rstrip('/'))}")
        return None
    fora = {}
    for nome in sorted(os.listdir(diretorio)):
        m = re.match(r"(.+)\.r(\d+)\.txt$", nome)
        if not m or m.group(2) == "0":
            continue
        prog = m.group(1)
        nivel = None
        vistos = {}
        for ln in open(os.path.join(diretorio, nome), encoding="utf-8", errors="replace"):
            n = NIVEL.match(ln)
            if n:
                nivel = n.group(1)
                continue
            s = SUB.match(ln)
            if s and nivel:
                col = SUB_EN.get(s.group(1), s.group(1))
                fora.setdefault(f"{prog}: {nivel} {col}", []).append(float(s.group(2)))
                continue
            c = LINHA.match(ln.rstrip())
            if c:
                rot = c.group(1).strip()
                if rot.startswith("-") or "medicao" in rot or "measurement" in rot:
                    continue
                # ROTULO PURAMENTE NUMERICO E COLUNA, NAO MEDICAO.
                #
                # O `custo-paralelismo` publica a mesma grandeza duas vezes: na
                # tabela estatistica, com rotulo (`1 nucleo`), e numa
                # tabela-resumo cuja primeira coluna e o numero de nucleos.
                # Lendo as duas, o comparativo emitia `1`, `1 #2` e `1 nucleo`
                # para a MESMA medicao -- e rotulo ambiguo num comparativo e
                # pior que linha faltando: quem le depois nao tem como saber
                # qual das tres citar.
                if rot.isdigit():
                    continue
                # NORMALIZA O IDIOMA DO ROTULO.
                #
                # A partir de 20/09/2026 os programas imprimem em ingles, e as
                # 92 coletas ja arquivadas estao em portugues. O rotulo e a
                # CHAVE da comparacao: sem normalizar, uma coleta nova
                # comparada com uma antiga mostraria toda linha como ausente de
                # um dos lados -- e o fatorial 2x2 do segundo pente compara
                # exatamente atraves dessa fronteira.
                rot = normalizar(rot)
                k = vistos.get(rot, 0)
                vistos[rot] = k + 1
                chave = f"{prog}: {rot}" + (f" #{k+1}" if k else "")
                fora.setdefault(chave, []).append(float(c.group(2)))
    return fora


def configuracao(diretorio):
    """`2026-09-25-1720-expo6000-canal-duplo` -> `expo6000-canal-duplo`.

    A configuracao e o que vem DEPOIS do carimbo. Compara-la importa porque a
    amplitude de um rotulo sensivel a memoria e outra em 4800 e em 6000: medir
    a dispersao misturando as duas inflaria o limiar justamente onde ele
    precisa ser apertado.
    """
    nome = os.path.basename(str(diretorio).rstrip("/"))
    m = re.match(r"^\d{4}-\d{2}-\d{2}-\d{4}-(.+)$", nome)
    return m.group(1) if m else None


def irmas(diretorio):
    """As coletas arquivadas de MESMA configuracao e MESMA condicao de sessao.

    Exclui a propria: a amplitude tem de ser a do historico contra o qual a
    coleta nova sera julgada, e incluir a julgada faria o limiar crescer
    junto com o desvio que ele deveria acusar.
    """
    d = os.path.abspath(str(diretorio).rstrip("/"))
    base, conf, cond = os.path.dirname(d), configuracao(d), condicao_coleta.e_texto(d)
    if conf is None:
        return []
    fora = []
    for nome in sorted(os.listdir(base)):
        outro = os.path.join(base, nome)
        if outro == d or not os.path.isdir(outro):
            continue
        if configuracao(outro) != conf or condicao_coleta.e_texto(outro) != cond:
            continue
        fora.append(outro)
    return fora


def amplitudes(diretorio):
    """{rotulo: amplitude relativa, em %} sobre as coletas irmas.

    Amplitude e `(max - min) / mediana`, ordinal e sem suposicao de
    distribuicao -- o mesmo criterio que os consolidadores deste projeto usam.
    Rotulo com menos de tres irmas nao tem amplitude: tres e o minimo para que
    `max - min` signifique alguma coisa, e abaixo disso o limiar volta ao piso.
    """
    art_ref = artefatos(diretorio)
    por = {}
    for outro in irmas(diretorio):
        art_irma = artefatos(outro)
        for k, v in coletar(outro).items():
            if not (v and len(v) >= 2):
                continue
            prog = programa_do_rotulo(k)
            a = sha_texto_valido((art_ref.get(prog) or {}).get("text_sha256"))
            b = sha_texto_valido((art_irma.get(prog) or {}).get("text_sha256"))
            # A REGUA E DE UM INSTRUMENTO SO, e esta era a metade que faltava.
            #
            # Filtrar irmas por configuracao e condicao nao basta: a amplitude
            # de `neighbour on physical core` nas quatro irmas da coleta de
            # 26/09/2026 e 0,00% -- as quatro deram o MESMO valor -- enquanto
            # trocar so `-falign-loops` move o rotulo 15,8%. A regua media a
            # reprodutibilidade de UMA familia de artefatos e era aplicada a
            # uma comparacao ENTRE familias.
            #
            # O LEGADO E AUSENCIA DE BLOCO, e nao "identidade invalida".
            #
            # A condicao era `a is None and b is None`, e como `sha_texto_valido`
            # devolve None tambem para `nao-disponivel`, duas coletas que
            # DECLARAM nao ter `.text` caiam no ramo do legado -- tratadas como
            # anteriores ao mecanismo, que nao sao. Perguntar pelo bloco separa
            # "nunca registrou" de "registrou que nao ha".
            #
            # Coleta anterior a 27/09/2026 entra: o portao ja bloqueia a marca
            # dela por `SEM_IDENTIDADE`, entao a amplitude e informativa e nao
            # autoriza um `<<<`.
            legado = prog not in art_ref and prog not in art_irma
            if (a and b and a == b) or legado:
                por.setdefault(k, []).append(st.median(v))
    saida = {}
    for k, v in por.items():
        if len(v) >= 3 and st.median(v) > 0:
            saida[k] = (max(v) - min(v)) / st.median(v) * 100.0
    return saida


def limiar(amplitude):
    """O corte para este rotulo em %, ou None quando nao ha regua.

    SEM AMPLITUDE NAO HA MARCA. Uma coleta cuja configuracao e condicao nao
    tem irmas arquivadas -- a primeira de um hardware novo, ou a primeira com
    sessao grafica -- nao tem historico contra o que ser julgada. Cair num
    piso fixo ali seria repetir o defeito que esta funcao existe para
    corrigir: marcar por um numero que ninguem mediu. O resumo conta quantos
    ficaram sem regua, e isso e o veredito honesto sobre eles.
    """
    if amplitude is None:
        return None
    return max(PISO_PCT, FATOR_AMPLITUDE * amplitude)


def artefatos(diretorio):
    """{programa: {campo: valor}} lido dos blocos `# ARTIFACT` do manifesto.

    O `origin:` que cada programa imprime identifica a FONTE. Nao identifica o
    INSTRUMENTO: o mesmo commit compilado com `-falign-loops` 16, 32, 64 e 128
    da quatro `.text` diferentes, e a razao `with/without SMT sibling` varia
    20% entre eles. Sao identidades separadas, e e a terceira que decide se
    duas medicoes vieram do mesmo aparelho:

        source_origin   qual fonte produziu o programa
        binary_sha256   qual arquivo ELF foi executado
        text_sha256     qual codigo executavel foi produzido  <- a autoridade

    Coleta anterior a 27/09/2026 nao tem esses blocos, e ai a resposta e vazia
    -- que NAO e o mesmo que "os artefatos sao iguais".
    """
    man = os.path.join(str(diretorio).rstrip("/"), "manifesto.txt")
    saida, atual = {}, None
    try:
        with io.open(man, encoding="utf-8", errors="replace") as fh:
            for linha in fh:
                m = re.match(r"^#\s*ARTIFACT\s+(\S+)", linha)
                if m:
                    atual = m.group(1)
                    saida[atual] = {}
                    continue
                # `[a-z_0-9]` E NAO `[a-z_]`: `text_sha256` tem digitos, e a primeira
                # versao deste regex lia `source_origin` e `build_id` e deixava
                # passar em SILENCIO justamente o campo que decide a comparacao.
                # O autoteste 13 pegou; sem ele, o portao responderia
                # "sem identidade" para todo manifesto que o tivesse.
                m = re.match(r"^#\s+([a-z_0-9]+)=(.*)$", linha.rstrip("\n"))
                if m and atual:
                    saida[atual][m.group(1)] = m.group(2)
    except OSError:
        return {}
    return saida


def programa_do_rotulo(rotulo):
    """`custo-comunicacao: 1 thread ...` -> `custo-comunicacao`."""
    return rotulo.split(":", 1)[0].strip() if ":" in rotulo else None


def classificacao_leiaute():
    """{rotulo: INVARIAVEL|SENSIVEL|DOMINADO} do arquivo declarado.

    AUSENTE NAO E INVARIAVEL. Um rotulo que nao esta na lista nao foi
    caracterizado, e a resposta honesta sobre ele e "identificabilidade nao
    estabelecida" -- nem permissao, nem proibicao.
    """
    caminho = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "sensibilidade-leiaute.tsv")
    fora = {}
    try:
        with io.open(caminho, encoding="utf-8") as fh:
            for linha in fh:
                if linha.startswith("#") or not linha.strip():
                    continue
                partes = linha.rstrip("\n").split("\t")
                if len(partes) >= 2:
                    fora[partes[0]] = partes[1].strip().upper()
    except OSError:
        pass
    return fora


# O QUE A FERRAMENTA PODE AFIRMAR, POR ROTULO.
#
# Ela existe para detectar mudanca da MAQUINA. Quando o instrumento binario
# muda junto, a diferenca observada tem duas causas possiveis e a ferramenta
# nao tem como separa-las -- entao ela recusa a inferencia em vez de emitir
# uma conclusao com um asterisco.
COMPARAVEL, NAO_ESTABELECIDO, NAO_COMPARAVEL, SEM_IDENTIDADE = range(4)

# A palavra que a campanha grava quando o campo nao existe para aquele alvo.
AUSENTE = "nao-disponivel"

# O sha256 da ENTRADA VAZIA. Alvo sem secao `.text` -- um script -- produzia
# este valor, e dois alvos diferentes coincidiam nele.
SHA_DO_VAZIO = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


def sha_texto_valido(bruto):
    """O `text_sha256` utilizavel, ou None. PRESENCA NAO IMPLICA VALIDADE.

    Um campo usado como autoridade tem quatro modos de ser invalido, e os
    quatro apareceram neste projeto em 27/09/2026:

        chave ausente         -- coleta anterior ao mecanismo
        chave presente vazia  -- um auxiliar faltou e ninguem viu
        sentinela             -- `nao-disponivel`, que e uma string truthy
        valor fora do dominio -- o sha do vazio, que COINCIDE entre alvos

    Nenhum dos quatro pode significar "mesmo instrumento". Concentrar a regra
    aqui evita que cada sitio de uso reinvente uma metade dela -- foi assim que
    a sentinela passou pelo `if not a or not b`.
    """
    if not bruto:
        return None
    valor = bruto.strip().lower()
    # O SHA DO VAZIO E O CASO TRAICOEIRO: ele esta DENTRO do dominio -- 64 hex
    # legitimos -- e coincide entre todo alvo sem secao `.text`. A sentinela
    # `nao-disponivel` e a string vazia caem no dominio abaixo sozinhas, e
    # testa-las aqui de novo seria um ramo que nenhuma mutacao distingue.
    if valor == SHA_DO_VAZIO:
        return None
    if not re.fullmatch(r"[0-9a-f]{64}", valor):
        return None
    return valor


def estado_de_comparacao(rotulo, art_base, art_novo, classes):
    """Decide o que se pode afirmar sobre este rotulo. Ver COMPARAVEL etc."""
    prog = programa_do_rotulo(rotulo)
    a = sha_texto_valido((art_base.get(prog) or {}).get("text_sha256"))
    b = sha_texto_valido((art_novo.get(prog) or {}).get("text_sha256"))
    if a is None or b is None:
        return SEM_IDENTIDADE
    if a == b:
        return COMPARAVEL
    classe = classes.get(rotulo)
    if classe == "INVARIAVEL":
        return COMPARAVEL
    if classe in ("SENSIVEL", "DOMINADO"):
        return NAO_COMPARAVEL
    return NAO_ESTABELECIDO


def comparar(dirs, rotulos):
    dados = [coletar(d) for d in dirs]
    if any(d is None for d in dados):
        return 1
    vazios = [dirs[i] for i, d in enumerate(dados) if not d]
    if vazios:
        for v in vazios:
            n = len([x for x in os.listdir(v) if x.endswith(".txt")])
            print(f"  nada reconhecido em {v} ({n} arquivo(s) .txt)")
            print("  a campanha pode estar em curso: r1 em diante e que contam, r0 e aquecimento")
        return 1
    # A AMPLITUDE E A DA COLETA NOVA, que e a ultima da linha de comando: e ela
    # que esta sendo julgada contra o historico dela.
    amps = amplitudes(dirs[-1])
    art_base, art_novo = artefatos(dirs[0]), artefatos(dirs[-1])
    classes = classificacao_leiaute()
    contagem = {COMPARAVEL: 0, NAO_ESTABELECIDO: 0, NAO_COMPARAVEL: 0, SEM_IDENTIDADE: 0}
    chaves = sorted(set().union(*[set(d) for d in dados]))
    largura = max(len(k) for k in chaves) if chaves else 10
    cab = "  " + "medicao".ljust(largura) + "".join(f"  {r:>14}" for r in rotulos) + "   delta"
    print(cab)
    print("  " + "-" * (len(cab) - 2))
    for k in chaves:
        vals = []
        for d in dados:
            v = d.get(k)
            vals.append(st.median(v) if v and len(v) >= 2 else None)
        if vals[0] is None or all(v is None for v in vals[1:]):
            continue
        cels = "".join(f"  {('%14.3f' % v) if v is not None else '             -'}" for v in vals)
        delta = ""
        if len(vals) > 1 and vals[0] and vals[-1]:
            d = 100.0 * (vals[-1] - vals[0]) / vals[0]
            # O PORTAO DO ARTEFATO VEM ANTES DA REGUA, e a ordem e o ponto:
            # nao adianta medir bem um desvio que pode nao ser da maquina.
            est = estado_de_comparacao(k, art_base, art_novo, classes)
            contagem[est] += 1
            if est == NAO_COMPARAVEL:
                delta = f"  {d:+6.1f}%  NAO COMPARAVEL ENTRE ARTEFATOS"
            elif est == NAO_ESTABELECIDO:
                delta = f"  {d:+6.1f}%  artefatos diferentes -- identificabilidade nao estabelecida"
            elif est == SEM_IDENTIDADE:
                # `SEM_IDENTIDADE` CAIA NO RAMO NORMAL e podia marcar `<<<`,
                # contradizendo o resumo que o proprio arquivo imprime tres
                # telas abaixo: "ausencia de identidade NAO e prova de que o
                # instrumento foi o mesmo". Os quatro estados sao exclusivos.
                delta = f"  {d:+6.1f}%  SEM IDENTIDADE DE ARTEFATO"
            else:
                a = amps.get(k)
                lim = limiar(a)
                # A AMPLITUDE VAI IMPRESSA ao lado do delta. Marca sem a regua que a
                # produziu obriga quem le a confiar; com ela, da para discordar.
                regua = "  (amp %5.1f%%)" % a if a is not None else "  (sem regua)"
                marca = "  <<<" if lim is not None and abs(d) > lim else ""
                delta = f"  {d:+6.1f}%{regua}{marca}"
        print("  " + k.ljust(largura) + cels + delta)
    n_amp = sum(1 for k in chaves if k in amps)
    print(f"\n  {len(chaves)} rotulo(s); mediana das medianas, execucao de aquecimento descartada")
    n_irmas = len(irmas(dirs[-1]))
    print(f"  marca: |delta| > max({PISO_PCT:.0f}%, {FATOR_AMPLITUDE:.0f}x a amplitude do rotulo "
          f"em {n_irmas} coleta(s) irma(s) de mesma configuracao e condicao)")
    if n_amp < len(chaves):
        print(f"  SEM REGUA: {len(chaves) - n_amp} rotulo(s) sem amplitude historica -- nao "
              f"foram julgados, e nenhuma marca acima cobre eles")
    relatar_artefatos(art_base, art_novo, contagem, rotulos)
    return 0


def relatar_artefatos(art_base, art_novo, contagem, rotulos):
    """Diz de qual INSTRUMENTO cada lado veio, e o que isso permite afirmar."""
    if contagem[SEM_IDENTIDADE]:
        print(f"\n  SEM IDENTIDADE DE ARTEFATO: {contagem[SEM_IDENTIDADE]} rotulo(s). Uma das")
        print("  coletas e anterior a 27/09/2026 e nao registra `# ARTIFACT` no manifesto.")
        print("  Ausencia de identidade NAO e prova de que o instrumento foi o mesmo.")
    if contagem[NAO_ESTABELECIDO] or contagem[NAO_COMPARAVEL]:
        print(f"\n  ARTEFATOS DIFERENTES entre {rotulos[0]} e {rotulos[-1]}:")
        for prog in sorted(set(art_base) | set(art_novo)):
            a = (art_base.get(prog) or {}).get("text_sha256", "-")
            b = (art_novo.get(prog) or {}).get("text_sha256", "-")
            if a != b:
                print(f"    {prog}")
                print(f"      text_sha256 base : {a}")
                print(f"      text_sha256 nova : {b}")
        if contagem[NAO_ESTABELECIDO]:
            print(f"    {contagem[NAO_ESTABELECIDO]} rotulo(s) com identificabilidade NAO ESTABELECIDA:")
            print("    nao ha caracterizacao de sensibilidade ao leiaute para eles, entao a")
            print("    diferenca observada tem duas causas possiveis -- maquina e instrumento")
            print("    -- e esta ferramenta nao separa as duas. Ver sensibilidade-leiaute.tsv.")
        if contagem[NAO_COMPARAVEL]:
            print(f"    {contagem[NAO_COMPARAVEL]} rotulo(s) NAO COMPARAVEIS: sensibilidade ao")
            print("    leiaute demonstrada para eles, e o artefato mudou.")


def autoteste():
    import tempfile
    falhas = 0

    def caso(n, descricao, obtido, esperado):
        nonlocal falhas
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    caso(1, "configuracao e o que vem depois do carimbo",
         configuracao("/x/2026-09-25-1720-expo6000-canal-duplo"), "expo6000-canal-duplo")
    caso(2, "nome sem carimbo nao tem configuracao",
         configuracao("/x/coleta-solta"), None)

    # 3 a 6. O LIMIAR. Sem amplitude nao ha corte -- e o caso que separa "nao
    #    se moveu" de "nao da para dizer se se moveu".
    caso(3, "sem amplitude nao ha limiar", limiar(None), None)
    caso(4, "amplitude pequena cai no piso", limiar(0.05), PISO_PCT)
    caso(5, "amplitude grande manda", limiar(9.0), 18.0)
    caso(6, "o fator e 2, nao 1", limiar(3.0), 6.0)

    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp) / "historico"
        base.mkdir()

        def coleta(nome, valores, graficos=0):
            d = base / nome
            d.mkdir()
            (d / "ambiente.txt").write_text(
                "  sessao grafica ......... %d processo(s); graphical.target x; "
                "alvo padrao y\n" % graficos)
            for i, v in enumerate(valores, start=1):
                (d / ("prog.r%d.txt" % i)).write_text(
                    "  custo alvo          %.3f  1.0-1.0   1.0-1.0   0.0%%\n" % v)
            return d

        # Quatro irmas de mesma configuracao e condicao, e uma de OUTRA
        # configuracao que nao pode entrar na regua.
        a1 = coleta("2026-09-01-0100-expo6000-canal-duplo", [10.0, 10.0])
        a2 = coleta("2026-09-02-0100-expo6000-canal-duplo", [10.2, 10.2])
        a3 = coleta("2026-09-03-0100-expo6000-canal-duplo", [10.4, 10.4])
        outra = coleta("2026-09-04-0100-jedec4800-canal-duplo", [50.0, 50.0])
        # MESMA CONFIGURACAO, outra condicao. O sufixo tem de ser identico: se
        # a grafica tivesse nome proprio, o filtro de configuracao a excluiria
        # sozinho e o de condicao passaria sem ser testado.
        graf = coleta("2026-09-05-0100-expo6000-canal-duplo", [10.1, 10.1], graficos=2)
        nova = coleta("2026-09-06-0100-expo6000-canal-duplo", [10.3, 10.3])

        irm = sorted(os.path.basename(x) for x in irmas(nova))
        caso(7, "as irmas sao so as de mesma configuracao e condicao",
             irm, [os.path.basename(str(x)) for x in (a1, a2, a3)])
        caso(8, "a configuracao diferente fica de fora",
             os.path.basename(str(outra)) in irm, False)
        caso(9, "a coleta grafica fica de fora de uma referencia de texto",
             os.path.basename(str(graf)) in irm, False)

        # 10. A AMPLITUDE E (max-min)/mediana sobre as irmas: 10,0 a 10,4 sobre
        #     mediana 10,2 da 3,92%.
        amps = amplitudes(nova)
        caso(10, "amplitude = (max-min)/mediana, em %%",
             round(amps.get("prog: custo alvo", -1.0), 2), 3.92)

        # 11. MENOS DE TRES IRMAS NAO DA AMPLITUDE. Com duas, `max - min` e um
        #     par de pontos, e chamar isso de dispersao seria inventar regua.
        # DUAS irmas, que e o caso de fronteira: `max - min` sobre dois pontos
        # e um par, nao dispersao. Com uma irma so o corte de tres nem seria
        # exercitado -- o de dois ja falharia.
        so_duas = coleta("2026-09-07-0100-soduas-x", [1.0, 1.0])
        coleta("2026-09-08-0100-soduas-x", [1.1, 1.1])
        coleta("2026-09-09-0100-soduas-x", [1.2, 1.2])
        caso(11, "com duas irmas nao ha amplitude", amplitudes(so_duas), {})
        # E com tres ha: e a fronteira pelo outro lado.
        caso(12, "com tres irmas ha amplitude",
             "prog: custo alvo" in amplitudes(coleta("2026-09-10-0100-soduas-x", [1.3, 1.3])), True)

        # 13 a 20. O PORTAO DO ARTEFATO.
        #
        # A ferramenta existe para detectar mudanca da MAQUINA. Quando o
        # instrumento binario muda junto, a diferenca tem duas causas possiveis
        # e ela nao separa as duas -- entao recusa a inferencia em vez de
        # marcar com um asterisco.
        def manifesto(d, text_sha):
            with io.open(os.path.join(str(d), "manifesto.txt"), "w", encoding="utf-8") as fh:
                fh.write("%-40s %-7s %s\n" % ("CELL", "STATUS", "RC"))
                fh.write("# ARTIFACT prog\n")
                fh.write("#   source_origin=v0.0.0-1-gabc\n")
                fh.write("#   text_sha256=%s\n" % text_sha)
                fh.write("%-40s %-7s %s\n" % ("prog.r1.txt", "PASS", "0"))

        base = coleta("2026-09-20-0100-artef-x", [1.0, 1.0])
        novo = coleta("2026-09-21-0100-artef-x", [1.0, 1.0])
        # HASHES DO DOMINIO REAL nos fixtures. Com "aaa"/"bbb" o teste passava
        # por acidente enquanto o codigo aceitava qualquer string; assim que a
        # validade virou regra, os fixtures reprovaram -- corretamente.
        SHA_A, SHA_B = "a" * 64, "b" * 64
        manifesto(base, SHA_A)
        manifesto(novo, SHA_B)
        ab, an = artefatos(base), artefatos(novo)
        caso(13, "o bloco ARTIFACT e lido do manifesto",
             ab.get("prog", {}).get("text_sha256"), SHA_A)
        caso(14, "o comentario nao vira celula",
             ab.get("prog", {}).get("source_origin"), "v0.0.0-1-gabc")
        caso(15, "artefato igual -> comparavel",
             estado_de_comparacao("prog: x", ab, ab, {}), COMPARAVEL)
        caso(16, "artefato diferente e rotulo nao caracterizado -> nao estabelecido",
             estado_de_comparacao("prog: x", ab, an, {}), NAO_ESTABELECIDO)
        caso(17, "artefato diferente e rotulo SENSIVEL -> nao comparavel",
             estado_de_comparacao("prog: x", ab, an, {"prog: x": "SENSIVEL"}), NAO_COMPARAVEL)
        caso(18, "artefato diferente e rotulo DOMINADO -> nao comparavel",
             estado_de_comparacao("prog: x", ab, an, {"prog: x": "DOMINADO"}), NAO_COMPARAVEL)
        # A PERMISSAO SO VEM DE CARACTERIZACAO, e por isso ela e explicita.
        caso(19, "artefato diferente e rotulo INVARIAVEL -> comparavel",
             estado_de_comparacao("prog: x", ab, an, {"prog: x": "INVARIAVEL"}), COMPARAVEL)
        # AUSENCIA DE IDENTIDADE NAO E IDENTIDADE IGUAL: coleta velha nao
        # registra artefato, e dizer "comparavel" ali seria inventar a garantia.
        caso(20, "sem bloco ARTIFACT -> sem identidade",
             estado_de_comparacao("prog: x", {}, an, {}), SEM_IDENTIDADE)
        caso(21, "rotulo sem programa nao quebra o portao",
             estado_de_comparacao("sem-dois-pontos", ab, an, {}), SEM_IDENTIDADE)
        # 22. `nao-disponivel` E AUSENCIA, e nao um valor que possa coincidir.
        #     Dois alvos sem secao `.text` -- scripts -- gravam a mesma palavra,
        #     e compara-la por igualdade os faria passar por mesmo instrumento.
        nd = {"prog": {"text_sha256": "nao-disponivel"}}
        caso(22, "`nao-disponivel` dos dois lados nao e equivalencia",
             estado_de_comparacao("prog: x", nd, nd, {}), SEM_IDENTIDADE)
        caso(23, "campo vazio tambem e ausencia",
             estado_de_comparacao("prog: x", {"prog": {"text_sha256": ""}}, an, {}),
             SEM_IDENTIDADE)
        # 23b. OS QUATRO MODOS DE INVALIDO, num lugar so. O sha do vazio e o
        #      mais traicoeiro: e um hash legitimo, de 64 hex, que COINCIDE
        #      entre todo alvo sem secao `.text`.
        caso(231, "ausente e invalido", sha_texto_valido(None), None)
        caso(232, "vazio e invalido", sha_texto_valido(""), None)
        caso(233, "sentinela e invalido", sha_texto_valido(AUSENTE), None)
        caso(234, "sha do vazio e invalido", sha_texto_valido(SHA_DO_VAZIO), None)
        caso(235, "hash curto e invalido", sha_texto_valido("abc123"), None)
        caso(236, "64 caracteres nao-hex sao invalidos", sha_texto_valido("z" * 64), None)
        caso(2361, "e hex maiusculo vale, normalizado para minusculo",
             sha_texto_valido("A" * 63 + "B"), "a" * 63 + "b")
        caso(237, "e o hash real passa, normalizado",
             sha_texto_valido("  " + "a1" * 32 + "  "), "a1" * 32)
        caso(238, "o sha do vazio nunca vira identidade",
             estado_de_comparacao("prog: x", {"prog": {"text_sha256": SHA_DO_VAZIO}},
                                  {"prog": {"text_sha256": SHA_DO_VAZIO}}, {}),
             SEM_IDENTIDADE)

        # 24 e 25. A REGUA E DE UM INSTRUMENTO SO.
        #
        # Filtrar irmas por configuracao e condicao nao bastava: a amplitude
        # de `neighbour on physical core` nas quatro irmas de 26/09/2026 era
        # 0,00% -- as quatro deram o mesmo valor -- enquanto trocar so
        # `-falign-loops` move o rotulo 15,8%. A regua media a reprodutibilidade
        # de uma familia de artefatos e julgava uma comparacao entre familias.
        SHA_IRMA, SHA_OUTRO = "c" * 64, "d" * 64
        for i, sha in enumerate((SHA_IRMA, SHA_IRMA, SHA_IRMA)):
            manifesto(coleta("2026-09-2%d-0200-regua-x" % (2 + i), [1.0 + i / 10.0, 1.0 + i / 10.0]), sha)
        alvo = coleta("2026-09-25-0200-regua-x", [1.2, 1.2])
        manifesto(alvo, SHA_IRMA)
        caso(24, "irmas do MESMO artefato formam regua",
             "prog: custo alvo" in amplitudes(alvo), True)
        manifesto(alvo, SHA_OUTRO)
        caso(25, "artefato diferente das irmas deixa o rotulo SEM REGUA",
             "prog: custo alvo" in amplitudes(alvo), False)
        # 26. O LEGADO CONTINUA COM REGUA, e e escolha declarada: coleta
        #     anterior a 27/09/2026 nao tem manifesto de artefato dos DOIS
        #     lados, e exigi-lo ali apagaria a amplitude do historico inteiro
        #     sem ganho -- o portao ja bloqueia a marca por SEM_IDENTIDADE.
        legado = coleta("2026-09-26-0200-legado-x", [1.0, 1.0])
        for i in (1, 2, 3):
            coleta("2026-09-2%d-0300-legado-x" % (6 + i % 3), [1.0 + i / 10.0, 1.0 + i / 10.0])
        # 25b. DECLARAR QUE NAO HA NAO E O MESMO QUE NUNCA TER REGISTRADO.
        #      Duas coletas com `text_sha256=nao-disponivel` tem bloco, logo
        #      nao sao legado, e nao podem formar regua de "mesmo artefato".
        manifesto(alvo, AUSENTE)
        for i in (1, 2, 3):
            manifesto(coleta("2026-09-2%d-0400-sent-x" % (2 + i), [1.0, 1.0]), AUSENTE)
        alvo_s = coleta("2026-09-26-0400-sent-x", [1.0, 1.0])
        manifesto(alvo_s, AUSENTE)
        caso(251, "identidade declarada ausente nao forma regua de mesmo artefato",
             "prog: custo alvo" in amplitudes(alvo_s), False)

        # 25c. O SHA DO VAZIO E O UNICO QUE ENGANA A COMPARACAO CRUA. A
        #      sentinela cai fora do dominio hex sozinha; este NAO -- sao 64
        #      hex legitimos, iguais entre todo alvo sem `.text`. Comparar os
        #      brutos aqui formaria regua de "mesmo artefato" entre programas
        #      diferentes, que e o fail-open que `sha_texto_valido` fecha.
        for i in (1, 2, 3):
            manifesto(coleta("2026-09-2%d-0500-vazio-x" % (2 + i), [1.0, 1.0]), SHA_DO_VAZIO)
        alvo_v = coleta("2026-09-26-0500-vazio-x", [1.0, 1.0])
        manifesto(alvo_v, SHA_DO_VAZIO)
        caso(252, "o sha do vazio nao forma regua de mesmo artefato",
             "prog: custo alvo" in amplitudes(alvo_v), False)

        caso(26, "sem manifesto dos dois lados a regua do legado permanece",
             "prog: custo alvo" in amplitudes(legado), True)

        # 27 e 28. O PORTAO SUPRIME O `<<<`, e nao so escreve um aviso.
        #
        # `SEM_IDENTIDADE` caia no ramo normal e podia marcar, contradizendo o
        # resumo que o proprio arquivo imprime. Aqui a saida inteira e capturada
        # e a ausencia da marca e conferida.
        import contextlib
        import io as _io

        def saida_de(dirs):
            buf = _io.StringIO()
            with contextlib.redirect_stdout(buf):
                comparar([str(x) for x in dirs], ["base", "nova"])
            return buf.getvalue()

        g1 = coleta("2026-09-28-0100-marca-x", [1.0, 1.0])
        for i in (1, 2, 3):
            coleta("2026-09-28-0%d00-marca-x" % (i + 1), [1.0, 1.0])
        g2 = coleta("2026-09-28-0500-marca-x", [2.0, 2.0])   # +100%, marcaria
        texto = saida_de([g1, g2])
        caso(27, "sem identidade de artefato o delta NAO e marcado",
             "<<<" in texto, False)
        linha = next((l for l in texto.splitlines() if "prog: custo alvo" in l), "")
        caso(28, "e o motivo sai na PROPRIA LINHA do rotulo",
             "SEM IDENTIDADE DE ARTEFATO" in linha, True)

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    if len(sys.argv) < 2:
        print(__doc__)
        print("uso: comparar-hardware.py <dir1> [dir2 ...]")
        sys.exit(2)
    sys.exit(comparar(sys.argv[1:], [os.path.basename(d.rstrip("/"))[:14] for d in sys.argv[1:]]) or 0)
