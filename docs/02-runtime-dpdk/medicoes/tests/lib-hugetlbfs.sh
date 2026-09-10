# SPDX-License-Identifier: MIT
#
# Descoberta do hugetlbfs para os testes L3 de multiprocesso.
#
# POR QUE ISTO EXISTE
#
# Os testes L3 deste módulo exigem hugetlbfs gravável, e antes desta função eles
# só o encontravam se o estudante exportasse DPDK_ACADEMY_HUGE_DIR à mão. O
# resultado prático foi o pior possível: numa máquina com `/mnt/huge-academia`
# montado e gravável — exatamente o que `scripts/preparar-hugepages.sh` cria —
# os dois testes saíam com 77 e a suíte reportava PULADO, deixando DEZESSEIS
# asserções sem cobertura, num ambiente que podia executá-las.
#
# Pular por falta de requisito é correto. Pular por falta de uma variável de
# ambiente, tendo o requisito disponível, é cobertura perdida em silêncio — e
# silêncio é justamente o que a suíte deste projeto tenta eliminar.
#
# A ORDEM DE BUSCA, e o motivo de cada passo:
#
#   1. DPDK_ACADEMY_HUGE_DIR, se já definido. Escolha explícita vence detecção;
#      é como o estudante aponta para uma montagem específica.
#   2. Qualquer hugetlbfs em /proc/mounts que o usuário consiga escrever. Cobre
#      /mnt/huge-academia, /dev/hugepages quando as permissões permitem, e
#      qualquer montagem própria.
#
# Não monta nada e não pede privilégio: montar é trabalho de
# `scripts/preparar-hugepages.sh`, que é explícito sobre alterar o host.

# Ecoa o diretório utilizável, ou string vazia. Nunca falha.
descobrir_hugetlbfs() {
    if [ -n "${DPDK_ACADEMY_HUGE_DIR:-}" ] && [ -w "${DPDK_ACADEMY_HUGE_DIR}" ]; then
        printf '%s' "$DPDK_ACADEMY_HUGE_DIR"
        return 0
    fi
    # Campo 2 de /proc/mounts é o ponto de montagem; campo 3, o tipo.
    while read -r _ ponto tipo _; do
        [ "$tipo" = "hugetlbfs" ] || continue
        # -w sozinho responde "sim" para root mesmo sem permissão real; estes
        # testes não rodam como root, então -w basta e mantém a função simples.
        if [ -w "$ponto" ]; then
            printf '%s' "$ponto"
            return 0
        fi
    done < /proc/mounts
    printf ''
}
