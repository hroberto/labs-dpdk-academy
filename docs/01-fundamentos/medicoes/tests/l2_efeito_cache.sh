#!/usr/bin/env bash
# L2 do `efeito-cache`: a coluna `sequencial` tem de continuar PLANA.
#
# POR QUE ESTE TESTE EXISTE
#
# O laco de `medir()` acumula numa cadeia carregada pelo laco, com teto de ~1
# elemento por ciclo. Esse teto nao depende de onde o dado esta: com o conjunto
# na L1d e com ele em 256 MB de DRAM o valor e o MESMO, porque a memoria
# entrega mais do que o laco consome.
#
# A planura e o resultado que a §4.2 publica -- o prefetcher sustenta a emissao
# cheia ate a DRAM. Ela tambem e a evidencia de que a coluna NAO mede banda: um
# bandimetro mostraria gradiente entre os niveis.
#
# QUANDO ESTE TESTE FALHAR, NAO CONSERTE O TESTE
#
# Se a coluna deixar de ser plana, o laco mudou de carater -- alguem quebrou a
# cadeia do acumulador, ligou vetorizacao ou trocou as flags. Isso pode ser uma
# MELHORIA, e nesse caso a §4.2 precisa ser reescrita: a coluna passa a medir
# outra coisa, e o texto que explica a planura deixa de valer.
#
# O defeito que este teste impede e o mesmo de `test_l1_cadeia.cpp`: o programa
# medir uma coisa enquanto o documento afirma outra, com a suite verde.
set -u
BIN=${1:?uso: l2_efeito_cache.sh <binario>}
falhas=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FALHA- $1"; falhas=$((falhas+1)); fi; }

saida=$("$BIN" 2>&1) || { echo "FALHA: o programa nao executou"; exit 1; }

# A coluna `sequencial` de cada nivel, na ordem em que o programa os imprime.
mapfile -t seq < <(grep -oP '^\s+sequential\s+\(amortised\)\s+\K[0-9.]+' <<<"$saida")
[ "${#seq[@]}" -eq 4 ]
check "as quatro linhas de sequencial foram lidas (${#seq[@]})" $?
[ "${#seq[@]}" -eq 4 ] || { echo "saida inesperada"; exit 1; }

l1d=${seq[0]}; ram=${seq[3]}
# 25% e folgado de proposito: a planura e um efeito de ordem de grandeza, e a
# tolerancia nao pode ser tao apertada que o ruido da maquina a dispare.
plano=$(awk -v a="$l1d" -v b="$ram" 'BEGIN{d=(b-a)/a; if(d<0)d=-d; print (d<0.25)?0:1}')
check "sequencial plano entre L1d ($l1d ns) e RAM ($ram ns): a coluna nao mede banda" "$plano"

# O contraste que prova que o teto e do LACO e nao da maquina: as outras duas
# colunas, no mesmo programa e na mesma execucao, mostram gradiente enorme.
dep_l1d=$(grep -oP '^\s+dependent\s+\(LATENCY\)\s+\K[0-9.]+' <<<"$saida" | head -1)
dep_ram=$(grep -oP '^\s+dependent\s+\(LATENCY\)\s+\K[0-9.]+' <<<"$saida" | tail -1)
cresce=$(awk -v a="$dep_l1d" -v b="$dep_ram" 'BEGIN{print (b>a*20)?0:1}')
check "dependente cresce mais de 20x de L1d ($dep_l1d) a RAM ($dep_ram): a memoria APARECE quando o laco nao a esconde" "$cresce"

[ "$falhas" -eq 0 ] || exit 1
echo "  efeito-cache: coluna sequencial plana, colunas de memoria com gradiente"
