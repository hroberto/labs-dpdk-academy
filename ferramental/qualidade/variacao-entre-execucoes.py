#!/usr/bin/env python3
"""Mede a dispersão das medianas ENTRE execuções de um programa de medição.

POR QUE ISTO EXISTE

Os selos `~` e `!` descrevem a dispersão **dentro de uma coleta**. Não existia
instrumento nenhum para a outra dispersão -- a que aparece quando o mesmo
binário roda de novo --, e ela derrubou um número publicado.

O caso, em 19/09/2026: o `custo-syscall` publicava 0,924 ns para a chamada de
função de referência, com `disp` de 0,4% e `CV` de 0,3%. Selo limpo, e correto:
dentro daquela coleta a dispersão era mesmo pequena. Rodando o MESMO binário
vinte vezes, dezenove execuções deram entre 0,713 e 0,750. O valor publicado
aparecia uma vez em dez, e a causa tem teste: com `setarch -R` ele some.

Nenhuma quantidade de amostras teria pego isso, porque o problema não está na
amostra -- está na EXECUÇÃO. Aumentar `n` caracteriza melhor a distribuição de
uma coleta; não diz nada sobre a próxima.

O QUE ELE MEDE, e o que a saída significa

Para cada linha da tabela, N execuções produzem N medianas. O programa publica:

    entre   a dispersão robusta DESSAS medianas (IQR sobre mediana)
    dentro  a mediana das dispersões que cada execução reportou

A leitura é a comparação das duas, e é ela que decide:

    entre <= dentro    o valor é estável; o selo de uma coleta basta
    entre >> dentro    CADA coleta é limpa e elas DISCORDAM entre si --
                       é o caso do custo-syscall, e o único jeito de ver
                       é este

O sinal `!!` marca a segunda situação. Ele não é veredito sobre o número: é
aviso de que publicar uma coleta sozinha, com o selo dela, promete mais do que
o programa entrega.

O QUE ELE NAO E

Não é portão. Roda sob demanda, porque custa N vezes o tempo de uma coleta --
e o `custo-traducao` sozinho leva minutos. Entra na régua de quem vai
PUBLICAR um número, não na de quem vai commitar um texto.

O PROTOCOLO, em uma linha: descarta uma execucao de aquecimento e coleta N.

Uso:
    ./variacao-entre-execucoes.py <programa> [-n N] [--amostras M]
    ./variacao-entre-execucoes.py --autoteste
"""
import argparse
import os
import re
import statistics
import subprocess
import sys

# Uma linha de medição: rótulo, mediana, IQR, amplitude, disp%, CV%, selo.
# O rótulo pode ter espaços; o que o separa dos números são DOIS espaços.
# Uma linha de medicao: rotulo, mediana, IQR, e o resto.
#
# O RESTO E DELIBERADAMENTE LIVRE, e a razao esta medida. A primeira versao
# exigia o formato completo -- amplitude, `disp` e `CV` -- e com isso o
# `custo-mckenney` nao casava com NENHUMA linha: a tabela dele traz
# `mediana | p25-p75 | ciclos | disp`, sem amplitude e sem CV. A campanha de
# 19/09/2026 rodou os seis programas e aquele saiu VAZIO, o que se le como
# "nenhuma suspeita" em vez de "nao consegui ler".
#
# Agora o casamento exige o que TODA tabela deste repositorio tem -- rotulo,
# mediana e um intervalo interquartil -- e a dispersao e a PRIMEIRA
# porcentagem que aparecer depois disso, que e `disp` nos dois formatos.
LINHA = re.compile(r"^\s{2,}(\S.*?)\s{2,}"
                   r"(\d+\.\d+)\s+"
                   r"\d+\.\d+-\d+\.\d+\s+"
                   r"(\S.*)$")
PORCENTO = re.compile(r"(\d+\.\d+)%")

LIMIAR_RAZAO = 2.0     # `entre` maior que isto vezes `dentro` acende o !!
LIMIAR_PISO = 1.0      # ...desde que `entre` passe deste piso, em %


def coletar(cmd, n, ambiente):
    """Roda o programa n vezes e devolve {chave: [(mediana, disp), ...]}.

    A CHAVE INCLUI A OCORRENCIA, e nao so o rotulo.

    O `efeito-cache` imprime os MESMOS tres rotulos quatro vezes -- uma por
    nivel de cache --, e a primeira versao deste arquivo os fundia num so.
    O resultado foi absurdo e instrutivo: `dependente` apareceu com 484% de
    variacao "entre execucoes", faixa de 0,892 a 130,8 ns. Isso nao e variacao
    entre execucoes; e a L1d contra a RAM, que e justamente o que aquele
    programa existe para mostrar.

    Um instrumento que mede a dispersao errada com aparencia de precisao e pior
    que instrumento nenhum -- e este foi pego na primeira vez que rodou contra
    um programa de varias secoes."""
    # A PRIMEIRA EXECUCAO E DESCARTADA, e o motivo foi medido.
    #
    # Em 19/09/2026 a campanha marcou QUATRO linhas do custo-mckenney como
    # dois regimes, e nas quatro a destoante era a execucao numero 1:
    #
    #   CAS em melhor caso       9.270  7.130 7.140 7.140 7.140 7.140 7.140
    #   trava em melhor caso     2.550  2.060 2.050 2.050 2.000 2.050 2.010
    #   falta simples, mesmo L3  27.580 20.780 21.180 21.030 20.870 20.820 ...
    #   falta simples, OUTRO L3  94.390 89.770 88.840 89.710 88.850 88.890 ...
    #
    # ASLR sorteia a cada carga e poria a destoante em posicao aleatoria. Ser
    # SEMPRE a primeira e assinatura de aquecimento do SISTEMA -- rampa de
    # frequencia depois da maquina ociosa, e cache de paginas do binario.
    #
    # Descartando uma execucao antes de comecar, tres das quatro linhas ficam
    # limpas: 7,130-7,150 contra 7,13-9,27; 2,010-2,060 contra 2,00-2,55;
    # 87,73-89,03 contra 88,80-94,39.
    #
    # Sem o descarte, este instrumento reporta como propriedade do programa um
    # artefato do proprio protocolo de medicao -- que e exatamente a classe de
    # erro que ele existe para encontrar.
    print("  execucao de aquecimento (descartada)", file=sys.stderr)
    subprocess.run(cmd, capture_output=True, text=True, env=ambiente)

    saidas = {}
    for i in range(n):
        r = subprocess.run(cmd, capture_output=True, text=True, env=ambiente)
        vistos = {}
        for linha in r.stdout.splitlines():
            m = LINHA.match(linha)
            if m is None:
                continue
            pct = PORCENTO.search(m.group(3))
            if pct is None:          # linha sem dispersao: nao e medicao
                continue
            rotulo = " ".join(m.group(1).split())
            k = vistos.get(rotulo, 0)
            vistos[rotulo] = k + 1
            chave = rotulo if k == 0 else f"{rotulo} [{k + 1}a]"
            saidas.setdefault(chave, []).append(
                (float(m.group(2)), float(pct.group(1))))
        print(f"  execucao {i + 1}/{n}", file=sys.stderr)
    return saidas


def dispersao_robusta(valores):
    """IQR sobre mediana, em %. A mesma régua de statistics.h."""
    if len(valores) < 3:
        return 0.0
    v = sorted(valores)
    mediana = statistics.median(v)
    if mediana == 0.0:
        return 0.0
    q = statistics.quantiles(v, n=4, method="inclusive")
    return 100.0 * (q[2] - q[0]) / mediana


# Separacao MINIMA para dois grupos serem distinguiveis, como fracao da
# mediana. Abaixo disso o "vale" e resolucao de impressao, nao fenomeno.
SEPARACAO_MINIMA = 0.05
# ...e tem de superar o ruido DENTRO de uma execucao por esta folga: dois
# regimes so sao separaveis se a distancia entre eles passa da incerteza com
# que cada um foi medido.
SEPARACAO_SOBRE_RUIDO = 4.0


def regimes(valores, dentro_pct=0.0):
    """Separa RUIDO CONTINUO de DOIS REGIMES DISCRETOS.

    POR QUE A DISTINCAO EXISTE, e por que `CV` nao a faz.

    O caso que motivou o arquivo -- 0,923 / 0,714 / 0,750 / 0,749 / ... -- nao e
    uma distribuicao larga: sao DUAS populacoes. Um unico numero de dispersao
    descreve as duas situacoes do mesmo jeito, e elas pedem investigacoes
    OPOSTAS. Ruido continuo manda melhorar a coleta; dois regimes mandam
    procurar a VARIAVEL OMITIDA que escolhe um deles -- e foi assim que a ASLR
    apareceu.

    O criterio e o maior INTERVALO VAZIO entre medianas consecutivas. Se ele
    domina os demais, ha um vale na distribuicao, e vale e assinatura de
    separacao. Devolve (ha_regimes, corte, tamanho_relativo_do_vao).

    Exige pelo menos 5 execucoes: com menos, "o maior vao" e ruido de amostragem
    e o detector viraria gerador de hipotese falsa."""
    if len(valores) < 5:
        return False, None, 0.0
    v = sorted(valores)
    mediana = statistics.median(v)
    vaos = [(v[i + 1] - v[i], i) for i in range(len(v) - 1)]
    maior, corte = max(vaos)
    faixa = v[-1] - v[0]
    if faixa <= 0 or mediana <= 0:
        return False, None, 0.0

    # TRES testes, e os tres precisam passar.
    #
    # O terceiro nasceu de um falso positivo em massa: na primeira campanha o
    # detector marcou NOVE de doze linhas do efeito-cache, incluindo uma com
    # faixa de 0,187 a 0,189 ns. A causa era estrutural -- com valores quase
    # iguais a saida tem EMPATES, o vao tipico vira zero, e a versao anterior
    # tratava "tipico == 0" como destoante por definicao. Toda linha estavel
    # virava dois regimes, que e o oposto do que o instrumento existe para
    # dizer.
    #
    # 1. o vao domina a FAIXA -- senao e so a cauda;
    grande = maior / faixa >= 0.5
    # 2. o vao destoa dos OUTROS vaos -- senao a distribuicao e larga e
    #    continua. Com empates (tipico == 0) este teste nao decide nada, e por
    #    isso ele deixou de poder aprovar sozinho;
    outros = sorted(g for g, _ in vaos)[:-1]
    tipico = statistics.median(outros) if outros else 0.0
    destoante = maior > 4.0 * tipico if tipico > 0 else True
    # 3. o vao e MAIOR QUE A RESOLUCAO: precisa passar de 5% da mediana e
    #    superar o ruido dentro de uma execucao com folga. Dois regimes so sao
    #    separaveis se a distancia entre eles passa da incerteza com que cada
    #    um foi medido.
    separacao = maior / mediana
    piso = max(SEPARACAO_MINIMA, SEPARACAO_SOBRE_RUIDO * dentro_pct / 100.0)
    resolve = separacao >= piso

    if grande and destoante and resolve:
        return True, (v[corte] + v[corte + 1]) / 2.0, separacao
    return False, None, separacao


def relatar(saidas, n):
    print(f"\n  VARIACAO ENTRE {n} EXECUCOES do mesmo binario\n")
    print(f"  {'medicao':<38} {'mediana':>9} {'entre':>7} {'dentro':>7}   min-max entre execucoes")
    print(f"  {'-' * 38} {'-' * 9} {'-' * 7} {'-' * 7}   {'-' * 24}")
    suspeitas = 0
    bimodais = []
    for rotulo, pares in saidas.items():
        medianas = [p[0] for p in pares]
        disps = [p[1] for p in pares]
        if len(medianas) < n:          # linha que nem sempre aparece
            continue
        entre = dispersao_robusta(medianas)
        dentro = statistics.median(disps)
        marca = ""
        if entre > LIMIAR_PISO and entre > LIMIAR_RAZAO * max(dentro, 0.01):
            marca = " !!"
            suspeitas += 1
        dois, corte, vao = regimes(medianas, dentro)
        if dois:
            marca += " REGIMES"
            bimodais.append((rotulo, medianas, corte))
        print(f"  {rotulo[:38]:<38} {statistics.median(medianas):>9.3f}"
              f" {entre:>6.1f}% {dentro:>6.1f}%   {min(medianas):.3f}-{max(medianas):.3f}{marca}")
    print()
    if suspeitas:
        print(f"  {suspeitas} linha(s) com `!!`: cada coleta e limpa e elas DISCORDAM")
        print("  entre si. Publicar uma delas com o selo dela promete demais.")
    else:
        print("  Nenhuma linha com `!!`: as coletas concordam entre execucoes.")

    # AS MEDIANAS, UMA A UMA. Um resumo estatistico esconde a forma da
    # distribuicao, e a forma e o dado -- foi vendo os vinte numeros em fila
    # que o caso do custo-syscall deixou de ser "CV alto" e virou "dois modos".
    if bimodais:
        print("\n  DOIS REGIMES, e nao dispersao larga. A distincao muda a")
        print("  investigacao: ruido pede coleta melhor; regime pede procurar a")
        print("  VARIAVEL OMITIDA que escolhe entre os dois.\n")
        for rotulo, medianas, corte in bimodais:
            baixo = [v for v in medianas if v < corte]
            alto = [v for v in medianas if v >= corte]
            print(f"    {rotulo}")
            print(f"      regime baixo: {len(baixo)}/{len(medianas)} execucoes,"
                  f" mediana {statistics.median(baixo):.3f}")
            print(f"      regime alto : {len(alto)}/{len(medianas)} execucoes,"
                  f" mediana {statistics.median(alto):.3f}")
            print(f"      execucoes   : " + " ".join(f"{v:.3f}" for v in medianas))
    return suspeitas


def autoteste():
    import tempfile as _tf, stat as _st
    """O detector precisa acender no caso real e ficar quieto no estavel."""
    falhas = 0

    # O caso que motivou o arquivo: dezenove execucoes em 0,713-0,750 e uma em
    # 0,923, cada uma com disp interna de 0,4%. `entre` tem de superar `dentro`.
    real = [0.923, 0.714, 0.750, 0.749, 0.723, 0.714, 0.726, 0.714, 0.723, 0.716,
            0.746, 0.749, 0.748, 0.720, 0.748, 0.715, 0.720, 0.717, 0.723, 0.749]
    entre = dispersao_robusta(real)
    if not (entre > LIMIAR_PISO and entre > LIMIAR_RAZAO * 0.4):
        print(f"  AUTOTESTE FALHOU: o caso real do custo-syscall nao acendeu"
              f" (entre={entre:.2f}%, dentro=0,4%)")
        falhas += 1

    # E a syscall da MESMA tabela, que nao se mexe, tem de ficar quieta.
    estavel = [33.25, 33.24, 33.23, 33.25, 33.27, 33.22, 33.24, 33.26]
    entre_e = dispersao_robusta(estavel)
    if entre_e > LIMIAR_PISO:
        print(f"  AUTOTESTE FALHOU: linha estavel acendeu (entre={entre_e:.2f}%)")
        falhas += 1

    # O PARSER e a outra metade, e ele quebra calado: uma mudanca de formato em
    # statistics.h faz LINHA nao casar com nada, e o relatorio sai VAZIO --
    # que se le como "nenhuma suspeita" em vez de "nao consegui ler".
    # OS DOIS FORMATOS de tabela do repositorio. O segundo entrou depois de o
    # `custo-mckenney` sair VAZIO de uma campanha inteira -- ele nao tem
    # amplitude nem CV, e o parser antigo exigia os dois.
    for amostra, med, disp, nome in [
        (("  chamada de funcao (user-space)         0.717  0.715-0.747"
          "     0.713-1.009         4.6%  11.3% ~"), "0.717", "4.6",
         "formato padrao, com amplitude e CV"),
        (("  CAS em melhor caso                      9.25  9.24-9.25"
          "             40        0.1%  "), "9.25", "0.1",
         "formato do custo-mckenney, com ciclos e sem CV"),
    ]:
        m = LINHA.match(amostra)
        pct = PORCENTO.search(m.group(3)) if m else None
        if m is None or m.group(2) != med or pct is None or pct.group(1) != disp:
            print(f"  AUTOTESTE FALHOU: o parser nao le o {nome}")
            falhas += 1
    # E nao pode casar com linha de texto comum.
    if LINHA.match("  Orcamento de 10 GbE com quadros de 64 B: 67.2 ns por pacote"):
        print("  AUTOTESTE FALHOU: o parser casou com prosa")
        falhas += 1

    # REGIMES x RUIDO, e os tres casos vem de dados reais ou construidos para
    # o limiar. Sem eles, alguem "simplifica" o detector e ele volta a chamar
    # tudo de dispersao -- que e o estado anterior, e o que escondeu a ASLR.
    real = [0.923, 0.714, 0.750, 0.749, 0.723, 0.714, 0.726, 0.714, 0.723, 0.716,
            0.746, 0.749, 0.748, 0.720, 0.748, 0.715, 0.720, 0.717, 0.723, 0.749]
    # (serie, dispersao interna tipica em %, esperado)
    #
    # As tres primeiras sao DADOS REAIS. As duas do efeito-cache entraram
    # depois de um falso positivo em massa: o detector marcou nove de doze
    # linhas daquele programa, inclusive faixas de 0,002 ns. Sem elas aqui, a
    # regressao volta sem ninguem notar -- e um detector que marca tudo diz o
    # mesmo que um que nao marca nada.
    for serie, dentro, esperado, nome in [
        (real, 0.3, True, "custo-syscall: dois modos reais, vao de 24%"),
        ([0.187, 0.187, 0.188, 0.187, 0.189, 0.187, 0.188, 0.187, 0.187], 0.1,
         False, "efeito-cache sequencial[L2]: EMPATES, faixa de 0,002 ns"),
        ([2.68, 2.68, 2.68, 2.70, 2.68, 2.68, 2.69, 2.68, 2.68], 0.5,
         False, "efeito-cache dependente[L2]: estavel"),
        ([1.00, 1.02, 1.05, 1.07, 1.09, 1.12, 1.14, 1.17], 2.0,
         False, "dispersao larga porem CONTINUA"),
        ([33.25, 33.24, 33.23, 33.25, 33.27, 33.22, 33.24, 33.26], 0.7,
         False, "syscall real: a linha que nao se mexe"),
        ([0.71, 0.72, 0.92, 0.93], 0.3,
         False, "quatro execucoes: o maior vao ainda e ruido de amostragem"),
    ]:
        if regimes(serie, dentro)[0] != esperado:
            print(f"  AUTOTESTE (regimes) FALHOU: {nome} -> esperado"
                  f" {esperado}, veio {regimes(serie, dentro)[0]}")
            falhas += 1

    # ROTULO REPETIDO. O caso real: efeito-cache imprime "dependente" quatro
    # vezes, uma por nivel. Fundir as quatro produz uma dispersao inventada.
    import tempfile as _tf, stat as _st
    with _tf.TemporaryDirectory() as d:
        falso = os.path.join(d, "falso.sh")
        with open(falso, "w") as f:
            f.write("#!/bin/sh\n"
                    "echo '  dependente   (LATENCIA)              0.892  0.892-0.892"
                    "     0.891-0.893         0.0%   0.1%'\n"
                    "echo '  dependente   (LATENCIA)              103.1  103.0-103.2"
                    "     103.0-103.3         0.2%   0.2%'\n")
        os.chmod(falso, os.stat(falso).st_mode | _st.S_IEXEC)
        saidas = coletar([falso], 3, dict(os.environ))
    if len(saidas) != 2:
        print(f"  AUTOTESTE (rotulo repetido) FALHOU: duas secoes com o mesmo"
              f" rotulo viraram {len(saidas)} serie(s), deviam virar 2")
        falhas += 1
    else:
        for chave, pares in saidas.items():
            if dispersao_robusta([x[0] for x in pares]) > 0.01:
                print(f"  AUTOTESTE (rotulo repetido) FALHOU: a serie '{chave}'"
                      f" ficou com dispersao onde os valores sao identicos")
                falhas += 1

    # ================= OS DEFEITOS QUE A CAMPANHA ENCONTROU =================
    #
    # Regra do ferramental: todo defeito achado rodando vira caso de regressao.
    # Nao porque isso prove correcao -- nunca provaria --, mas porque so assim a
    # descoberta AUMENTA PERMANENTEMENTE o dominio que o instrumento sabe
    # fiscalizar. Os tres abaixo sao os tres modos de FALSO VERDE que a campanha
    # de 19/09/2026 produziu, e os tres estavam invisiveis aos testes originais.

    # 1. AQUECIMENTO DESCARTADO. Sem ele o instrumento reporta como propriedade
    #    do programa um artefato do proprio protocolo -- no custo-mckenney,
    #    quatro linhas sairam como "dois regimes" e nas quatro a destoante era a
    #    execucao numero 1.
    with _tf.TemporaryDirectory() as d:
        contador = os.path.join(d, "n")
        prog = os.path.join(d, "conta.sh")
        with open(prog, "w") as f:
            f.write("#!/bin/sh\n"
                    f"echo x >> {contador}\n"
                    "echo '  linha de medicao                        1.000"
                    "  1.000-1.000     1.000-1.000         0.1%   0.1%'\n")
        os.chmod(prog, os.stat(prog).st_mode | _st.S_IEXEC)
        coletar([prog], 4, dict(os.environ))
        invocacoes = sum(1 for _ in open(contador))
    if invocacoes != 5:
        print(f"  AUTOTESTE (aquecimento) FALHOU: com -n 4 o programa foi"
              f" invocado {invocacoes} vezes; deviam ser 5 (4 + 1 descartada)")
        falhas += 1

    # 2. O AVISO DE "NADA RECONHECIDO" TEM DE SAIR EM STDOUT. Ele morava em
    #    stderr, e a campanha o silenciou com `2>/dev/null` -- idioma comum para
    #    calar o progresso. Um programa inteiro deixou de ser lido e a saida
    #    vazia passou por "nenhuma suspeita".
    # E o teste e de COMPORTAMENTO, nao de texto do fonte. A primeira versao
    # procurava "stderr" no proprio arquivo e casava com o literal da propria
    # busca -- um teste que se le a si mesmo e sempre passa.
    with _tf.TemporaryDirectory() as d:
        mudo = os.path.join(d, "so-prosa.sh")
        with open(mudo, "w") as f:
            f.write("#!/bin/sh\necho 'Orcamento de 10 GbE: 67.2 ns por pacote'\n")
        os.chmod(mudo, os.stat(mudo).st_mode | _st.S_IEXEC)
        r = subprocess.run([sys.executable, __file__, mudo, "-n", "3"],
                           capture_output=True, text=True)
    if r.returncode == 0:
        print("  AUTOTESTE (canal do aviso) FALHOU: saida irreconhecivel"
              " terminou com sucesso")
        falhas += 1
    if "ERRO" not in r.stdout:
        print("  AUTOTESTE (canal do aviso) FALHOU: o aviso de saida nao"
              " reconhecida nao esta em STDOUT -- em stderr, `2>/dev/null` o"
              " apaga, e foi assim que um programa inteiro deixou de ser lido")
        falhas += 1

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("programa", nargs="?")
    ap.add_argument("-n", type=int, default=7, help="execucoes (padrao 7)")
    ap.add_argument("--amostras", type=int,
                    help="teto de amostras POR execucao; acelera, mas as "
                         "dispersoes internas ficam menos confiaveis")
    ap.add_argument("--autoteste", action="store_true")
    a = ap.parse_args()
    if a.autoteste:
        sys.exit(1 if autoteste() else 0)
    if not a.programa:
        ap.error("informe o programa, ou use --autoteste")
    ambiente = dict(os.environ)
    if a.amostras:
        ambiente["DPDK_ACADEMY_AMOSTRAS"] = str(a.amostras)
    saidas = coletar([a.programa], a.n, ambiente)
    if not saidas:
        # EM STDOUT, e nao em stderr. A campanha de 19/09/2026 invocava com
        # `2>/dev/null` -- idioma comum para calar o progresso -- e com isso
        # silenciou exatamente o aviso que dizia que um programa inteiro nao
        # tinha sido lido. Aviso que so existe no canal que todo mundo fecha
        # nao e aviso.
        print("  ERRO: nenhuma linha de medicao reconhecida na saida de"
              f" {a.programa}.")
        print("  O programa rodou, e este instrumento NAO o leu. Isso nao e"
              " 'nenhuma suspeita'.")
        sys.exit(2)
    relatar(saidas, a.n)


if __name__ == "__main__":
    main()
