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
    if [ -n "${DPDK_ACADEMY_HUGE_DIR:-}" ] && gravavel_de_fato "${DPDK_ACADEMY_HUGE_DIR}"; then
        printf '%s' "$DPDK_ACADEMY_HUGE_DIR"
        return 0
    fi
    # Campo 2 de /proc/mounts é o ponto de montagem; campo 3, o tipo.
    while read -r _ ponto tipo _; do
        [ "$tipo" = "hugetlbfs" ] || continue
        if gravavel_de_fato "$ponto"; then
            printf '%s' "$ponto"
            return 0
        fi
    done < /proc/mounts
    printf ''
}

# Escreve de verdade, em vez de perguntar se e possivel escrever.
#
# POR QUE NAO `-w`. O teste `-w` responde SIM para root em qualquer diretorio,
# mesmo sem permissao real -- e a versao anterior desta biblioteca sabia disso,
# documentando que "estes testes nao rodam como root, entao -w basta". A
# suposicao e falsa toda vez que alguem executa `sudo ./scripts/test-all.sh`:
# ali o pulo deixa de acontecer, os testes rodam num ambiente que a precondicao
# aprovou por engano, e a falha resultante parece defeito do projeto.
#
# Criar e remover um arquivo responde a mesma pergunta sem depender do uid.
gravavel_de_fato() {
    local ponto=$1 alvo="$1/.academia-escrita-$$"
    [ -d "$ponto" ] || return 1
    # Subshell: `2>/dev/null` no comando NAO cala a mensagem que o shell emite
    # quando o proprio redirecionamento falha. Redirecionar o subshell inteiro
    # cala a origem certa.
    ( : > "$alvo" ) 2>/dev/null || return 1
    rm -f -- "$alvo"
    return 0
}

# Pre-requisitos observaveis ANTES de executar a aplicacao. Uma falha da EAL
# depois desta verificacao e FAIL: nao se infere falta de hardware pelo log.
#
# Confere tres coisas, e as tres importam: que o diretorio aceite escrita deste
# usuario, que ele seja mesmo hugetlbfs (e nao um diretorio comum apontado por
# engano na variavel de ambiente), e que haja pagina livre do tamanho da
# montagem -- montagem sem pagina livre falha na EAL, nao aqui.
hugetlbfs_disponivel() {
    local ponto=$1 tamanho livres
    [ -n "$ponto" ] && gravavel_de_fato "$ponto" || return 1
    [ "$(stat -f -c %T -- "$ponto" 2>/dev/null)" = hugetlbfs ] || return 1
    tamanho=$(stat -f -c %S -- "$ponto") || return 1
    livres="/sys/kernel/mm/hugepages/hugepages-$((tamanho / 1024))kB/free_hugepages"
    [ -r "$livres" ] && [ "$(cat "$livres")" -gt 0 ]
}

# Confere que a limpeza do teste FUNCIONOU, e nao apenas que ela rodou.
#
# POR QUE ISTO EXISTE
#
# Ate 21/09/2026 o `l3_multiprocesso.sh` removia `/dev/hugepages/${PREFIXO}*`
# com o caminho fixo no codigo, enquanto passava `--huge-dir` para outro lugar.
# Cada execucao vazava uma hugepage de 2 MB, e a suite ficava VERDE: nada
# conferia o resultado da limpeza.
#
# Corrigir a remocao nao resolve o problema de fundo. Uma limpeza sem
# verificacao e indistinguivel de uma limpeza que nao funciona -- o mesmo
# argumento que a secao 5.1 do topico de mempool faz sobre asserçao que nunca
# falha. Esta funcao e a verificacao, e o teste negativo dela esta no
# `l1_multiprocesso.sh`.
#
# Ecoa cada residuo encontrado e devolve 1 se houver algum.
conferir_sem_residuo() { # <prefixo>
    local prefixo=$1 achou=0 d f
    [ -n "$prefixo" ] || return 0
    for d in /dev/hugepages "${DPDK_ACADEMY_HUGE_DIR:-}" \
             "${XDG_RUNTIME_DIR:-/var/run}/dpdk"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        for f in "$d/$prefixo"*; do
            [ -e "$f" ] || continue
            echo "  FALHA - a limpeza deixou residuo: $f"
            achou=1
        done
    done
    return "$achou"
}
