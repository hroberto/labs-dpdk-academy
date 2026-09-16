#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Prepara uma NIC física para o DPDK, com as travas que evitam perder a máquina.
#
# POR QUE ISTO É UM SCRIPT, E COM TANTA VERIFICAÇÃO
#
# Tirar uma placa de rede do kernel é a operação mais perigosa da trilha, e a
# falha é imediata e total: se a interface bindada for a que carrega o seu
# acesso, a sessão morre no meio do comando e a recuperação exige console
# físico. Nenhuma outra coisa que este projeto pede tem esse custo.
#
# O `dpdk-devbind.py` não protege contra isso -- ele avisa em alguns casos e
# obedece em todos. Este script recusa antes de tentar.
#
# A DOUTRINA, e ela é o que diferencia esta versão da anterior: uma verificação
# que NÃO CONSEGUIU APURAR nunca libera. "Apurei e a resposta é não" e "não
# consegui apurar" são coisas diferentes, e a segunda recusa. A versão anterior
# deste script errava isso em quatro lugares, cada um deles capaz de autorizar o
# bind a partir de uma não-leitura:
#
#   - a rota default era comparada com `$(ip route ... | awk '{print $5}')`: com
#     o `ip` falhando, a variável ficava vazia, a comparação dava falsa e o
#     script LIBERAVA;
#   - os grupos IOMMU eram contados com `ls | wc -l`, que devolve 0 tanto para
#     "não há grupos" quanto para "não consegui olhar";
#   - um membro do grupo IOMMU cujo driver não pudesse ser lido era classificado
#     junto com as pontes, isto é, como "não impede";
#   - o vendor PCI ilegível caía no ramo `*)` de `modelo_de_driver`, que responde
#     "captura" -- exatamente o veredito que autoriza o bind.
#
# Todos os quatro liberavam no caminho preguiçoso. Hoje a leitura do sistema
# passa por `lib-apuracao.sh`, que devolve tri-estado, e o não-apurado recusa.
#
# AS TRAVAS, na ordem em que rodam e com o que cada uma impede:
#
#   0. registro e trava de exclusão -- o diretório de estado precisa ser modo
#      700 e a operação inteira roda sob `flock`, para que duas execuções
#      simultâneas não se atropelem entre verificar e agir.
#   1. identidade PCI -- vendor, device, subsystem e classe lidos do sysfs. Sem
#      vendor não se decide o modelo de driver; sem classe não se sabe se é
#      sequer uma controladora Ethernet.
#   2. modelo de driver -- Mellanox/mlx5 é bifurcado e NÃO se binda ao vfio-pci.
#   3. grupo IOMMU -- a NIC precisa ser o único *endpoint* do grupo. Pontes
#      (`pcieport`) não contam, porque o VFIO as permite; membro com driver não
#      apurado conta, porque não se sabe o que é.
#   4. rota default, estado e endereços -- `nic_bind_guard` recusa a interface
#      que carrega o default gateway, a que está UP, e o caso em que a rota ou o
#      estado não puderam ser apurados. Endereço configurado indica uso e exige
#      `--forcar`; falha ao CONSULTAR endereços não é contornável por `--forcar`.
#   5. PMD -- um PMD do DPDK precisa declarar suporte à identidade PCI COMPLETA.
#      Sem isso o bind funciona e nenhuma aplicação enxerga a porta.
#   6. a trava 4 de novo -- entre a primeira verificação e o bind roda um
#      programa externo, e nesse intervalo a interface pode subir. A segunda
#      passagem fecha essa janela.
#
# Só então o driver de origem é gravado em disco e o bind acontece. Gravar ANTES
# é deliberado: se o bind falhar no meio, o registro sobrevive e `--desfazer`
# ainda sabe de onde a placa veio.
#
# Uso:
#   ./scripts/preparar-nic.sh --status          # o que existe, sem alterar nada
#   sudo ./scripts/preparar-nic.sh 08:00.0      # binda ao vfio-pci
#   sudo ./scripts/preparar-nic.sh --desfazer 08:00.0
set -u

ESTADO_DIR="/var/lib/dpdk-academy/nic"

# shellcheck source=lib-nic.sh
. "$(dirname "$0")/lib-nic.sh"
# shellcheck source=lib-apuracao.sh
. "$(dirname "$0")/lib-apuracao.sh" || { echo "nao consegui carregar lib-apuracao.sh" >&2; exit 1; }
# shellcheck source=lib-bind-guard.sh
. "$(dirname "$0")/lib-bind-guard.sh" || { echo "nao consegui carregar lib-bind-guard.sh" >&2; exit 1; }

erro() { printf '  RECUSADO - %s\n' "$1" >&2; }
ok()   { printf '  ok    - %s\n' "$1"; }
info() { printf '  info  - %s\n' "$1"; }
uso()  { printf 'uso: %s [--status | [--desfazer] [--forcar] [--driver=NOME] [--pmd=ELF] BDF]\n' "$0" >&2; exit 2; }

# --- linha de comando -------------------------------------------------------
#
# Invocação malformada sai com 2, e não com 1, porque as duas coisas têm leitor
# diferente: 1 é "o sistema está num estado que não autoriza a operação" e o
# leitor é quem opera a máquina; 2 é "você escreveu o comando errado" e o leitor
# é quem digitou. Colapsar os dois faria um erro de digitação passar por
# veredito sobre o hardware.
ACAO=""
FORCAR=0
BDF=""
DRIVER=""
PMD=""
for arg in "$@"; do
    case "$arg" in
        --status)   [ -z "$ACAO" ] || uso; ACAO="status" ;;
        --desfazer) [ -z "$ACAO" ] || uso; ACAO="desfazer" ;;
        --forcar)   FORCAR=1 ;;
        --driver=*) DRIVER="${arg#--driver=}" ;;
        --pmd=*)    PMD="${arg#--pmd=}" ;;
        -*)         echo "opcao desconhecida: $arg" >&2; uso ;;
        *)          [ -z "$BDF" ] || uso; BDF="$arg" ;;
    esac
done
[ -n "$ACAO" ] || ACAO="bind"

# O nome do driver vira argumento de `--bind=` e, mais adiante, componente de
# caminho sob /sys/bus/pci/drivers. Aceitar "../bad" ali seria deixar a linha de
# comando escolher um caminho fora da árvore.
if [ -n "$DRIVER" ]; then
    [ "$ACAO" = "desfazer" ] || uso
    [[ "$DRIVER" =~ ^[A-Za-z0-9_.-]+$ ]] || uso
    case "$DRIVER" in .|..|*/*) uso ;; esac
fi
[ -z "$PMD" ] || [ "$ACAO" != "status" ] || uso

# --- status: não altera nada, e é o único modo que dispensa root -------------
if [ "$ACAO" = "status" ]; then
    [ -z "$BDF" ] || uso
    echo "== NICs e o que o DPDK pode fazer com elas =="
    echo ""
    if apur_cmd ip -4 route show default; then
        printf '  rota default: %s\n' "${_APUR:-nenhuma}"
    else
        printf '  rota default: NAO APURADA -- %s\n' "$_APUR_MOTIVO"
    fi
    if apur_listar /sys/kernel/iommu_groups; then
        printf '  grupos IOMMU no sistema: %s\n' "$_APUR_N"
    else
        printf '  grupos IOMMU no sistema: NAO APURADO -- %s\n' "$_APUR_MOTIVO"
    fi
    echo ""
    echo "  modelo de driver por dispositivo:"
    if apur_listar /sys/bus/pci/devices; then
        for d in $_APUR; do
            [ -d "/sys/bus/pci/devices/$d/net" ] || continue
            if vendor_apurar "$d"; then
                printf '    %-14s %-10s %s\n' "$d" "$(modelo_de_driver "$_APUR")" \
                       "$(v=$(nome_do_vendor "$_APUR"); printf '%s' "${v:+-- $v}")"
            else
                printf '    %-14s %s\n' "$d" "vendor NAO APURADO -- $_APUR_MOTIVO"
            fi
        done
    else
        info "dispositivos PCI nao apurados -- $_APUR_MOTIVO"
    fi
    echo ""
    # A tabela do devbind é o conteúdo do --status, e não um enfeite: se ela não
    # sai, o comando não respondeu à pergunta que foi feita. Sair 0 aqui seria
    # publicar silêncio como resposta.
    if ! apur_cmd dpdk-devbind.py --status-dev net; then
        erro "nao apurei o estado de bind: $_APUR_MOTIVO"
        exit 1
    fi
    printf '%s\n' "$_APUR" | sed 's/^/  /'
    exit 0
fi

[ -n "$BDF" ] || uso
# Normaliza 08:00.0 -> 0000:08:00.0
case "$BDF" in *:*:*) : ;; *) BDF="0000:$BDF" ;; esac
# Domínio:barramento:dispositivo.função, com os limites do próprio PCI --
# dispositivo tem 5 bits (00-1f) e função tem 3 (0-7). Validar aqui, e não só
# "contém dois-pontos", é o que impede um argumento como "../outro" de virar
# componente de caminho sob /sys.
[[ "$BDF" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[01][0-9a-fA-F]\.[0-7]$ ]] || uso

# --- a partir daqui a operacao altera o sistema ------------------------------
#
# A checagem de root vem DEPOIS de validar a linha de comando, e a ordem foi
# corrigida contra a maquina real: como usuario comum, `preparar-nic.sh 08:20.0`
# saia com 1 e a mensagem "precisa de root" -- um BDF impossivel (dispositivo
# PCI tem 5 bits, 0x20 nao cabe) sendo reportado como problema de privilegio.
# O teste L1 nao pega isso, porque neutraliza justamente esta linha para poder
# rodar sem root; so a execucao na maquina mostrou.
(( EUID == 0 )) || { erro "esta operacao altera o bind de driver e precisa de root"; exit 1; }

if ! apur_listar "/sys/bus/pci/devices/$BDF"; then
    erro "dispositivo $BDF nao apurado: $_APUR_MOTIVO"
    exit 1
fi
ENTRADAS=$_APUR

# --- TRAVA 0 -- registro e exclusão mútua ------------------------------------
#
# O registro guarda o driver de origem, que é a única informação que o sistema
# APAGA ao bindar: depois que a placa está no vfio-pci, nada no sysfs diz de
# onde ela veio. A versão anterior deduzia isso do campo `unused=` do devbind --
# um palpite, tomado justamente no momento em que errar significa religar uma
# Intel num driver de Realtek.
#
# Modo 700 é exigido, não ajustado: o conteúdo decide para qual driver a placa
# volta, e um diretório gravável por outro usuário transforma isso em escolha
# alheia. Corrigir calado esconderia que a permissão estava errada.
if [ -d "$ESTADO_DIR" ]; then
    modo=$(stat -c '%a' "$ESTADO_DIR" 2>/dev/null || printf '')
    if [ "$modo" != "700" ]; then
        erro "$ESTADO_DIR precisa estar em modo 700 (esta em ${modo:-nao apurado})"
        echo "         O registro decide para qual driver a placa volta." >&2
        exit 1
    fi
elif ! mkdir -p -m 700 "$ESTADO_DIR" 2>/dev/null; then
    erro "nao consegui criar $ESTADO_DIR para registrar o driver de origem"
    exit 1
fi
REGISTRO="$ESTADO_DIR/$BDF.state"
TRAVA="$ESTADO_DIR/$BDF.lock"

if ! command -v flock >/dev/null 2>&1; then
    erro "\"flock\" nao esta no PATH; sem ele nao ha como impedir duas execucoes"
    exit 1
fi
exec {FD_TRAVA}>>"$TRAVA" || { erro "nao consegui abrir $TRAVA"; exit 1; }
if ! flock -n "$FD_TRAVA"; then
    erro "outra operacao sobre $BDF esta em andamento (trava $TRAVA)"
    echo "         Verificar e agir precisa ser indivisivel: entre a trava e o" >&2
    echo "         bind, outro processo poderia mudar o que acabou de ser lido." >&2
    exit 1
fi

# --- identidade PCI ----------------------------------------------------------
#
# Lida do sysfs, e não do `lspci`: são os mesmos números, mas o sysfs não pode
# faltar no PATH nem depender de um banco de identificadores instalado à parte.
identidade_apurar() { # <campo> -> $_ID
    local campo=$1
    if ! apur_ler "/sys/bus/pci/devices/$BDF/$campo"; then
        _ID_MOTIVO="$campo nao apurado: $_APUR_MOTIVO"
        return 1
    fi
    if [[ ! "$_APUR" =~ ^0x[0-9a-fA-F]{4}$ ]]; then
        _ID_MOTIVO="$campo invalido em /sys/bus/pci/devices/$BDF/$campo: \"$_APUR\""
        return 1
    fi
    _ID=$_APUR
    return 0
}

# O vendor tem mensagem própria porque é dele que sai a decisão mais destrutiva
# do script -- capturar ou não capturar. Ilegível e malformado dão no mesmo
# lugar: o vendor não foi apurado, e supor "captura" autorizaria o bind.
if ! vendor_apurar "$BDF" || [[ ! "$_APUR" =~ ^0x[0-9a-fA-F]{4}$ ]]; then
    erro "vendor nao apurado para $BDF: ${_APUR_MOTIVO:-valor fora do formato 0xNNNN}"
    echo "         Sem o vendor nao da para dizer se o modelo de driver e de" >&2
    echo "         captura total ou bifurcado, e supor 'captura' autorizaria o bind." >&2
    exit 1
fi
VENDOR=$_APUR

for campo in device subsystem_vendor subsystem_device; do
    if ! identidade_apurar "$campo"; then
        erro "$_ID_MOTIVO"
        exit 1
    fi
    case "$campo" in
        device)            DEVICE=$_ID ;;
        subsystem_vendor)  SUBVENDOR=$_ID ;;
        subsystem_device)  SUBDEVICE=$_ID ;;
    esac
done
IDENTIDADE="$VENDOR $DEVICE $SUBVENDOR $SUBDEVICE"
ok "identidade PCI: $IDENTIDADE"

# --- desfazer: devolve a placa ao driver do kernel ---------------------------
#
# O driver de volta e LIDO DO REGISTRO, nao adivinhado. A versao anterior
# deduzia do campo `unused=` do `dpdk-devbind.py --status-dev`, que lista os
# drivers compativeis e nao diz qual estava em uso -- um palpite tomado
# justamente no momento em que errar significa religar uma Intel num driver de
# Realtek, com a placa ja fora do kernel.
#
# Sem registro o script NAO adivinha: exige --driver explicito. E a mesma
# doutrina das travas -- nao apurado nao vira resposta --, aplicada ao caminho
# de recuperacao.
if [ "$ACAO" = "desfazer" ]; then
    echo "== Devolvendo $BDF ao kernel =="
    ALVO=""
    if apur_ler "$REGISTRO"; then
        mapfile -t LINHAS <<<"$_APUR"
        GRAVADO=${LINHAS[0]}
        ALVO=${LINHAS[${#LINHAS[@]} - 1]}
        # A identidade e conferida porque o BDF NAO e um nome estavel: remover a
        # placa e recolocar noutro slot, ou trocar por outra, mantem o endereco e
        # muda o dispositivo. Religar no driver da placa anterior seria um erro
        # silencioso, e o registro e justamente o que sobreviveu a troca.
        if [ "$GRAVADO" != "$BDF $IDENTIDADE" ]; then
            erro "identidade PCI diverge do registro em $BDF"
            echo "         registrado: $GRAVADO" >&2
            echo "         no sysfs:   $BDF $IDENTIDADE" >&2
            echo "         O registro foi mantido: quem decide se e a mesma placa" >&2
            echo "         e voce, e apagar aqui destruiria a unica prova." >&2
            exit 1
        fi
        if [ -n "$DRIVER" ] && [ "$DRIVER" != "$ALVO" ]; then
            erro "--driver=$DRIVER contradiz o registro, que diz \"$ALVO\""
            echo "         Um dos dois esta errado, e o script nao escolhe por voce." >&2
            exit 1
        fi
        info "driver de origem, pelo registro: $ALVO"
    elif [ "$_APUR_ESTADO" = "ausente" ]; then
        if [ -z "$DRIVER" ]; then
            erro "nao ha registro de origem para $BDF; informe --driver=<nome>"
            echo "         Este script nao adivinha o driver de origem: religar na" >&2
            echo "         familia errada falha com a placa ja fora do kernel." >&2
            echo "         Candidatos:  dpdk-devbind.py --status-dev net" >&2
            exit 1
        fi
        ALVO=$DRIVER
        info "sem registro para $BDF; usando --driver=$ALVO"
    else
        erro "registro $REGISTRO nao apurado: $_APUR_MOTIVO"
        exit 1
    fi

    if [ "$ALVO" = "vfio-pci" ]; then
        erro "vfio-pci nao e driver de origem; --desfazer devolve a placa ao kernel"
        exit 1
    fi

    modprobe "$ALVO" || info "modprobe $ALVO falhou; siga assim se ele for embutido"
    dpdk-devbind.py --bind="$ALVO" "$BDF" || { erro "falha ao religar em $ALVO"; exit 1; }
    if ! apur_link "/sys/bus/pci/devices/$BDF/driver" || [ "${_APUR##*/}" != "$ALVO" ]; then
        erro "retorno nao confirmado: $BDF nao esta em $ALVO depois do devbind"
        echo "         O devbind saiu com sucesso e o sysfs diz outra coisa; o" >&2
        echo "         registro, se havia, foi mantido para nova tentativa." >&2
        exit 1
    fi
    rm -f "$REGISTRO"
    ok "religado em $ALVO; confira com 'ip link'"
    exit 0
fi

if [ "$(modelo_de_driver "$VENDOR")" = "bifurcado" ]; then
    erro "$BDF e Mellanox/mlx5 -- driver bifurcado, nao se binda ao vfio-pci"
    echo "" >&2
    explicar_bifurcado "$BDF" "$VENDOR" >&2
    exit 1
fi
ok "modelo de driver: captura total (vfio-pci) -- bind se aplica"

# A classe PCI tem TRES bytes -- classe base, subclasse e interface de
# programacao --, e nao dois como os identificadores de vendor e device. Ler os
# tres e comparar so o par de cima e deliberado: `0x0200` e "Ethernet
# controller", e o terceiro byte varia entre implementacoes sem mudar o que o
# dispositivo e.
if ! apur_ler "/sys/bus/pci/devices/$BDF/class"; then
    erro "classe PCI nao apurada para $BDF: $_APUR_MOTIVO"
    exit 1
fi
if [[ ! "$_APUR" =~ ^0x[0-9a-fA-F]{6}$ ]]; then
    erro "classe PCI invalida em /sys/bus/pci/devices/$BDF/class: \"$_APUR\""
    exit 1
fi
_ID=${_APUR:0:6}
# 0x0200é é "Ethernet controller" na classificação PCI. Recusar aqui evita
# entregar ao vfio-pci uma controladora de armazenamento por engano de BDF.
case "$_ID" in
    0x0200) : ;;
    *) erro "$BDF nao e uma controladora Ethernet (classe PCI $_ID, esperado 0x0200)"; exit 1 ;;
esac
ok "classe PCI: controladora Ethernet"


# --- TRAVA: grupo IOMMU ------------------------------------------------------
#
# O VFIO opera no granularidade do GRUPO, não do dispositivo: bindar a NIC leva
# todo endpoint do grupo junto. Por isso a NIC precisa ser o único endpoint.
#
# Pontes (`pcieport`, `pci-stub`) não contam, e isto foi checado contra a
# documentação do VFIO no kernel -- ela permite que pontes permaneçam no grupo.
# Este projeto já publicou o contrário, e a correção é esta.
#
# Membro cujo driver NÃO PÔDE SER LIDO conta como endpoint. É a inversão que
# importa: a versão anterior classificava driver vazio junto com as pontes, de
# modo que um membro ilegível AUTORIZAVA a captura.
case "$ENTRADAS" in
    *iommu_group*) : ;;
    *) erro "$BDF esta sem link de grupo IOMMU em /sys -- IOMMU desligado?"
       echo "         Ligue no kernel (intel_iommu=on ou amd_iommu=on). Sem IOMMU o" >&2
       echo "         vfio-pci so funciona em modo no-IOMMU, sem isolamento de DMA." >&2
       exit 1 ;;
esac
if ! apur_link "/sys/bus/pci/devices/$BDF/iommu_group"; then
    erro "grupo IOMMU nao apurado para $BDF: $_APUR_MOTIVO"
    exit 1
fi
GRUPO=${_APUR##*/}
if ! apur_listar "/sys/kernel/iommu_groups/$GRUPO/devices"; then
    erro "grupo IOMMU nao apurado: membros de $GRUPO ilegiveis -- $_APUR_MOTIVO"
    exit 1
fi
MEMBROS=$_APUR
tem_bdf=0
for m in $MEMBROS; do [ "$m" = "$BDF" ] && tem_bdf=1; done
if [ "$tem_bdf" -eq 0 ]; then
    erro "grupo exclusivo nao confirmado: $BDF nao aparece entre os membros de $GRUPO"
    exit 1
fi
if ! apur_link "/sys/kernel/iommu_groups/$GRUPO/devices/$BDF"; then
    erro "grupo IOMMU nao apurado: o membro $BDF de $GRUPO nao resolve -- $_APUR_MOTIVO"
    exit 1
fi
if [ "${_APUR##*/}" != "$BDF" ]; then
    erro "o membro $BDF do grupo $GRUPO nao corresponde ao dispositivo: resolve para $_APUR"
    exit 1
fi
for m in $MEMBROS; do
    [ "$m" = "$BDF" ] && continue
    if apur_link "/sys/bus/pci/devices/$m/driver"; then drv=${_APUR##*/}; else drv=""; fi
    case "$drv" in
        pcieport|pci-stub)
            info "grupo $GRUPO: $m usa '$drv' -- ponte, o VFIO permite" ;;
        *)
            erro "grupo exclusivo nao confirmado: $m esta no grupo $GRUPO com driver '${drv:-NAO APURADO}'"
            echo "         Todo endpoint do grupo IOMMU vai junto para o vfio-pci, e" >&2
            echo "         driver nao apurado nao pode ser tratado como ponte." >&2
            exit 1 ;;
    esac
done
ok "grupo IOMMU $GRUPO tem a NIC como unico endpoint"

# --- TRAVA: rota default, estado e endereços ---------------------------------
#
# `nic_bind_guard` responde a pergunta mais cara do script -- "esta placa
# carrega o seu acesso?" -- e recusa também quando não conseguiu responder.
if ! nic_bind_guard "$BDF"; then
    erro "trava de captura recusou $BDF: $NIC_BIND_REASON"
    echo "         Recusar e o modo de falha seguro: liberar aqui seria afirmar," >&2
    echo "         sem ter apurado, que bindar esta placa nao custa nada." >&2
    exit 1
fi
ok "trava de captura: rotas e estado das interfaces apurados"

# Endereço configurado indica uso, e uso é do operador -- por isso `--forcar`
# passa por cima. Falha ao CONSULTAR não é, e por isso não passa: `--forcar` diz
# "eu sei que tem IP e quero mesmo assim", não "pode seguir sem olhar".
if ! apur_listar "/sys/bus/pci/devices/$BDF/net"; then
    erro "interfaces de $BDF nao apuradas: $_APUR_MOTIVO"
    exit 1
fi
for iface in $_APUR; do
    for fam in -4 -6; do
        if ! apur_cmd ip -o "$fam" addr show dev "$iface"; then
            erro "enderecos $fam de $iface nao apurados: $_APUR_MOTIVO"
            exit 1
        fi
        [ -n "$_APUR" ] || continue
        if [ "$FORCAR" -eq 0 ]; then
            erro "$iface tem endereco $fam configurado; use --forcar se for mesmo isso"
            exit 1
        fi
        info "$iface tem endereco $fam, mas --forcar foi passado"
    done
done
ok "enderecos das interfaces apurados"

# --- TRAVA: existe PMD para esta identidade PCI? -----------------------------
#
# Não é "existe algum driver de rede do DPDK", e sim "algum PMD declara suporte
# a ESTES quatro identificadores". A versão anterior procurava os dois bytes do
# par vendor/device dentro do binário com um grep de bytes, o que casa com
# qualquer coincidência no arquivo -- e, quando não achava, apenas avisava e
# bindava assim mesmo. O resultado era a placa fora do kernel e invisível para
# a aplicação.
#
# A confirmação é delegada a verificar-pmd-pci.py, que lê a tabela declarada
# pelo `dpdk-pmdinfo.py` e recusa por padrão: sem artefato, sem tabela legível
# ou sem casamento completo, não há confirmação.
declare -a ARTEFATOS=()
if [ -n "$PMD" ]; then
    ARTEFATOS=("$PMD")
elif apur_cmd pkg-config --variable=libdir libdpdk; then
    shopt -s nullglob
    ARTEFATOS=("$_APUR"/dpdk/pmds-*/librte_net_*.so)
    shopt -u nullglob
else
    info "libdir do DPDK nao apurado via pkg-config: $_APUR_MOTIVO"
    info "informe o artefato com --pmd=/caminho/librte_net_*.so"
fi
if ! python3 "$(dirname "$0")/verificar-pmd-pci.py" \
        "$VENDOR" "$DEVICE" "$SUBVENDOR" "$SUBDEVICE" ${ARTEFATOS[@]+"${ARTEFATOS[@]}"}; then
    erro "nenhum PMD confirmado para $IDENTIDADE -- o bind funcionaria e nenhuma"
    echo "         aplicacao enxergaria a porta. Recusado antes de tirar do kernel." >&2
    exit 1
fi

# --- TRAVA: de novo, agora que nada mais roda antes do bind ------------------
#
# Entre a primeira passagem e aqui rodaram programas externos, e o intervalo é
# real: o NetworkManager pode subir a interface, e a decisão teria sido tomada
# sobre um estado que não existe mais. Verificar e agir precisam estar colados.
if ! nic_bind_guard "$BDF"; then
    erro "trava de captura recusou $BDF na reconferencia: $NIC_BIND_REASON"
    echo "         O estado mudou entre a primeira verificacao e o bind." >&2
    exit 1
fi
ok "reconferencia da trava de captura: estado inalterado"

# --- registrar a origem, e só então bindar -----------------------------------
#
# A ordem é deliberada. Se o registro fosse gravado DEPOIS, uma falha no meio do
# bind deixaria a placa num estado indefinido e sem ninguém sabendo de onde ela
# veio -- que é o pior resultado possível desta operação.
if apur_link "/sys/bus/pci/devices/$BDF/driver"; then
    ORIGEM=${_APUR##*/}
else
    erro "driver atual de $BDF nao apurado: $_APUR_MOTIVO"
    echo "         Sem saber de onde a placa vem, --desfazer nao teria como" >&2
    echo "         devolve-la. Recusado antes de tirar do kernel." >&2
    exit 1
fi
if [ "$ORIGEM" = "vfio-pci" ]; then
    erro "$BDF ja esta em vfio-pci; nada a fazer"
    exit 1
fi
umask 077
printf '%s %s\n%s\n' "$BDF" "$IDENTIDADE" "$ORIGEM" > "$REGISTRO" || {
    erro "nao consegui gravar $REGISTRO"; exit 1; }
ok "driver de origem registrado em $REGISTRO: $ORIGEM"

echo ""
echo "  Todas as travas passaram. Bindando..."
modprobe vfio-pci || { erro "modprobe vfio-pci falhou; o registro foi mantido"; exit 1; }
dpdk-devbind.py --bind=vfio-pci "$BDF" || { erro "dpdk-devbind falhou; o registro foi mantido"; exit 1; }

# O devbind pode sair 0 sem ter trocado o driver. Confirmar relendo o sysfs é a
# diferença entre "o comando não reclamou" e "a placa está no vfio-pci".
if ! apur_link "/sys/bus/pci/devices/$BDF/driver" || [ "${_APUR##*/}" != "vfio-pci" ]; then
    erro "bind nao confirmado: $BDF nao esta em vfio-pci depois do devbind"
    echo "         O registro foi mantido; desfaca com:  $0 --desfazer $BDF" >&2
    exit 1
fi

echo ""
ok "$BDF agora usa vfio-pci"
echo ""
echo "  Confira:  dpdk-devbind.py --status-dev net"
echo "  Teste:    dpdk-testpmd -l 0-1 -- --total-num-mbufs=2048 --stats-period=1"
echo "  Desfazer: sudo $0 --desfazer $BDF"
echo ""
