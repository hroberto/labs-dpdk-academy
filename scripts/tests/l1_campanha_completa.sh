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

eval "$(sed -n '/^repeticoes_de() {/,/^}/p;/^faltando_em() {/,/^}/p;/^estado_da_celula() {/,/^}/p;/^nao_passaram_em() {/,/^}/p;/^manifesto_reprova() {/,/^}/p;/^completa() {/,/^}/p' "$fonte")"
for f in repeticoes_de faltando_em estado_da_celula nao_passaram_em manifesto_reprova completa; do
    declare -F "$f" >/dev/null || { echo "FALHA: nao consegui extrair $f() de campanha.sh"; exit 1; }
done

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

manifesto() { # <configuracao> <modulo> <linhas "celula STATUS rc">
    local d="docs/$2/medicoes/historico/$1"
    mkdir -p "$d"
    {
        echo "# manifesto de teste"
        printf '%-40s %-7s %s\n' "CELL" "STATUS" "RC"
        shift 2
        local l
        for l in "$@"; do printf '%-40s %-7s %s\n' $l; done
    } > "$d/manifesto.txt"
}

# ---- O ARQUIVO EXISTE E A MEDICAO REPROVOU ------------------------------
# `programa > saida.txt 2>&1` cria a saida mesmo quando o programa sai com
# erro. Sem consultar o manifesto, a celula esta presente com o nome certo e
# passa por medida -- o defeito mais traicoeiro desta familia, porque a coleta
# parece intacta em disco.
for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt
    criar nova "$m" A.r1.txt A.r2.txt
    manifesto nova "$m" "A.r1.txt PASS 0" "A.r2.txt FAIL 1"
done
caso "celula presente com FAIL no manifesto NAO e completa" 1

for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt
    criar nova "$m" A.r1.txt A.r2.txt
    manifesto nova "$m" "A.r1.txt PASS 0" "A.r2.txt SKIP 77"
done
caso "celula presente com SKIP no manifesto NAO e completa" 1

for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt
    criar nova "$m" A.r1.txt A.r2.txt
    manifesto nova "$m" "A.r1.txt PASS 0" "A.r2.txt PASS 0"
done
caso "todas PASS no manifesto e completa" 0

# SEM MANIFESTO A RESPOSTA E VAZIA, E NAO "PASS". As coletas anteriores a
# 26/09/2026 nao o tem, e presumir aprovacao delas inventaria um dado que
# ninguem registrou. Vale a conferencia por nomes, que e o que havia.
for m in $MODULOS; do
    criar ref  "$m" A.r1.txt A.r2.txt
    criar nova "$m" A.r1.txt A.r2.txt
done
caso "sem manifesto, decide pelos nomes (compatibilidade)" 0

# SILENCIO DENTRO DO MANIFESTO NAO E APROVACAO.
#
# Esta assercao ja esteve INVERTIDA aqui -- "celula ausente do manifesto nao
# reprova", esperando 0 --, e o teste passava. O defeito era que
# `estado_da_celula` devolvia vazio tanto para "nao ha manifesto" quanto para
# "ha manifesto e a celula nao esta nele", e o `case` tratava os dois como
# aprovados. O contrato real era "nao diz FAIL/SKIP -> valida", que e
# inferencia por ausencia: o que o manifesto veio substituir.
for m in $MODULOS; do
    criar ref  "$m" A.r1.txt B.r1.txt
    criar nova "$m" A.r1.txt B.r1.txt
    manifesto nova "$m" "A.r1.txt PASS 0"
done
caso "com manifesto, celula SEM REGISTRO nao e completa" 1

conferir_estado() { # <descricao> <obtido> <esperado>
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}
# OS DOIS VAZIOS TEM NOME PROPRIO, e e isso que impede o `case` de confundi-los.
for m in $MODULOS; do criar nova "$m" A.r1.txt; done
conferir_estado "sem manifesto -> SEM_MANIFESTO" \
    "$(estado_da_celula nova 01-fundamentos A.r1.txt)" "SEM_MANIFESTO"
manifesto nova 01-fundamentos "B.r1.txt PASS 0"
conferir_estado "com manifesto, celula fora dele -> SEM_REGISTRO" \
    "$(estado_da_celula nova 01-fundamentos A.r1.txt)" "SEM_REGISTRO"
conferir_estado "com manifesto, celula nele -> o estado registrado" \
    "$(estado_da_celula nova 01-fundamentos B.r1.txt)" "PASS"
rm -rf docs

# ETAPAS FORA DA MATRIZ TAMBEM CONTAM. `ambiente.txt` nao e um `*.r<N>.txt`,
# entao nao aparece em `repeticoes_de` e escapava da conferencia -- um FAIL
# nela era visto na hora da coleta e sumia ao reabrir a pasta depois. E dela
# que sai a condicao texto/grafico de toda comparacao posterior.
for m in $MODULOS; do
    criar ref  "$m" A.r1.txt
    criar nova "$m" A.r1.txt
    manifesto nova "$m" "A.r1.txt PASS 0" "ambiente.txt FAIL 1"
done
caso "FAIL em etapa fora da matriz reprova a coleta" 1

for m in $MODULOS; do
    criar ref  "$m" A.r1.txt
    criar nova "$m" A.r1.txt
    manifesto nova "$m" "A.r1.txt PASS 0" "teste-estado-maquina.txt SKIP 77"
done
caso "SKIP em etapa fora da matriz reprova a coleta" 1

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 17 assercoes; completude por matriz E por estado registrado"
