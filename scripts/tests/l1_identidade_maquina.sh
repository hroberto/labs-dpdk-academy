#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# L1 da identidade de hardware da maquina.
#
# A FIXTURE E UM SYSFS DE MENTIRA, e nao a maquina. Um teste que lesse
# `/sys/bus/pci/devices` passaria nesta maquina e nao exercitaria nada: a
# pergunta e se a impressao MUDA quando o hardware muda, e isso nao se testa
# sem controlar o hardware. `PCI_SYSFS` existe para isso.
set -euo pipefail
raiz=$(cd "$(dirname "$0")/../.." && pwd)
fonte="$raiz/ferramental/qualidade/identidade-maquina.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }
falhas=0
total=0

conferir() { # <descricao> <obtido> <esperado>
    total=$((total + 1))
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}
diferente() { # <descricao> <a> <b>
    total=$((total + 1))
    if [ "$2" = "$3" ]; then
        echo "  FALHOU: $1 (os dois deram '$2')"
        falhas=$((falhas + 1))
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT

dispositivo() { # <raiz> <endereco> <vendor> <device> [<classe>] [<driver>]
    local d="$1/$2"
    mkdir -p "$d"
    printf '0x%s\n' "$3" > "$d/vendor"
    printf '0x%s\n' "$4" > "$d/device"
    printf '0x%s\n' "${5:-010802}" > "$d/class"
    if [ -n "${6:-}" ]; then
        mkdir -p "$1/.drivers/$6"
        ln -s "../.drivers/$6" "$d/driver"
    fi
}

# --- a maquina de setembro: sem a ConnectX --------------------------------
sem="$tmp/sem"; mkdir -p "$sem"
dispositivo "$sem" 0000:02:00.0 144d a80a 010802 nvme
dispositivo "$sem" 0000:08:00.0 10ec 8125 020000 r8169
dispositivo "$sem" 0000:08:00.1 14c3 0717 028000 mt7925e

# --- a maquina de outubro: a MESMA, mais a placa de duas portas -----------
com="$tmp/com"; cp -r "$sem" "$com"
dispositivo "$com" 0000:01:00.0 15b3 1015 020000 mlx5_core
dispositivo "$com" 0000:01:00.1 15b3 1015 020000 mlx5_core

imp() { PCI_SYSFS="$1" bash -c "set -u; source '$fonte'; $2"; }

# ---- 1. a impressao muda quando a placa entra ---------------------------
#
# E a assercao central: e por ela que o agregador consegue recusar somar as
# duas eras. Se ela nao mudar, nada do resto tem valor.
a=$(imp "$sem" 'impressao_pci'); b=$(imp "$com" 'impressao_pci')
diferente "a impressao muda quando a placa entra" "$a" "$b"
conferir "e tem 12 digitos hex" "$(printf '%s' "$a" | grep -cE '^[0-9a-f]{12}$')" "1"

# ---- 2. e NAO muda quando nada muda ------------------------------------
#
# Portao que acusa diferenca em hardware igual obriga uma decisao humana a
# cada coleta, e decisao que se repete sem conteudo deixa de ser lida.
conferir "a mesma maquina da a mesma impressao" "$(imp "$sem" 'impressao_pci')" "$a"

# ---- 3. MULTIPLICIDADE CONTA ------------------------------------------
#
# Uma placa de duas portas sao dois dispositivos no barramento. Se a impressao
# descartasse repetidos, trocar uma placa de uma porta por uma de duas -- que
# dobra os vetores de interrupcao -- nao seria acusado.
uma="$tmp/uma"; cp -r "$sem" "$uma"
dispositivo "$uma" 0000:01:00.0 15b3 1015 020000 mlx5_core
diferente "uma porta nao da a mesma impressao que duas" \
    "$(imp "$uma" 'impressao_pci')" "$b"

# ---- 4. a ordem de leitura nao entra na impressao ---------------------
#
# O glob do shell e ordenado, mas a impressao nao pode DEPENDER disso: basta um
# endereco PCI diferente para a ordem mudar sem o hardware mudar.
outro="$tmp/outro"; mkdir -p "$outro"
dispositivo "$outro" 0000:ff:00.0 10ec 8125 020000 r8169
dispositivo "$outro" 0000:00:01.0 144d a80a 010802 nvme
dispositivo "$outro" 0000:7f:00.0 14c3 0717 028000 mt7925e
conferir "enderecos em outra ordem dao a mesma impressao" \
    "$(imp "$outro" 'impressao_pci')" "$a"

# ---- 5. SYSFS VAZIO NAO VIRA HASH -------------------------------------
#
# O sha256 do vazio e um valor valido e estavel. Publicar ele seria afirmar
# "este hardware" sobre "nao li nada" -- o falso verde que o
# `comparar-hardware.py` ja recusou pelo nome `SHA_DO_VAZIO`.
vazio="$tmp/vazio"; mkdir -p "$vazio"
conferir "sysfs vazio da nao-disponivel" "$(imp "$vazio" 'impressao_pci')" "nao-disponivel"
conferir "e a contagem tambem" "$(imp "$vazio" 'conta_pci')" "nao-disponivel"
conferir "caminho inexistente da nao-disponivel" \
    "$(imp "$tmp/nao-existe" 'impressao_pci')" "nao-disponivel"

# ---- 6. dispositivo sem vendor legivel nao entra calado ----------------
#
# Diretorio sem `vendor` e pulado -- mas se TODOS forem assim o resultado e
# ausencia, e nao uma impressao de subconjunto apresentada como do conjunto.
quebrado="$tmp/quebrado"; mkdir -p "$quebrado/0000:01:00.0"
conferir "so diretorio ilegivel da nao-disponivel" \
    "$(imp "$quebrado" 'impressao_pci')" "nao-disponivel"

# ---- 7. a contagem conta dispositivos, nao placas ---------------------
conferir "contagem sem a placa" "$(imp "$sem" 'conta_pci')" "3"
conferir "contagem com a placa de duas portas" "$(imp "$com" 'conta_pci')" "5"

# ---- 8. o resumo de rede e legivel e so traz classe 0x02 --------------
#
# A linha existe para quem LE o `ambiente.txt`: a impressao diz QUE mudou, e o
# resumo diz O QUE. O nvme fica fora porque nao e controlador de rede.
# A multiplicidade aparece so quando passa de um: `x1` em toda linha e ruido
# que o leitor aprende a ignorar, e marca que se ignora deixa de marcar.
conferir "o resumo traz as tres de rede, e marca a de duas portas" \
    "$(imp "$com" 'resumo_rede')" \
    "10ec:8125 (r8169), 14c3:0717 (mt7925e), 15b3:1015 x2 (mlx5_core)"
conferir "o nvme nao aparece no resumo de rede" \
    "$(imp "$com" 'resumo_rede' | grep -c 144d)" "0"
conferir "maquina sem rede diz nenhum" \
    "$(imp "$tmp/vazio" 'resumo_rede')" "nenhum"

# ---- 9. driver ausente e dito, nao omitido ---------------------------
#
# Placa presente e sem driver e um estado real -- e exatamente o que se veria
# se alguem prendesse a ConnectX ao `vfio-pci` por engano, que o topico de NIC
# proibe. Omitir o campo faria isso passar como igual.
sdrv="$tmp/sdrv"; mkdir -p "$sdrv"
dispositivo "$sdrv" 0000:01:00.0 15b3 1015 020000
conferir "sem driver aparece como sem-driver" \
    "$(imp "$sdrv" 'resumo_rede')" "15b3:1015 (sem-driver)"

if [ "$falhas" -gt 0 ]; then
    echo "FALHA: $falhas de $total assercao(oes)"
    exit 1
fi
echo "  ok: $total assercoes; a impressao de hardware muda com a placa,"
echo "      nao muda sem ela, e ausencia nao vira hash"
