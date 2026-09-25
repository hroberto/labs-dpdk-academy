#!/usr/bin/env python3
"""Nomeia a funcao por tras do maior evento de thread num rastro do `rtla osnoise`.

POR QUE ESTE ARQUIVO EXISTE

Um rastro do `rtla osnoise` mostra QUE um `kworker` ocupou a CPU e por quanto
tempo, e nao O QUE ele executava. Na captura de 2026-09-25 00:19 isso ficou
explicito: 696 606 ns de `kworker/2:3`, e zero ocorrencias de `gfx` em 31 127
linhas. O nome da funcao vive noutro evento -- `workqueue:workqueue_execute_start`
--, que o `rtla` nao habilita sozinho.

Com esse evento ligado, a associacao e posicional: a funcao iniciada por uma
thread e a que ela executa ate o proximo inicio. Este script faz essa costura, e
so ela.

O QUE ELE NAO FAZ

Nao decide se a atribuicao esta certa. Se o rastro nao tiver o evento do
workqueue, ele DIZ que nao tem, em vez de devolver "nenhuma ocorrencia" -- que e
a diferenca entre "nao existe" e "nao medi", e foi exatamente o erro que a
primeira versao do experimento de GFXOFF cometeu.

    uso:  analisar-rastro-osnoise.py <trace.txt> [--autoteste]
"""
import re
import sys

INICIO = re.compile(r"workqueue_execute_start:.*?function (\S+)")
RUIDO = re.compile(r"thread_noise: (\S+?):\d+ start \S+ duration (\d+) ns")


def analisar(linhas):
    """-> (ns, thread, funcao|None). ns == 0 quando nao ha thread_noise."""
    maior, quem, casada = 0, None, None
    ultima = {}  # campo de thread da linha de rastro -> funcao
    for l in linhas:
        campos = l.split()
        if not campos:
            continue
        m = INICIO.search(l)
        if m:
            ultima[campos[0]] = m.group(1)
            continue
        m = RUIDO.search(l)
        if m and int(m.group(2)) > maior:
            maior, quem = int(m.group(2)), m.group(1)
            casada = ultima.get(campos[0])
    return maior, quem, casada


def relatar(ns, thread, funcao):
    if ns == 0:
        return "rastro gravado, sem thread_noise -- o maior evento nao foi de thread"
    nome = funcao or "funcao NAO nomeada (sem evento de workqueue no rastro)"
    marca = "NOMEIA gfx_off" if funcao and "gfx_off" in funcao else "funcao"
    return "%s: %s  em %s, %d ns (%.0f us)" % (marca, nome, thread, ns, ns / 1000.0)


def autoteste():
    falhas = 0

    def caso(n, descricao, linhas, esperado):
        nonlocal falhas
        obtido = analisar(linhas)
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, descricao, esperado, obtido))
            falhas += 1

    inicio = ("  kworker/2:3-446 [002] d..2. 1.0: workqueue_execute_start: "
              "work struct 0xffff function amdgpu_device_delay_enable_gfx_off\n")
    ruido = ("  kworker/2:3-446 [002] d..2. 1.7: thread_noise: kworker/2:3:446 "
             "start 1.0 duration 696606 ns\n")
    menor = ("  kworker/2:3-446 [002] d..2. 2.7: thread_noise: kworker/2:3:446 "
             "start 2.0 duration 1000 ns\n")

    # 1. O caso que justifica o arquivo: a funcao so aparece com o evento ligado.
    caso(1, "com o evento de workqueue, nomeia",
         [inicio, ruido], (696606, "kworker/2:3", "amdgpu_device_delay_enable_gfx_off"))
    # 2. SEM o evento, tem de dizer que nao sabe -- e nao devolver silencio.
    caso(2, "sem o evento de workqueue, nao inventa",
         [ruido], (696606, "kworker/2:3", None))
    # 3. Rastro sem thread_noise nenhum: zero, e o relato diz isso.
    caso(3, "rastro sem thread_noise", [inicio], (0, None, None))
    # 4. O MAIOR, e nao o ultimo: sem isto o script reportaria o evento errado
    #    sempre que um ruido pequeno viesse depois do grande, que e o normal.
    caso(4, "escolhe o maior, nao o ultimo",
         [inicio, ruido, menor], (696606, "kworker/2:3", "amdgpu_device_delay_enable_gfx_off"))
    # 5. Duas threads: a funcao de uma nao pode vazar para o ruido da outra.
    outra_inicio = ("  kworker/5:1-99 [005] d..2. 1.1: workqueue_execute_start: "
                    "work struct 0xffff function outra_coisa\n")
    caso(5, "nao cruza threads", [outra_inicio, ruido],
         (696606, "kworker/2:3", None))

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], errors="replace") as f:
        print(relatar(*analisar(f)))
