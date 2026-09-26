#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# O estado de cada medicao sobe da subcampanha, em vez de morrer no redirecionamento.
#
# POR QUE ESTE TESTE EXISTE
#
# `campanha-hardware.sh` executava ~30 medicoes como chamadas soltas. O script
# roda sob `set -u` e NAO sob `set -e`, entao um programa que saisse com erro
# nao interrompia nada e a ultima linha imprimia CONCLUIDA com codigo 0.
#
# O custo disso ficou concreto quando `custo-contencao` passou a RECUSAR a
# amostra cuja condicao nao ocorreu: o programa detectava o experimento
# invalido, devolvia 1, a subcampanha ignorava, `campanha.sh` lia "ok" e a
# coleta entrava no historico. Instrumento novo nao vale nada se o orquestrador
# acima dele apaga o sinal.
#
# E HA UM SEGUNDO FIO, menos obvio: `programa > saida.txt 2>&1` cria o arquivo
# MESMO quando o programa falha. A conferencia de completude por nomes ve a
# celula presente e nao sabe que ela contem uma execucao reprovada. Presenca do
# artefato nao e sucesso da medicao -- e o manifesto e o que separa as duas.
# O caso 4 abaixo e exatamente esse.
#
# As funcoes sao EXTRAIDAS do arquivo real; copia-las deixaria este teste verde
# enquanto a campanha divergisse.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
fonte="$raiz/ferramental/qualidade/campanha-hardware.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }

eval "$(sed -n '/^rodar() {/,/^}/p;/^veredito_hw() {/,/^}/p;/^contar_estado() {/,/^}/p;/^registrar() {/,/^}/p;/^coletar_estado_maquina() {/,/^}/p;/^corre_feed() {/,/^}/p' "$fonte")"
for f in rodar veredito_hw contar_estado registrar coletar_estado_maquina corre_feed; do
    declare -F "$f" >/dev/null || { echo "FALHA: nao extrai $f() de campanha-hardware.sh"; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
RAIZ="$tmp" D="$tmp" CONF="teste" MANIFESTO="$tmp/manifesto.txt"
falhas=0

# O CABECALHO E PARTE DO CONTRATO, e o teste o reproduz porque `contar_estado`
# roda awk sobre o arquivo inteiro: uma linha de cabecalho contada como celula
# estragaria todo veredito.
zerar_manifesto() {
    {
        echo "# manifesto da coleta $CONF -- estado com que cada celula terminou"
        echo "# STATUS: PASS (mediu), SKIP (pre-requisito ausente), FAIL (correu e reprovou)"
        printf '%-40s %-7s %s\n' "CELL" "STATUS" "RC"
    } > "$MANIFESTO"
}

conferir() { # <descricao> <obtido> <esperado>
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}

# Programas de mentira, um por desfecho possivel.
cat > mediu   <<'P'
#!/bin/sh
echo "numero: 1.23"; exit 0
P
cat > recusou <<'P'
#!/bin/sh
echo "AMOSTRA INVALIDA"; exit 1
P
cat > pulou   <<'P'
#!/bin/sh
echo "PULADO: sem topologia"; exit 77
P
chmod +x mediu recusou pulou

# ---- 1. os tres desfechos viram os tres estados -------------------------
zerar_manifesto
rodar "$tmp/a.r1.txt" ./mediu
rodar "$tmp/b.r1.txt" ./recusou
rodar "$tmp/c.r1.txt" ./pulou
conferir "conta uma falha e um pulo" "$(contar_estado FAIL)/$(contar_estado SKIP)" "1/1"
conferir "conta um sucesso"          "$(contar_estado PASS)" "1"
conferir "o rc fica na terceira coluna"  "$(awk '$1=="b.r1.txt"{print $2, $3}' "$MANIFESTO")" "FAIL 1"
conferir "o rc do pulo e 77"             "$(awk '$1=="c.r1.txt"{print $2, $3}' "$MANIFESTO")" "SKIP 77"
# O CABECALHO NAO E CELULA. `CELL STATUS RC` tem "STATUS" na segunda coluna e
# nao casa nenhum dos tres estados; contar mal aqui inflaria todo veredito.
conferir "o cabecalho nao entra na contagem" \
    "$(( $(contar_estado PASS) + $(contar_estado SKIP) + $(contar_estado FAIL) ))" "3"

# ---- 2. a rodada NAO para na primeira falha -----------------------------
# Abortar aqui perderia as celulas seguintes de uma campanha de horas. O erro
# e registrado e a coleta segue; quem decide e o veredito, no fim.
conferir "a celula seguinte a uma falha foi executada" "$(cat "$tmp/c.r1.txt")" "PULADO: sem topologia"

# ---- 3. O ARQUIVO EXISTE MESMO NA FALHA ---------------------------------
# E a razao de o manifesto precisar existir: conferir completude por nomes
# encontraria `b.r1.txt` e a daria por medida.
conferir "a saida da celula reprovada existe em disco" "$([ -s "$tmp/b.r1.txt" ] && echo sim)" "sim"

# ---- 4. o veredito, nos tres estados ------------------------------------
zerar_manifesto; rodar "$tmp/ok.txt" ./mediu
rc=0; veredito_hw >/dev/null 2>&1 || rc=$?
conferir "tudo mediu -> 0" "$rc" "0"

zerar_manifesto; rodar "$tmp/ok.txt" ./mediu; rodar "$tmp/s.txt" ./pulou
rc=0; veredito_hw >/dev/null 2>&1 || rc=$?
conferir "alguma pulou -> 2 (incompleta, nao falha)" "$rc" "2"

zerar_manifesto; rodar "$tmp/f.txt" ./recusou
rc=0; veredito_hw >/dev/null 2>&1 || rc=$?
conferir "alguma falhou -> 1" "$rc" "1"

# FALHA GANHA DE PULO. Uma campanha com as duas coisas nao pode sair como
# apenas incompleta: ha celula que correu e reprovou.
zerar_manifesto
# A CELULA QUE PASSOU ENTRA AQUI DE PROPOSITO. Sem ela a assercao "o veredito
# nao lista as que passaram" seria vazia -- `ok.txt` nao estaria no manifesto
# de jeito nenhum, e um veredito que despejasse o arquivo inteiro passaria.
# Medido: trocando o `grep -v PASS$` por `cat`, o mutante sobrevivia.
rodar "$tmp/ok.txt" ./mediu; rodar "$tmp/f.txt" ./recusou; rodar "$tmp/s.txt" ./pulou
rc=0; veredito_hw >/dev/null 2>&1 || rc=$?
conferir "falha e pulo juntos -> 1" "$rc" "1"

# ---- 5. o veredito NOMEIA as celulas que nao mediram, e so elas ---------
saida=$(veredito_hw 2>&1)
conferir "o veredito lista a celula reprovada" \
    "$(printf '%s' "$saida" | grep -c 'f.txt')" "1"
conferir "o veredito NAO lista as celulas que passaram" \
    "$(printf '%s' "$saida" | grep -c 'ok.txt')" "0"

# ---- 6. o estado de `le` chega ao chamador ------------------------------
#
# ESTE CASO EXISTE POR CAUSA DE UM FAIL-OPEN QUE A PRIMEIRA CORRECAO INTRODUZIU.
# A versao anterior de `le()` fazia `LE_FALHOU=1` la dentro, e era chamada como
# `a=$(le)`. Substituicao de comando roda em SUBSHELL: a atribuicao morria com
# ele, o pai seguia vendo 0, e o manifesto recebia PASS para uma etapa que nao
# correu. Trocar um fail-open por outro nao e correcao.
#
# Medido isoladamente:
#     FLAG=0; f() { FLAG=1; }; a=$(f); echo $FLAG   ->  0
#
# `le` e resolvida em tempo de chamada, entao basta defini-la aqui.
le() { printf 'A B'; }
rc=0; coletar_estado_maquina 2 0 >/dev/null || rc=$?
conferir "todas as leituras vieram -> 0" "$rc" "0"

le() { return 1; }
rc=0; coletar_estado_maquina 2 0 >/dev/null || rc=$?
conferir "leitura que falha chega ao chamador -> 1" "$rc" "1"

# UMA FALHA NO MEIO TAMBEM CONTA. Se so a ultima leitura decidisse, um erro na
# primeira das oito sumiria -- e o arquivo sairia com uma coluna em branco e
# nenhum sinal.
#
# O CONTADOR VAI EM ARQUIVO, e nao em variavel: `le` e chamada dentro de
# `$( )`, entao um `n=$((n+1))` la dentro morre com o subshell e a stub
# falharia SEMPRE, tornando esta assercao incapaz de distinguir "so a primeira
# falhou" de "todas falharam". Medido: com a stub por variavel, o mutante "so
# a ultima leitura decide" SOBREVIVIA.
echo 0 > "$tmp/n_le"
le() {
    local n; n=$(( $(cat "$tmp/n_le") + 1 )); echo "$n" > "$tmp/n_le"
    [ "$n" -ne 1 ] || return 1
    printf 'A B'
}
rc=0; coletar_estado_maquina 2 0 >/dev/null || rc=$?
conferir "falha so na PRIMEIRA leitura ainda reprova" "$rc" "1"

echo 0 > "$tmp/n_le"
le() {
    local n; n=$(( $(cat "$tmp/n_le") + 1 )); echo "$n" > "$tmp/n_le"
    [ "$n" -ne 4 ] || return 1
    printf 'A B'
}
rc=0; coletar_estado_maquina 2 0 >/dev/null || rc=$?
conferir "falha so na ULTIMA leitura ainda reprova" "$rc" "1"

# E A SAIDA CONTINUA SENDO PRODUZIDA na falha: o arquivo de diagnostico serve
# para ver O QUE veio, e abortar a coleta dele nao ajudaria ninguem.
le() { return 1; }
conferir "a tabela sai mesmo com leitura falhando" \
    "$(coletar_estado_maquina 1 0 | wc -l)" "2"

# ---- 7. a propria `le` -- e nao uma stub no lugar dela ------------------
#
# Os casos acima substituem `le` inteira, entao nunca exercitam o tratamento de
# erro DELA. Medido: com eles sozinhos, o mutante que apaga o `|| return 1` de
# dentro de `le` SOBREVIVIA. Aqui a stub e o PROGRAMA, um nivel abaixo.
unset -f le
eval "$(sed -n '/^le() {/,/^}/p' "$fonte")"
declare -F le >/dev/null || { echo "FALHA: nao extrai le() de campanha-hardware.sh"; exit 1; }
B="binarios"; mkdir -p "$tmp/$B"
# AS LINHAS SAO AS REAIS, copiadas de uma coleta arquivada. `le` conta CAMPOS
# ($8 numa, $7 na outra), entao uma stub com espacamento inventado testaria um
# extrator que nao e o do projeto -- e foi o que aconteceu na primeira versao
# deste caso, que media $8 do lugar errado e obtinha "1 1".
cat > "$tmp/$B/custo-comunicacao" <<'P'
#!/bin/sh
[ "${FALHAR:-0}" = 0 ] || exit 1
echo "  within domain 0 (cpu 0 <-> 2)          20.43  20.20-20.47     20.04-22.45         1.4%   2.9%"
echo "  BETWEEN domains (cpu 0 <-> 6)          81.43  81.42-81.45     81.41-81.50         0.0%   0.0%"
P
chmod +x "$tmp/$B/custo-comunicacao"
# `export` E NECESSARIO: a stub e um processo filho, e variavel de shell nao
# atravessa sem ele. Sem `export` o caso de falha nunca falhava.
export FALHAR=0
rc=0; le >/dev/null || rc=$?
conferir "le com o programa OK devolve 0" "$rc" "0"
conferir "le extrai os dois valores" "$(le)" "20.43 81.43"

export FALHAR=1
rc=0; le >/dev/null || rc=$?
conferir "le com o programa falhando devolve 1" "$rc" "1"
export FALHAR=0

# ---- 8. SESSAO DEGENERADA NAO VIRA EVIDENCIA ---------------------------
#
# O supervisor abre `primary.txt`/`secondary.txt` em CADA tentativa, antes de
# saber se a sessao sera valida. `corre_feed` perguntava "existe alguma
# tentativa?" em vez de "existe uma tentativa VALIDA?", e com todas falhando
# copiava a saida degenerada para o historico com nome de celula normal --
# promovida a evidencia e consumida pelos comparadores como tal.
#
# A copia e a FRONTEIRA DE PUBLICACAO, e estes dois casos sao o que a defende.
falso_python() { # <rc> [sessao-vencedora]
    cat > "$tmp/bin/python3" <<P
#!/usr/bin/env bash
# Reproduz o supervisor: cria session-1 e session-2 com os dois arquivos, como
# ele faz antes de qualquer conferencia de validade.
saida=""
for a in "\$@"; do [ "\$anterior" = --output ] && saida="\$a"; anterior="\$a"; done
mkdir -p "\$saida/session-1" "\$saida/session-2"
echo "log da tentativa 1 (degenerada)" > "\$saida/session-1/primary.txt"
echo "log da tentativa 1 (degenerada)" > "\$saida/session-1/secondary.txt"
echo "log da tentativa 2" > "\$saida/session-2/primary.txt"
echo "log da tentativa 2" > "\$saida/session-2/secondary.txt"
[ -n "${2:-}" ] && echo "${2:-}" > "\$saida/successful-session"
exit $1
P
    chmod +x "$tmp/bin/python3"
}

mkdir -p "$tmp/bin" "$tmp/d2"
PATH="$tmp/bin:$PATH"
D2="$tmp/d2"; B2="$tmp/bin"; DPDK_ACADEMY_HUGE_DIR="$tmp"

# 8a. TODAS AS TENTATIVAS FALHAM: nada e promovido, as duas celulas viram FAIL.
zerar_manifesto; rm -f "$D2"/feed-*
falso_python 1
corre_feed 3
conferir "supervisor rc=1: feed-primario NAO e promovido" \
    "$([ -e "$D2/feed-primario.r3.txt" ] && echo sim || echo nao)" "nao"
conferir "supervisor rc=1: feed-secundario NAO e promovido" \
    "$([ -e "$D2/feed-secundario.r3.txt" ] && echo sim || echo nao)" "nao"
conferir "supervisor rc=1: as duas celulas sao FAIL" \
    "$(awk '$1 ~ /^feed-/ && $2 == "FAIL" { n++ } END { print n+0 }' "$MANIFESTO")" "2"
rc=0; veredito_hw >/dev/null 2>&1 || rc=$?
conferir "supervisor rc=1: a subcampanha reprova" "$rc" "1"

# 8b. A SEGUNDA TENTATIVA VENCE: so ELA e promovida.
#
# Nao basta recusar fracasso -- e preciso escolher a tentativa CERTA. O
# supervisor nomeia a vencedora, e este caso prova que o shell obedece ao nome
# em vez de reconstrui-lo por ordenacao.
zerar_manifesto; rm -f "$D2"/feed-*
falso_python 0 session-2
corre_feed 4
conferir "supervisor rc=0: promove o conteudo da sessao VENCEDORA" \
    "$(cat "$D2/feed-primario.r4.txt" 2>/dev/null)" "log da tentativa 2"
conferir "supervisor rc=0: as duas celulas sao PASS" \
    "$(awk '$1 ~ /^feed-/ && $2 == "PASS" { n++ } END { print n+0 }' "$MANIFESTO")" "2"
conferir "supervisor rc=0: os nomes sao os da matriz" \
    "$(awk '$1 ~ /^feed-/ { print $1 }' "$MANIFESTO" | sort | tr '\n' ' ')" \
    "feed-primario.r4.txt feed-secundario.r4.txt "

# 8c. VENCEDORA E A PRIMEIRA: a ordenacao daria a outra.
zerar_manifesto; rm -f "$D2"/feed-*
falso_python 0 session-1
corre_feed 5
conferir "promove session-1 quando e ela a vencedora, nao a ultima" \
    "$(cat "$D2/feed-primario.r5.txt" 2>/dev/null)" "log da tentativa 1 (degenerada)"

# 8c-bis. AS DUAS FONTES DISCORDAM: o supervisor nomeia uma sessao vencedora E
#     sai com erro. Nao deveria acontecer -- ele escreve o nome e devolve 0 na
#     linha seguinte --, e por isso mesmo a conferencia do `rc` precisa ser
#     testada: sem este caso ela e um branch que nunca dispara, e um mutante
#     que a apaga sobrevive. Medido: sobrevivia.
#
#     Diante da discordancia, RECUSA. A alternativa seria escolher em qual das
#     duas acreditar, sem base para escolher.
zerar_manifesto; rm -f "$D2"/feed-*
falso_python 1 session-2
corre_feed 7
conferir "nome de sessao vencedora com rc!=0: NAO promove" \
    "$([ -e "$D2/feed-primario.r7.txt" ] && echo sim || echo nao)" "nao"
conferir "nome de sessao vencedora com rc!=0: registra FAIL" \
    "$(awk '$1 == "feed-primario.r7.txt" { print $2 }' "$MANIFESTO")" "FAIL"

# 8c-ter. COPIA PARCIAL. A primeira copia passa, a segunda nao -- e sem o
#     `rm -f` a celula promovida pela primeira fica no historico com nome
#     valido e FAIL no manifesto, que e a contradicao que o manifesto existe
#     para nao ter. Medido: sem este caso, o mutante que apaga o `rm -f`
#     sobrevivia, porque nos demais nada chegava a ser promovido.
zerar_manifesto; rm -f "$D2"/feed-*
cat > "$tmp/bin/python3" <<'P'
#!/usr/bin/env bash
saida=""
for a in "$@"; do [ "${anterior:-}" = --output ] && saida="$a"; anterior="$a"; done
mkdir -p "$saida/session-1"
echo "secundario" > "$saida/session-1/secondary.txt"
# `primary.txt` NAO e criado: a segunda copia falha.
echo session-1 > "$saida/successful-session"
exit 0
P
chmod +x "$tmp/bin/python3"
# o erro do `cp` vai ao stderr de proposito -- na campanha real ele entra no
# diario; aqui so polui a saida do teste.
corre_feed 8 2>/dev/null
conferir "copia parcial: nada fica promovido" \
    "$(ls "$D2"/feed-*.r8.txt 2>/dev/null | wc -l)" "0"
conferir "copia parcial: as duas celulas viram FAIL" \
    "$(awk '$1 ~ /r8.txt$/ && $2 == "FAIL" { n++ } END { print n+0 }' "$MANIFESTO")" "2"

# 8d. SEM HUGETLBFS o feed nem e tentado, e nao registra nada: o PULO e
#     decidido em `campanha.sh`, e contar aqui tambem inflaria o veredito.
zerar_manifesto; rm -f "$D2"/feed-*
DPDK_ACADEMY_HUGE_DIR="" corre_feed 6
conferir "sem hugetlbfs o feed nao registra celula" \
    "$(awk '$1 ~ /^feed-/ { n++ } END { print n+0 }' "$MANIFESTO")" "0"

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 34 assercoes; estado por celula sobe do manifesto ate o codigo de saida"
