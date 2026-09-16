# SPDX-License-Identifier: MIT
#
# O veredito sobre hugepages, isolado do estado da máquina.
#
# POR QUE ESTA FUNÇÃO RECEBE ARGUMENTOS EM VEZ DE LER O SISTEMA
#
# É a mesma razão de `modelo_de_driver` em `lib-nic.sh`, e ela foi aprendida
# duas vezes neste projeto: uma decisão que lê o ambiente por conta própria só
# pode ser testada no ambiente em que se está.
#
# O caso aqui é literal. Esta máquina tem 1024 hugepages reservadas e nenhum
# ponto `hugetlbfs` gravável, então o veredito correto é "L3 não pode rodar".
# Enquanto a decisão vivia embutida no `check-env.sh`, um mutante que a
# substituísse por "sempre NÃO" era **indistinguível** do código certo — porque
# "sempre NÃO" e "NÃO porque apurei" dão a mesma saída numa máquina em que a
# resposta é NÃO. Foi medido: o mutante sobreviveu.
#
# Recebendo `total` e `ponto_gravavel` como argumentos, os dois ramos passam a
# ser exercitáveis em qualquer lugar, e o teste deixa de depender de ter — ou de
# não ter — hugepages disponíveis.
#
# A REGRA, e ela é uma conjunção:
#
#   páginas reservadas  E  ponto hugetlbfs gravável por este usuário
#
# Nenhuma das duas basta. O caso comum numa máquina de desenvolvimento é a
# primeira sem a segunda -- montagem padrão do systemd é `root:root 755` --, e é
# exatamente o caso que passava calado quando os dois fatos eram relatados
# separados, sem conclusão.

# hugepages_veredito <total_reservado> <ponto_gravavel_ou_vazio>
#   0 = L3 pode rodar        $_HUGE_MOTIVO descreve o que foi encontrado
#   1 = L3 não pode rodar    $_HUGE_MOTIVO diz qual das duas condições faltou
_HUGE_MOTIVO=""
hugepages_veredito() {
    # `${1-}` e NAO `${1:-0}`. A forma com dois-pontos substitui tambem quando o
    # valor e VAZIO, de modo que "nao consegui ler /proc/meminfo" -- que chega
    # como string vazia -- virava ZERO, e o veredito saia como "nao ha hugepage
    # reservada": um FATO NEGATIVO no lugar de uma nao-leitura. E o defeito que
    # esta funcao existe para nao cometer, cometido dentro dela.
    #
    # Foi o autoteste que pegou, na primeira execucao.
    local total=${1-} ponto=${2-}
    # `total` vem de /proc/meminfo e pode chegar vazio ou não numérico se o
    # arquivo não puder ser lido. Tratar isso como zero seria o defeito que este
    # projeto combate -- não apurado virando fato negativo --, então o motivo
    # diz qual dos dois aconteceu.
    if [ -z "$total" ] || ! [ "$total" -ge 0 ] 2>/dev/null; then
        _HUGE_MOTIVO="total de hugepages nao apurado (valor recebido: \"$total\")"
        return 1
    fi
    if [ "$total" -eq 0 ] && [ -z "$ponto" ]; then
        _HUGE_MOTIVO="nao ha hugepage reservada nem ponto hugetlbfs gravavel"
        return 1
    fi
    if [ "$total" -eq 0 ]; then
        _HUGE_MOTIVO="ha ponto gravavel ($ponto) e NENHUMA hugepage reservada"
        return 1
    fi
    if [ -z "$ponto" ]; then
        _HUGE_MOTIVO="ha $total pagina(s) reservada(s) e NENHUM ponto hugetlbfs gravavel; reservada nao e utilizavel"
        return 1
    fi
    _HUGE_MOTIVO="$total pagina(s) reservada(s) e ponto gravavel em $ponto"
    return 0
}
