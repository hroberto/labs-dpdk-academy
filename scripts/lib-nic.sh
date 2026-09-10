# SPDX-License-Identifier: MIT
#
# Classificação do MODELO DE DRIVER de uma NIC, para o DPDK.
#
# POR QUE ISTO EXISTE
#
# `scripts/preparar-nic.sh` e `scripts/diagnostico-nic.sh` foram escritos
# supondo que preparar uma NIC para o DPDK significa TIRÁ-LA DO KERNEL e
# bindá-la ao `vfio-pci`. Isso vale para a maioria das placas, e é falso para
# uma família inteira -- a que este projeto vai usar a seguir.
#
# OS DOIS MODELOS, e a diferença não é detalhe de configuração:
#
#   CAPTURA TOTAL (vfio-pci) -- Intel, Realtek, Broadcom e a maioria. O
#   dispositivo é desligado do driver do kernel e entregue ao user-space. A
#   interface DESAPARECE do `ip link`. O DPDK passa a falar com o hardware
#   diretamente, e o kernel não vê mais nada. É o modelo que os dois scripts
#   já tratavam.
#
#   BIFURCADO (mlx4, mlx5) -- Mellanox/NVIDIA. A documentação do DPDK diz que
#   "the same device is managed by both kernel and DPDK drivers": kernel e DPDK
#   convivem no MESMO dispositivo. A interface CONTINUA no `ip link`, o
#   `dpdk-devbind.py` não é usado, e bindar ao `vfio-pci` seria erro -- tiraria
#   do PMD justamente o driver de kernel de que ele depende. O que o PMD exige
#   no lugar é a pilha de userspace do RDMA (`rdma-core`), e o isolamento entre
#   os dois lados é configurado em tempo de execução, com `rte_flow_isolate()`.
#
# COMO A CLASSIFICAÇÃO É FEITA
#
# Pelo *vendor ID* do PCI, que é o critério estável: `0x15b3` é
# Mellanox/NVIDIA, e toda a linha ConnectX usa o modelo bifurcado. Não se usa o
# nome do driver do kernel, que muda por distribuição e por versão, nem o nome
# da interface, que o usuário renomeia.
#
# Esta função é o único lugar do projeto que sabe dessa distinção. Se aparecer
# outra família bifurcada, ela entra aqui e os dois scripts herdam.

# Vendors cujos PMDs são bifurcados. Um por linha, com o nome para a mensagem.
_VENDOR_BIFURCADO_15b3="Mellanox/NVIDIA (ConnectX)"

# modelo_de_driver <vendor_id_hex>  ->  "bifurcado" | "captura"
#
# Recebe o vendor em vez de ler o sysfs para ser TESTÁVEL sem o hardware: os
# testes passam IDs conhecidos e conferem a classificação. Sem isso, o caminho
# da Mellanox só seria exercitado no dia em que a placa chegasse -- e é
# exatamente o caminho que não pode estar errado nesse dia.
modelo_de_driver() {
    case "${1,,}" in
        0x15b3|15b3) printf 'bifurcado' ;;
        *)           printf 'captura' ;;
    esac
}

# nome_do_vendor <vendor_id_hex> -> descrição legível, ou vazio
nome_do_vendor() {
    case "${1,,}" in
        0x15b3|15b3) printf '%s' "$_VENDOR_BIFURCADO_15b3" ;;
        *)           printf '' ;;
    esac
}

# vendor_de <bdf> -> "0x15b3", ou vazio se o dispositivo não existir
vendor_de() {
    cat "/sys/bus/pci/devices/$1/vendor" 2>/dev/null || printf ''
}

# rdma_core_ok -> 0 se a pilha de userspace do RDMA está completa
#
# O PMD mlx5 depende de `rdma-core`. Faltando, o dispositivo simplesmente não é
# probado, e a mensagem do DPDK não aponta para a causa -- por isso a
# verificação é explícita e vem ANTES de tentar.
rdma_core_ok() {
    local faltando=""
    local l
    for l in libibverbs.so.1 libmlx5.so.1 librdmacm.so.1; do
        ldconfig -p 2>/dev/null | grep -q "$l" || faltando="$faltando $l"
    done
    _RDMA_FALTANDO="${faltando# }"
    [ -z "$_RDMA_FALTANDO" ]
}

# rdma_core_faltando -> lista do que faltou na última chamada de rdma_core_ok
rdma_core_faltando() { printf '%s' "${_RDMA_FALTANDO:-}"; }

# explicar_bifurcado <bdf> <vendor> -- por que não se binda, e o que fazer.
explicar_bifurcado() {
    local bdf=$1 vendor=$2
    echo "  Este dispositivo usa driver BIFURCADO -- $(nome_do_vendor "$vendor")."
    echo ""
    echo "  Kernel e DPDK gerenciam o MESMO dispositivo. A documentacao do DPDK:"
    echo "    \"The same device is managed by both kernel and DPDK drivers.\""
    echo ""
    echo "  Consequencias, e a primeira surpreende:"
    echo "    - NAO se binda ao vfio-pci. Fazer isso tira do PMD o driver de"
    echo "      kernel de que ele depende."
    echo "    - a interface CONTINUA no 'ip link'. Isso e esperado, nao falha."
    echo "    - dpdk-devbind.py nao participa."
    echo "    - o PMD exige rdma-core no user-space."
    echo ""
    if rdma_core_ok; then
        echo "  rdma-core: completo."
    else
        echo "  rdma-core: FALTANDO ->$(rdma_core_faltando)"
        echo "    Debian/Ubuntu: sudo apt install rdma-core libibverbs1 ibverbs-providers"
    fi
    echo ""
    echo "  Para usar, basta rodar a aplicacao apontando o dispositivo:"
    echo "    dpdk-testpmd -l 0-1 -a $bdf -- -i"
    echo ""
    echo "  Confira antes que o RDMA enxerga a placa:  ibv_devinfo"
}
