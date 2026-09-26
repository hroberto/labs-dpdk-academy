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

mapfile -t dep < <(grep -oP '^\s+dependent\s+\(LATENCY\)\s+\K[0-9.]+' <<<"$saida")
[ "${#dep[@]}" -eq 4 ]
check "as quatro linhas de dependente foram lidas (${#dep[@]})" $?

# A COMPARACAO E ENTRE AS DUAS COLUNAS, NAO CONTRA UMA TOLERANCIA FIXA.
#
# Uma primeira versao exigia "L1d e RAM dentro de 25%" na coluna sequencial.
# Passava isolada e falhava na suite: o Meson roda os testes em PARALELO, e sob
# a disputa a L1d chegou a sair MAIS LENTA que a RAM (0,325 contra 0,223 ns).
# Ruido de contencao move os dois numeros e estoura qualquer limite absoluto.
#
# A propriedade real e relacional e sobrevive a isso: as duas colunas veem a
# MESMA contencao na MESMA execucao, entao a razao entre os espalhamentos nao
# depende da carga. Sequencial quase nao espalha porque o teto e do laco;
# dependente espalha por duas ordens de grandeza porque mede a memoria.
# LC_ALL=C em todo awk: numa locale com virgula decimal o awk le "0.185" como
# 0, e a conta sai em infinito ou NaN sem que nada no teste pareca errado.
espalhamento() { # max/min de uma lista
    printf '%s\n' "$@" | LC_ALL=C awk 'NR==1{mn=mx=$1} {if($1<mn)mn=$1; if($1>mx)mx=$1}
                                        END{printf "%.4f", (mn>0)?mx/mn:0}'
}
esp_seq=$(espalhamento "${seq[@]}")
esp_dep=$(espalhamento "${dep[@]}")
razao=$(LC_ALL=C awk -v s="$esp_seq" -v d="$esp_dep" 'BEGIN{printf "%.1f", (s>0)?d/s:0}')
# 10x e folgado: limpo a razao fica perto de 95x, e sob contencao caiu a 67x.
ok_razao=$(LC_ALL=C awk -v r="$razao" 'BEGIN{print (r>10)?0:1}')
check "dependente espalha ${esp_dep}x e sequencial ${esp_seq}x (razao ${razao}x): uma coluna ve a memoria, a outra ve o laco" "$ok_razao"

[ "$falhas" -eq 0 ] || exit 1
echo "  efeito-cache: coluna sequencial plana, colunas de memoria com gradiente"
