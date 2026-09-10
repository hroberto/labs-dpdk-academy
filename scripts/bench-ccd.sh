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
segundo()  { local l=${1%%,*}; echo "${l#*-}"; }

A=$(primeiro "${DOM[0]}")
A2=$(( A + 2 ))
echo "Dominios de cache L3: ${#DOM[@]}"
for i in "${!DOM[@]}"; do echo "  dominio $i: CPUs ${DOM[$i]}"; done
echo

melhor() {  # $1 = args da EAL, $2 = lote
    for _ in 1 2 3; do
        $BIN $1 --in-memory --no-huge -- -n "$PACOTES" -b "$2" 2>/dev/null |
            awk '/Tempo medio/{print $3}'
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
