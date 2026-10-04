#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Identidade do HARDWARE da maquina, para a procedencia da coleta.
#
# POR QUE ISTO EXISTE
#
# Em 03/10/2026 uma ConnectX-4 Lx entrou na maquina. Nenhuma das dez coletas
# de modo texto arquivadas registra dispositivo PCI algum -- o `ambiente.txt`
# guarda governor, kernel, cmdline, memoria, carga e uptime, e nada sobre o que
# esta no barramento. O arquivo nao sabia responder "a placa estava aqui?", e a
# resposta teve de ser buscada no journal de uma maquina viva.
#
# A consequencia nao era teorica: o `consolidar-isolamento.py` filtra as
# coletas por SESSAO GRAFICA e nada mais. Uma coleta nova entraria nas tabelas
# da §6 junto com as dez de setembro -- maquina com placa somada a maquina sem
# placa, numa mediana so. E a mesma classe do defeito que tirou nove coletas do
# historico em 24/09/2026, quando "os diretorios colidiam no nome e um deles
# carregava a configuracao de memoria errada".
#
# O QUE A IMPRESSAO E, E O QUE ELA DELIBERADAMENTE NAO E
#
# E o conjunto ordenado dos pares `vendor:device` do barramento PCI, COM
# MULTIPLICIDADE -- uma placa de duas portas conta duas vezes --, reduzido a
# sha256. Ela muda quando um dispositivo entra ou sai, que e o evento que
# aconteceu aqui.
#
# Ela NAO carrega o endereco PCI, e isso e escolha: mover uma placa de slot
# nao muda a impressao. O custo esta declarado -- uma troca de slot altera as
# linhas disponiveis e nao seria acusada -- e a razao e que endereco varia em
# barramento com hotplug por motivo que nao e troca de hardware, e falso
# positivo em portao de agregacao custa uma decisao humana a cada coleta.
#
# LE DO SYSFS, E NAO DO `lspci`
#
# Em 03/10/2026 o `uutils tee` reportou `Operation not permitted` onde o kernel
# devolvia `EIO`: o texto da ferramenta mentiu sobre o estado. O sysfs e o
# mecanismo, nao o relato dele -- e nao exige pacote instalado.
PCI_SYSFS="${PCI_SYSFS:-/sys/bus/pci/devices}"

_ids_pci() { # -> um `vendor:device` por linha, ordenado, ou nada
    local d v p
    for d in "$PCI_SYSFS"/*; do
        [ -r "$d/vendor" ] && [ -r "$d/device" ] || continue
        v=$(cat "$d/vendor") || continue
        p=$(cat "$d/device") || continue
        printf '%s:%s\n' "${v#0x}" "${p#0x}"
    done | sort
}

impressao_pci() { # -> 12 digitos hex, ou nao-disponivel
    local ids
    ids=$(_ids_pci)
    # VAZIO NAO VIRA HASH. O sha256 da entrada vazia e um valor valido e
    # estavel, e publicar ele seria afirmar "este hardware" sobre "nao li
    # nada" -- o falso verde que o `comparar-hardware.py` ja teve de recusar
    # pelo nome (`SHA_DO_VAZIO`).
    [ -n "$ids" ] || { printf 'nao-disponivel'; return; }
    printf '%s' "$ids" | sha256sum | cut -c1-12 | tr -d '\n'
}

conta_pci() { # -> quantos dispositivos, ou nao-disponivel
    local ids
    ids=$(_ids_pci)
    [ -n "$ids" ] || { printf 'nao-disponivel'; return; }
    # `printf '%s'` NAO fecha a ultima linha, e `wc -l` conta separadores: a
    # primeira versao devolvia 2 para tres dispositivos. O `\n` do formato e o
    # que faz a conta fechar.
    printf '%s\n' "$ids" | wc -l | tr -d ' \n'
}

resumo_rede() { # -> `15b3:1015 x2 (mlx5_core), ...`, ou nao-disponivel
    local d c v p drv chave saida="" ordem="" n
    declare -A vistos=() drivers=()
    for d in "$PCI_SYSFS"/*; do
        [ -r "$d/class" ] && [ -r "$d/vendor" ] && [ -r "$d/device" ] || continue
        c=$(cat "$d/class") || continue
        # classe 0x02xxxx e controlador de rede; a comparacao e no prefixo
        # porque o terceiro byte distingue ethernet de outras subclasses que
        # perturbam igual.
        case "$c" in 0x02*) ;; *) continue ;; esac
        v=$(cat "$d/vendor"); p=$(cat "$d/device")
        chave="${v#0x}:${p#0x}"
        # O TESTE DO LINK VEM ANTES DO `readlink`. `readlink -f` de caminho
        # inexistente devolve o proprio caminho, e `basename` disso e a palavra
        # `driver` -- a primeira versao publicava `(driver)` para dispositivo
        # SEM driver, que e justamente o estado que importa acusar: a ConnectX
        # presa ao `vfio-pci` por engano, que o topico de NIC proibe.
        if [ -L "$d/driver" ]; then
            drv=$(basename "$(readlink -f "$d/driver")")
        else
            drv="sem-driver"
        fi
        [ -n "$drv" ] || drv="sem-driver"
        if [ -z "${vistos[$chave]:-}" ]; then
            ordem="$ordem $chave"
            drivers[$chave]="$drv"
        fi
        vistos[$chave]=$(( ${vistos[$chave]:-0} + 1 ))
    done
    [ -n "$ordem" ] || { printf 'nenhum'; return; }
    for chave in $(printf '%s\n' $ordem | sort); do
        n=${vistos[$chave]}
        saida="$saida, $chave$([ "$n" -gt 1 ] && echo " x$n") (${drivers[$chave]})"
    done
    printf '%s' "${saida#, }"
}
