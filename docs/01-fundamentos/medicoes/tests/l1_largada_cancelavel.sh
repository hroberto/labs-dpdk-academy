#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Criação parcial de trabalhadores termina, e termina reprovando.
#
# Uso: l1_largada_cancelavel.sh <shim.so> <binario>...
#
# POR QUE ESTE TESTE EXISTE
#
# `pthread_create` praticamente nunca falha numa máquina de estudo, e o caminho
# de erro dela ficou sem ser exercitado. Ele continha um deadlock
# determinístico: com `pthread_barrier_t`, as threads já criadas esperavam
# participantes que nunca viriam, e o `join` do criador esperava por elas. Uma
# campanha de horas travaria indefinidamente, sem diagnóstico.
#
# O QUE O TESTE SEPARA, E O QUE NAO SEPARA -- e a distinção importa.
#
#   `custo-paralelismo`: a versão anterior TRAVA sob esta injeção e a atual sai
#   com erro. Aqui o teste distingue o defeito da correção, que é o que dá
#   valor a um teste de regressão.
#
#   `custo-comunicacao`: a versão anterior também termina sob esta injeção,
#   porque ela derruba TODAS as amostras e a mediana zero já era recusada como
#   abaixo da resolução. A exposição real daquele código era PARCIAL -- algumas
#   amostras 0.0 absorvidas pela mediana -- e esta injeção não a reproduz. Para
#   ele, o caso abaixo fixa o contrato, e não separa as duas versões. Dizer
#   isso é melhor que contar o caso como prova do que ele não prova.
#
# A INJEÇÃO MIRA A CRIAÇÃO PARCIAL: o shim falha quando já há thread viva, que
# é a condição em que as anteriores ficam presas na sincronização.
set -u
shim=${1:?uso: $0 <shim.so> <binario>...}
shift
[ -r "$shim" ] || { echo "FALHA: nao achei $shim"; exit 1; }

falhas=0
# 40 s é folga: sob injeção o programa não chega a medir nada. A versão
# defeituosa não terminava em tempo algum.
LIMITE=40

# ASAN JA INTERPOE `pthread_create`, E DOIS INTERPOSITORES NAO CONVIVEM.
#
# Sob `b_sanitize=address`, o runtime do ASan intercepta `pthread_create` para
# registrar a pilha de cada thread. Empilhar este objeto por cima, via
# LD_PRELOAD, quebra a cadeia: na primeira tentativa isto derrubou o proprio
# `timeout` com SIGABRT, e a suite de sanitizadores parou num diagnostico que
# nao era sobre o codigo medido.
#
# PULAR E A RESPOSTA CERTA, E NAO DESLIGAR O ASAN: a injecao exercita o caminho
# de erro, e o ASan exercita memoria. Sao dois testes, e a build normal ja roda
# este. Um PULADO declarado diz isso; um teste que nao roda em silencio, nao.
if ldd "$1" 2>/dev/null | grep -q 'libasan'; then
    echo "  PULADO: binarios com AddressSanitizer -- o ASan ja interpoe"
    echo "          pthread_create, e a injecao por LD_PRELOAD conflita com ele."
    echo "          Este caminho e coberto na build sem sanitizadores."
    exit 77
fi

# 77 E "ESTA MAQUINA NAO OFERECE A CONDICAO", E NAO FALHA.
#
# `custo-paralelismo` e `custo-comunicacao` saem com 77 quando a topologia nao
# tem o que eles exigem -- nucleos fisicos distintos no mesmo dominio de L3,
# por exemplo. Num runner pequeno isso e o comportamento CORRETO, e a primeira
# versao deste teste o tratava como defeito:
#
#     FALHA: sem injecao, custo-paralelismo devia medir e saiu com 77
#     FALHA: custo-paralelismo reprovou sem dizer por que
#
# A segunda mensagem e consequencia da primeira: sob injecao o programa para no
# guarda de topologia ANTES de chegar ao caminho de recusa, entao a saida nao
# fala em coleta invalida -- ele recusou por outro motivo, legitimo.
#
# O erro e o mesmo que uma revalidacao apontou no teste de topologia: uma
# assercao que presume a maquina de referencia. Aqui cada binario e sondado
# primeiro SEM injecao, e o que nao puder medir nesta maquina e pulado com a
# razao dita -- em vez de reprovar o runner por nao ser a bancada.
medivel() { # <binario> -> 0 se mede aqui, 1 se pula, 2 se esta quebrado
    local rc=0
    timeout "$LIMITE" env DPDK_ACADEMY_AMOSTRAS=3 DPDK_ACADEMY_RODADAS=1000 \
        "$1" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0)  return 0 ;;
        77) return 1 ;;
        *)  echo "  FALHA: $(basename "$1") sem injecao devia medir ou pular, e saiu com $rc"
            return 2 ;;
    esac
}

exercitados=0
for bin in "$@"; do
    nome=$(basename "$bin")
    [ -x "$bin" ] || { echo "  FALHA: $bin nao e executavel"; falhas=$((falhas+1)); continue; }

    medivel "$bin"; estado=$?
    if [ "$estado" -eq 1 ]; then
        echo "  PULADO para $nome: esta maquina nao oferece a condicao que ele exige (77)"
        continue
    elif [ "$estado" -eq 2 ]; then
        falhas=$((falhas + 1))
        continue
    fi
    exercitados=$((exercitados + 1))

    saida=$(mktemp); rc=0
    timeout "$LIMITE" env LD_PRELOAD="$shim" FALHAR_NA_CRIACAO_PARCIAL=1 \
        DPDK_ACADEMY_AMOSTRAS=3 DPDK_ACADEMY_RODADAS=1000 \
        "$bin" > "$saida" 2>&1 || rc=$?

    if [ "$rc" -eq 124 ]; then
        echo "  FALHA: $nome NAO TERMINOU em ${LIMITE}s sob criacao parcial (deadlock)"
        falhas=$((falhas + 1))
    elif [ "$rc" -eq 0 ]; then
        echo "  FALHA: $nome saiu com 0 apos falha de criacao de thread"
        falhas=$((falhas + 1))
    fi

    # E NAO BASTA REPROVAR: precisa DIZER que recusou.
    #
    # A primeira versao desta assercao exigia que nada fosse impresso antes da
    # recusa, e estava errada: as linhas que saem sao medicoes VALIDAS de fases
    # que terminaram antes da injecao -- a tabela que falhou sai so com
    # cabecalho. Exigir silencio puniria o comportamento correto.
    #
    # O contrato que importa e outro: quem le o arquivo bruto precisa encontrar
    # a razao da recusa, e nao so um codigo de saida que o arquivo nao carrega.
    if ! grep -qiE "INVALIDA|invalid" "$saida"; then
        echo "  FALHA: $nome reprovou sem dizer por que (nada sobre coleta invalida na saida)"
        falhas=$((falhas + 1))
    fi
    rm -f "$saida"
done

# O CAMINHO NORMAL JA FOI EXERCITADO por `medivel`, uma vez por binario, antes
# de cada bloco de injecao. Um shim que falhasse sempre faria as assercoes
# acima passarem por motivo errado, e e essa sondagem que impede.
#
# E SE NENHUM BINARIO PUDER MEDIR AQUI, o teste PULA em vez de dizer "ok": ele
# nao exercitou nada, e dizer que passou seria a mesma inferencia por ausencia
# que o resto desta auditoria combate.
if [ "$exercitados" -eq 0 ] && [ "$falhas" -eq 0 ]; then
    echo "  PULADO: nenhum dos binarios mede nesta maquina; nada foi exercitado"
    exit 77
fi

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: $exercitados binario(s) exercitado(s); criacao parcial termina e reprova"
