#!/usr/bin/env bash
# Campanha B4-tempo: a taxa de miss aparece no TEMPO?
#
# O QUE ESTA CAMPANHA RESPONDE, E POR QUE ELA NAO EXISTIA
#
# A §1.4 do modulo 03 mede IDAS AO ANEL COMUM e declara, nas limitacoes, que
# nao ha medida de tempo. O bloqueio era duplo e os dois lados cairam:
#
#   1. o build. `RTE_LIBRTE_MEMPOOL_STATS` incrementa contadores no caminho
#      quente, entao o programa medido nao era o de producao. Os prefixos
#      `-sem-stats` resolvem, e `preparar-dpdk.sh --sem-stats` os constroi.
#   2. o instrumento. O `pipeline_ring` imprimia o tempo com `%.1f`, o que
#      sobre ~4 ns quantiza em 2%. Com `DPDK_ACADEMY_BRUTO` ele emite os tres
#      inteiros de onde a media sai, sem arredondamento nenhum.
#
# POR QUE 21 REPETICOES, E NAO 6
#
# A contagem de idas ao anel e DETERMINISTICA acima do limiar de absorcao: as
# seis execucoes de uma celula davam o mesmo numero. Tempo nao e: um piloto de
# dez execucoes da mesma celula deu 8,4% entre a menor e a maior. Seis
# repeticoes sobre essa dispersao produziriam medianas que se movem entre
# coletas, que e o defeito que a §9.1 do modulo 01 documenta.
#
# O EFEITO ESPERADO E MUITO MAIOR QUE O RUIDO, e isso foi conferido ANTES de
# medir, nao depois: em `cache=64` assimetrico as versoes diferem em 20 833
# idas por milhao de pacotes, ou 0,0208 por pacote. A 50-200 ns por ida, sao
# 1,0 a 4,2 ns/pacote sobre uma base de ~3,8 -- de 27% a 109%.
#
# Se a diferenca medida ficar DENTRO da dispersao, isso tambem e resultado: a
# ida ao anel custa menos do que se supoe, e a §1.4 passa a poder dize-lo.
#
# EXIGE MAQUINA DEDICADA. A coleta nao deve ser iniciada sem aviso explicito.
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSOES=(25.11 26.07)
CACHES=(0 16 24 32 48 64 96 128 256 512)
declare -A TOPOLOGIA=( [simetrico]="-l 0" [assimetrico]="-l 0,2" )
PACOTES=2000000
LOTE=32

ENSAIO=0
if [ "${1:-}" = "--ensaio" ]; then ENSAIO=1; CACHES=(64); shift; fi
SAIDA=${1:?uso: campanha-mempool-tempo.sh <saida> [repeticoes]}
REPETICOES=${2:-21}
[ "$ENSAIO" -eq 1 ] && REPETICOES=3

binario() { echo "build-$1-sem-stats/trilha/01-fundamentos/02-mempool-ring/pipeline_ring"; }

# O PORTAO E O INVERSO DO DA OUTRA CAMPANHA, e por isso ele precisa existir.
# Medir tempo contra um prefixo COM estatisticas produziria numero plausivel e
# errado -- o contador roda no caminho quente. Conferir so a existencia do
# binario deixaria esse caso passar.
for v in "${VERSOES[@]}"; do
    b=$(binario "$v")
    [ -x "$b" ] || { echo "FALHA: $b ausente; construa contra o prefixo -sem-stats"; exit 1; }
    ./scripts/preparar-dpdk.sh --sem-stats --conferir "$v" >/dev/null || {
        echo "FALHA: o prefixo do DPDK $v NAO esta livre de RTE_LIBRTE_MEMPOOL_STATS"
        echo "       medir tempo com o contador ligado mede outro programa"
        exit 1
    }
done

mkdir -p "$SAIDA"
CSV="$SAIDA/mempool-tempo.csv"
echo "repeticao,ordem,versao,topologia,cache,ciclos,tsc_hz,pacotes,ns_por_pacote" > "$CSV"

uma() { # <versao> <topologia> <cache> <repeticao> <ordem>
    local v=$1 topo=$2 c=$3 rep=$4 ordem=$5 tmp
    tmp=$(mktemp)
    local pref="acad_t_$$_${v//./}_${topo}_${c}"
    # shellcheck disable=SC2086
    if ! DPDK_ACADEMY_BRUTO=1 "$(binario "$v")" ${TOPOLOGIA[$topo]} --no-huge --no-pci \
            --file-prefix="$pref" -- -n "$PACOTES" -b "$LOTE" -c "$c" >"$tmp" 2>&1; then
        echo "FALHA: execucao saiu com erro ($v, $topo, cache $c)"
        sed 's/^/    | /' "$tmp"; rm -f "$tmp"; exit 1
    fi
    local linha
    linha=$(grep -oP '^raw timing: cycles=\K[0-9]+ tsc_hz=[0-9]+ packets=[0-9]+' "$tmp" \
            | sed 's/tsc_hz=//;s/packets=//') || true
    if [ -z "$linha" ]; then
        echo "FALHA: o programa nao emitiu 'raw timing' ($v, $topo, cache $c)"
        echo "       DPDK_ACADEMY_BRUTO nao chegou, ou o binario e antigo"
        sed 's/^/    | /' "$tmp"; rm -f "$tmp"; exit 1
    fi
    read -r ciclos hz pkts <<<"$linha"
    # A conta sai dos TRES INTEIROS, nao da linha arredondada que o programa
    # tambem imprime. E o motivo de existir a saida bruta.
    local ns
    ns=$(python3 -c "print(f'{$ciclos*1e9/$hz/$pkts:.4f}')")
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$rep" "$ordem" "$v" "$topo" "$c" "$ciclos" "$hz" "$pkts" "$ns" >> "$CSV"
    cp "$tmp" "$SAIDA/$v.$topo.c$c.r$rep.txt"
    rm -f "$tmp"
}

echo "==> campanha B4-tempo: ${#VERSOES[@]} versoes x ${#TOPOLOGIA[@]} topologias"
echo "    x ${#CACHES[@]} tamanhos de cache x $REPETICOES repeticoes"
echo "    prefixos SEM RTE_LIBRTE_MEMPOOL_STATS, metrica em ns/pacote"
echo "    saida: $CSV"

for rep in $(seq 1 "$REPETICOES"); do
    # A unidade de repeticao e a CELULA, e as duas versoes de uma celula correm
    # adjacentes: e o mesmo desenho da campanha de contagem, pela mesma razao --
    # bracos em blocos confundem efeito com deriva de estado da maquina.
    mapfile -t celulas < <(
        for topo in "${!TOPOLOGIA[@]}"; do for c in "${CACHES[@]}"; do echo "$topo $c"; done; done | shuf)
    ordem=0
    for cel in "${celulas[@]}"; do
        read -r topo c <<<"$cel"
        ordem=$((ordem + 1))
        for v in "${VERSOES[@]}"; do uma "$v" "$topo" "$c" "$rep" "$ordem"; done
    done
    echo "    repeticao $rep de $REPETICOES concluida"
done

echo "==> $(( $(wc -l < "$CSV") - 1 )) execucoes registradas em $CSV"
