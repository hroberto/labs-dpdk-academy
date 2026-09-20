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
import re
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rotulos import normalizar  # noqa: E402

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
            delta = f"  {d:+6.1f}%" + ("  <<<" if abs(d) > 5 else "")
        print("  " + k.ljust(largura) + cels + delta)
    print(f"\n  {len(chaves)} rotulo(s); mediana das medianas, execucao de aquecimento descartada")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        print("uso: comparar-hardware.py <dir1> [dir2 ...]")
        sys.exit(2)
    sys.exit(comparar(sys.argv[1:], [os.path.basename(d.rstrip("/"))[:14] for d in sys.argv[1:]]) or 0)
