#!/usr/bin/env bash
# A GPU ou a sessão gráfica? — intervenção sobre o GFXOFF, sem reiniciar.
#
# O QUE ESTE EXPERIMENTO SEPARA
#
# O rastreamento da §6.6 do tópico de isolamento nomeia
# `amdgpu_device_delay_enable_gfx_off` como a função presente nas paradas da
# casa das centenas de microssegundos, e a associação está medida: doze
# execuções em treze segundos com sessão gráfica viva, nenhuma sem ela. Uma
# associação, porém, não distingue duas leituras:
#
#   (a) o custo vem da reativação do *power gating* do bloco GFX;
#   (b) o custo vem da sessão gráfica por outro caminho, e o `gfx_off` é
#       apenas mais um sintoma dela.
#
# Só a intervenção separa as duas: desligar o GFXOFF com a sessão gráfica VIVA.
# Se (a), a função some e o máximo cai; se (b), nada muda.
#
# PRÉ-REGISTRO
#
#   HIPÓTESE.   O modo alto vem da reativação do *power gating* do bloco GFX.
#
#   PREVISÃO.   Na janela com GFXOFF desligado, `amdgpu_device_delay_enable_gfx_off`
#               não aparece no rastro, e o máximo de thread do `osnoise` cai da
#               casa das centenas para a das dezenas de microssegundos.
#
#   REFUTADA SE. A função continuar aparecendo, ou o máximo permanecer em
#               centenas de microssegundos. Isso colocaria a atribuição da §6.6
#               em sintoma, não em causa.
#
#   NULO NÃO É REFUTAÇÃO SE a janela do meio não diferir da primeira em nada —
#               nem no contador, nem no rastro. Isso indicaria que a escrita não
#               teve efeito, e o desfecho a reportar é "sem efeito observável",
#               não "hipótese refutada". Veja `amdgpu_gfx_off_ctrl`, abaixo.
#
# POR QUE QUATRO BYTES, E NÃO `echo`
#
# A primeira tentativa usou `printf '0' > $KNOB` e recebeu `EINVAL`. O erro foi
# lido como "o arquivo é somente status" — e era leitura errada. O handler
# existe e está carregado; a recusa veio de dentro dele. Da desmontagem do
# módulo em uso (`amdgpu.ko`, 7.0.0-31-generic):
#
#   amdgpu_debugfs_gfxoff_fops: +24 = ..._read, +32 = ..._write
#
#   amdgpu_debugfs_gfxoff_write:
#       test $0x3,%dl          <- tamanho da escrita
#       jne  <+0x118>             -> movq $-22 ; ou seja, -EINVAL
#       mov  (%rcx),%rax       <- deslocamento
#       and  $0x3,%eax
#       jne  <+0x118>
#       ...
#       call __get_user_4      <- lê o buffer em palavras de 4 bytes
#       setne %sil
#       call amdgpu_gfx_off_ctrl
#
# A interface é um vetor de `u32` binários, não texto, e rejeita qualquer
# escrita cujo tamanho ou deslocamento não seja múltiplo de quatro ANTES de
# tocar na GPU. `printf '0'` escreve um byte; 1 & 3 = 1, logo `EINVAL`. O
# experimento não falhou por política do kernel: falhou na codificação da
# entrada.
#
# SEMÂNTICA:  palavra == 0  ->  amdgpu_gfx_off_ctrl(adev, false)  -> DESLIGA
#             palavra != 0  ->  amdgpu_gfx_off_ctrl(adev, true)   -> religa
#
# O CONTADOR PRECISA FECHAR
#
# `amdgpu_gfx_off_ctrl` não é um interruptor: é uma contagem de pedidos
# (`gfx_off_req_count`). Cada desligamento incrementa; cada religamento
# decrementa, e só quando chega a zero o driver reenfileira o trabalho atrasado.
# Uma palavra 0 exige exatamente uma palavra != 0 depois. Duas escritas de 0 e
# uma de 1 deixam o GFXOFF desligado até o próximo boot; o inverso dispara o
# aviso de estouro do contador no kernel. Por isso este script escreve UMA vez
# em cada sentido, e religa também em INT/TERM/erro.
#
# EXIGE MÁQUINA DEDICADA e SESSÃO GRÁFICA VIVA. Sem a sessão, a pergunta já foi
# respondida pela coleta de modo texto, e o experimento não distingue nada.
#
#   uso:  sudo bash ferramental/qualidade/experimento-gfxoff.sh [saida]
set -uo pipefail
cd "$(dirname "$0")/../.."

CPU=${CPU:-2}
JANELA=${JANELA:-60}

[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo (debugfs exige root)." >&2; exit 1; }
command -v rtla    >/dev/null || { echo "FALHA: rtla ausente." >&2; exit 1; }
command -v python3 >/dev/null || { echo "FALHA: python3 ausente." >&2; exit 1; }

KNOB=$(ls /sys/kernel/debug/dri/*/amdgpu_gfxoff 2>/dev/null | head -1)
[ -n "$KNOB" ] || { echo "FALHA: amdgpu_gfxoff nao encontrado." >&2; exit 1; }

# A SESSÃO GRÁFICA É A CONDIÇÃO DO EXPERIMENTO, não um detalhe do ambiente.
graficos=$(pgrep -c -x 'Xorg|Xwayland|gnome-shell|kwin_wayland|sway' 2>/dev/null || true)
graficos=${graficos:-0}
if [ "$graficos" -eq 0 ]; then
    echo "FALHA: nenhum processo grafico vivo." >&2
    echo "       E a sessao ativa que distingue 'e a GPU' de 'e a sessao'." >&2
    exit 1
fi

SAIDA=${1:-trilha/03-performance/03-isolamento-cpu/historico/$(date +%Y-%m-%d-%H%M)-gfxoff-intervencao}
DONO=${SUDO_USER:-$(stat -c %U . 2>/dev/null || echo root)}
mkdir -p "$SAIDA"

# `os.write` de uma palavra, no deslocamento zero. Nem `echo` nem `dd`: o
# primeiro escreve texto e o segundo trunca por padrão, e ambos já produziram o
# `EINVAL` que este script existe para não repetir.
escrever() { # <valor u32>
    python3 - "$KNOB" "$1" <<'PY' 2>&1
import os, struct, sys
fd = os.open(sys.argv[1], os.O_WRONLY)
try:
    n = os.write(fd, struct.pack("<I", int(sys.argv[2])))
    print("ok %d bytes" % n)
finally:
    os.close(fd)
PY
}

DESLIGADO=0
religar() {
    [ "$DESLIGADO" -eq 1 ] || return 0
    DESLIGADO=0
    r=$(escrever 1)
    case "$r" in
        ok*) echo "==> GFXOFF religado ($r)" ;;
        *)   echo "==> AVISO: nao religuei o GFXOFF -> $r"
             echo "           O contador ficou desbalanceado. Reinicie." ;;
    esac
}
trap religar EXIT INT TERM

medir() { # <rotulo>
    local nome=$1
    ( cd "$SAIDA" && rtla osnoise top -c "$CPU" -d "${JANELA}s" -T 1 -q -t \
        > "osnoise-$nome.txt" 2>&1 || true
      [ -f osnoise_trace.txt ] && mv osnoise_trace.txt "trace-$nome.txt" )
}

relatar() { # <rotulo>
    local nome=$1 top="$SAIDA/osnoise-$1.txt" tr="$SAIDA/trace-$1.txt"
    local linha ocorr
    linha=$(grep -E "^ *$CPU " "$top" 2>/dev/null | tail -1)
    ocorr=$(grep -ci 'gfx_off\|gfxoff' "$tr" 2>/dev/null || echo 0)
    printf "   %-10s  %-58s  gfx_off no rastro: %s\n" "$nome" "${linha:-sem linha}" "$ocorr"
}

{
    echo "knob              : $KNOB"
    echo "cpu medida        : $CPU"
    echo "janela por celula : ${JANELA}s"
    echo "processos grafico : $graficos"
    echo "kernel            : $(uname -r)"
    echo "cmdline           : $(cat /proc/cmdline)"
    echo "pg_mask           : $(cat /sys/module/amdgpu/parameters/pg_mask 2>/dev/null)"
    echo "governor          : $(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor 2>/dev/null)"
} > "$SAIDA/ambiente.txt"

echo "==> intervencao GFXOFF  $(date -Is)"
echo "    saida: $SAIDA"
echo

# DESENHO A-B-A. Duas janelas com GFXOFF ligado, uma sem, na ordem ligado /
# desligado / ligado. A terceira célula custa um minuto e responde à objeção
# mais barata que existe contra um antes-e-depois: a de que a máquina apenas
# esquentou, ou esfriou, ao longo da coleta. Se A1 e A3 concordarem e B diferir
# das duas, a deriva está descartada por construção.
echo "==> A1: GFXOFF ligado (linha de base)  — ${JANELA}s"
medir a1-ligado

echo "==> desligando o GFXOFF (palavra 0)"
r=$(escrever 0)
case "$r" in
    ok*) DESLIGADO=1; echo "    $r — se a tela congelar daqui, reinicie." ;;
    *)   echo "FALHA: escrita recusada -> $r" >&2
         echo "       Veja o cabecalho deste arquivo: a escrita tem de ser de" >&2
         echo "       4 bytes binarios em deslocamento multiplo de 4." >&2
         exit 1 ;;
esac

echo "==> B: GFXOFF desligado  — ${JANELA}s"
medir b-desligado

echo "==> religando"
religar

echo "==> A3: GFXOFF ligado de novo (controle de deriva)  — ${JANELA}s"
medir a3-ligado

echo
echo "==> resultado"
echo "   celula      linha do osnoise para a CPU $CPU"
echo "   ----------  --------------------------------------------------------"
for c in a1-ligado b-desligado a3-ligado; do relatar "$c"; done
echo
echo "   Leia assim: a previsao exige que 'b-desligado' tenha ZERO ocorrencias"
echo "   de gfx_off e maximo na casa das dezenas, com 'a1' e 'a3' concordando"
echo "   entre si. Qualquer outro padrao esta no pre-registro do cabecalho."

chown -R "$DONO" "$SAIDA" 2>/dev/null || true
echo
echo "==> CONCLUIDO  $(date -Is)"
