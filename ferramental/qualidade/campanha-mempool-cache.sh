#!/usr/bin/env bash
# Campanha do estudo B4: cache do mempool, 25.11 contra 26.07.
#
# POR QUE ESTE SCRIPT EXISTE, E POR QUE ELE INTERCALA
#
# A primeira campanha deste estudo, com 168 execucoes, foi conduzida a mao e com
# os BRACOS EM BLOCOS: todas as execucoes de uma versao, depois todas da outra.
# Coleta em blocos confunde o efeito com a deriva de estado da maquina --
# frequencia, temperatura, carga --, e foi assim que uma diferenca de 0,70 ns
# por pacote virou 0,15 ns quando as mesmas medicoes foram intercaladas.
#
# Aqui a UNIDADE DE REPETICAO E A CELULA, nao o braco: as duas versoes de uma
# mesma celula correm adjacentes, e a ordem das celulas e permutada a cada
# repeticao. Deriva que atinja uma versao atinge a outra no mesmo instante.
#
# A METRICA PUBLICADA E `get_common`: idas ao anel comum, normalizadas por
# milhao de pacotes entregues. NAO e a taxa de miss.
#
# A taxa (`miss_pct`) continua no CSV porque e o que o programa imprime, e o CSV
# registra a saida, nao a conclusao. Mas ela NAO e publicavel: o denominador
# dela sao as chamadas de `get`, e o produtor retenta quando a fila enche --
# cada retentativa e mais uma chamada. Em cache_size 96, 49 023 das 111 523
# chamadas sao retentativa. O denominador mede a corrida entre os dois lcores,
# nao o cache. O numerador nao varia; a razao varia. Ver a subsecao "A metrica:
# por que nao e 'taxa de miss'" do modulo 03.
#
# O ns/pacote foi descartado de proposito: os dois prefixos tem
# RTE_LIBRTE_MEMPOOL_STATS ligado, o contador e atualizado no caminho quente, e
# o tempo medido ali e o de um programa que nao e o de producao.
#
# EXIGE MAQUINA DEDICADA. A coleta nao deve ser iniciada sem aviso explicito de
# que a maquina esta exclusiva para esta finalidade.
#
# USO
#
#   campanha-mempool-cache.sh <saida> [repeticoes]
#   campanha-mempool-cache.sh --ensaio    # uma repeticao, 2 celulas, so para
#                                         # conferir a mecanica
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSOES=(25.11 26.07)
# Varredura fina entre 16 e 128 porque e ali que o degrau nao explicado de
# c=32->64 aparece; se ele sobreviver a intercalacao, tem forma, e forma se
# explica. Se dissolver, era deriva entre blocos e a pergunta desaparece.
CACHES=(16 24 32 48 64 96 128 256 512)
# `c=0` desliga o cache em vez de dimensiona-lo: e PONTO DE CONTROLE, nao
# celula do fatorial, e por isso corre a parte e uma vez por repeticao.
CONTROLE=0
# -l 0    get e put no MESMO cache  -> simetrico
# -l 0,2  um lcore so obtem, outro so devolve -> assimetrico
declare -A TOPOLOGIA=( [simetrico]="-l 0" [assimetrico]="-l 0,2" )

ENSAIO=0
if [ "${1:-}" = "--ensaio" ]; then
    ENSAIO=1; CACHES=(32 64); shift
fi
SAIDA=${1:?uso: campanha-mempool-cache.sh <saida> [repeticoes]}
REPETICOES=${2:-6}
[ "$ENSAIO" -eq 1 ] && REPETICOES=1

binario() { echo "build-$1/trilha/01-fundamentos/02-mempool-ring/pipeline_ring"; }

for v in "${VERSOES[@]}"; do
    b=$(binario "$v")
    [ -x "$b" ] || { echo "FALHA: $b ausente; construa contra o prefixo do DPDK $v"; exit 1; }
    ./scripts/preparar-dpdk.sh --conferir "$v" >/dev/null || {
        echo "FALHA: o prefixo do DPDK $v nao tem RTE_LIBRTE_MEMPOOL_STATS visivel"
        echo "       sem ele a metrica primaria nao existe e a campanha nao tem eixo"
        exit 1
    }
done

mkdir -p "$SAIDA"
CSV="$SAIDA/mempool-cache.csv"
echo "repeticao,ordem,versao,topologia,cache,get_bulk,get_common,miss_pct" > "$CSV"

# A linha `total` e a que agrega os lcores; na topologia assimetrica ha duas
# linhas de lcore e e a soma que interessa.
extrair() { # <arquivo-de-saida>
    awk '/^  total/ { print $2 "," $3 "," $4; encontrou=1 }
         END { if (!encontrou) exit 1 }' "$1" | tr -d '%'
}

uma_execucao() { # <versao> <topologia> <cache> <repeticao> <ordem>
    local v=$1 topo=$2 c=$3 rep=$4 ordem=$5
    local tmp; tmp=$(mktemp)
    local pref="academy_b4_$$_${v//./}_${topo}_${c}"
    # shellcheck disable=SC2086
    if ! "$(binario "$v")" ${TOPOLOGIA[$topo]} --no-huge --no-pci \
            --file-prefix="$pref" -- -n 2000000 -b 32 -c "$c" >"$tmp" 2>&1; then
        echo "FALHA: execucao saiu com erro (versao $v, $topo, cache $c)"
        sed 's/^/    | /' "$tmp"; rm -f "$tmp"
        # Coleta parcial nao vira tabela: abortar e o comportamento certo.
        exit 1
    fi
    local dados
    if ! dados=$(extrair "$tmp"); then
        echo "FALHA: sem linha 'total' na saida (versao $v, $topo, cache $c)."
        echo "       O binario foi construido contra um DPDK sem as estatisticas?"
        sed 's/^/    | /' "$tmp"; rm -f "$tmp"; exit 1
    fi
    echo "$rep,$ordem,$v,$topo,$c,$dados" >> "$CSV"
    # A SAIDA BRUTA E ARQUIVADA, nao so o CSV. O verificador de blocos confere
    # numero publicado contra coleta arquivada, e uma linha de CSV nao carrega a
    # procedencia que o programa imprime -- versao do DPDK, commit, host, gcc e
    # data. Sem o bruto, a tabela publicada seria um numero sem rastro.
    cp "$tmp" "$SAIDA/$v.$topo.c$c.r$rep.txt"
    rm -rf "${XDG_RUNTIME_DIR:-/var/run}/dpdk/$pref"
    rm -f "$tmp"
}

echo "==> campanha B4: ${#VERSOES[@]} versoes x ${#TOPOLOGIA[@]} topologias"
echo "    x ${#CACHES[@]} tamanhos de cache x $REPETICOES repeticoes"
echo "    saida: ${CSV#$PWD/}"

for rep in $(seq 1 "$REPETICOES"); do
    # A ORDEM DAS CELULAS MUDA A CADA REPETICAO. Sem isto, uma celula sempre
    # medida no inicio e outra sempre no fim carregariam estados diferentes da
    # maquina de forma sistematica -- que e deriva com outro nome.
    mapfile -t celulas < <(
        for topo in "${!TOPOLOGIA[@]}"; do
            for c in "${CACHES[@]}" "$CONTROLE"; do echo "$topo $c"; done
        done | shuf
    )
    ordem=0
    for celula in "${celulas[@]}"; do
        read -r topo c <<<"$celula"
        ordem=$((ordem + 1))
        # AS DUAS VERSOES ADJACENTES: e este par que torna a comparacao imune a
        # deriva lenta. A ordem interna tambem alterna, para que nenhuma versao
        # seja sempre a primeira a rodar depois de uma pausa.
        if [ $(( (rep + ordem) % 2 )) -eq 0 ]; then
            uma_execucao "${VERSOES[0]}" "$topo" "$c" "$rep" "$ordem"
            uma_execucao "${VERSOES[1]}" "$topo" "$c" "$rep" "$ordem"
        else
            uma_execucao "${VERSOES[1]}" "$topo" "$c" "$rep" "$ordem"
            uma_execucao "${VERSOES[0]}" "$topo" "$c" "$rep" "$ordem"
        fi
    done
    echo "    repeticao $rep de $REPETICOES concluida"
    # Residuo acumulado esgotaria as hugepages no meio da campanha, e a falha
    # pareceria da campanha. Conferir entre repeticoes e barato.
    if [ -x ferramental/qualidade/rastros-da-suite.py ]; then
        marca=$(mktemp)
        ferramental/qualidade/rastros-da-suite.py --marcar >"$marca" 2>/dev/null || true
        ferramental/qualidade/rastros-da-suite.py --conferir "$marca" >/dev/null 2>&1 ||
            echo "      AVISO: rastro deixado no sistema apos a repeticao $rep"
        rm -f "$marca"
    fi
done

echo "==> $(( $(wc -l < "$CSV") - 1 )) execucoes registradas em ${CSV#$PWD/}"
