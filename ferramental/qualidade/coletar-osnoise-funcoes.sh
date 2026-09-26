#!/usr/bin/env bash
# Distribuicao por funcao do ruido de workqueue, com sessao grafica viva.
#
# POR QUE ESTE SCRIPT EXISTE
#
# A tabela da §6.6.5 do topico de isolamento publica tres numeros --
# `amdgpu_device_delay_enable_gfx_off` com n=12, maior 808,5 us, soma 2 455 us
# -- e o rastro que os produziu NAO FOI ARQUIVADO. Sao numeros sem coleta, que e
# o que a regra editorial deste projeto proibe.
#
# POR QUE `trace-cmd` E NAO `rtla ... -t`
#
# O `-t` do `rtla` so grava quando a sessao e INTERROMPIDA por `-s`, `-S` ou
# `-a`. Isso serve para capturar UM evento grande -- e foi assim que a funcao
# foi nomeada pela primeira vez --, mas nao serve para contar ocorrencias numa
# janela: a sessao termina na primeira.
#
# O `trace-cmd` grava a janela inteira. A distribuicao por funcao sai dela.
#
# EXIGE SESSAO GRAFICA VIVA. E ela que agenda o trabalho do `gfx_off`; em modo
# texto a tabela sai vazia, e vazia por um motivo que a §6.6.6 ja mediu.
#
#   uso:  sudo bash ferramental/qualidade/coletar-osnoise-funcoes.sh [segundos]
set -uo pipefail
cd "$(dirname "$0")/../.."

JANELA=${1:-13}
CPU=${CPU:-2}

[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo." >&2; exit 1; }
command -v trace-cmd >/dev/null || { echo "FALHA: trace-cmd ausente." >&2; exit 1; }

graficos=$(pgrep -c -x 'Xorg|Xwayland|gnome-shell|kwin_wayland|sway' 2>/dev/null || true)
if [ "${graficos:-0}" -eq 0 ]; then
    echo "FALHA: nenhum processo grafico vivo." >&2
    echo "       E a sessao que agenda o trabalho do gfx_off. Em modo texto a" >&2
    echo "       tabela sai vazia -- e a §6.6.6 ja mediu esse vazio." >&2
    exit 1
fi

DONO=${SUDO_USER:-$(stat -c %U . 2>/dev/null || echo root)}
SAIDA="trilha/03-performance/03-isolamento-cpu/historico/$(date +%Y-%m-%d-%H%M)-osnoise-funcoes"
mkdir -p "$SAIDA"

{
    echo "janela          : ${JANELA}s"
    echo "cpu             : $CPU"
    echo "processos grafic: $graficos"
    echo "kernel          : $(uname -r)"
    echo "trace-cmd       : $(trace-cmd --version 2>&1 | head -1)"
} > "$SAIDA/ambiente.txt"

echo "==> rastreando ${JANELA}s na CPU $CPU  ($(date -Is))"
# `workqueue_execute_start` e `_end` dao inicio e fim de cada item; a duracao
# sai da diferenca. Sem o `_end` a soma seria estimada, e estimativa nao entra
# numa tabela que publica "Soma".
( cd "$SAIDA" && trace-cmd record -C mono -M "$((1 << CPU))" \
    -e workqueue:workqueue_execute_start \
    -e workqueue:workqueue_execute_end \
    sleep "$JANELA" ) > "$SAIDA/trace-cmd.log" 2>&1

( cd "$SAIDA" && trace-cmd report > relatorio.txt 2>&1 )

echo "==> distribuicao por funcao"
./ferramental/qualidade/apurar-osnoise-funcoes.py "$SAIDA/relatorio.txt" "$JANELA" \
    | tee "$SAIDA/distribuicao.txt"
chown -R "$DONO" "$SAIDA" 2>/dev/null || true
echo
echo "==> saida em $SAIDA"
