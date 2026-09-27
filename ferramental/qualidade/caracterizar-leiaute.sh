#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# =========================================================================
# CARACTERIZAR A SENSIBILIDADE DE CADA ROTULO AO LEIAUTE DO BINARIO
#
#   sudo ./ferramental/qualidade/caracterizar-leiaute.sh [opcoes] <programa>...
#
#   --repeticoes N      execucoes por artefato (padrao 20; o `meson.build`
#                       adotou "cinco a vinte" e os casos marginais do
#                       `custo-mckenney` nao se resolveram com dez)
#   --alinhamentos "…"  valores de `-falign-loops` (padrao "16 32 64 128")
#
# POR QUE ISTO NAO E UMA ETAPA DO `run-all.sh`
#
# Todo o `run-all.sh` mede a MAQUINA sob um artefato fixo. Isto mede o
# INSTRUMENTO, variando o artefato de proposito. Sao perguntas opostas: uma
# segura o binario para ver a maquina, a outra segura a maquina para ver o
# binario.
#
# Os gatilhos tambem diferem. A coleta normal se repete quando o hardware
# muda; a sensibilidade de um rotulo so muda quando o CODIGO daquele programa
# muda. E a saida daqui e CALIBRACAO -- o `sensibilidade-leiaute.tsv`, que e
# entrada do `comparar-hardware.py`. Calibracao e medicao compartilhando
# gatilho faria a regua ser recalibrada pelos dados que ela julga.
#
# O QUE ELE RESPONDE
#
# Para cada rotulo, tres perguntas que separam tres coisas distintas:
#
#   reprodutibilidade  a faixa entre execucoes do MESMO artefato
#   envelope           a variacao das medianas ENTRE alinhamentos
#   identificabilidade o sinal e a materialidade do efeito sobrevivem ao
#                      envelope?
#
# UMA VARIAVEL, E SO UMA. As flags saem do `compile_commands.json` do build do
# projeto, e so `-falign-loops` e substituido. A caracterizacao de 27/09/2026
# compilou com `cc -Wall -std=c11 -O2 -g -pthread` e esqueceu
# `-D_FILE_OFFSET_BITS=64`, que o meson passa -- os artefatos diferiam da
# producao em mais de uma variavel, e o desenho exige exatamente uma.
#
# O MODO E TEXTO, E O PORTAO RECUSA SESSAO GRAFICA
#
# A §7 da metodologia manda mediana e razao para "maquina dedicada, sessao
# grafica permitida", e dispersao para modo texto. Isto cai nos dois lados: a
# grandeza e comparacao de medianas, e a resolucao exigida e de dispersao --
# separar leiaute de variacao entre execucoes.
#
# Decide o segundo, e a razao esta medida: em 27/09/2026 uma execucao
# perturbada em dez moveu a faixa de `lock, best case` em 84% (um valor de
# 3,79 entre nove de 2,04), e `2 threads on 2 physical cores` teve 3038,70
# entre valores de 3690. Foi sessao grafica viva.
#
# O GOVERNOR VAI FIXO em `performance`, e restaurado no fim. Ele e a unica
# razao pela qual o modo grafico parecia melhor para medianas -- a rampa de
# relogio em texto, que o `custo-alocacao` mostrou indo de 4,33 a 5,57 GHz
# DENTRO da medicao. Com ele fixo, o argumento some.
# =========================================================================
set -u
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"

REPETICOES=20
ALINHAMENTOS="16 32 64 128"
while [ $# -gt 0 ]; do
    case "$1" in
        --repeticoes)    REPETICOES=$2; shift 2 ;;
        --alinhamentos)  ALINHAMENTOS=$2; shift 2 ;;
        -*) echo "opcao desconhecida: $1" >&2; exit 2 ;;
        *)  break ;;
    esac
done
[ $# -ge 1 ] || {
    echo "uso: $0 [--repeticoes N] [--alinhamentos \"16 32 64 128\"] <programa>..." >&2
    echo "  exemplo: $0 custo-comunicacao custo-mckenney" >&2
    exit 2
}
PROGRAMAS="$*"

# ---- PORTAO 1: ROOT, porque o governor exige ----------------------------
[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo (fixar o governor exige root)." >&2; exit 1; }
DONO=${SUDO_USER:-$(stat -c %U "$RAIZ" 2>/dev/null || echo root)}

# ---- PORTAO 2: SESSAO GRAFICA RECUSADA ----------------------------------
# Assimetrico como o da campanha: aqui a ausencia de sessao NAO e a hipotese,
# e sim a condicao que torna a faixa entre execucoes legivel.
graficos=$(pgrep -c -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" 2>/dev/null)
graficos=${graficos:-0}
if [ "$graficos" -ne 0 ]; then
    echo "FALHA: a caracterizacao exige modo texto, e ha $graficos processo(s) grafico(s)." >&2
    pgrep -a -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" | sed 's/^/           /' >&2
    echo "       sudo grub-reboot modo-texto && systemctl reboot -i" >&2
    exit 1
fi

# ---- PORTAO 3: RECONSTRUIR ANTES DE LER AS FLAGS ------------------------
#
# O contrato desta etapa e simples e precisa continuar simples:
#
#   a caracterizacao deriva as flags do BUILD NORMAL ATUAL, que acabou de
#   passar pela mesma reconstrucao que a campanha usa.
#
# Conferir a data do `compile_commands.json` nao bastaria: uma mudanca no
# `meson.build` altera as flags sem tocar em nenhum `.c`, e o arquivo ficaria
# "recente" descrevendo outra coisa. `build-all.sh` e no-op quando nada mudou,
# entao reconstruir custa segundos e fecha o caso inteiro. Chamado sozinho ou
# pela ETAPA 5 do `run-all`, o caminho e o mesmo.
echo "==> reconstruindo o build normal (no-op se nada mudou)"
if ! sudo -u "$DONO" -H ./scripts/build-all.sh build > /tmp/caracterizar-build.$$.log 2>&1; then
    echo "FALHA: a compilacao nao passou. A caracterizacao NAO comeca." >&2
    tail -20 /tmp/caracterizar-build.$$.log >&2
    rm -f /tmp/caracterizar-build.$$.log
    exit 1
fi
rm -f /tmp/caracterizar-build.$$.log

# SO O BUILD NORMAL, E NUNCA UM FALLBACK.
#
# A versao anterior aceitava `build-san` quando `build` faltava. O `build-san`
# e configurado com `-Db_sanitize=address,undefined`, e suas flags trazem
#
#     -fsanitize=address,undefined -fno-omit-frame-pointer
#
# O `-fno-omit-frame-pointer` sozinho ja muda alocacao de registradores e
# leiaute -- que e A VARIAVEL SOB ESTUDO. Caracterizar a partir dali mediria o
# efeito do sanitizador e chamaria de sensibilidade ao leiaute.
CC_JSON="build/compile_commands.json"
[ -f "$CC_JSON" ] || { echo "FALHA: $CC_JSON nao existe mesmo apos reconstruir." >&2; exit 1; }

CARIMBO="$(date +%Y-%m-%d-%H%M)"
SAIDA="docs/01-fundamentos/medicoes/historico/$CARIMBO-leiaute"
mkdir -p "$SAIDA/saidas" "$SAIDA/artefatos"
MANIFESTO="$SAIDA/manifesto.txt"
. "$RAIZ/ferramental/qualidade/identidade-artefato.sh"
{
    echo "# manifesto da caracterizacao de leiaute $CARIMBO"
    echo "# STATUS: PASS (mediu), SKIP (pre-requisito ausente), FAIL (correu e reprovou)"
    printf '%-40s %-7s %s\n' "CELL" "STATUS" "RC"
} > "$MANIFESTO"

# ---- O GOVERNOR, E A RESTAURACAO QUE NAO DEPENDE DE CHEGAR AO FIM -------
GOV_ANTES=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo desconhecido)
fixar_gov() {
    for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        echo "$1" > "$c" 2>/dev/null || :
    done
}
restaurar_gov() {
    [ "$GOV_ANTES" = "desconhecido" ] || { fixar_gov "$GOV_ANTES"; echo "==> governor restaurado para $GOV_ANTES"; }
}
# TRAPS SEPARADOS: o de saida limpa, os de sinal limpam E TERMINAM. Um trap de
# INT que so limpa devolve o controle e a caracterizacao segue depois de o
# operador achar que a interrompeu -- foi o defeito que o `run-all` corrigiu.
trap 'restaurar_gov' EXIT
trap 'echo "==> interrompido (SIGINT)" >&2; exit 130' INT
trap 'echo "==> terminado (SIGTERM)" >&2; exit 143' TERM
fixar_gov performance
echo "==> governor: $GOV_ANTES -> performance (restaurado no fim)"

# ---- A CONDICAO VAI NO ARQUIVO, e nao so na tela ------------------------
{
    echo "tipo           : caracterizacao de sensibilidade ao leiaute"
    echo "modo detectado : texto ($graficos processo(s) grafico(s))"
    echo "carimbo        : $CARIMBO"
    echo "programas      : $PROGRAMAS"
    echo "alinhamentos   : $ALINHAMENTOS"
    echo "repeticoes     : $REPETICOES por artefato"
    echo "governor       : $GOV_ANTES -> performance"
    echo "execucao       : completa"
    echo
} > "$SAIDA/ambiente.txt"
./scripts/ambiente.sh >> "$SAIDA/ambiente.txt" 2>&1

# ---- CONSTRUIR AS VARIANTES --------------------------------------------
flags_do_programa() { # <programa> -> flags do meson, sem -falign-loops
    python3 - "$CC_JSON" "$1" <<'PYF'
import json, re, sys
cc = json.load(open(sys.argv[1]))
alvo = sys.argv[2]
for e in cc:
    base = re.sub(r'\.[^.]+$', '', e.get('file', '').split('/')[-1])
    if base == alvo:
        fora = []
        for x in e.get('command', '').split():
            if not x.startswith('-'):
                continue
            if x.startswith(('-I', '-MD', '-MQ', '-MF', '-o', '-falign-loops')):
                continue
            if x == '-c':
                continue
            fora.append(x)
        print(' '.join(fora))
        raise SystemExit
raise SystemExit("sem entrada para %s" % alvo)
PYF
}
fonte_do_programa() { # <programa> -> caminho ABSOLUTO do .c
    # O `file` do `compile_commands.json` e relativo ao `directory` (o diretorio
    # de build), e sai como `../docs/...`. Este script roda de `$RAIZ`, entao
    # usa-lo cru resolveria para fora da arvore -- em silencio, porque `cc`
    # diria apenas "arquivo nao encontrado" e a variante seria marcada FAIL.
    python3 - "$CC_JSON" "$1" <<'PYF'
import json, os, re, sys
cc = json.load(open(sys.argv[1]))
alvo = sys.argv[2]
for e in cc:
    if re.sub(r'\.[^.]+$', '', e.get('file', '').split('/')[-1]) == alvo:
        print(os.path.realpath(os.path.join(e.get('directory', '.'), e['file'])))
        raise SystemExit
raise SystemExit("sem fonte para %s" % alvo)
PYF
}

BINARIOS=""
for prog in $PROGRAMAS; do
    fonte=$(fonte_do_programa "$prog") || { echo "FALHA: $prog nao esta no compile_commands.json" >&2; exit 1; }
    flags=$(flags_do_programa "$prog")
    inc=$(dirname "$fonte")
    # A PROCEDENCIA DO FONTE, por programa. E ela que diz, depois, se a
    # classificacao envelheceu: rotulo caracterizado contra um fonte que
    # mudou nao autoriza mais comparacao nenhuma.
    commit_fonte=$(sudo -u "$DONO" git log -1 --format=%H -- "$fonte" 2>/dev/null || echo desconhecido)
    echo "# FONTE $prog"          >> "$MANIFESTO"
    echo "#   path=${fonte#$RAIZ/}" >> "$MANIFESTO"
    echo "#   commit=$commit_fonte" >> "$MANIFESTO"
    echo "#   flags_base=$flags"    >> "$MANIFESTO"
    for al in $ALINHAMENTOS; do
        bin="$SAIDA/artefatos/$prog.al$al"
        # shellcheck disable=SC2086
        if cc -I"$inc" $flags -falign-loops="$al" "$fonte" -o "$bin" -lm 2>"$SAIDA/artefatos/$prog.al$al.erro"; then
            rm -f "$SAIDA/artefatos/$prog.al$al.erro"
            identidade_artefato "$bin"
            BINARIOS="$BINARIOS $prog:$al"
            echo "    construido: $prog -falign-loops=$al"
        else
            printf '%-40s %-7s %s\n' "$prog.al$al" "FAIL" "build" >> "$MANIFESTO"
            echo "    FALHA ao construir $prog -falign-loops=$al" >&2
            sed 's/^/        /' "$SAIDA/artefatos/$prog.al$al.erro" >&2
        fi
    done
done
[ -n "$BINARIOS" ] || { echo "FALHA: nenhum artefato construido." >&2; exit 1; }

# ---- MEDIR, COM A ORDEM CONTRABALANCEADA --------------------------------
# A ordem se inverte nas repeticoes pares. Sem isso, o primeiro artefato de
# cada rodada mede sempre no relogio mais frio e a diferenca entre artefatos
# absorve a diferenca entre posicoes.
echo "==> medindo: $(echo $BINARIOS | wc -w) artefato(s) x $REPETICOES repeticoes  ($(date +%T))"
rep=1
while [ "$rep" -le "$REPETICOES" ]; do
    if [ $((rep % 2)) -eq 1 ]; then ordem="$BINARIOS"; else ordem=$(echo $BINARIOS | tr ' ' '\n' | tac | tr '\n' ' '); fi
    for par in $ordem; do
        prog=${par%%:*}; al=${par##*:}
        saida="$SAIDA/saidas/r$rep-al$al-$prog.txt"
        if sudo -u "$DONO" -H "$SAIDA/artefatos/$prog.al$al" > "$saida" 2>&1; then
            rc=0
        else
            rc=$?
        fi
        case "$rc" in 0) est=PASS ;; 77) est=SKIP ;; *) est=FAIL ;; esac
        printf '%-40s %-7s %s\n' "$(basename "$saida")" "$est" "$rc" >> "$MANIFESTO"
    done
    echo "    repeticao $rep de $REPETICOES concluida  ($(date +%T))"
    rep=$((rep + 1))
done

chown -R "$DONO" "$SAIDA"
falhas=$(awk '$2 == "FAIL" { n++ } END { print n + 0 }' "$MANIFESTO")
echo
echo "==> CONCLUIDA  $(date -Is)"
echo "    saida: $SAIDA"
echo "    celulas com FAIL: $falhas"
echo
echo "    Para classificar:"
echo "      ./ferramental/qualidade/classificar-leiaute.py $SAIDA"
[ "$falhas" -eq 0 ] || { echo "==> CARACTERIZACAO COM FALHA: $falhas celula(s)" >&2; exit 1; }
exit 0
