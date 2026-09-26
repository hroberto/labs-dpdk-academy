#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Compara o pipeline do tópico 02 com o consumidor em núcleos de domínios de
# cache diferentes. Descobre os domínios pelo sysfs, então funciona em qualquer
# CPU — em máquinas de um único domínio, avisa e mede só o caso disponível.
#
# Uso: scripts/bench-ccd.sh [pacotes]
set -u
cd "$(dirname "$0")/.."
BIN=build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring
PACOTES=${1:-3000000}
[ -x "$BIN" ] || { echo "compile antes: ./scripts/build-all.sh" >&2; exit 1; }

# Domínios de L3 distintos, na ordem em que aparecem.
mapfile -t DOM < <(for c in /sys/devices/system/cpu/cpu*/cache/index3/shared_cpu_list; do
                       cat "$c" 2>/dev/null; done | sort -u)
primeiro() { echo "${1%%[,-]*}"; }

# `0-5,12-17` -> `0 1 2 3 4 5 12 13 14 15 16 17`
expandir() {
    local parte ini fim saida="" partes
    IFS=',' read -ra partes <<< "$1"
    for parte in "${partes[@]}"; do
        if [[ $parte == *-* ]]; then
            ini=${parte%-*}; fim=${parte#*-}
            for ((c = ini; c <= fim; c++)); do saida+="$c "; done
        else
            saida+="$parte "
        fi
    done
    echo "$saida"
}

# O PARCEIRO E ESCOLHIDO NA LISTA DO DOMINIO, e nao por aritmetica.
#
# Ate aqui a CPU do "mesmo dominio" era `A + 2`. O script LE a topologia no
# sysfs, imprime os dominios na tela, e entao ignora o que leu. Nesta maquina
# acerta por coincidencia do enumerador -- o CCD0 e `0-5,12-17`, logo 0 e 2 sao
# vizinhos --, e noutra topologia o script que existe para comparar DENTRO do
# domínio compararia ENTRE dominios, com o rotulo errado. Um numero certo por
# acidente de layout e um numero errado esperando outra maquina.
#
# Duas condicoes, e as duas importam:
#   - pertencer ao mesmo dominio de L3, que e a variavel do experimento;
#   - estar em NUCLEO FISICO distinto, senao a comparacao mede disputa por
#     unidades de execucao em vez de distancia de cache.
# MULTILINHA DE PROPOSITO, com o `}` na coluna zero: os testes deste projeto
# extraem funcoes com `sed -n '/^nome() {/,/^}/p'`, e uma funcao de uma linha so
# faz o intervalo engolir tudo ate o fechamento da proxima.
irmaos_de() {
    cat "/sys/devices/system/cpu/cpu$1/topology/thread_siblings_list" 2>/dev/null
}

parceiro_no_dominio() { # <cpu> <lista-do-dominio>
    local a=$1 irmaos c
    irmaos=",$(expandir "$(irmaos_de "$a")" | tr ' ' ',')"
    # LISTA DE IRMAOS VAZIA NAO PROVA NADA, e aceitar assim mesmo seria inferir
    # por ausencia. Sem ela, qualquer CPU do dominio passaria -- inclusive o
    # irmao SMT --, e a comparacao "mesmo dominio" mediria disputa por unidades
    # de execucao em vez de distancia de cache.
    if [ "$irmaos" = ",," ] || [ "$irmaos" = "," ]; then
        return 1
    fi
    for c in $(expandir "$2"); do
        [ "$c" = "$a" ] && continue
        case "$irmaos" in *",$c,"*) continue ;; esac
        echo "$c"; return 0
    done
    return 1
}

# A GUARDA VEM ANTES DO PRIMEIRO USO. `${DOM[0]}` com o vetor vazio, sob
# `set -u`, mata o script com "unbound variable" -- e a mensagem util estava
# treze linhas abaixo, sem chance de ser alcancada.
if [ "${#DOM[@]}" -eq 0 ]; then
    echo "o sysfs nao expos nenhum dominio de L3 (index3/shared_cpu_list)." >&2
    echo "  Sem a topologia nao ha o que comparar: a distancia de cache E o experimento." >&2
    exit 1
fi

A=$(primeiro "${DOM[0]}")
if ! A2=$(parceiro_no_dominio "$A" "${DOM[0]}"); then
    echo "o dominio de L3 da cpu $A nao tem segunda CPU em nucleo fisico distinto." >&2
    echo "  dominio 0: ${DOM[0]}" >&2
    exit 1
fi
echo "Dominios de cache L3: ${#DOM[@]}"
for i in "${!DOM[@]}"; do echo "  dominio $i: CPUs ${DOM[$i]}"; done
echo

melhor() {  # $1 = args da EAL, $2 = lote
    for _ in 1 2 3; do
        $BIN $1 --no-huge --file-prefix=academy_ccd_$$ -- -n "$PACOTES" -b "$2" 2>/dev/null |
            awk '/Mean time/{print $3}'
    done | sort -n | head -1
}

if [ "${#DOM[@]}" -lt 2 ]; then
    echo "CPU com um unico dominio de L3: sem par 'distante' para comparar."
    printf "%-6s %12s %14s\n" "lote" "1 lcore" "2 lcores"
    for b in 1 8 32 128; do
        printf "%-6s %10s ns %11s ns\n" "$b" "$(melhor "-l $A" $b)" "$(melhor "-l $A,$A2" $b)"
    done
    exit 0
fi

B=$(primeiro "${DOM[1]}")
printf "%-6s %11s %14s %16s %8s\n" "lote" "1 lcore" "mesmo dominio" "dominios difer." "razao"
for b in 1 4 8 32 64 128 256; do
    um=$(melhor "-l $A" $b)
    mesmo=$(melhor "-l $A,$A2" $b)
    dif=$(melhor "-l $A,$B" $b)
    razao=$(LC_ALL=C awk -v d="$dif" -v m="$mesmo" 'BEGIN{printf "%.1fx", d/m}')
    printf "%-6s %9s ns %11s ns %13s ns %8s\n" "$b" "$um" "$mesmo" "$dif" "$razao"
done
echo
echo "produtor no cpu $A | consumidor: $A2 (mesmo dominio) vs $B (outro dominio)"
