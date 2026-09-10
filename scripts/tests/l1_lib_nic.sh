#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L1 de scripts/lib-nic.sh — a classificação do modelo de driver.
#
# POR QUE ESTE TESTE EXISTE, E POR QUE E L1
#
# O caminho da Mellanox e o unico do projeto que nao pode ser exercitado pelo
# hardware disponivel: a placa chega em semanas. Sem este teste, a primeira vez
# que a classificacao rodaria de verdade seria no dia em que a ConnectX-4 Lx
# fosse instalada -- e um erro ali significaria bindar ao vfio-pci uma placa que
# nao pode ser bindada, quebrando o dispositivo dos dois lados.
#
# Por isso `modelo_de_driver` recebe o vendor como ARGUMENTO em vez de ler o
# sysfs: assim a decisao e testavel sem o dispositivo. E logica pura, roda em
# milissegundos, e nao precisa da EAL -- a definicao de L1 neste projeto.
#
# O que este teste NAO prova: que o PMD mlx5 funciona. Isso exige a placa, e
# esta registrado como pendente no modulo de RX/TX. O que ele prova e que a
# DECISAO de nao bindar sera tomada corretamente.
set -u

# shellcheck source=../lib-nic.sh
. "$(dirname "$0")/../lib-nic.sh"

falhas=0
check() {
    if [ "$2" = "$3" ]; then
        echo "  ok    - $1"
    else
        echo "  FALHA - $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}
contem() {
    if grep -qi -- "$2" <<<"$3"; then
        echo "  ok    - $1"
    else
        echo "  FALHA - $1 (nao encontrou '$2')"
        falhas=$((falhas + 1))
    fi
}

echo "== L1: classificacao do modelo de driver =="

# --- o caso que importa: Mellanox nunca pode ser classificada como captura ---
check "0x15b3 (Mellanox) e bifurcado"        "$(modelo_de_driver 0x15b3)" "bifurcado"
check "15b3 sem prefixo tambem"              "$(modelo_de_driver 15b3)"   "bifurcado"
check "0x15B3 maiusculo tambem"              "$(modelo_de_driver 0x15B3)" "bifurcado"

# --- as placas desta maquina, e outras comuns, sao captura total ------------
check "0x10ec (Realtek) e captura"           "$(modelo_de_driver 0x10ec)" "captura"
check "0x8086 (Intel) e captura"             "$(modelo_de_driver 0x8086)" "captura"
check "0x14c3 (MediaTek) e captura"          "$(modelo_de_driver 0x14c3)" "captura"
check "vendor desconhecido cai em captura"   "$(modelo_de_driver 0xdead)" "captura"
check "vendor vazio cai em captura"          "$(modelo_de_driver '')"     "captura"

# --- nome legivel, usado nas mensagens --------------------------------------
contem "0x15b3 tem nome legivel" "ConnectX" "$(nome_do_vendor 0x15b3)"
check  "vendor comum nao tem nome especial" "$(nome_do_vendor 0x10ec)" ""

# --- a explicacao precisa dizer as tres coisas que evitam o erro ------------
explicacao=$(explicar_bifurcado 0000:01:00.0 0x15b3 2>&1)
contem "explicacao diz que NAO se binda ao vfio-pci" "vfio-pci" "$explicacao"
contem "explicacao cita rdma-core"                   "rdma-core" "$explicacao"
contem "explicacao avisa que a interface continua"   "continua"  "$explicacao"
contem "explicacao da o comando de uso"              "dpdk-testpmd" "$explicacao"

# --- vendor_de num dispositivo inexistente nao pode explodir ---------------
check "vendor_de de BDF inexistente devolve vazio" "$(vendor_de 0000:99:99.9)" ""

# --- rdma_core_ok reporta o que falta, sem falhar o teste -------------------
if rdma_core_ok; then
    echo "  info  - rdma-core completo nesta maquina"
else
    echo "  info  - rdma-core incompleto:$(rdma_core_faltando) (esperado ate a placa chegar)"
fi

echo ""
if [ $falhas -eq 0 ]; then
    echo "L1: todos os testes passaram"
else
    echo "L1: $falhas falha(s)"
    exit 1
fi
