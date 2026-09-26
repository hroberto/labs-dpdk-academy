#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# `completa()` da campanha decide pela MATRIZ, e nao pela quantidade.
#
# POR QUE ESTE TESTE EXISTE
#
# A funcao responde uma pergunta que decide se uma coleta entra no historico
# como pronta. A versao anterior contava `*.r<N>.txt` nos tres modulos e
# aceitava quando a nova tinha ao menos tantos quanto a referencia. Contagem
# acerta o numero e erra a pergunta: uma referencia com
#
#     A.r1 A.r2 B.r1 B.r2
#
# e uma coleta nova com
#
#     A.r1 A.r2 C.r1 C.r2
#
# tem a mesma cardinalidade e nao tem a mesma matriz experimental. A coleta
# passava por completa faltando B inteiro, e o passo 6 comparava contra celulas
# que nao existem do outro lado.
#
# O caso 2 abaixo e exatamente esse, e foi conferido contra a versao antiga da
# funcao: ela declara COMPLETA ali. Um teste que a versao anterior tambem
# passaria nao provaria nada.
#
# AS FUNCOES SAO EXTRAIDAS DO ARQUIVO REAL, e nao copiadas para ca. Copiar
# deixaria o teste verde enquanto a campanha divergisse -- que e a mesma classe
# de defeito que ele existe para pegar.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
fonte="$raiz/ferramental/qualidade/campanha.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }

eval "$(sed -n '/^repeticoes_de() {/,/^}/p;/^faltando_em() {/,/^}/p;/^completa() {/,/^}/p' "$fonte")"
if ! declare -F completa >/dev/null; then
    echo "FALHA: nao consegui extrair completa() de campanha.sh"
    exit 1
fi

REF=ref
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

MODULOS="01-fundamentos 02-runtime-dpdk 03-mempool-ring-mbuf"
falhas=0

criar() { # <configuracao> <modulo> <nomes...>
    local d="docs/$2/medicoes/historico/$1"
    mkdir -p "$d"
    shift 2
    local n
    for n in "$@"; do : > "$d/$n"; done
}

caso() { # <descricao> <esperado: 0 completa, 1 incompleta>
    local descricao=$1 esperado=$2 rc=0
    completa nova || rc=$?
    if [ "$rc" -ne "$esperado" ]; then
        echo "  FALHOU: $descricao (esperado $esperado, obtido $rc)"
        falhas=$((falhas + 1))
    fi
    rm -rf docs
}

for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt B.r1.txt B.r2.txt
    criar nova "$m" A.r1.txt A.r2.txt B.r1.txt B.r2.txt
done
caso "matriz identica e completa" 0

# O CASO QUE A VERSAO ANTERIOR ERRAVA.
for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt B.r1.txt B.r2.txt
    criar nova "$m" A.r1.txt A.r2.txt C.r1.txt C.r2.txt
done
caso "mesma quantidade com celula trocada NAO e completa" 1

# A referencia e o piso, nao o teto: medir a mais nao reprova.
for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt
    criar nova "$m" A.r1.txt A.r2.txt Z.r9.txt
done
caso "sobra na coleta nova nao reprova" 0

for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt
    criar nova "$m" A.r1.txt
done
caso "repeticao faltando reprova" 1

# UM MODULO INTEIRO AUSENTE. A campanha cobre tres, e conferir so o primeiro
# deixaria passar uma coleta que parou depois dele.
for m in $MODULOS; do criar ref "$m" A.r1.txt; done
criar nova 01-fundamentos A.r1.txt
caso "modulo inteiro ausente na coleta nova reprova" 1

# REFERENCIA SEM SAIDA DE REPETICAO nao serve de gabarito: aceitar aqui faria
# qualquer diretorio vazio passar por completo.
for m in $MODULOS; do
    criar ref  "$m" diario.txt ambiente.txt
    criar nova "$m" diario.txt
done
caso "referencia sem saidas de repeticao reprova" 1

# O LIXO DA REFERENCIA NAO E EXIGIDO DA NOVA. Foi por causa dele que a versao
# que contava `ls | wc -l` abortou uma campanha que devia ter rodado.
for m in $MODULOS; do
    criar ref  "$m" A.r1.txt diario.txt.tmp
    criar nova "$m" A.r1.txt
done
caso "lixo na referencia nao e exigido da coleta nova" 0

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 7 casos; completude decidida por matriz, nao por contagem"
