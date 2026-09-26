#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Apura o ambiente que decide se uma medição é reprodutível — e não altera nada.
#
# POR QUE ISTO EXISTE
#
# Seis documentos deste projeto publicam tempos, e cinco carregam alguma forma
# da mesma ressalva: "sem fixar a frequência da CPU e sem isolar núcleos; serve
# para ordem de grandeza". A ressalva é honesta e é vaga: ela diz que algo não
# foi controlado, e não diz o que estava valendo na hora.
#
# Um número publicado sem o ambiente em que saiu não é reprodutível, porque quem
# for repetir não sabe contra o quê comparar. Este script produz esse registro.
#
# O QUE ELE NÃO FAZ, e é deliberado: não muda governor, não desliga boost, não
# isola núcleo. Alterar a máquina de quem estuda, a partir de um script de
# diagnóstico, é a mesma classe de erro que fez `preparar-nic.sh` descer uma
# interface no meio da verificação. O que ele faz é APURAR, dizer o que cada
# achado custa em dispersão, e imprimir o comando que corrige — para quem opera
# a máquina decidir.
#
# TRI-ESTADO, como o resto do projeto: cada item sai APURADO com valor, ou NÃO
# APURADO com o motivo. "Não consegui ler o governor" nunca vira "governor
# ausente", que viraria "sem escalonamento de frequência", que é falso e
# tranquilizador -- a pior combinação.
#
# Uso:
#   ./scripts/ambiente-medicao.sh            # relatório legível
#   ./scripts/ambiente-medicao.sh --uma-linha  # uma linha, para carimbar medição
set -u

# shellcheck source=lib-apuracao.sh
. "$(dirname "$0")/lib-apuracao.sh" || { echo "nao consegui carregar lib-apuracao.sh" >&2; exit 1; }

UMA_LINHA=0
for arg in "$@"; do
    case "$arg" in
        --uma-linha) UMA_LINHA=1 ;;
        *) echo "uso: $0 [--uma-linha]" >&2; exit 2 ;;
    esac
done

nao_apurados=0
declare -a RESUMO=()

# item <rótulo> <chave-curta> <caminho>
#
# A CHAVE CURTA é o que sai no modo --uma-linha, e ela não tem espaço de
# propósito: a linha existe para ser carimbada junto de uma medição e lida
# depois por programa. Um valor com espaço no meio ("performance powersave")
# quebra qualquer leitor que separe por branco, e quebra em silêncio.
item() {
    local rotulo=$1 chave=$2 caminho=$3 valor
    if apur_ler "$caminho"; then
        valor=${_APUR:-vazio}
    elif [ "$_APUR_ESTADO" = "ausente" ]; then
        # AUSENTE é fato: este kernel/hardware não expõe o controle. Diferente
        # de não ter sido possível ler.
        valor="nao-exposto"
    else
        valor="NAO-APURADO"
        nao_apurados=$((nao_apurados + 1))
    fi
    RESUMO+=("$chave=${valor// /,}")
    [ "$UMA_LINHA" -eq 1 ] && return 0
    if [ "$valor" = "NAO-APURADO" ]; then
        printf '  %-22s NAO APURADO -- %s\n' "$rotulo" "$_APUR_MOTIVO"
    else
        printf '  %-22s %s\n' "$rotulo" "$valor"
    fi
}

if [ "$UMA_LINHA" -eq 0 ]; then
    echo "== Ambiente de medição =="
    echo ""
    echo "  -- escalonamento de frequência --"
fi

base=/sys/devices/system/cpu
item "driver de frequencia" driver "$base/cpu0/cpufreq/scaling_driver"
item "governor" governor "$base/cpu0/cpufreq/scaling_governor"
item "governors possiveis" governors "$base/cpu0/cpufreq/scaling_available_governors"
item "frequencia minima" freq_min "$base/cpu0/cpufreq/scaling_min_freq"
item "frequencia maxima" freq_max "$base/cpu0/cpufreq/scaling_max_freq"
item "boost" boost "$base/cpufreq/boost"

# A FAIXA é o número que importa, e não o governor pelo nome: é ela que limita o
# quanto uma medição pode variar por causa do clock. Só é calculada quando os
# DOIS extremos foram apurados -- dividir por um valor não apurado seria
# inventar a razão.
faixa="NAO-APURADA"
if apur_ler "$base/cpu0/cpufreq/scaling_min_freq"; then
    minf=$_APUR
    if apur_ler "$base/cpu0/cpufreq/scaling_max_freq"; then
        maxf=$_APUR
        if [ "$minf" -gt 0 ] 2>/dev/null; then
            faixa=$(awk -v a="$minf" -v b="$maxf" 'BEGIN{printf "%.1fx_%.2f-%.2fGHz", b/a, a/1e6, b/1e6}')
        fi
    fi
fi
[ "$UMA_LINHA" -eq 0 ] && printf '  %-22s %s\n' "faixa de frequencia" "$faixa"
RESUMO+=("faixa=$faixa")

if [ "$UMA_LINHA" -eq 0 ]; then
    echo ""
    echo "  -- isolamento e concorrência --"
fi
item "nucleos isolados" isolados "$base/isolated"
item "nohz_full" nohz_full "$base/nohz_full"
item "SMT" smt "$base/smt/control"
item "ASLR" aslr /proc/sys/kernel/randomize_va_space
item "NMI watchdog" nmi_watchdog /proc/sys/kernel/nmi_watchdog

if apur_ler /proc/loadavg; then
    carga=${_APUR%% *}
    [ "$UMA_LINHA" -eq 0 ] && printf '  %-22s %s (media de 1 min)\n' "carga" "$carga"
    RESUMO+=("carga=$carga")
else
    [ "$UMA_LINHA" -eq 0 ] && printf '  %-22s NAO APURADO -- %s\n' "carga" "$_APUR_MOTIVO"
    RESUMO+=("carga=NAO-APURADO")
    nao_apurados=$((nao_apurados + 1))
fi

if [ "$UMA_LINHA" -eq 1 ]; then
    printf '%s\n' "${RESUMO[*]}"
    exit $([ "$nao_apurados" -eq 0 ] && echo 0 || echo 1)
fi

cat <<'TEXTO'

  -- o que isto custa, medido nesta arvore --

  A faixa de frequencia assusta mais do que cobra. Doze execucoes de
  `custo-syscall` partindo de frequencias entre 0,61 e 5,62 GHz -- variacao de
  9x -- produziram entre 0,714 e 0,747 ns por chamada de funcao: 4,6% de
  amplitude. O laco de medicao leva o nucleo ao teto em microssegundos, e a
  mediana absorve o resto.

  O que cobra caro e outra coisa: a PRIMEIRA execucao depois de ociosidade
  prolongada mediu 0,926, 0,927 e 0,930 ns em tres observacoes independentes,
  contra 0,713 a 0,747 nas execucoes imediatamente seguintes. Excesso de ~30%,
  na operacao mais curta. O mecanismo nao foi isolado -- saida de C-state
  profundo e paginas fora do cache sao os candidatos --, e o efeito e
  reprodutivel.

  Consequencia pratica, que inverte a intuicao da ressalva -- E QUE VALE PARA
  O MODO EM QUE FOI MEDIDA, com sessao grafica ativa: fixar o governor ajuda
  pouco; DESCARTAR A PRIMEIRA EXECUCAO apos ociosidade ajuda muito.

  EM MODO TEXTO A CONCLUSAO SE INVERTE, e isto foi medido em 24/09/2026.

  Com sessao grafica o compositor mantem a CPU ocupada, entao so a primeira
  execucao apos ociosidade e fria e descarta-la resolve. Sem sessao grafica
  nada aquece a CPU entre invocacoes: TODA execucao e a primeira apos
  ociosidade, e o descarte nao alcanca o problema.

  O par medido, mesma maquina e mesma configuracao, diferindo so no governor:

    powersave     relogio 4,33 -> 4,94..5,57 GHz   malloc 2,78 nas seis
    performance   relogio 5,58 -> 5,55 GHz         malloc 2,18 a 2,19

  O 2,78 nao era ruido: era o valor que a operacao mais curta dava por ser
  medida PRIMEIRO, sempre no relogio frio. Com o governor fixo ele volta ao
  que o modo grafico da.

  A regra que sobrevive nao e "governor ajuda pouco"; e que o remedio depende
  do que mantem a CPU quente. Em modo grafico, o compositor faz isso e o
  descarte basta. Em modo texto, nada faz, e o governor passa a ser a variavel
  dominante dos valores absolutos.

  -- para fixar o que da para fixar --

    sudo cpupower frequency-set -g performance       # governor
    echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost
    # isolamento exige reinicio, na linha de comando do kernel:
    #   isolcpus=6-11,18-23 nohz_full=6-11,18-23 rcu_nocbs=6-11,18-23

  Nada disto e executado por este script: ele apura e declara.
TEXTO

echo ""
if [ "$nao_apurados" -gt 0 ]; then
    echo "  $nao_apurados item(ns) NAO APURADO(S) -- o registro do ambiente esta incompleto"
    echo "  Publicar medicao com ambiente incompleto e publicar numero sem procedencia."
    exit 1
fi
echo "  ambiente apurado por inteiro"
