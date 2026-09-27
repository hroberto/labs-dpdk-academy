#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# O leitor de ciclos do `run-all` corre contra a SONDA DE VERDADE.
#
# POR QUE ESTE TESTE EXISTE
#
# A ETAPA 2 do `run-all` le os ciclos por operacao da saida da sonda com um
# `sed`. Em 26/09/2026 o commit `6a6dd828` escreveu esse leitor as 01:13,
# procurando `por HARDWARE (sysfs ...)`; o `ba7b8b1d`, as 13:31 do mesmo dia,
# renomeou a linha da sonda para `pela frequencia reportada (sysfs ...)`.
#
# Doze horas separam os dois, e as duas campanhas seguintes -- uma de modo
# texto e uma de modo grafico, uma hora de maquina dedicada cada -- sairam com
#
#     VEREDITO NAO APURADO: nao li os ciclos da sonda.
#
# enquanto a sonda media 1,122 e 1,123, com o modelo previndo 1,125. O dado
# estava certo, arquivado e ilegivel para quem devia julga-lo.
#
# NAO REPROVOU NADA, E E ESSE O PONTO. O desfecho "nao apurado" foi uma
# correcao deliberada -- antes dele, valor nao lido virava "MODELO REFUTADO",
# que e pior. Mas honestidade no relato nao substitui deteccao: um leitor de
# texto sobre a saida de um programa quebra em silencio, e o unico jeito de
# nao descobrir isso numa campanha de uma hora e roda-lo contra o programa
# toda vez que a suite roda.
#
# Com 200 amostras a sonda responde em meio segundo. O custo deste teste e
# menor que o de ler o comentario que o explica.
set -u
sonda=${1:-}
raiz=$(cd "$(dirname "$0")/../../../.." && pwd)
fonte="$raiz/ferramental/qualidade/run-all.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }
[ -n "$sonda" ] && [ -x "$sonda" ] || { echo "PULADO: sonda-relaxed ausente"; exit 77; }

# Recorta do fonte REAL: uma copia do `sed` aqui deixaria este teste verde
# enquanto o `run-all` continuasse com o leitor velho -- que e exatamente a
# divergencia que ele existe para pegar.
eval "$(awk '/^    ciclos\(\) \{/,/^    \}/' "$fonte")"
declare -F ciclos >/dev/null || { echo "FALHA: nao extrai ciclos() de run-all.sh"; exit 1; }

falhas=0
total=0
conferir() { # <descricao> <obtido> <esperado>
    total=$((total + 1))
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! "$sonda" 200 0 > "$tmp/sonda.txt" 2>&1; then
    echo "PULADO: a sonda nao correu nesta maquina"
    sed 's/^/    /' "$tmp/sonda.txt" | tail -5
    exit 77
fi

conferir "a sonda emite o bloco de ciclos" \
    "$(grep -c 'CICLOS por operacao' "$tmp/sonda.txt")" "1"

lido=$(ciclos "$tmp/sonda.txt")
conferir "o leitor do run-all extrai um valor" \
    "$([ -n "$lido" ] && echo sim || echo nao)" "sim"

# O CAMPO CERTO, e nao qualquer numero da vizinhanca. A sonda publica dois
# valores de ciclos -- um pelo relogio do sysfs, outro pela cadeia de emissao
# --, e o modelo de 1,125 e sobre o primeiro. Um `sed` que deslizasse para a
# linha de baixo leria um numero plausivel e responderia outra pergunta.
esperado=$(awk '/pela frequencia reportada/ { print $NF }' "$tmp/sonda.txt")
conferir "e e o valor do relogio do sysfs, nao o da emissao" "$lido" "$esperado"

conferir "o valor e um numero" \
    "$(printf '%s' "$lido" | grep -cE '^[0-9]+\.[0-9]+$')" "1"
# A FAIXA FISICA SAIU, e a razao e de escopo.
#
# Ela exigia `0,3 < ciclos < 20`. O runner do `releases-dpdk (26.07)` nao
# expoe `scaling_cur_freq`, a sonda reporta frequencia 0,00 GHz e o campo do
# sysfs sai `0.000` -- corretamente. O leitor leu certo, e o teste reprovou.
#
# Este L1 afere se o `run-all` CONTINUA ENTENDENDO a saida da sonda. Transformar
# a disponibilidade de cpufreq do runner em contrato do parser e testar outra
# coisa -- e foi assim que a CI ficou vermelha por uma propriedade da maquina.
#
# A assercao que o escopo pede ja existe e e mais forte: o valor lido tem de
# ser o DA LINHA do sysfs, e nao qualquer numero da vizinhanca.
if [ "$(awk -v v="$lido" 'BEGIN { print (v > 0) ? "sim" : "nao" }')" = "sim" ]; then
    conferir "quando o sysfs reporta frequencia, o valor e plausivel" \
        "$(awk -v v="$lido" 'BEGIN { print (v > 0.3 && v < 20) ? "sim" : "nao" }')" "sim"
else
    echo "  (sysfs sem frequencia nesta maquina: a faixa fisica nao se aplica)"
fi

# O CASO NEGATIVO: com o rotulo ANTIGO o leitor tem de devolver vazio. Sem
# esta assercao, um `sed` que casasse qualquer linha passaria em tudo acima --
# e seria justamente o defeito oposto, igualmente silencioso.
printf '    por HARDWARE (sysfs 5.53 GHz):  1.125\n' > "$tmp/velho.txt"
conferir "o rotulo antigo NAO e aceito como se fosse o novo" \
    "$([ -z "$(ciclos "$tmp/velho.txt")" ] && echo vazio || echo leu)" "vazio"

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: $total assercoes; o leitor de ciclos do run-all le a sonda de verdade"
