#!/usr/bin/env bash
# =========================================================================
# ROTEIRO DAS QUATRO CELULAS: memoria 4800/6000 x canal unico/duplo
#
# Nada aqui roda sozinho. Cada celula e um bloco COMENTADO: descomente a
# linha do `campanha`, rode, e comente de volta antes de passar a proxima.
#
# POR QUE UM ROTEIRO, E NAO QUATRO COMANDOS DIGITADOS NA HORA
#
# A campanha anterior foi rotulada errado porque a configuracao medida vivia
# na cabeca de quem digitava, nao no comando. O nome da coleta dizia a data,
# e a data nao distingue 4800 de 6000. Aqui o nome e a conferencia da BIOS
# estao na MESMA linha: errar exige contrariar o portao, nao esquecer.
#
# COMO NAO VOLTAR AO MODO GRAFICO ENTRE AS CELULAS
#
# `grub-reboot` e de UM boot so: depois dele, o proximo volta ao padrao. Para
# encadear, cada bloco reagenda o modo texto ANTES de reiniciar. Rodando
# `proxima_celula` no fim de cada coleta, a maquina volta direto ao console.
#
# POR QUE ESTE ARQUIVO ESTA VERSIONADO
#
# Ele nasceu em `temp/`, que o git ignora. O cabecalho do `campanha-hardware.sh`
# ja explica por que isso nao serve: a primeira campanha deste projeto rodou de
# um script solto que a limpeza apagou junto com os dados, e um protocolo que
# nao sobrevive a um reboot nao e reproduzivel por definicao. As quatro celulas
# de 24/09/2026 sairam daqui; quem quiser repeti-las noutra maquina precisa do
# roteiro, nao so dos numeros.
#
#   uso:  cd <raiz do repositorio>
#         sudo bash ferramental/qualidade/roteiro-fatorial-memoria.sh
#         (edite o bloco da celula e rode de novo)
# =========================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

# -------------------------------------------------------------------------
# PORTAO: a maquina esta na configuracao que o comando declara?
#
# Le o dmidecode AO VIVO, nao o cache: o cache e reescrito pela propria
# campanha e responderia pelo estado anterior. A conferencia e a mesma que o
# `ambiente.sh --cachear-memoria` faz, para os dois nunca divergirem.
# -------------------------------------------------------------------------
conferir() { # <velocidade esperada> <pentes esperados>
    local vel_q="$1" pentes_q="$2" D vel pentes
    D=$(dmidecode -t memory 2>/dev/null)
    pentes=$(printf '%s' "$D" | grep -c "^[[:space:]]*Size: [0-9]")
    # Sem root o dmidecode sai com 0 e imprime so o cabecalho; a ausencia de
    # linha de Size e o unico sinal confiavel.
    [ "$pentes" -gt 0 ] || {
        echo "    FALHA: dmidecode exige root. Rode com sudo." >&2; return 1; }
    vel=$(printf '%s' "$D" | awk -F': ' '/Configured Memory Speed/ && $2 !~ /Unknown/ {print $2; exit}')
    echo "    BIOS agora : ${vel:-nao reportado}, $pentes pente(s)"
    echo "    o comando declara: $vel_q, $pentes_q pente(s)"
    if [ "${vel%% *}" != "${vel_q%% *}" ] || [ "$pentes" != "$pentes_q" ]; then
        echo "    ABORTADO: a maquina NAO esta na configuracao declarada." >&2
        echo "              Medir assim rotularia a coleta com a configuracao errada," >&2
        echo "              e um comparativo entre iguais parece nulo, nao invalido." >&2
        return 1
    fi
    echo "    confere."
    return 0
}

# Reagenda o modo texto para o proximo boot. Chame ANTES de reiniciar.
proxima_celula() {
    grub-reboot modo-texto && echo "==> proximo boot: modo texto. Reinicie com: reboot"
}

campanha() { # <velocidade> <pentes> <nome-da-coleta> [--so-hardware]
    local vel="$1" pentes="$2" nome="$3"; shift 3
    echo "==> celula: $nome"
    conferir "$vel" "$pentes" || return 1
    ./ferramental/qualidade/campanha-modo-texto.sh "$@" "$nome"
}

# =========================================================================
# ESTADO ATUAL -- isto SEMPRE roda, e e so leitura
# =========================================================================
echo "== estado da maquina =="
# `dmidecode` sem root sai com 0 e imprime so o cabecalho, entao testar o
# codigo de saida -- ou se a saida e vazia -- nao distingue nada. O que
# distingue e haver linha de Size.
D=$(dmidecode -t memory 2>/dev/null)
pentes=$(printf '%s' "$D" | grep -c "^[[:space:]]*Size: [0-9]")
if [ "$pentes" -gt 0 ]; then
    echo "  memoria : $(printf '%s' "$D" | awk -F': ' '/Configured Memory Speed/ && $2 !~ /Unknown/ {print $2; exit}')"
    echo "  pentes  : $pentes"
else
    echo "  memoria : (dmidecode exige root -- rode com sudo para ver)"
fi
echo "  graficos: $(pgrep -c -x 'Xorg|Xwayland|gnome-shell|kwin_wayland|sway' 2>/dev/null || echo 0)  (0 = modo texto)"
echo "  coletas ja feitas:"
ls -d trilha/03-performance/03-isolamento-cpu/historico/*/ 2>/dev/null \
  | sed 's|.*/historico/||;s|/$||;s/^/    /'
echo


# =========================================================================
# CELULA 1 -- 1 pente, 4800 MT/s (canal unico, JEDEC)
#
#   ANTES: desligue a maquina, deixe UM pente, e desligue o EXPO na BIOS.
#   Campanha COMPLETA. Esta celula e a CELULA 4 formam o par que responde ao
#   confundimento A x C: mesma BIOS (4800), mesmo modo texto, diferindo so no
#   numero de pentes. Emparelhar com a celula 3 seria erro -- ela muda canal
#   E velocidade ao mesmo tempo, e duas variaveis nao isolam nenhuma.
# =========================================================================
# campanha "4800" 1 2026-09-24-jedec4800-canal-unico-texto
# proxima_celula


# =========================================================================
# CELULA 2 -- 1 pente, 6000 MT/s (canal unico, EXPO)
#
#   ANTES: so BIOS. Ligue o EXPO 6000. Nao abra a maquina.
#   `--so-hardware`: os passos 1 a 4 nao dependem do perfil de memoria, e a
#   celula 1 ja os mediu em canal unico.
# =========================================================================
# campanha "6000" 1 2026-09-24-expo6000-canal-unico-texto --so-hardware
# proxima_celula


# =========================================================================
# CELULA 3 -- 2 pentes, 6000 MT/s (canal duplo, EXPO)
#
#   ANTES: desligue e instale o segundo pente. O EXPO ja esta ligado.
#   `--so-hardware`: o isolamento em canal duplo sai da celula 4, que compara
#   com a celula 1 na mesma BIOS.
# =========================================================================
# campanha "6000" 2 2026-09-24-expo6000-canal-duplo-texto --so-hardware
# proxima_celula


# =========================================================================
# CELULA 4 -- 2 pentes, 4800 MT/s (canal duplo, JEDEC)
#
#   ANTES: so BIOS. Desligue o EXPO.
#   Campanha COMPLETA: fecha o 2x2 E fecha o par com a celula 1 -- as duas em
#   4800, uma com um pente e outra com dois. E o unico par do roteiro em que
#   canal e a unica variavel.
#   Depois desta, `proxima_celula` NAO e chamada: o proximo boot volta ao
#   modo grafico sozinho.
# =========================================================================
campanha "4800" 2 2026-09-24-jedec4800-canal-duplo-texto


# =========================================================================
# DEPOIS DAS QUATRO
#
#   O 2x2 fica assim, e cada par isola uma variavel:
#
#                    canal unico        canal duplo
#     4800 MT/s      celula 1 <-------> celula 4      <- canal, isolado
#     6000 MT/s      celula 2 <-------> celula 3      <- canal, isolado
#                       ^                  ^
#                       +-- velocidade, isolada --+
#
#   As celulas 1 e 4 sao as COMPLETAS: alem do 2x2 de memoria, elas medem
#   isolamento de CPU em canal unico e duplo com todo o resto igual, que e o
#   que o confundimento A x C do §6.7 pede e os dados atuais nao respondem.
#
#   Comparar (o script ja faz isto no passo 6 contra a referencia, mas o 2x2
#   pede os pares certos):
#
#     ./ferramental/qualidade/comparar-hardware.py \
#        docs/01-fundamentos/medicoes/historico/<celula1> \
#        docs/01-fundamentos/medicoes/historico/<celula2>
#
#   So APOS as quatro coletas existirem e o portao passar vale apagar as
#   antigas: ate la elas sao a unica evidencia dos blocos publicados, e
#   `verificar-blocos.py` confere 154 deles contra o que esta arquivado.
# =========================================================================
