# SPDX-License-Identifier: MIT
#
# Decisões do diagnóstico de AF_XDP zero-copy, separadas de quem as coleta.
#
# POR QUE ISTO EXISTE
#
# `scripts/xdp-zerocopy.sh` tinha o veredito inteiro escrito DENTRO do ramo que
# exige root. Medido, como uid 1000: a heurística do módulo acertava
# ("simbolos xdp_ 0 ... baixa probabilidade de suporte") e mesmo assim o
# veredito saía "Resultado inconclusivo", porque as variáveis `capacidade` e
# `basico` só recebiam valor depois de `xdp-loader features`, que aborta sem
# root. O script descartava uma conclusão que ele já tinha em mãos, e o ramo
# severo -- o que descreve exatamente a placa desta máquina -- nunca podia
# disparar. Pior: nenhuma linha daquele ramo era executável sem privilégio,
# então ele nunca foi exercitado por ninguém.
#
# A separação aqui segue a mesma regra de `scripts/lib-nic.sh`: DECISÃO recebe
# tudo por argumento e é testável sem hardware; COLETA toca netlink, sysfs e
# `nm`, e não decide nada. Sem isso, o caminho "a placa anuncia zero-copy" só
# seria exercitado no dia em que uma NIC Intel ou Mellanox chegasse -- e é
# justamente o caminho que não pode estar errado nesse dia.
#
# O VOCABULÁRIO ÚNICO DE VEREDITO
#
# Há duas fontes para a mesma pergunta (netlink e `xdp-loader features`), e
# elas respondem em formatos diferentes: a primeira devolve uma bitmask, a
# segunda devolve linhas "NOME:<espaços>yes|no". As duas são traduzidas para as
# MESMAS classes antes de qualquer decisão:
#
#   zero-copy      NETDEV_XDP_ACT_XSK_ZEROCOPY anunciada
#   nativo-sem-zc  tem XDP nativo (BASIC), não tem zero-copy
#   sem-xdp        nem BASIC -- só resta o modo genérico (SKB), com cópia
#   sem-atributo   o kernel respondeu, e não anunciou xdp_features
#   inconclusivo   nenhuma fonte respondeu; o motivo tem que ser dito
#
# "inconclusivo" e "sem-xdp" são coisas OPOSTAS, e confundi-las foi o defeito
# original: falta de privilégio virava "a placa não suporta".

# classe_conhecida <classe>  ->  rc 0 se a palavra pertence ao vocabulario
#
# INCIDENTE. O vocabulario de cinco classes estava documentado no cabecalho
# deste arquivo e em lugar nenhum do CODIGO -- e `texto_veredito` abaixo tem um
# ramo `*)` que aceita qualquer palavra e a trata como "inconclusivo". A
# consequencia foi medida em scripts/xdp-zerocopy.sh: o guarda do fallback
# aceitava QUALQUER string nao vazia como "veredito fechado", entao uma classe
# que este arquivo nao conhece (um helper de outra versao grafando "no-xdp")
# produzia "Resultado INCONCLUSIVO" sem a linha "O que faltou" -- exatamente a
# invariante que o comentario de `texto_veredito` declara obrigatoria.
#
# A lista fica AQUI, ao lado de quem a consome, e nao no chamador: o vocabulario
# e decisao, e decisao neste projeto mora em lib-xdp.sh, onde o teste L1 a
# alcanca sem hardware.
classe_conhecida() {
    case "${1:-}" in
        zero-copy|nativo-sem-zc|sem-xdp|sem-atributo|inconclusivo) return 0 ;;
        *) return 1 ;;
    esac
}

# xdp_valor <chave> <bloco KEY=VALUE>  ->  valor, ou vazio
#
# Lê a saída de `scripts/xdp-features.py`. Sem `eval`, de propósito: os valores
# vêm do kernel, e `eval` sobre saída de programa é injeção esperando
# acontecer. `-v k=` em vez de interpolar a chave na fonte do awk pelo mesmo
# motivo.
xdp_valor() {
    printf '%s\n' "$2" | awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
}

# campo_xdploader <chave> <saida de xdp-loader features>  ->  valor minusculo
#
# PROCEDENCIA DO FORMATO -- leia antes de confiar neste parser.
#
# Ele e o UNICO deste arquivo que nunca rodou contra a ferramenta real. O
# formato foi RECONSTRUIDO do binario, e a reconstrucao e reproduzivel:
#
#     $ dpkg-query -W -f='${Version}\n' xdp-tools     ->  1.6.2-1ubuntu1
#     $ strings -n 2 /usr/sbin/xdp-loader | grep -n -B3 -x '%s:%s%s'
#         1712-yes
#         1713-no
#         1714-<tab><tab>
#         1715:%s:%s%s
#
# `%s:%s%s` e NOME, espacos de alinhamento e valor -- dai separar em ':' e
# remover TODO espaco em branco do segundo campo. As grafias "yes" e "no"
# aparecem coladas ao formato. Note o `-n 2`: com o minimo padrao de 4
# caracteres, `strings` NAO mostra "yes" nem "no", e a citacao antiga --
# `strings /usr/sbin/xdp-loader`, sem o -n -- nao reproduzia o que afirmava.
#
# NAO FOI POSSIVEL rodar `xdp-loader features`: ele exige root, e nesta sessao
# `sudo -n true` responde "interactive authentication is required". O texto de
# referencia do teste L1 e uma captura feita num dia em que houve privilegio,
# HOJE NAO PUBLICADA EM LUGAR NENHUM.
#
# INCIDENTE. Este comentario e o do teste citavam "o bloco publicado em
# trilha/04-projeto-final/README.md" (linhas 43-45) como procedencia. O bloco
# existia ali e foi REMOVIDO quando o documento passou a usar
# scripts/xdp-features.py; hoje aquelas linhas trazem saida de outra
# ferramenta, em outro formato (KEY=VALUE). A ancora nasceu morta no mesmo
# conjunto de mudancas que a criou, e apontava em silencio para o lugar
# errado. Nao se inventou substituta: o lastro real e o binario acima.
campo_xdploader() {
    printf '%s\n' "$2" |
        awk -F: -v k="$1" '$1 == k { gsub(/[[:space:]]/, "", $2); print tolower($2); exit }'
}

# resposta_xdploader <valor bruto>  ->  "sim" | "nao" | "desconhecida"
#
# As grafias aceitas sao exatamente as que o script anterior aceitava. Nao se
# acrescentou "true"/"1"/"0": o binario imprime yes/no (as duas strings estao
# no dump de `strings -n 2` citado acima), e inventar grafias que ninguem
# observou transforma um valor inesperado -- que MERECE virar "desconhecida" e
# aparecer no relatorio -- num "sim" ou "nao" silencioso.
resposta_xdploader() {
    case "${1:-}" in
        yes|sim)     printf 'sim' ;;
        no|nao|não)  printf 'nao' ;;
        *)           printf 'desconhecida' ;;
    esac
}

# classe_de_xdploader <zerocopy sim/nao/desconhecida> <basico ...>  ->  classe
#
# Traduz a resposta da ferramenta para o vocabulario unico. A ordem importa: a
# pergunta "tem zero-copy?" so faz sentido depois de "tem XDP nativo?", e e por
# isso que BASIC=no e uma classe propria e nao um detalhe do "nao".
classe_de_xdploader() {
    local zc=${1:-desconhecida} basico=${2:-desconhecida}
    case "$zc" in
        sim) printf 'zero-copy' ; return ;;
    esac
    case "$basico" in
        nao) printf 'sem-xdp' ; return ;;
    esac
    case "$zc" in
        nao) printf 'nativo-sem-zc' ; return ;;
    esac
    printf 'inconclusivo'
}

# classificar_alvo <alvo> <e_interface sim/nao> <e_driver sim/nao>
#   ->  "interface" | "driver" | "desconhecido"
#
# Recebe os dois predicados prontos em vez de consultar /sys e `modinfo`, pelo
# mesmo motivo de `modelo_de_driver` em lib-nic.sh: assim a regra de decisao e
# testavel numa maquina que nao tem nem a interface nem o modulo.
#
# Interface ganha do driver quando os dois predicados dizem "sim". Nenhuma
# colisao de nome foi observada nesta maquina; a precedencia existe porque
# ambiguidade tem que resolver de forma deterministica, e porque o modo
# interface e estritamente mais informativo: ele tem um netdev para
# interrogar, e o modo driver so tem simbolos de modulo.
classificar_alvo() {
    case "${2:-nao}" in sim) printf 'interface' ; return ;; esac
    case "${3:-nao}" in sim) printf 'driver' ; return ;; esac
    printf 'desconhecido'
}

# motivo_netlink <codigo de saida de xdp-features.py>  ->  frase do porque
#
# Os codigos estao documentados na docstring de scripts/xdp-features.py. Cada
# um vira uma frase que nomeia O QUE faltou -- nunca "falhou".
motivo_netlink() {
    case "${1:-}" in
        0)  printf 'a consulta netlink respondeu' ;;
        2)  printf 'chamada incorreta ao scripts/xdp-features.py (defeito do script, reporte)' ;;
        3)  printf 'este kernel nao expoe a familia netlink "netdev" (veio no 6.1; xdp_features, no 6.3)' ;;
        4)  printf 'a familia "netdev" existe, mas a consulta netlink falhou' ;;
        5)  printf 'a interface nao existe para o kernel no momento da consulta' ;;
        # 126 e 127 nao vem do helper: sao do proprio xdp-zerocopy.sh, que os
        # usa para "o helper nao esta ao lado de mim" e "nao ha python3". Ficam
        # aqui porque o leitor precisa da MESMA frase explicativa nos dois
        # casos, e porque assim ha um so lugar que traduz codigo em motivo.
        # 125 e o terceiro deles, e nasceu de um defeito de leitura: o teste
        # do helper era `[ ! -r ]`, verdadeiro tanto para "nao existe" quanto
        # para "existe e nao posso ler", e os dois saiam com a frase do 126 --
        # mandando copiar um arquivo que ja estava la.
        125) printf 'scripts/xdp-features.py esta ao lado do script e nao pode ser lido por este processo (permissao)' ;;
        126) printf 'scripts/xdp-features.py nao esta ao lado do script (copie os dois juntos)' ;;
        127) printf 'python3 nao encontrado; sem ele a fonte primaria nao roda' ;;
        *)  printf 'scripts/xdp-features.py saiu com codigo inesperado' ;;
    esac
}

# interpretar_heuristica <chamadas ao nucleo XSK>  ->  frase
#
# Mantida palavra por palavra do script anterior: a frase e citada no material
# e reescreve-la mudaria texto publicado sem que ninguem tivesse medido nada
# novo.
interpretar_heuristica() {
    if [ "${1:-0}" -eq 0 ]; then
        printf 'nenhuma evidencia indireta de zero-copy no modulo; isto nao prova a ausencia total, mas indica baixa probabilidade de suporte neste ambiente.'
    else
        printf 'ha indicio de integracao XSK no modulo; isto ainda nao confirma que o bind com XDP_ZEROCOPY sera aceito pela interface atual.'
    fi
}

# diagnostico_modulo <simbolos xdp_> <chamadas ao nucleo xsk_> <codigo xsk_ proprio>
#   ->  rotulo curto, o da coluna "diagnostico" da tabela publicada
#
# O SEGUNDO argumento e que decide o rotulo "XDP + zero-copy": chamadas ao
# nucleo XSK sao simbolos INDEFINIDOS (`nm -u`), isto e, o driver invoca o
# nucleo AF_XDP do kernel. O terceiro -- codigo xsk_ proprio, simbolos
# DEFINIDOS -- entra na tabela publicada porque ajuda o leitor a ver quanto do
# caminho e do driver, e nao entra na decisao.
#
# INCIDENTE. A versao anterior deste comentario dizia que a tabela de
# trilha/04-projeto-final/README.md "e o teste de aceitacao deste rotulo". Nao
# era, e o teste que a copiava tambem nao: nos cinco drivers medidos,
# chamadas>0 acontece EXATAMENTE quando proprios>0 -- r8169 (0/0/0), i40e
# (37/7/13), ice (83/7/13), ixgbe (38/8/12), mlx5_core (59/8/43). Trocar `$2`
# por `$3` na linha abaixo passava pelas seis assercoes sem uma falha. Cinco
# pares onde duas colunas andam juntas nao distinguem qual das duas manda; sao
# medicao, nao especificacao. Os dois casos que separam as semanticas estao em
# scripts/tests/l1_xdp.sh, sao SINTETICOS e estao declarados como tais.
diagnostico_modulo() {
    local xdp=${1:-0} chamadas=${2:-0}
    if [ "$chamadas" -gt 0 ]; then
        printf 'XDP + zero-copy'
    elif [ "$xdp" -gt 0 ]; then
        printf 'XDP sem zero-copy'
    else
        printf 'sem XDP nenhum'
    fi
}

# texto_veredito <classe> [motivo]  --  o paragrafo do veredito, em stdout
#
# O motivo so e usado na classe "inconclusivo", e ali ele e OBRIGATORIO na
# pratica: "inconclusivo" sem dizer o que faltou e exatamente a saida que fez
# este script parecer quebrado para todo leitor sem root.
texto_veredito() {
    local classe=${1:-inconclusivo} motivo=${2:-}
    case "$classe" in
        zero-copy)
            echo "  O netdev anuncia AF_XDP zero-copy; esta e uma pista forte, mas a prova final"
            echo "  continua sendo o bind real com XDP_ZEROCOPY."
            ;;
        nativo-sem-zc)
            echo "  O netdev anuncia XDP nativo, mas NAO zero-copy. XDP_ZEROCOPY deve falhar; o"
            echo "  caminho nativo com copia continua disponivel, e nao equivale a zero-copy."
            ;;
        sem-xdp)
            # Caso mais severo, e o que a RTL8125 desta maquina apresenta.
            echo "  O netdev NAO anuncia XDP NATIVO (NETDEV_XDP_ACT_BASIC: no) -- nem zero-copy,"
            echo "  nem o caminho nativo. Aqui o AF_XDP so funciona em modo GENERICO (SKB), em que"
            echo "  o eBPF roda DEPOIS da alocacao do sk_buff: e o mais lento dos modos, e nao"
            echo "  representa AF_XDP para fins de medicao."
            echo "  Consequencia pratica: 'xdpsock -N' tambem falha, nao so '-z'."
            ;;
        sem-atributo)
            echo "  O kernel respondeu, e NAO anunciou xdp_features para esta interface. Isso NAO"
            echo "  e o mesmo que 'a placa nao suporta': e um kernel que tem a familia netdev sem"
            echo "  o atributo (anterior ao 6.3), ou um netdev que nao o preenche."
            echo "  Como o 'xdp-loader features' le o MESMO atributo, ele nao responderia melhor."
            echo "  So a heuristica do modulo acima, e o bind real, dizem algo aqui."
            ;;
        *)
            echo "  Resultado INCONCLUSIVO -- e isto NAO significa 'a placa nao suporta'."
            [ -n "$motivo" ] && printf '  O que faltou: %s.\n' "$motivo"
            echo "  Sem uma fonte que responda, o unico caminho restante e o bind real com"
            echo "  XDP_ZEROCOPY, que exige CAP_NET_RAW: nem o socket(AF_XDP) e criado sem ele."
            ;;
    esac
}
