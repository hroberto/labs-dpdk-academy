#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Marcador de teste L1 ausente por falta do GoogleTest.
#
# POR QUE ISTO EXISTE
#
# O GTest e opcional de proposito: sem rede para baixar o subprojeto, o build
# dos topicos continua funcionando. Mas "opcional" estava implementado como
# DESAPARECER: com `if gtest_dep.found()` sem `else`, os quatro executaveis de
# teste unitario simplesmente nao eram registrados, e a suite encolhia de 6
# testes para 2 -- reportando `Ok: 2, Fail: 0` e saindo com codigo 0.
#
# Reproduzido assim:
#
#     meson setup build --wrap-mode=nofallback   # rc=0
#     meson test -C build --suite l1             # Ok: 2, Fail: 0
#
# Uma suite verde com dois tercos dos testes ausentes e pior que uma suite
# vermelha: ela afirma que o codigo foi verificado quando ninguem o verificou.
# E o mesmo falso-verde que o codigo 77 ja resolveu para os testes L3 -- aqui a
# causa e outra (dependencia ausente, nao ambiente insuficiente), mas o remedio
# e o mesmo: dizer PULADO em vez de sumir.
#
# Uso: pular-sem-gtest.sh <nome-do-teste-que-nao-rodou>
set -u

NOME=${1:-"(sem nome)"}

echo "  PULADO - $NOME"
echo ""
echo "  O GoogleTest nao esta disponivel, entao este teste L1 nao foi"
echo "  compilado. Ele NAO passou: ele nao rodou."
echo ""
echo "  Para habilitar:"
echo "    meson subprojects download        # baixa o subprojeto fixado por hash"
echo "    ./scripts/build-all.sh"
echo ""
echo "  Ou instale o GoogleTest do sistema (Debian/Ubuntu: libgtest-dev)."

# 77 = PULADO para o Meson, e nao sucesso.
exit 77
