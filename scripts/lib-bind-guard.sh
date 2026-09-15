# SPDX-License-Identifier: MIT
# Pré-condições para captura total. Não altera interface, módulo ou driver.
# Requer os acessores de lib-apuracao.sh no shell chamador.
nic_bind_guard() {
    local bdf=$1 base=${2:-/sys/bus/pci/devices} names iface flags family line token previous routes=' '
    NIC_BIND_REASON=''
    if ! apur_listar "$base/$bdf/net"; then
        NIC_BIND_REASON='nao foi possivel enumerar as interfaces do dispositivo'
        return 1
    fi
    names=$_APUR
    for family in -4 -6; do
        if ! apur_cmd ip "$family" route show default; then
            NIC_BIND_REASON='nao foi possivel apurar as rotas default'
            return 1
        fi
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            previous=''; local found=0
            for token in $line; do
                if [ "$previous" = dev ]; then routes="$routes$token "; found=1; fi
                previous=$token
            done
            if [ "$found" -eq 0 ]; then
                NIC_BIND_REASON='rota default sem interface identificavel'; return 1
            fi
        done <<<"$_APUR"
    done
    for iface in $names; do
        if [[ "$routes" == *" $iface "* ]]; then
            NIC_BIND_REASON="interface $iface carrega rota default"; return 1
        fi
        if ! apur_ler "$base/$bdf/net/$iface/flags"; then
            NIC_BIND_REASON="nao foi possivel apurar estado de $iface"; return 1
        fi
        flags=$_APUR
        if [[ ! "$flags" =~ ^0x[0-9a-fA-F]{1,8}$ ]]; then
            NIC_BIND_REASON="flags invalidos para $iface"; return 1
        fi
        if (( (flags & 1) != 0 )); then
            NIC_BIND_REASON="interface $iface esta UP; captura recusada"; return 1
        fi
    done
    return 0
}
