#!/usr/bin/env bash
# Campanha em MODO TEXTO: a sessao grafica e a fonte do modo alto?
#
# PRE-REGISTRO -- ESCRITO ANTES DA COLETA, E E POR ISSO QUE ESTE CABECALHO
# EXISTE
#
# O tracador `osnoise` nomeou a fonte da maior parada: a funcao
# `amdgpu_device_delay_enable_gfx_off`, numa workqueue por CPU, com 706 e
# 808 us em dois rastros independentes. O kernel registrou no journal que
# `dm_irq_work_func [amdgpu]` -- mesmo driver, outro trabalho -- chegou a
# passar de 10 000 us sete vezes.
#
# As duas funcoes existem porque ha uma GPU com sessao grafica. Em modo texto
# nao ha composicao, nao ha redesenho e o GFX nao entra e sai de power gating
# atras de trabalho que nao existe.
#
#   HIPOTESE. O modo alto da distribuicao (630-834 us) e produzido por trabalho
#   do driver amdgpu, e depende da sessao grafica estar ativa.
#
#   PREVISAO. Em modo texto, nenhuma das 20 celulas do stall_probe apresenta
#   maior parada acima de 200 us, e o histograma do osnoise nao registra
#   amostra acima de 200 us em dez minutos.
#
#   REFUTADA SE. O modo alto aparecer com frequencia comparavel a das coletas
#   com sessao grafica -- 9 em 60 celulas, ou 15% -- ou se o osnoise registrar
#   amostras de centenas de microssegundos.
#
# A SEGUNDA PERGUNTA, que corre de graca na mesma condicao
#
# Os dois instrumentos discordam por um fator de 5,6 com sessao grafica: o
# osnoise preve 84% de celulas com evento acima de 35 us e o stall_probe
# observa 15%. Rodando os dois na MESMA condicao de modo texto, a discordancia
# ou persiste -- e e propriedade dos instrumentos -- ou desaparece junto com a
# fonte, e era propriedade da fonte.
#
# POR QUE MODO TEXTO E NAO `systemctl isolate multi-user.target`
#
# Parar a sessao grafica sem reiniciar deixa o driver carregado e o estado
# acumulado. Reiniciar em multi-user zera as duas coisas, e o custo e o mesmo
# reboot que a maquina ja leva para qualquer mudanca de linha de boot.
#
# COMO USAR
#
#   1. sudo systemctl set-default multi-user.target
#   2. sudo reboot
#   3. entrar no console e rodar:  sudo ferramental/qualidade/campanha-modo-texto.sh
#   4. ao terminar:  sudo systemctl set-default graphical.target && sudo reboot
#
# O passo 4 esta impresso no fim da execucao, para nao depender de memoria.
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"

# `--continuar` retoma uma coleta parcial em vez de exigir tudo de novo. Ele
# existe porque a primeira execucao perdeu os passos 2 e 3 por falta de
# permissao, e repetir os dez minutos de osnoise que JA deram certo seria
# desperdicio -- e tentacao para encurtar o protocolo da proxima vez.
CONTINUAR=0
[ "${1:-}" = "--continuar" ] && { CONTINUAR=1; shift; }

SAIDA="$RAIZ/trilha/03-performance/03-isolamento-cpu/historico/$(date +%Y-%m-%d)-modo-texto"
if [ -e "$SAIDA" ] && [ "$CONTINUAR" -eq 0 ]; then
    echo "ABORTADO: $SAIDA ja existe -- nao sobrescrevo coleta."
    echo "          use --continuar para completar o que faltou."
    exit 1
fi

# --------------------------------------------------------------------------
# PORTAO 1: ROOT. O rtla exige, e falhar no meio da campanha desperdicaria os
# minutos ja gastos.
# --------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo (o rtla exige root)."; exit 1; }
DONO=${SUDO_USER:-$(logname 2>/dev/null || echo root)}
id "$DONO" >/dev/null 2>&1 || { echo "FALHA: nao identifiquei o usuario dono ($DONO)"; exit 1; }
# O `-H` NAO E OPCIONAL nas chamadas abaixo: sem ele o sudo mantem HOME=/root, e
# `preparar-dpdk.sh --conferir` procura os prefixos em $HOME/opt. A conferencia
# falharia por caminho, nao por conteudo, e a mensagem apontaria para o lugar
# errado -- no meio de uma campanha que ninguem esta olhando.

# --------------------------------------------------------------------------
# PORTAO 2: MODO TEXTO DE VERDADE.
#
# "Rodei em modo texto" precisa ser CONFERIDO, nao declarado -- e a mesma regra
# que este projeto aplica a hugepage, a coleta e ao prefixo do DPDK. Um console
# aberto sobre uma sessao grafica ainda viva mediria a condicao errada e o
# resultado pareceria valido.
# --------------------------------------------------------------------------
alvo=$(systemctl get-default 2>/dev/null)
# `pgrep -c` imprime "0" E sai com 1 quando nao acha nada; um `|| echo 0`
# somaria um segundo "0" e o teste inteiro abaixo quebraria.
graficos=$(pgrep -c -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" 2>/dev/null)
graficos=${graficos:-0}
echo "==> conferindo a condicao"
echo "    alvo padrao do systemd : $alvo"
echo "    processos graficos     : $graficos"
if [ "$graficos" -ne 0 ]; then
    echo "FALHA: ha $graficos processo(s) grafico(s) vivo(s)."
    pgrep -a -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" | sed 's/^/           /'
    echo "       A campanha mede a AUSENCIA deles. Reinicie em multi-user.target."
    exit 1
fi
case "$alvo" in
    multi-user.target) ;;
    *) echo "AVISO: alvo padrao e '$alvo', nao multi-user.target."
       echo "       Sem processo grafico vivo a condicao vale, mas o proximo"
       echo "       boot volta ao grafico. Seguindo." ;;
esac

mkdir -p "$SAIDA"
# O DIRETORIO PRECISA PERTENCER AO DONO, e esta linha custou uma coleta.
#
# O script roda como root e cria a saida como root; as campanhas rodam como o
# DONO, via `sudo -u`, e fazem `mkdir` dentro dela. Sem o chown, as duas
# falham com "Permission denied" DEPOIS dos dez minutos do osnoise -- que e o
# pior momento possivel para descobrir.
chown -R "$DONO" "$SAIDA"
exec > >(tee -a "$SAIDA/diario.txt") 2>&1
echo "==> campanha em modo texto  $(date -Is)"
echo "    saida: $SAIDA"

# --------------------------------------------------------------------------
# PROCEDENCIA. O que descreve a maquina vai para o arquivo ANTES de medir: se
# a campanha morrer no meio, o que ja se sabe fica registrado.
# --------------------------------------------------------------------------
{
    echo "alvo systemd     : $alvo"
    echo "processos grafico: $graficos"
    echo "governor cpu2    : $(cat /sys/devices/system/cpu/cpu2/cpufreq/scaling_governor 2>/dev/null)"
    echo "C3 disable cpu2  : $(cat /sys/devices/system/cpu/cpu2/cpuidle/state3/disable 2>/dev/null)"
    echo "cmdline          : $(cat /proc/cmdline)"
    echo "kernel           : $(uname -r)"
    echo "uptime           : $(uptime -p)"
    awk '/^MemAvailable:|^SwapTotal:|^SwapFree:/{a[$1]=$2}
         END{printf "memoria          : avail %.2f GiB, swap em uso %.2f GiB\n",
             a["MemAvailable:"]/1048576,(a["SwapTotal:"]-a["SwapFree:"])/1048576}' /proc/meminfo
    echo "carga            : $(cut -d' ' -f1-3 /proc/loadavg)"
} > "$SAIDA/ambiente.txt"
sed 's/^/    /' "$SAIDA/ambiente.txt"

# --------------------------------------------------------------------------
# 1. osnoise: histograma de dez minutos. Nao para no primeiro evento, entao
#    da a DISTRIBUICAO -- que e o que responde a previsao.
# --------------------------------------------------------------------------
echo
echo "==> 1/3 osnoise hist, 10 min na CPU 2  ($(date +%T))"
if [ -s "$SAIDA/osnoise-hist.txt" ] && grep -q "^count:" "$SAIDA/osnoise-hist.txt"; then
    echo "    JA COLETADO nesta saida; preservando."
    grep -E "^(over|count|min|avg|max):" "$SAIDA/osnoise-hist.txt" | sed 's/^/    /'
elif command -v rtla >/dev/null; then
    rtla osnoise hist -c 2 -d 10m -T 1 > "$SAIDA/osnoise-hist.txt" 2>&1 \
        && echo "    ok" || echo "    FALHA (saida em osnoise-hist.txt)"
    grep -E "^(over|count|min|avg|max):" "$SAIDA/osnoise-hist.txt" | sed 's/^/    /'
else
    echo "    PULADO: rtla ausente" | tee "$SAIDA/osnoise-hist.txt"
fi

# --------------------------------------------------------------------------
# 2. stall_probe: as mesmas quatro celulas x cinco repeticoes das oito coletas
#    anteriores. Roda como o DONO, nao como root: as coletas arquivadas foram
#    feitas assim, e privilegio muda o que o escalonador faz com a thread.
# --------------------------------------------------------------------------
echo
echo "==> 2/3 campanha de isolamento, 4 celulas x 5 repeticoes  ($(date +%T))"
if [ -x build/trilha/03-performance/03-isolamento-cpu/stall_probe ]; then
    sudo -u "$DONO" -H ./ferramental/qualidade/campanha-isolamento.sh "$SAIDA/isolamento" 5 \
        && echo "    ok" || echo "    FALHA"
else
    echo "    PULADO: stall_probe ausente; rode scripts/build-all.sh antes"
fi

# --------------------------------------------------------------------------
# 3. mempool-tempo: o elo miss x tempo, que espera maquina dedicada desde que
#    os prefixos sem estatisticas ficaram prontos. Modo texto e a condicao mais
#    dedicada que esta maquina alcanca, entao ele corre aqui.
# --------------------------------------------------------------------------
echo
echo "==> 3/3 campanha de tempo do mempool  ($(date +%T))"
if [ -x build-25.11-sem-stats/trilha/01-fundamentos/02-mempool-ring/pipeline_ring ]; then
    sudo -u "$DONO" -H ./ferramental/qualidade/campanha-mempool-tempo.sh "$SAIDA/mempool-tempo" 21 \
        && echo "    ok" || echo "    FALHA"
else
    echo "    PULADO: binarios -sem-stats ausentes"
fi

echo
echo "==> CONCLUIDA  $(date -Is)"
echo
echo "    Para voltar ao modo grafico:"
echo "      sudo systemctl set-default graphical.target && sudo reboot"
