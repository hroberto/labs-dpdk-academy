#!/usr/bin/env python3
"""Pareamento pt/en dos rótulos de saída dos programas de medição.

POR QUE ESTE ARQUIVO EXISTE

Em 20/09/2026 o projeto decidiu que **os programas passam a imprimir em
inglês**. A decisão anterior, de 10/09, era o contrário, e está no ROADMAP: "a
saída dos programas e a prosa continuam em português".

O que forçou a troca foi uma contradição entre dois instrumentos. O
`verificar-idioma.py` foi construído para caçar português dentro de bloco de
código nos documentos em inglês -- inclusive "a saída dos programas", como diz o
cabeçalho dele. O ROADMAP mandava manter. O portão venceu, e o resultado foram
**21 blocos em 5 arquivos `.en.md` mostrando saída que o programa nunca
imprime**: números certos, rótulos traduzidos à mão.

Um bloco apresentado como saída de programa que não é a saída do programa é a
mesma classe de defeito que um número sem procedência.

O QUE ESTE ARQUIVO IMPEDE

Trocar o idioma da saída inutilizaria os **92 arquivos já arquivados** em
`medicoes/historico/`, porque o `comparar-hardware.py` usa o rótulo como CHAVE:
uma coleta em inglês comparada com uma em português mostraria toda linha como
ausente de um dos lados. Isso quebraria o fatorial 2×2 que o segundo pente de
memória vai fechar -- e as coletas de 4800 não podem ser refeitas sem outra
viagem à BIOS.

Com o mapa, a coleta antiga é normalizada na leitura e a comparação sobrevive.

DE ONDE SAIU A LISTA

**Do corpus, não da memória de quem escreve.** Os 47 rótulos foram extraídos
das 92 coletas arquivadas. Hoje mesmo, duas vezes, um vocabulário montado de
cabeça produziu falso positivo -- `establish` e `appears` no verificador de
força epistêmica. O autoteste fecha essa porta: ele relê o arquivo histórico e
falha se aparecer rótulo sem par.
"""
import os
import re
import sys

# pt -> en. O espaçamento interno é preservado porque as tabelas alinham por
# ele: `aleatorio    (amortizado)` ocupa a mesma largura que `dependente   (...)`.
PARES = {
    "1 nucleo": "1 core",
    "2 nucleos": "2 cores",
    "4 nucleos": "4 cores",
    "8 nucleos": "8 cores",
    "12 nucleos": "12 cores",
    "1 thread  em 1 nucleo fisico (cpu 0)": "1 thread  on 1 physical core (cpu 0)",
    "2 threads em 2 nucleos fisicos (cpu 0,2)": "2 threads on 2 physical cores (cpu 0,2)",
    "2 threads em 2 irmaos SMT (cpu 0,12)": "2 threads on 2 SMT siblings (cpu 0,12)",
    "CAS em melhor caso": "CAS, best case",
    "trava em melhor caso": "lock, best case",
    "CAS com falta, mesmo dominio L3": "CAS with miss, same L3 domain",
    "CAS com falta, OUTRO dominio L3": "CAS with miss, OTHER L3 domain",
    "falta simples, mesmo dominio L3": "plain miss, same L3 domain",
    "falta simples, OUTRO dominio L3": "plain miss, OTHER L3 domain",
    "DIFERENCA atribuivel a traducao": "DIFFERENCE attributable to translation",
    "paginas de 4 KB": "4 KB pages",
    "hugepages de 2 MB": "2 MB hugepages",
    "dentro do dominio 0 (cpu 0 <-> 2)": "within domain 0 (cpu 0 <-> 2)",
    "ENTRE dominios (cpu 0 <-> 6)": "BETWEEN domains (cpu 0 <-> 6)",
    "RAZAO entre/dentro (pareada)": "RATIO between/within (paired)",
    "RAZAO com/sem irmao SMT (pareada)": "RATIO with/without SMT sibling (paired)",
    "laco sozinho no nucleo": "loop alone on the core",
    "vizinho no irmao SMT (cpu 12)": "neighbour on SMT sibling (cpu 12)",
    "vizinho em nucleo fisico (cpu 2)": "neighbour on physical core (cpu 2)",
    "chamada de funcao (user-space)": "function call (user-space)",
    "clock_gettime (vDSO, sem trap)": "clock_gettime (vDSO, no trap)",
    "syscall real (SYS_getpid)": "real syscall (SYS_getpid)",
    "atomica relaxed (store+load)": "atomic relaxed (store+load)",
    "atomica seq_cst (store+load)": "atomic seq_cst (store+load)",
    "mutex lock+unlock": "mutex lock+unlock",
    "spinlock lock+unlock": "spinlock lock+unlock",
    "semaforo post+wait": "semaphore post+wait",
    "atomica + espera ativa (nao dorme)": "atomic + busy wait (does not sleep)",
    "mutex + espera ativa (nao dorme)": "mutex + busy wait (does not sleep)",
    "mutex + condvar (DORME)": "mutex + condvar (SLEEPS)",
    "semaforo POSIX (DORME)": "POSIX semaphore (SLEEPS)",
    "sequencial   (amortizado)": "sequential   (amortised)",
    "aleatorio    (amortizado)": "random       (amortised)",
    "dependente   (LATENCIA)": "dependent    (LATENCY)",
}
# Os rótulos de `custo-paralelismo` seguem um padrão, e escrevê-los um a um
# convidaria a esquecer um quando K mudar.
for _k in (1, 2, 4, 8, 12, 16, 32, 64):
    _pt = f"K = {_k}{' ' * (2 - len(str(_k)) + 1)} ({_k} acesso{'s' if _k > 1 else ''} em voo)"
    PARES[f"K = {_k:<2} ({_k} acesso{'s' if _k > 1 else ''} em voo)"] = \
        f"K = {_k:<2} ({_k} access{'es' if _k > 1 else ''} in flight)"

EN = set(PARES.values())


# --- MODULOS 02 E 03 -------------------------------------------------------
#
# Extraidos dos BLOCOS PUBLICADOS desses modulos, que sao a saida dos programas
# -- mesma regra do modulo 01: do corpus, nao da memoria.
#
# E A DESCOBERTA DESSE LEVANTAMENTO: dos 24 rotulos distintos, 14 sao NOMES DE
# CAMPO do `rte_mbuf` -- `buf_addr`, `data_len`, `nb_segs`, `refcnt`, `next`,
# `pkt_len`, `data_off`, `buf_len`, `port`, `pool` -- e identificador de API NAO
# SE TRADUZ. Traduzi-los quebraria a correspondencia com a documentacao do DPDK,
# que e o que o leitor consulta ao lado.
#
# A migracao desses modulos e, portanto, muito menor do que o numero bruto
# sugeria: dez rotulos, nao vinte e quatro.
PARES.update({
    "publicacao -> observacao": "publication -> observation",
    "mempool get/put, com cache": "mempool get/put, with cache",
    "mempool get/put, SEM cache": "mempool get/put, NO cache",
    "cabeca da cadeia": "head of the chain",
    "segundo segmento": "second segment",
    "recem-alocado": "freshly allocated",
    "prepend(14) = ethernet": "prepend(14) = ethernet",
    "prepend(20) = tunel": "prepend(20) = tunnel",
    "adj(20) = tira o tunel": "adj(20) = strips the tunnel",
    "trim(4) = tira do fim": "trim(4) = strips from the end",
    "append(60) = payload": "append(60) = payload",
})
EN = set(PARES.values())


def normalizar(rotulo):
    """Devolve o rótulo em inglês, venha ele em português ou já em inglês."""
    r = rotulo.strip()
    return PARES.get(r, r)


def autoteste():
    """Relê o arquivo histórico e exige par para cada rótulo encontrado.

    É o que impede este arquivo de envelhecer: rótulo novo sem tradução reprova
    aqui, e não numa comparação silenciosamente meia-vazia meses depois.
    """
    LINHA = re.compile(r"^\s{2,}(\S.*?)\s{2,}(\d+\.\d+)\s")
    raiz = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "..", "docs", "01-fundamentos", "medicoes", "historico")
    achados, sem_par = set(), set()
    if os.path.isdir(raiz):
        for base, _, nomes in os.walk(raiz):
            for n in nomes:
                if not n.endswith(".txt"):
                    continue
                for ln in open(os.path.join(base, n), encoding="utf-8", errors="replace"):
                    m = LINHA.match(ln.rstrip())
                    if not m:
                        continue
                    r = m.group(1).strip()
                    if r.startswith("-") or "medicao" in r or r.isdigit():
                        continue
                    achados.add(r)
                    if r not in PARES and r not in EN:
                        sem_par.add(r)
    for r in sorted(sem_par):
        print(f"  rotulo sem par: {r!r}")
    print(f"\n  {len(achados)} rotulo(s) no arquivo historico; "
          f"{len(PARES)} par(es) no mapa; {len(sem_par)} sem tradução")
    return len(sem_par)


if __name__ == "__main__":
    sys.exit(1 if autoteste() else 0)
