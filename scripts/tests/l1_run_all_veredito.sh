#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# `run-all` so devolve sucesso se tudo que ele declarou executar teve sucesso.
#
# POR QUE ESTE TESTE EXISTE
#
# A cadeia que o projeto construiu -- instrumento recusa, subcampanha preserva,
# manifesto registra, campanha agrega -- parava no penultimo elo. O `run-all`,
# que esta acima de todos, tinha tres caminhos de falso sucesso, e os tres
# foram reproduzidos pela auditoria de 26/09:
#
#   --so-ruido            o `exit 0` antecipado descartava o `rc` da campanha
#   SIGTERM               o trap restaurava o governor e DEVOLVIA o controle
#   etapa 4               as saidas eram redirecionadas sem conferir retorno
#
# Os tres viram regressao aqui. O script de reproducao da auditoria extrai
# trechos do fonte por casamento de texto e quebra quando a forma muda; este
# exercita o COMPORTAMENTO, que e o que precisa continuar valendo.
#
# E HA UM CASO POSITIVO, de proposito: um teste que so sabe recusar aprovaria
# um `run-all` que nunca conclui.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
fonte="$raiz/ferramental/qualidade/run-all.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }
falhas=0

conferir() { # <descricao> <obtido> <esperado>
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}

# Recorta do fonte REAL, e nao de uma copia: copiar deixaria este teste verde
# enquanto o `run-all` divergisse.
recorte() { # <marcador-inicial> <marcador-final>
    awk -v ini="$1" -v fim="$2" '
        index($0, ini) { dentro = 1 }
        dentro { print }
        dentro && index($0, fim) && NR > 1 { exit }
    ' "$fonte"
}

# O FECHAMENTO NA COLUNA ZERO, e nao o primeiro `fi` que aparecer.
#
# O bloco do `--so-ruido` contem um `if` interno, e recortar ate o primeiro
# `fi` deixava o externo aberto: o `bash` devolvia 2 por erro de SINTAXE, e o
# teste lia isso como veredito. Um recorte errado nao falha ruidosamente --
# ele responde outra coisa.
recorte_bloco() { # <ancora> <marcador-inicial>
    # A ANCORA IMPORTA: `if [ "$SO_RUIDO" -eq 1 ]` aparece mais de uma vez no
    # arquivo, e recortar a primeira ocorrencia extrai outro trecho -- que
    # roda, nao falha, e responde outra coisa. O script de reproducao da
    # auditoria ja ancorava na etapa 4 pelo mesmo motivo.
    awk -v anc="$1" -v ini="$2" '
        index($0, anc) { achou_ancora = 1 }
        achou_ancora && index($0, ini) { dentro = 1 }
        dentro { print }
        dentro && /^fi$/ { exit }
    ' "$fonte"
}

# ---- 1. o rc da campanha vira o estado agregado -------------------------
agregacao=$(recorte 'rc_final=0' 'esac')
for par in "0 0" "2 2" "42 1" "1 1"; do
    set -- $par
    obtido=$(bash -c "rc=$1
$agregacao
echo \$rc_final" 2>/dev/null)
    conferir "campanha rc=$1 agrega como $2" "$obtido" "$2"
done

# ---- 2. `--so-ruido` NAO descarta o resultado ---------------------------
so_ruido=$(recorte_bloco 'ETAPA 4/4' 'if [ "$SO_RUIDO" -eq 1 ]; then')
rc=0
bash -c "SO_RUIDO=1; rc=42; rc_final=1
$so_ruido" >/dev/null 2>&1 || rc=$?
conferir "--so-ruido com campanha falhando devolve o erro" "$rc" "1"

rc=0
bash -c "SO_RUIDO=1; rc=0; rc_final=0
$so_ruido" >/dev/null 2>&1 || rc=$?
conferir "--so-ruido com campanha boa devolve 0" "$rc" "0"

saida=$(bash -c "SO_RUIDO=1; rc=42; rc_final=1
$so_ruido" 2>&1)
conferir "e nao imprime CONCLUIDO quando falhou" \
    "$(printf '%s' "$saida" | grep -c 'run-all CONCLUIDO')" "0"

# ---- 3. SIGTERM TERMINA o fluxo -----------------------------------------
# O trap antigo restaurava o governor e devolvia o controle: `kill -TERM $$`
# nao parava nada, e uma campanha de horas seguia depois de o operador achar
# que a tinha interrompido.
traps=$(grep -E "^\s+trap " "$fonte" | sed 's/^[[:space:]]*//')
saida=$(bash -c "fixar_gov() { :; }; GOV_ANTES=powersave
limpar_governor() { echo LIMPOU; }
$traps
kill -TERM \$\$
echo CONTINUOU_APOS_TERM" 2>&1)
rc_term=0
bash -c "fixar_gov() { :; }; GOV_ANTES=powersave
limpar_governor() { :; }
$traps
kill -TERM \$\$
echo CONTINUOU_APOS_TERM" >/dev/null 2>&1 || rc_term=$?
conferir "SIGTERM nao deixa o fluxo continuar" \
    "$(printf '%s' "$saida" | grep -c CONTINUOU_APOS_TERM)" "0"
conferir "SIGTERM sai com 143" "$rc_term" "143"
conferir "e a limpeza do governor ainda acontece" \
    "$(printf '%s' "$saida" | grep -c LIMPOU)" "1"

# ---- 4. a etapa 4 confere o retorno de cada invocacao -------------------
# `rodar_bloco` promove o arquivo so quando a execucao termina bem. Antes, o
# redirecionamento criava a saida em qualquer caso, e como a completude e
# conferida por NOME, a coleta parecia intacta em disco.
bloco=$(recorte 'rodar_bloco() {' '    }')
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/falha" <<'P'
#!/bin/sh
echo FALHA_SINTETICA >&2
exit 42
P
cat > "$tmp/ok" <<'P'
#!/bin/sh
echo MEDIU
P
chmod +x "$tmp/falha" "$tmp/ok"

res=$(bash -c "DONO=\$(id -un); rc_final=0
sudo() { shift 3; \"\$@\"; }
$bloco
rodar_bloco '$tmp/saida-ruim.txt' '$tmp/falha'
echo \"rc_final=\$rc_final\"" 2>/dev/null)
conferir "invocacao que falha marca o agregado" \
    "$(printf '%s' "$res" | grep -c 'rc_final=1')" "1"
conferir "e o arquivo NAO e promovido" \
    "$([ -e "$tmp/saida-ruim.txt" ] && echo sim || echo nao)" "nao"
conferir "a saida fica no parcial, para diagnostico" \
    "$([ -s "$tmp/saida-ruim.txt.parcial" ] && echo sim || echo nao)" "sim"

res=$(bash -c "DONO=\$(id -un); rc_final=0
sudo() { shift 3; \"\$@\"; }
$bloco
rodar_bloco '$tmp/saida-boa.txt' '$tmp/ok'
echo \"rc_final=\$rc_final\"" 2>/dev/null)
conferir "invocacao boa nao marca o agregado" \
    "$(printf '%s' "$res" | grep -c 'rc_final=0')" "1"
conferir "e o arquivo E promovido" \
    "$([ -s "$tmp/saida-boa.txt" ] && echo sim || echo nao)" "sim"
conferir "sem deixar parcial para tras" \
    "$([ -e "$tmp/saida-boa.txt.parcial" ] && echo sim || echo nao)" "nao"

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: 15 assercoes; run-all so conclui se todas as etapas concluirem"
