#!/usr/bin/env python3
"""Distribuicao por funcao a partir de um relatorio do `trace-cmd`.

POR QUE A DURACAO SAI DE DOIS EVENTOS, E NAO DE UM

`workqueue_execute_start` diz QUANDO um item comecou e QUAL funcao ele executa.
Sozinho ele conta ocorrencias e nada mais. A duracao exige o `_end` do MESMO
item -- o casamento e pelo ponteiro `work struct`, que os dois eventos trazem.

Casar por thread seria mais simples e estaria errado: uma `kworker` executa
itens em sequencia, e casar o `start` de um com o `_end` do seguinte somaria o
intervalo entre eles ao trabalho.

    uso:  apurar-osnoise-funcoes.py <relatorio.txt> [<janela_s>]
          apurar-osnoise-funcoes.py --autoteste
"""
import re
import sys

# trace-cmd report:
#   kworker/2:3-446 [002] 8044.528193: workqueue_execute_start: work struct 0xffff9d80: function amdgpu_...
#   kworker/2:3-446 [002] 8044.528640: workqueue_execute_end:   work struct 0xffff9d80: function amdgpu_...
# O PONTEIRO E HEXADECIMAL, e a classe precisa dizer isso.
#
# A primeira versao usava `(\S+?):?` -- nao-guloso sem ancora. No `_end`, onde
# nao ha `function` depois para forcar o retrocesso, ele casava um unico
# caractere: `0` em vez de `0xAA`. O casamento entre start e end falhava em
# silencio e a tabela saia vazia.
PONTEIRO = r"([0-9a-fA-Fx]+)"
INICIO = re.compile(
    r"\s(\d+\.\d+):\s+workqueue_execute_start:\s+work struct\s+" + PONTEIRO +
    r":?\s+function\s+(\S+)")
FIM = re.compile(
    r"\s(\d+\.\d+):\s+workqueue_execute_end:\s+work struct\s+" + PONTEIRO)


def apurar(linhas):
    """-> {funcao: (n, maior_us, soma_us)}"""
    abertos, saida = {}, {}
    for l in linhas:
        m = INICIO.search(l)
        if m:
            t, work, func = float(m.group(1)), m.group(2), m.group(3)
            abertos[work] = (t, func)
            continue
        m = FIM.search(l)
        if m:
            t, work = float(m.group(1)), m.group(2)
            if work not in abertos:
                continue                      # `_end` sem `start` na janela
            t0, func = abertos.pop(work)
            us = (t - t0) * 1e6
            n, maior, soma = saida.get(func, (0, 0.0, 0.0))
            saida[func] = (n + 1, max(maior, us), soma + us)
    return saida


def relatar(dist, janela=None):
    if not dist:
        return ["  nenhum item de workqueue na janela -- em modo texto isso e o esperado"]
    linhas = ["| Função | n | Maior | Soma |", "|---|---:|---:|---:|"]
    for func, (n, maior, soma) in sorted(dist.items(), key=lambda kv: -kv[1][2]):
        linhas.append("| `%s` | %d | %s µs | %s µs |" % (
            func, n, ("%.1f" % maior).replace(".", ","),
            ("%.0f" % soma).replace(".", ",") if soma >= 100 else ("%.1f" % soma).replace(".", ",")))
    if janela:
        linhas.append("")
        linhas.append("  janela: %s s" % janela)
    return linhas


def autoteste():
    falhas = 0

    def arred(x):
        """Compara com tolerancia: a duracao vem de SUBTRACAO de dois floats de
        segundos, e 1.000500 - 1.000000 nao da 0.0005 exato em binario. Testar
        igualdade exata aqui cobraria do teste uma precisao que o dado nao tem."""
        if isinstance(x, tuple):
            return tuple(round(v, 3) if isinstance(v, float) else v for v in x)
        if isinstance(x, dict):
            return {k: arred(v) for k, v in x.items()}
        return x

    def caso(n, desc, obtido, esperado):
        nonlocal falhas
        obtido, esperado = arred(obtido), arred(esperado)
        if obtido != esperado:
            print("  AUTOTESTE %s FALHOU: %s\n    esperado %r\n    obtido   %r"
                  % (n, desc, esperado, obtido))
            falhas += 1

    L = [
        " kworker/2:3-446 [002]  1.000000: workqueue_execute_start: work struct 0xAA: function alpha",
        " kworker/2:3-446 [002]  1.000500: workqueue_execute_end:   work struct 0xAA: function alpha",
        " kworker/2:3-446 [002]  2.000000: workqueue_execute_start: work struct 0xBB: function alpha",
        " kworker/2:3-446 [002]  2.000200: workqueue_execute_end:   work struct 0xBB: function alpha",
    ]
    caso(1, "duas execucoes da mesma funcao somam",
         apurar(L)["alpha"], (2, 500.0, 700.0))

    # 2. O CASAMENTO E PELO `work struct`, e nao pela thread. Dois itens
    #    intercalados na MESMA kworker: casar por thread somaria o intervalo.
    M = [
        " kworker/2:3-446 [002]  1.000000: workqueue_execute_start: work struct 0xAA: function alpha",
        " kworker/2:3-446 [002]  5.000000: workqueue_execute_start: work struct 0xBB: function beta",
        " kworker/2:3-446 [002]  5.000100: workqueue_execute_end:   work struct 0xBB: function beta",
        " kworker/2:3-446 [002]  9.000000: workqueue_execute_end:   work struct 0xAA: function alpha",
    ]
    d = apurar(M)
    caso(2, "casa pelo work struct, nao pela thread", d["beta"], (1, 100.0, 100.0))
    caso(3, "o item longo nao rouba o curto", d["alpha"], (1, 8000000.0, 8000000.0))

    # 4. `_end` orfao na janela nao vira ocorrencia.
    caso(4, "end sem start e ignorado",
         apurar([" k-1 [002] 1.0: workqueue_execute_end: work struct 0xZZ: function alpha"]), {})
    # 5. `start` sem `_end` (janela cortou) tambem nao conta -- contar daria
    #    duracao zero e inflaria `n`.
    caso(5, "start sem end nao conta",
         apurar([" k-1 [002] 1.0: workqueue_execute_start: work struct 0xZZ: function alpha"]), {})
    caso(6, "janela vazia relata em vez de calar", len(relatar({})), 1)

    print("\n  autoteste: %d assercao(oes) falharam" % falhas)
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    if len(sys.argv) < 2:
        print("uso: apurar-osnoise-funcoes.py <relatorio.txt> [janela_s]", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], errors="replace") as f:
        d = apurar(f)
    print("\n".join(relatar(d, sys.argv[2] if len(sys.argv) > 2 else None)))
