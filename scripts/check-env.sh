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

# HUGEPAGES: RESERVADA NAO E UTILIZAVEL, e esta distincao ja custou tempo a quem
# leu este script.
#
# Antes de 16/09/2026 ele imprimia os dois fatos SEPARADOS -- "1024 hugepages
# reservadas (1024 livres)" e "/dev/hugepages montado (root:root drwxr-xr-x)" --
# e nunca tirava a conclusao. As duas linhas pareciam boas, o leitor seguia em
# frente, e so descobria o problema quando os testes L3 PULAVAM, muito depois.
#
# Para o DPDK multiprocesso e preciso das duas coisas AO MESMO TEMPO: paginas
# reservadas E um ponto hugetlbfs em que ESTE usuario possa escrever. Montagem
# padrao do systemd e root:root 755, entao o caso comum e "reservadas e
# inutilizaveis" -- exatamente o que passava calado.
# shellcheck source=lib-hugepages.sh
. "$(dirname "$0")/lib-hugepages.sh"

echo "Hugepages (os topicos iniciais rodam com --no-huge; L3 exige de verdade):"
total=$(awk '/HugePages_Total/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
livres=$(awk '/HugePages_Free/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
tam=$(awk '/Hugepagesize/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
if [ "${total:-0}" -gt 0 ]; then
    ok "$total hugepages de ${tam} kB reservadas ($livres livres)"
else
    info "nenhuma hugepage reservada"
fi

# Todos os pontos hugetlbfs montados, e quem pode escrever em cada um.
ponto_gravavel=""
while read -r ponto; do
    [ -n "$ponto" ] || continue
    if [ -w "$ponto" ]; then
        ponto_gravavel=$ponto
        ok "$ponto gravavel por $(id -un) ($(stat -c '%U:%G %A' "$ponto"))"
    else
        info "$ponto montado e NAO gravavel por $(id -un) ($(stat -c '%U:%G %A' "$ponto"))"
    fi
done <<EOF
$(mount 2>/dev/null | awk '$5 == "hugetlbfs" { print $3 }')
EOF

# O VEREDITO, que e o que faltava: as duas condicoes juntas.
#
# A DECISAO vive em lib-hugepages.sh e recebe o estado como ARGUMENTO, em vez de
# ler o sistema. Ver o comentario de la: embutida aqui, ela era intestavel numa
# maquina sem hugepage utilizavel -- "sempre NAO" e "NAO porque apurei" davam a
# mesma saida, e um mutante que trocasse uma pela outra sobrevivia.
if hugepages_veredito "${total:-0}" "$ponto_gravavel"; then
    ok "L3 pode rodar: $_HUGE_MOTIVO"
    [ "$ponto_gravavel" = "/dev/hugepages" ] || \
        info "aponte os testes para ele: export DPDK_ACADEMY_HUGE_DIR=$ponto_gravavel"
else
    info "L3 NAO pode rodar: $_HUGE_MOTIVO"
    info "  Corrija com UM comando, que pede privilegio UMA vez:"
    info "      sudo ./scripts/preparar-hugepages.sh"
    info "  Depois dele, nenhuma execucao precisa de root: o ponto passa a ser seu."
    info "  Sem isso, os testes L3 PULAM (codigo 77) -- nao falham, e nao mentem."
fi

# DIRETORIO DE RUNTIME DA EAL, e este aviso custou uma suite inteira vermelha.
#
# Cada execucao com `--file-prefix` novo cria um diretorio sob
# $XDG_RUNTIME_DIR/dpdk com os arquivos `fbarray`, que chegam a dezenas de MB. A
# suite limpa os seus; execucao ad-hoc, nao. Em 16/09/2026 umas centenas de
# execucoes manuais deixaram 847 diretorios e 1,5 GB -- o tamanho INTEIRO do
# tmpfs de /run/user.
#
# O sintoma nao aponta para a causa: a EAL morre com SIGBUS (codigo 135) ao
# mapear o fbarray, inclusive com --no-huge, e a mensagem fala de barramento, nao
# de disco cheio. Nove testes falharam ao mesmo tempo e pareciam regressao de
# codigo.
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
if [ -d "$runtime_dir" ]; then
    uso=$(df --output=pcent "$runtime_dir" 2>/dev/null | tail -1 | tr -dc '0-9')
    sobras=$(find "$runtime_dir/dpdk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    if [ "${uso:-0}" -ge 80 ]; then
        info "$runtime_dir em ${uso}% -- a EAL pode morrer com SIGBUS ao mapear fbarray"
        info "  $sobras diretorio(s) de runtime acumulado(s). Com nenhum DPDK rodando:"
        info "      rm -rf $runtime_dir/dpdk/*"
    elif [ "${sobras:-0}" -gt 20 ]; then
        info "$sobras diretorios de runtime em $runtime_dir/dpdk (${uso:-?}% usado)"
        info "  sobras de execucoes com --file-prefix proprio; limpe se crescer"
    else
        ok "$runtime_dir com folga (${uso:-?}% usado, $sobras diretorio(s) de runtime)"
    fi
fi

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
