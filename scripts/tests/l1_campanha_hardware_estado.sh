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

eval "$(sed -n '/^rodar() {/,/^}/p;/^veredito_hw() {/,/^}/p;/^contar_estado() {/,/^}/p;/^registrar() {/,/^}/p' "$fonte")"
for f in rodar veredito_hw contar_estado registrar; do
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

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 13 assercoes; estado por celula sobe do manifesto ate o codigo de saida"
