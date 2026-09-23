#!/usr/bin/env bash
# Campanha do tópico de isolamento — Parte A, sem rede e sem privilégio.
#
# POR QUE ESTE SCRIPT EXISTE
#
# A coleta anterior deste repositório que foi conduzida a mão -- 168 execuções
# do estudo de mempool -- não era reproduzível e tinha os braços em blocos. O
# mesmo erro não se repete aqui: as células correm intercaladas e o script fica
# na árvore.
#
# AS QUATRO CÉLULAS, E POR QUE CADA UMA
#
#   P0              sonda sozinha. É a linha de base: só afinidade.
#   P0+ipi-thread   provocador como THREAD do mesmo processo. Testa H3.
#   P0+ipi-proc     provocador como PROCESSO separado. É o CONTRASTE que mostra
#                   que o escopo do IPI é o espaço de endereçamento, não a CPU.
#   P5-irmao        laço ocupado no irmão SMT da CPU medida. Testa a última
#                   linha da tabela da §2, que não aparece como interrupção.
#
# O CONTRASTE ENTRE AS DUAS TERCEIRAS É O DESENHO. Sem a célula do processo
# separado, "o provocador aumenta o TLB" seria compatível com "qualquer carga
# em outra CPU aumenta o TLB", que é falso e foi o que eu supus primeiro.
#
# EXIGE MÁQUINA DEDICADA. A coleta não deve ser iniciada sem aviso explícito.
set -euo pipefail
cd "$(dirname "$0")/../.."

SONDA=build/trilha/03-performance/03-isolamento-cpu/stall_probe
PROC_SEP=build/trilha/03-performance/03-isolamento-cpu/ipi_provoker
CPU_SONDA=${CPU_SONDA:-2}
CPU_OUTRA=${CPU_OUTRA:-4}
DURACAO=${DURACAO:-30}
LIMIAR=${LIMIAR:-2000}

SAIDA=${1:?uso: campanha-isolamento.sh <saida> [repeticoes]}
REPETICOES=${2:-5}

for b in "$SONDA" "$PROC_SEP"; do
    [ -x "$b" ] || { echo "FALHA: $b ausente; rode scripts/build-all.sh"; exit 1; }
done

# O irmão SMT sai da topologia, não de suposição: em outra máquina o par é
# outro, e um número fixo aqui isolaria o núcleo errado em silêncio.
IRMAO=$(tr ',' '\n' < "/sys/devices/system/cpu/cpu$CPU_SONDA/topology/thread_siblings_list" \
        | grep -v "^$CPU_SONDA$" | head -1)
if [ -z "$IRMAO" ]; then
    echo "FALHA: nao achei o irmao SMT da CPU $CPU_SONDA; SMT desligado?"
    exit 1
fi

mkdir -p "$SAIDA"
CSV="$SAIDA/isolamento.csv"
echo "repeticao,ordem,celula,cpu,segundos,amostras,acima_limiar,p99_piso,p999_piso,maior_ns,preempcoes,loc,tlb,cal,res" > "$CSV"

extrair() { # <arquivo> <campo>
    case $2 in
      amostras)   grep -oP '^samples: \K[0-9]+' "$1" ;;
      acima)      grep -oP '^stalls above threshold: \K[0-9]+' "$1" ;;
      p99)        grep -oP '^p99 floor: \K[0-9]+' "$1" ;;
      p999)       grep -oP '^p99\.9 floor: \K[0-9]+' "$1" ;;
      maior)      grep -oP '^max stall: \K[0-9]+' "$1" ;;
      preemp)     grep -oP '^involuntary context switches: \K[0-9]+' "$1" ;;
      *)          awk -v r="$2" '$1==r {print $2; f=1} END{if(!f) print 0}' "$1" | head -1 ;;
    esac
}

uma() { # <celula> <repeticao> <ordem>
    local celula=$1 rep=$2 ordem=$3
    local tmp aux=0
    tmp=$(mktemp)

    case "$celula" in
      P0)            "$SONDA" "$CPU_SONDA" "$DURACAO" "$LIMIAR" >"$tmp" 2>&1 ;;
      P0+ipi-thread) "$SONDA" "$CPU_SONDA" "$DURACAO" "$LIMIAR" "$CPU_OUTRA" >"$tmp" 2>&1 ;;
      P0+ipi-proc)   "$PROC_SEP" "$CPU_OUTRA" "$DURACAO" 8 >/dev/null 2>&1 & aux=$!
                     "$SONDA" "$CPU_SONDA" "$DURACAO" "$LIMIAR" >"$tmp" 2>&1
                     wait "$aux" 2>/dev/null || true ;;
      P5-irmao)      taskset -c "$IRMAO" sh -c 'while :; do :; done' & aux=$!
                     "$SONDA" "$CPU_SONDA" "$DURACAO" "$LIMIAR" >"$tmp" 2>&1
                     kill "$aux" 2>/dev/null || true; wait "$aux" 2>/dev/null || true ;;
      *) echo "celula desconhecida: $celula"; rm -f "$tmp"; exit 1 ;;
    esac

    if ! grep -q '^max stall:' "$tmp"; then
        echo "FALHA: a sonda nao relatou ($celula, rep $rep)"
        sed 's/^/    | /' "$tmp"; rm -f "$tmp"; exit 1
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$rep" "$ordem" "$celula" "$CPU_SONDA" "$DURACAO" \
        "$(extrair "$tmp" amostras)" "$(extrair "$tmp" acima)" \
        "$(extrair "$tmp" p99)" "$(extrair "$tmp" p999)" "$(extrair "$tmp" maior)" \
        "$(extrair "$tmp" preemp)" \
        "$(extrair "$tmp" LOC)" "$(extrair "$tmp" TLB)" \
        "$(extrair "$tmp" CAL)" "$(extrair "$tmp" RES)" >> "$CSV"
    # A saída bruta é arquivada: a procedência que o programa imprime não cabe
    # numa linha de CSV, e sem ela a tabela publicada seria número sem rastro.
    cp "$tmp" "$SAIDA/$celula.r$rep.txt"
    rm -f "$tmp"
}

echo "==> campanha de isolamento: CPU $CPU_SONDA (irmao SMT $IRMAO), outra CPU $CPU_OUTRA"
echo "    4 celulas x $REPETICOES repeticoes x ${DURACAO}s"

for rep in $(seq 1 "$REPETICOES"); do
    # A ordem muda a cada repetição: célula sempre medida primeiro carregaria o
    # estado inicial da máquina de forma sistemática, que é deriva com outro nome.
    mapfile -t celulas < <(printf '%s\n' P0 P0+ipi-thread P0+ipi-proc P5-irmao | shuf)
    ordem=0
    for c in "${celulas[@]}"; do
        ordem=$((ordem + 1))
        uma "$c" "$rep" "$ordem"
    done
    echo "    repeticao $rep de $REPETICOES concluida"
done

echo "==> $(( $(wc -l < "$CSV") - 1 )) execucoes registradas em $CSV"
