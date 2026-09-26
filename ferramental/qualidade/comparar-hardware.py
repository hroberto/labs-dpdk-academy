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
    por = {}
    for outro in irmas(diretorio):
        for k, v in coletar(outro).items():
            if v and len(v) >= 2:
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
    return 0


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
             round(amps["prog: custo alvo"], 2), 3.92)

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
