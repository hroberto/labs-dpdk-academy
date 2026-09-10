#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verifica o ambiente necessário para a trilha DPDK Academy e informa o que falta.
# Uso: scripts/check-env.sh
set -u
ok()   { printf '  ok    - %s\n' "$1"; }
falta(){ printf '  FALTA - %s\n' "$1"; faltas=$((faltas + 1)); }
info() { printf '  info  - %s\n' "$1"; }
faltas=0

echo "Compiladores e ferramentas:"
for t in gcc g++ make pkg-config; do
    if command -v "$t" >/dev/null 2>&1; then ok "$t ($("$t" --version 2>/dev/null | head -1))"; else falta "$t"; fi
done
command -v clang++ >/dev/null 2>&1 && info "clang++ disponivel ($(clang++ --version | head -1))"

echo "Suporte a C++23:"
if printf '#include <print>\n#include <expected>\nint main(){std::println("ok");}\n' | g++ -std=c++23 -x c++ - -o /dev/null 2>/dev/null; then
    ok "g++ compila <print> e <expected> com -std=c++23"
else
    falta "g++ com suporte a C++23 (<print>, <expected>): use GCC 14+ ou Clang 18+"
fi

echo "DPDK:"
if pkg-config --exists libdpdk; then
    ok "libdpdk $(pkg-config --modversion libdpdk) encontrada pelo pkg-config"
else
    falta "libdpdk no pkg-config (instale dpdk-dev / dpdk-devel ou ajuste PKG_CONFIG_PATH)"
fi
for t in dpdk-testpmd dpdk-devbind.py dpdk-hugepages.py; do
    if command -v "$t" >/dev/null 2>&1; then ok "$t"; else info "$t nao encontrado (opcional para os topicos iniciais)"; fi
done

echo "Hugepages (opcionais: os topicos iniciais rodam com --no-huge):"
total=$(awk '/HugePages_Total/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
livres=$(awk '/HugePages_Free/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
tam=$(awk '/Hugepagesize/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
if [ "${total:-0}" -gt 0 ]; then ok "$total hugepages de ${tam} kB reservadas ($livres livres)"; else info "nenhuma hugepage reservada (rode scripts/preparar-hugepages.sh)"; fi
[ -d /dev/hugepages ] && info "/dev/hugepages montado ($(stat -c '%U:%G %A' /dev/hugepages))"

echo "Drivers para NIC fisica (opcionais ate os topicos de RX/TX):"
if lsmod 2>/dev/null | grep -q '^vfio_pci'; then ok "vfio-pci carregado"; else info "vfio-pci nao carregado (modprobe vfio-pci quando for usar uma NIC real)"; fi

# Duas familias de driver, duas pilhas de dependencia. A de captura total
# (vfio-pci) ja e verificada acima; esta e a bifurcada, que o mlx5 exige e que
# nao tem nada a ver com vfio. Ver scripts/lib-nic.sh.
echo "Pilha RDMA (necessaria so para NIC bifurcada: Mellanox/NVIDIA):"
# shellcheck source=lib-nic.sh
. "$(dirname "$0")/lib-nic.sh"
if rdma_core_ok; then
    ok "rdma-core completo"
else
    info "faltando:$(rdma_core_faltando) (instale antes de usar uma ConnectX)"
fi
if ls /sys/bus/pci/devices/*/vendor >/dev/null 2>&1 && grep -lq '0x15b3' /sys/bus/pci/devices/*/vendor 2>/dev/null; then
    ok "ha NIC Mellanox/NVIDIA nesta maquina"
else
    info "nenhuma NIC Mellanox/NVIDIA presente"
fi

# O README lista estas quatro como "ferramentas de qualidade". Elas nao sao
# necessarias para compilar nem para rodar a trilha -- por isso entram como
# 'info', e nao como 'FALTA' -- mas antes desta secao o script dizia "Ambiente
# pronto" numa maquina onde NENHUMA delas estava instalada. Um diagnostico que
# so verifica o que ja funciona nao e diagnostico.
echo "Ferramentas de qualidade (opcionais ate a etapa de benchmarking e CI):"
for t in clang-format clang-tidy perf; do
    # Distribuicoes empacotam clang-format-19, clang-tidy-21 etc. sem o nome
    # generico: procurar so o nome curto reportaria ausencia onde ha ferramenta.
    achado=$(command -v "$t" 2>/dev/null || compgen -c "$t-" 2>/dev/null | sort -V | tail -1)
    if [ -n "$achado" ]; then ok "$t ($achado)"; else info "$t nao encontrado"; fi
done
if printf 'int main(){return 0;}\n' | gcc -fsanitize=address,undefined -x c - -o /dev/null 2>/dev/null; then
    ok "sanitizers (ASan/UBSan) disponiveis no gcc"
else
    info "sanitizers indisponiveis no gcc (instale libasan/libubsan)"
fi

echo
if [ $faltas -eq 0 ]; then
    echo "Ambiente pronto para a trilha."
else
    echo "$faltas item(ns) faltando. Veja os requisitos em README.md."
    exit 1
fi
