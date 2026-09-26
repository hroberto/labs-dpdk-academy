#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# O provocador precisa estar TRABALHANDO antes de a janela abrir.
#
# Uso: l1_provocador_lento.sh <binario-lento> <binario-normal>
#
# POR QUE ESTE TESTE EXISTE
#
# `pthread_create` devolve quando a thread foi CRIADA, nao quando foi
# escalonada. Sem handshake, a captura de /proc/interrupts e o aquecimento da
# sonda podiam ocorrer com o provocador ainda parado, e a conferencia do fim --
# que exige `voltas > 0` -- aprovaria uma execucao em que a carga so comecou
# depois de metade da janela.
#
# O caminho de recusa nunca roda numa execucao normal: o provocador sobe em
# microssegundos. Um caminho que a suite nunca exercita e indistinguivel de um
# que nao existe, e este decide se a janela medida tem carga. A variante lenta
# dorme 3 s contra o limite de 2 s.
#
# E O CASO NORMAL TAMBEM E CONFERIDO: um teste que so exige recusa aprovaria um
# programa que recusa sempre.
set -u
lento=${1:?uso: $0 <binario-lento> <binario-normal>}
normal=${2:?uso: $0 <binario-lento> <binario-normal>}
falhas=0

saida=$(mktemp); trap 'rm -f "$saida"' EXIT

# A CPU 1 precisa existir e estar permitida; senao o programa recusa por outro
# motivo e o teste mediria outra coisa.
if ! taskset -c 0,1 true 2>/dev/null; then
    echo "  PULADO: as CPUs 0 e 1 nao estao disponiveis a este processo"
    exit 77
fi

recusa() { # <descricao> <esperado-no-stderr> <VAR=valor>...
    local descricao=$1 esperado=$2; shift 2
    local rc=0
    timeout 40 env "$@" "$lento" 0 2 1000 1 > "$saida" 2>&1 || rc=$?
    if [ "$rc" -eq 124 ]; then
        echo "  FALHA: $descricao -- NAO TERMINOU"
        falhas=$((falhas + 1))
    elif [ "$rc" -eq 0 ]; then
        echo "  FALHA: $descricao -- saiu com 0, e a janela nao tinha carga"
        falhas=$((falhas + 1))
    fi
    if ! grep -q "$esperado" "$saida"; then
        echo "  FALHA: $descricao -- a recusa nao diz por que (esperava '$esperado')"
        falhas=$((falhas + 1))
    fi
    # E NAO PODE TER PUBLICADO A TABELA: a linha do provocador so sai quando a
    # medicao chegou ao fim, e encontra-la aqui seria janela aberta sem carga.
    if grep -q "provoker rounds completed" "$saida"; then
        echo "  FALHA: $descricao -- publicou a contagem apesar de recusar"
        falhas=$((falhas + 1))
    fi
}

# 1. DEMORA A FICAR ATIVO: o handshake expira.
recusa "provocador lento" "did not start within" INJETAR_LENTO=3

# 2. FICA ATIVO E NAO TRABALHA. Sem exigir a primeira volta, o handshake
#    liberaria a janela com a thread fixada e sem ter mapeado nada -- e estar
#    fixado nao e provocar. Medido: sem este caso, o mutante que aceita ATIVO
#    sozinho SOBREVIVIA.
recusa "ativo, porem sem a primeira volta" "did not start within" INJETAR_SEM_VOLTA=3

# 3. TRABALHA E PARA LOGO DEPOIS. O handshake passa -- havia volta completa --
#    e a conferencia do FIM tem de pegar: nenhuma volta concluiu DURANTE a
#    janela. Medido: sem este caso, o mutante que nao exige continuidade
#    SOBREVIVIA.
recusa "para logo apos a primeira volta" "stopped before the window ended" INJETAR_PARA=1

# ---- o caminho normal continua medindo --------------------------------
rc=0
timeout 30 "$normal" 0 1 1000 1 > "$saida" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "  FALHA: o binario normal devia medir e saiu com $rc"
    falhas=$((falhas + 1))
fi
if ! grep -q "provoker rounds completed during the window" "$saida"; then
    echo "  FALHA: o binario normal nao publicou a contagem de voltas completas"
    falhas=$((falhas + 1))
fi

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: tres formas de janela sem carga recusadas, e o caminho normal mede"
