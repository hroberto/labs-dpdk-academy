#!/usr/bin/env bash
# Quanto a frequencia livre cobra: N execucoes, cada uma com o clock onde estiver.
#
# POR QUE ESTE SCRIPT EXISTE
#
# A §do topico de benchmarking publica doze pares `frequencia de partida` x
# `ns por chamada`, e o `custo-syscall` NAO IMPRIME FREQUENCIA NENHUMA. A tabela
# foi montada a mao, lendo o sysfs ao lado de cada execucao -- numero sem
# programa, que e o que a regra editorial deste projeto proibe.
#
# O DESENHO DEPENDE DE NAO FIXAR O GOVERNOR, e isso e o oposto de todo o resto
# da campanha. Aqui a variavel de interesse E a frequencia de partida: fixa-la
# apagaria o experimento. Por isso este script nao entra no `run-all.sh` --
# ele mede sob a condicao que as outras coletas excluem, e misturar os dois
# regimes num mesmo arquivo confundiria quem lesse depois.
#
# A DISPERSAO SAI DE GRACA. Entre execucoes o governor leva o clock a lugares
# diferentes conforme o que a maquina acabou de fazer; nao e preciso provocar
# nada. Se sair estreita demais, rode com mais repeticoes ou depois de ociosidade.
#
#   uso:  bash ferramental/qualidade/campanha-frequencia-livre.sh [repeticoes]
set -uo pipefail
cd "$(dirname "$0")/../.."

N=${1:-12}
CPU=${CPU:-0}
BIN=build/docs/01-fundamentos/medicoes/custo-syscall
[ -x "$BIN" ] || { echo "FALHA: $BIN ausente; rode ./scripts/build-all.sh" >&2; exit 1; }

SAIDA="docs/01-fundamentos/medicoes/historico/$(date +%Y-%m-%d-%H%M)-frequencia-livre"
mkdir -p "$SAIDA"
./scripts/ambiente.sh > "$SAIDA/ambiente.txt" 2>&1
{
    echo "repeticoes      : $N"
    echo "cpu observada   : $CPU"
    echo "governor        : $(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor 2>/dev/null)"
    echo "NAO fixado de proposito: a frequencia de partida e a variavel medida"
} >> "$SAIDA/ambiente.txt"

echo "  freq_ghz	ns_por_chamada" > "$SAIDA/frequencia-livre.tsv"
echo "==> $N execucoes  ($(date -Is))"
printf "  %-10s %s\n" "GHz" "ns/chamada"
for r in $(seq 1 "$N"); do
    # A LEITURA VEM ANTES DA EXECUCAO, e a ordem e o experimento: o que se quer
    # e o clock em que o programa PARTIU, nao a media dele durante a medicao.
    khz=$(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
    # `LC_NUMERIC=C`: sem isso o `awk` herda a virgula decimal da locale e grava
    # `4,33` num TSV. Arquivo de dados leva ponto -- a virgula e do texto, e
    # misturar as duas quebra todo leitor que fizer conta com o campo.
    ghz=$(LC_NUMERIC=C awk -v k="$khz" 'BEGIN{printf "%.2f", k/1e6}')
    "$BIN" > "$SAIDA/custo-syscall.r$r.txt" 2>&1
    ns=$(grep -oP '^\s+function call \(user-space\)\s+\K[0-9.]+' "$SAIDA/custo-syscall.r$r.txt" | head -1)
    printf "  %-10s %s\n" "$ghz" "${ns:-?}"
    printf "  %s\t%s\n" "$ghz" "${ns:-?}" >> "$SAIDA/frequencia-livre.tsv"
done

echo
echo "==> faixa"
# `+0` forca conversao numerica: sem isso a comparacao e de STRING, e
# "0.719" < "0.924" so por acaso -- "10.0" seria menor que "9.0".
LC_NUMERIC=C awk -F'\t' '
     NR>1 { f=$1+0; n=$2+0; if (n==0) next
            if (fmin==""||f<fmin) fmin=f; if (f>fmax) fmax=f
            if (nmin==""||n<nmin) nmin=n; if (n>nmax) nmax=n }
     END { if (nmin=="") { print "    nenhuma execucao valida"; exit }
           printf "    frequencia: %.2f a %.2f GHz\n", fmin, fmax
           printf "    resultado : %.3f a %.3f ns (%.1f%% de amplitude)\n",
                  nmin, nmax, (nmax/nmin-1)*100 }' "$SAIDA/frequencia-livre.tsv"
echo "    saida: $SAIDA"
