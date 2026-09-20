#!/usr/bin/env python3
"""Audita ONDE a fonte de cada afirmacao esta, nao SE ela existe.

POR QUE ISTO EXISTE

O material adotou a regra de tese: toda afirmacao que nao seja medida aqui
precisa apontar a fonte. A regra passou a ser cumprida no fim do documento --
as secoes 10 e 13 acumularam as referencias -- e isso cria uma ilusao de
cobertura. Uma fonte listada no rodape nao sustenta um paragrafo mil linhas
acima: o leitor nao faz essa ligacao, e um avaliador tambem nao.

Foi assim com o futex. As duas afirmacoes do 5.2 ("a culpa nao e do mutex" e
"o caminho rapido resolve em espaco de usuario") tinham fonte desde sempre, so
que a mil linhas de distancia. E o que estava no 10 nem citacao era: parafrase
minha, formatada como bloco de citacao.

ESTE PROGRAMA NAO E UM PORTAO

Ele levanta CANDIDATOS e ordena o trabalho. Falso positivo aqui e barato e
esperado -- afirmacao derivada por aritmetica dos proprios dados aparece como
candidata e nao e defeito. Ligar isto no pre-commit repetiria o erro que o
repositorio ja documentou: verificador ruidoso e desligado, e verificador
desligado nao verifica nada.

AS TRES SONDAS

  1. fonte remota  -- referencia usada SO nas tabelas (10 e 13), nunca no
     ponto da afirmacao. Mede distancia, nao ausencia.
  2. mecanismo nu  -- paragrafo que afirma comportamento de hardware, kernel
     ou terceiro, sem citacao e sem ancora em medicao local.
  3. numero orfao  -- numero sobre terceiro que nao sai de programa deste
     repositorio nem de fonte citada no paragrafo.
"""
import collections
import pathlib
import re
import sys

# TODOS os .md de docs/, nao so os README. Em 19/09/2026 o modulo 01 ganhou
# dois anexos -- metodologia.md e 6.3-aprofundamento.md -- e com o glob antigo
# o material movido para eles SAIU do alcance desta auditoria. Mover conteudo
# de lugar nao pode tirar cobertura: e a mesma falha do bit de execucao e do
# nome `inventariar-*`, agora pela terceira vez.
DOCS = sorted(str(p) for p in pathlib.Path('docs').rglob('*.md'))
# As secoes de tabela sao reconhecidas pelo TITULO, nao pelo numero. A primeira
# versao trazia {"10", "13", "14"}, que e a numeracao do modulo 01, e por isso
# declarava "0 fontes remotas" nos modulos 02 e 03 -- onde as tabelas de
# referencia tem outro numero. Zero por miscalibragem parece zero por limpeza.
TABELAS = re.compile(r"(Refer[êe]ncias?|References|Confronto com a literatura"
                     r"|literature|Navega[çc][ãa]o|Navigation)", re.I)

SUJEITO = (r"(o kernel|o hardware|a NIC|a placa|o processador|a CPU|o driver"
           r"|o escalonador|a glibc|o compilador|a DRAM|o controlador|o DPDK"
           r"|o Linux|a MMU|a TLB|o prefetcher|o sistema operacional"
           r"|the kernel|the hardware|the NIC|the processor|the CPU|the driver"
           r"|the scheduler|glibc|the compiler|the memory controller"
           r"|the prefetcher|the operating system)")
MODAL = (r"(sempre|nunca|por padr[ao]|precisa|tem de|n[ao]o pode|garante"
         r"|obriga|impede|s[o0] pode"
         r"|always|never|by default|must|cannot|guarantees|forces|prevents)")
LOCAL = (r"(medicoes/|\.c\)|\.h\)|nesta m[a�]quina|nesta placa|on this machine"
         r"|medi[cç][ãa]o|medi[çc][õo]es|measured here|the table above"
         r"|a tabela acima)")
NUMERO = (r"\b\d[\d  .,]*\s*(ns|µs|us|ms|ciclos?|cycles?|KB|KiB|MB|MiB"
          r"|GB|GiB|bits?|entradas|entries|n[íi]veis|levels|vias|ways|%|×"
          r"|GHz|MHz|Gb/s|GT/s)\b")
EXTERNO = (r"(x86|Intel|AMD|Zen|Linux|kernel|NIC|DRAM|PCIe|TLB|p[áa]gina|page"
           r"|cache|Ethernet|DPDK|padr[ãa]o|default|especifica|specificat)")


def blocos(linhas):
    """Quebra o documento em paragrafos, anotando capitulo e subsecao."""
    fora, atual, inicio = [], [], 0
    secao, capitulo, codigo = "(preambulo)", "0", False
    for n, linha in enumerate(linhas, 1):
        if linha.lstrip().startswith("```"):
            codigo = not codigo
            continue
        if codigo:
            continue
        cab = re.match(r"^(#{2,4})\s+(.*)", linha)
        if cab:
            secao = cab.group(2).strip()
            if cab.group(1) == "##":
                num = re.match(r"(\d+)", secao)
                capitulo = num.group(1) if num else capitulo
        if linha.strip():
            if not atual:
                inicio = n
            atual.append(linha)
        elif atual:
            fora.append((inicio, capitulo, secao, atual))
            atual = []
    if atual:
        fora.append((inicio, capitulo, secao, atual))
    return fora


def auditar(caminho):
    linhas = pathlib.Path(caminho).read_text().split("\n")
    rotulos = {m.group(1) for m in
               (re.match(r"^\[([^\]]+)\]:\s+\S+", l) for l in linhas) if m}

    usos = collections.defaultdict(set)
    for inicio, capitulo, secao, corpo in blocos(linhas):
        for linha in corpo:
            if re.match(r"^\[[^\]]+\]:\s+\S+", linha):
                continue
            for rotulo in re.findall(r"\]\[([^\]]+)\]", linha):
                if rotulo in rotulos:
                    usos[rotulo].add(bool(TABELAS.search(secao)))

    remotas = sorted(r for r in rotulos if usos[r] and usos[r] == {True})
    nunca = sorted(r for r in rotulos if not usos[r])

    mecanismo, numeros = [], []
    exigem = sustentadas = 0
    for inicio, capitulo, secao, corpo in blocos(linhas):
        if TABELAS.search(secao) or any(l.lstrip().startswith("|") for l in corpo):
            continue
        texto = re.sub(r"\s+", " ", " ".join(corpo))

        # EXIGE sustentação? O critério é o mesmo das duas sondas, aplicado
        # ANTES de saber se o parágrafo cita — é isso que produz o denominador.
        e_mecanismo = bool(re.search(SUJEITO, texto, re.I)
                           and re.search(MODAL, texto, re.I))
        e_numero = bool(re.search(NUMERO, texto) and re.search(EXTERNO, texto))
        if not (e_mecanismo or e_numero):
            continue
        exigem += 1

        # TEM sustentação? Citação no próprio parágrafo, âncora em programa
        # deste repositório, ou declaração de que o dado é local.
        cita = any(r in rotulos for r in re.findall(r"\]\[([^\]]+)\]", texto))
        ancora = bool(re.search(r"(medicoes/|\.c\)|\.h\))", texto))
        local = bool(re.search(LOCAL, texto, re.I))
        if cita or ancora or local:
            sustentadas += 1
            continue

        resumo = (inicio, secao, texto[:150])
        if e_mecanismo and not local:
            mecanismo.append(resumo)
        if e_numero:
            numeros.append(resumo)
    return rotulos, remotas, nunca, mecanismo, numeros, exigem, sustentadas


def main():
    detalhe = "-v" in sys.argv
    total = 0
    for caminho in DOCS:
        rotulos, remotas, nunca, mecanismo, numeros, exigem, sust = auditar(caminho)
        total += len(remotas) + len(mecanismo) + len(numeros)
        cobertura = (100.0 * sust / exigem) if exigem else 100.0
        print(f"\n== {caminho}")
        # A COBERTURA, e nao a contagem de fontes.
        #
        # Contar referencias definidas e proxy ruim, e ele produziu um
        # diagnostico errado em 19/09/2026: o `00-visao-geral/README.md`
        # aparecia como "0 fontes definidas" ao lado das 61 do modulo 01, e a
        # conclusao tirada foi que ele destoava. Ele nao destoa -- e
        # majoritariamente REGRA AUTORAL do projeto ("afirmacao numerica
        # precisa de programa que a produza"), que nao pede citacao nenhuma.
        #
        # O denominador certo e quantos paragrafos fazem afirmacao EXTERNA
        # verificavel; o numerador, quantos deles citam fonte, ancoram em
        # programa daqui ou declaram o dado como local.
        print(f"   cobertura    : {cobertura:5.1f}%  ({sust}/{exigem} afirmacoes"
              f" externas sustentadas)   {len(rotulos)} fontes definidas")
        print(f"   fonte remota : {len(remotas):3d} usadas so em secao de"
              f" referencia/confronto")
        if nunca:
            print(f"   nunca usada  : {len(nunca):3d}  {', '.join(nunca)}")
        print(f"   mecanismo nu : {len(mecanismo):3d} paragrafos")
        print(f"   numero orfao : {len(numeros):3d} paragrafos")
        if detalhe:
            for titulo, itens in (("fonte remota", [(0, "", f"[{r}]")
                                                    for r in remotas]),
                                  ("mecanismo nu", mecanismo),
                                  ("numero orfao", numeros)):
                print(f"\n   -- {titulo}")
                for linha, secao, texto in itens:
                    onde = f"L{linha:5d} [{secao[:34]}] " if linha else "     "
                    print(f"      {onde}{texto}")
    print(f"\n{total} candidato(s). Isto e um inventario de trabalho, "
          f"nao um veredito.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
