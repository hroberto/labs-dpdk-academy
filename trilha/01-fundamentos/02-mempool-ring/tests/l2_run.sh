#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L2 (integração) do tópico 02 — mempool e ring reais.
#
# O L1 cobre a lógica de pacote isoladamente. O L2 cobre o que só aparece com o
# runtime do DPDK: se todo objeto retirado do mempool volta para ele. Vazamento
# de objeto é a falha clássica deste tópico — o pool esvazia, rte_ring/rx passa a
# devolver 0 e o pipeline para.
#
# QUEM VERIFICA O INVARIANTE: o próprio programa, que compara
# rte_mempool_avail_count() com o tamanho do pool e sai com código != 0 se
# houver vazamento. Este script confere o CÓDIGO DE SAÍDA, que é o contrato, e
# confere a linha de texto de forma INDEPENDENTE DE FORMATO — ver pool_integro()
# abaixo.
#
# A distinção custou uma versão anterior deste teste, que casava a substring
# literal "4095 de 4095". Aquilo validava a mensagem, não a propriedade: mudar o
# tamanho do pool ou reescrever o printf quebrava o teste sem defeito algum, e
# um vazamento acompanhado de mudança de formato passaria despercebido. A forma
# atual extrai o par de números e exige que sejam iguais, sejam eles quais forem.
#
# Uso: l2_run.sh <caminho-do-binario>
set -u
BIN=${1:?uso: l2_run.sh <binario> <binario-com-vazamento>}
BIN_VAZADO=${2:-}
EAL_ARGS=${EAL_ARGS:--l 0 --in-memory --no-huge}
falhas=0

# Segundo lcore do modo de dois nucleos. NAO pode ser fixo: numa maquina de duas
# CPUs o lcore 2 nao existe, e a EAL rejeita a linha de comando inteira com
# "Error parsing command line arguments" -- o teste falharia em VERMELHO por
# falta de hardware, e nao por defeito do codigo. Preferimos o lcore 2 quando ha
# folga, para que produtor e consumidor caiam em nucleos fisicos distintos.
CPUS=$(nproc 2>/dev/null || echo 1)
LCORE_CONSUMIDOR=${LCORE_CONSUMIDOR:-$([ "$CPUS" -ge 3 ] && echo 2 || echo 1)}

check() { if [ "$2" -eq 0 ]; then echo "  ok    - $1"; else echo "  FALHA - $1"; falhas=$((falhas + 1)); fi; }

# Guarda a ultima saida capturada, para poder mostra-la se algo falhar.
#
# POR QUE ISTO EXISTE: a primeira execucao desta suite na CI falhou com "EAL
# inicializa e reporta sucesso: FALHA" e MAIS NADA. O teste dizia qual asserção
# quebrou e escondia a razao -- a mensagem da EAL, que e justamente o que se
# precisa para diagnosticar. Um teste que falha sem mostrar a evidencia obriga
# quem investiga a reproduzir o ambiente, o que num runner de CI e caro.
ultima_saida=""
mostrar_diagnostico() {
    [ -n "$ultima_saida" ] || return 0
    echo ""
    echo "  --- saida do programa na ultima execucao (diagnostico) ---"
    sed 's/^/    | /' <<<"$ultima_saida"
}

# Invariante do pool sem depender do numero exato nem do formato do printf:
# extrai o par "livres de total" e exige que sejam iguais. Um pool de outro
# tamanho continua valido; um vazamento, nao. Linha ausente conta como falha --
# se a mensagem sumir, o teste precisa gritar, nao passar em silencio.
pool_integro() { # <saida-do-programa>
    local par
    par=$(grep -oE 'Objetos livres no pool ao final: [0-9]+ de [0-9]+' <<<"$1" \
          | grep -oE '[0-9]+ de [0-9]+')
    [ -n "$par" ] || return 1
    [ "${par% de *}" = "${par#* de }" ]
}

saida=$("$BIN" $EAL_ARGS -- -n 10 2>&1); rc=$?

ultima_saida="$saida"
check "n=10: codigo de saida 0" "$([ $rc -eq 0 ]; echo $?)"
grep -q "^Pacotes processados: 10$" <<<"$saida"; check "n=10: processa exatamente 10 pacotes" $?
grep -q "^Total de bytes: 695$" <<<"$saida"; check "n=10: 695 bytes (mesmo contrato da alternativa C++23)" $?
pool_integro "$saida"; check "n=10: pool integro, sem vazamento de objetos" $?

# Volume alto com lote maior: o pool tem 4095 objetos para 100k pacotes, ou seja,
# só termina se a devolução ao pool estiver correta a cada ciclo.
saida=$("$BIN" $EAL_ARGS -- -n 100000 -b 64 2>&1); rc=$?
ultima_saida="$saida"
check "n=100000 b=64: codigo de saida 0" "$([ $rc -eq 0 ]; echo $?)"
grep -q "^Pacotes processados: 100000$" <<<"$saida"; check "n=100000: contagem exata sob reuso do pool" $?
pool_integro "$saida"; check "n=100000: pool integro apos ~25x de reuso" $?
grep -q "^Lote (burst): 64 " <<<"$saida"; check "n=100000: tamanho de lote aplicado" $?

# --- Modo de dois lcores: o consumidor ganha nucleo proprio e a fila passa a
# --- atravessar caches. O resultado precisa ser IDENTICO ao de um lcore: mudar
# --- o posicionamento e decisao de desempenho, nunca de semantica.
if [ "$CPUS" -lt 2 ]; then
    echo "  PULADO - modo de dois lcores (maquina com $CPUS CPU)"
else
    DOIS="-l 0,$LCORE_CONSUMIDOR --in-memory --no-huge"
    # shellcheck disable=SC2086
    saida=$("$BIN" $DOIS -- -n 10 2>&1); rc=$?
    ultima_saida="$saida"
    check "2 lcores: codigo de saida 0" "$([ $rc -eq 0 ]; echo $?)"
    grep -q "^Modo: 2 lcores (produtor 0, consumidor $LCORE_CONSUMIDOR)$" <<<"$saida"
    check "2 lcores: consumidor no lcore $LCORE_CONSUMIDOR" $?
    grep -q "^Pacotes processados: 10$" <<<"$saida"; check "2 lcores: mesma contagem de 1 lcore" $?
    grep -q "^Total de bytes: 695$" <<<"$saida"; check "2 lcores: mesmo resultado de 1 lcore" $?
    pool_integro "$saida"; check "2 lcores: pool integro" $?

    # shellcheck disable=SC2086
    saida=$("$BIN" $DOIS -- -n 200000 -b 32 2>&1)
    ultima_saida="$saida"
    grep -q "^Pacotes processados: 200000$" <<<"$saida"; check "2 lcores: 200k pacotes sem perda entre nucleos" $?
    pool_integro "$saida"; check "2 lcores: sem vazamento sob concorrencia" $?
fi

"$BIN" $EAL_ARGS -- -b 0 >/dev/null 2>&1;   check "lote 0 e rejeitado"           "$([ $? -ne 0 ]; echo $?)"
"$BIN" $EAL_ARGS -- -b 999 >/dev/null 2>&1; check "lote acima do maximo e rejeitado" "$([ $? -ne 0 ]; echo $?)"

# --- TESTE NEGATIVO: o invariante do pool realmente dispara? ---------------
#
# Tudo acima verifica que o programa CORRETO se comporta bem. Isso não prova
# que a verificação do pool funciona: uma verificação que nunca falhou é
# indistinguível de uma que nunca dispara. `pipeline_ring_vazado` é o mesmo
# fonte com a devolução do retorno parcial removida; aqui o esperado é FALHAR.
#
# CUIDADO COM A PRÉ-CONDIÇÃO, e esta parte custou uma versão anterior deste
# teste: o vazamento vive no caminho de RETORNO PARCIAL, que só executa quando
# o ring enche. Se o consumidor acompanhar o produtor, o ring não enche, o
# caminho não roda e nada vaza — o teste falhava em 1 de cada 4 execuções,
# acusando defeito onde não havia. A pré-condição agora é VERIFICADA: o próprio
# programa publica "objetos que nao couberam na fila", e o teste só afirma o vazamento
# depois de confirmar que o caminho foi exercitado.
if [ -n "$BIN_VAZADO" ] && [ -x "$BIN_VAZADO" ]; then
    forcou=0
    for tentativa in "-n 500000 -b 256" "-n 2000000 -b 256" "-n 5000000 -b 256"; do
        # shellcheck disable=SC2086
        saida=$("$BIN_VAZADO" -l 0,"$LCORE_CONSUMIDOR" --in-memory --no-huge -- $tentativa 2>&1)
        rc=$?
        ultima_saida="$saida"
        cheia=$(grep -o 'nao couberam na fila: [0-9]\+' <<<"$saida" | grep -o '[0-9]\+')
        if [ -n "$cheia" ] && [ "$cheia" -gt 0 ]; then forcou=1; break; fi
    done

    if [ "$forcou" -eq 0 ]; then
        echo "  PULADO - o ring nunca encheu; o caminho com o vazamento nao foi exercitado"
    else
        check "variante com vazamento sai com codigo != 0" "$([ $rc -ne 0 ]; echo $?)"
        grep -q "INVARIANTE VIOLADO" <<<"$saida"
        check "o invariante identifica o vazamento ($cheia objeto(s) sem lugar na fila)" $?
        vaz=$(grep -o '[0-9]\+ objeto(s) vazaram' <<<"$saida" | grep -o '^[0-9]\+')
        [ -n "$vaz" ] && [ "$vaz" -gt 0 ]
        check "vazamento quantificado: ${vaz:-0} objeto(s)" $?
    fi
else
    echo "  PULADO - teste negativo (binario com vazamento nao informado)"
fi

if [ $falhas -eq 0 ]; then
    echo "L2: todos os testes passaram"
else
    mostrar_diagnostico
    echo ""
    echo "L2: $falhas falha(s)"
    exit 1
fi
