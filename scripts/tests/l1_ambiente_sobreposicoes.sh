#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# O que muda o NUMERO entra no registro de ambiente.
#
# POR QUE ESTE TESTE EXISTE
#
# `DPDK_ACADEMY_AMOSTRAS` reduz quantas amostras cada programa coleta e
# `DPDK_ACADEMY_RODADAS` quantas operacoes entram em cada amostra. As duas
# existem para a CI caber no teto de tempo, e as duas mudam o numero publicado:
# menos rodadas fazem o custo de ler o relogio virar fracao maior da amostra;
# menos amostras mudam quartis e selos.
#
# Nenhuma delas aparecia no `ambiente.txt`. Duas coletas com o mesmo commit, o
# mesmo hardware e o mesmo banner podiam ter sido produzidas com protocolos
# diferentes, e nada no arquivo arquivado permitia distinguir -- que e a mesma
# familia de "a condicao nao fica ao lado do numero" que o manifesto e a
# condicao texto/grafico vieram fechar.
#
# E AUSENCIA E DECLARADA: sem sobreposicao a linha sai dizendo `(padrao)`, e
# nao some. Omitir deixaria o leitor sem saber se o protocolo era o padrao ou
# se aquela versao do script simplesmente nao olhava.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
amb="$raiz/scripts/ambiente.sh"
[ -x "$amb" ] || { echo "FALHA: nao achei $amb"; exit 1; }
falhas=0

conferir() { # <descricao> <obtido> <esperado>
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}
linha() { # <rotulo> ; le do texto ja capturado
    printf '%s' "$1" | sed -n "s/^ *$2 *\.* //p" | head -1
}

# TODAS AS QUINZE, E NAO SO AS DO CASO EM MAO.
#
# A primeira versao limpava apenas as variaveis que cada caso definia, e
# passava isolada. Sob o pre-commit ela FALHOU: o ambiente de quem chama tinha
# `PKG_CONFIG_PATH` -- natural em qualquer maquina que compile contra um
# prefixo do DPDK --, e ele aparecia em todas as linhas esperadas.
#
# O defeito era do teste, nao do script: um teste que herda o ambiente mede o
# ambiente. A lista abaixo e a mesma que `ambiente.sh` inspeciona, e precisa
# acompanha-la -- por isso o ultimo caso confere que nenhuma ficou de fora.
LIMPAR="-u DPDK_ACADEMY_AMOSTRAS -u DPDK_ACADEMY_RODADAS -u DPDK_ACADEMY_CPU_RUIDO
        -u DPDK_ACADEMY_TICKS -u DPDK_ACADEMY_ESPERA
        -u DPDK_ACADEMY_INJECT_PAUSE -u DPDK_ACADEMY_INJECT_LEAK
        -u DPDK_ACADEMY_INJECT_INVALID_SAMPLE
        -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS
        -u LD_PRELOAD -u PKG_CONFIG_PATH -u LD_LIBRARY_PATH"

# shellcheck disable=SC2086
limpo() { env $LIMPAR "$@" "$amb" 2>/dev/null; }

sem=$(limpo)
conferir "sem sobreposicao, declara o padrao" \
    "$(linha "$sem" 'sobreposicoes')" "(nenhuma; protocolo padrao)"
conferir "sem variaveis de build, declara nenhuma" \
    "$(linha "$sem" 'variaveis de build')" "(nenhuma)"

com=$(limpo DPDK_ACADEMY_AMOSTRAS=3 DPDK_ACADEMY_RODADAS=20000)
conferir "registra amostras e rodadas" \
    "$(linha "$com" 'sobreposicoes')" "DPDK_ACADEMY_AMOSTRAS=3 DPDK_ACADEMY_RODADAS=20000"

# A CPU DE RUIDO muda deliberadamente o fenomeno de contencao medido.
ruido=$(limpo DPDK_ACADEMY_CPU_RUIDO=7)
conferir "registra a CPU de ruido" \
    "$(linha "$ruido" 'sobreposicoes')" "DPDK_ACADEMY_CPU_RUIDO=7"

# AS INJECOES QUEBRAM O PROGRAMA DE PROPOSITO. Uma coleta produzida com
# qualquer delas ligada nao e medicao, e precisa dizer isso de si mesma.
inj=$(limpo DPDK_ACADEMY_INJECT_LEAK=1)
conferir "registra a injecao de falha" \
    "$(linha "$inj" 'sobreposicoes')" "DPDK_ACADEMY_INJECT_LEAK=1"

# FLAGS DE BUILD mudam o binario medido sem mudar o commit.
fl=$(limpo CFLAGS="-O1 -g")
conferir "registra CFLAGS" "$(linha "$fl" 'variaveis de build')" "CFLAGS=-O1 -g"

# `LD_PRELOAD` e o caso extremo: troca a implementacao sob o programa medido.
pre=$(limpo LD_PRELOAD=/nao/existe.so)
conferir "registra LD_PRELOAD" \
    "$(linha "$pre" 'variaveis de build')" "LD_PRELOAD=/nao/existe.so"

# A LISTA DO TESTE PRECISA ACOMPANHAR A DO SCRIPT. Se `ambiente.sh` passar a
# inspecionar uma variavel que `LIMPAR` nao apaga, o teste volta a herdar o
# ambiente e a falhar em maquina alheia -- foi exatamente o que aconteceu.
inspecionadas=$(grep -oE 'DPDK_ACADEMY_[A-Z_]+|\bCFLAGS\b|\bCXXFLAGS\b|\bCPPFLAGS\b|\bLDFLAGS\b|\bLD_PRELOAD\b|\bPKG_CONFIG_PATH\b|\bLD_LIBRARY_PATH\b' \
    <(sed -n '/^SOBREPOSICOES=""/,/^\[ -n "\$FLAGS_BUILD" \]/p' "$amb") | sort -u)
# `LIMPAR` e multilinha; sem normalizar, o padrao com espacos literais nao casa
# nas quebras de linha -- e a conferencia acusaria variaveis que ela LIMPA.
# shellcheck disable=SC2086
limpar_norm=" $(echo $LIMPAR) "
for v in $inspecionadas; do
    case "$limpar_norm" in
        *" -u $v "*) ;;
        *) echo "  FALHOU: ambiente.sh inspeciona $v e o teste nao a limpa"
           falhas=$((falhas + 1)) ;;
    esac
done

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 7 assercoes + a lista conferida; o protocolo da coleta fica registrado ao lado do numero"
