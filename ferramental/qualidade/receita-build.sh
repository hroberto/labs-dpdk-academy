#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# A receita de compilacao arquivada pelo meson, com o alinhamento variado.
#
# POR QUE ISTO E UM ARQUIVO, E NAO UM TRECHO DO CARACTERIZADOR
#
# O `l1_ancora_producao.sh` extraia `comando_de()` por `sed`/`eval` -- a classe
# de falso-verde que o `PADROES.md` passou a proibir na manha do mesmo dia, e
# que ja mordeu duas vezes nesta arvore: a producao ganha um auxiliar, a lista
# do `sed` nao acompanha, e a funcao ausente vira "comando nao encontrado" sem
# interromper nada.
#
# Hoje `comando_de()` e autocontida. Amanha pode nao ser, e o teste nao teria
# como saber. Producao e teste carregam este arquivo, e o grafo e o mesmo por
# construcao.
#
# CONTRATO. Quem carrega define `CC_JSON`, o caminho do `compile_commands.json`
# do build que a campanha mede.
# REPRODUZIR O COMANDO DO MESON, E NAO REMONTA-LO A MAO.
#
# A versao anterior extraia as flags e reconstruia a invocacao com
# `cc -I<medicoes> $flags`. Isso perdia os OUTROS `-I` que o meson passa --
# entre eles o do diretorio de build, onde `academy_version.h` e gerado. O
# `statistics.h` o inclui sob `__has_include`, entao o artefato compilava SEM
# a linha de procedencia e ficava com outro `.text`:
#
#     com o cabecalho : eaf9abfa...   <- o que a campanha mede
#     sem o cabecalho : 394f847c...   <- o que a caracterizacao media
#
# Dois instrumentos, e a campanha media um enquanto a caracterizacao
# caracterizava o outro.
#
# O QUE A FUNCAO FAZ, DITO COM PRECISAO. Ela nao "muda so o alinhamento": o
# comando arquivado compila para objeto, entao ela tira o `-c`, tira a saida e
# as flags de geracao de dependencia, acrescenta o `-lm` que a ligacao exige, e
# substitui o `-falign-loops`. O que se afirma nao e que o comando e identico
# -- e que o CODIGO RESULTANTE converge: no alinhamento de producao, o `.text`
# sai byte a byte igual ao do binario que a campanha mede. E e isso que o
# portao do caracterizador exige antes de medir qualquer coisa.
comando_de() { # <programa> <alinhamento> <saida>  -> `cd <dir> && cc ...`
    python3 - "$CC_JSON" "$1" "$2" "$3" <<'PYCMD'
import json, re, shlex, sys
cc = json.load(open(sys.argv[1]))
alvo, al, saida = sys.argv[2], sys.argv[3], sys.argv[4]
for e in cc:
    if re.sub(r'\.[^.]+$', '', e.get('file', '').split('/')[-1]) != alvo:
        continue
    fora, pula = [], False
    for x in shlex.split(e.get('command', '')):
        if pula:
            pula = False
            continue
        if x == '-c':
            continue
        if x in ('-o', '-MQ', '-MF'):
            pula = True
            continue
        if x.startswith('-MD'):
            continue
        if x.startswith('-falign-loops='):
            fora.append('-falign-loops=' + al)
            continue
        fora.append(x)
    fora += ['-o', saida, '-lm']
    print('cd %s && %s' % (shlex.quote(e.get('directory', '.')),
                           ' '.join(shlex.quote(a) for a in fora)))
    raise SystemExit
raise SystemExit("sem entrada para %s" % alvo)
PYCMD
}
fonte_do_programa() { # <programa> -> caminho ABSOLUTO do .c
    python3 - "$CC_JSON" "$1" <<'PYF'
import json, os, re, sys
cc = json.load(open(sys.argv[1]))
alvo = sys.argv[2]
for e in cc:
    if re.sub(r'\.[^.]+$', '', e.get('file', '').split('/')[-1]) == alvo:
        print(os.path.realpath(os.path.join(e.get('directory', '.'), e['file'])))
        raise SystemExit
raise SystemExit("sem fonte para %s" % alvo)
PYF
}
