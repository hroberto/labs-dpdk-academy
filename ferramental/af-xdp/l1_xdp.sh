#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L1 do diagnóstico de AF_XDP zero-copy: lib-xdp.sh e o decodificador de
# ferramental/af-xdp/xdp-features.py.
#
# POR QUE ESTE TESTE EXISTE, E POR QUE E L1
#
# Nenhuma placa desta maquina anuncia XDP. Medido, nas quatro interfaces:
# xdp_features=0x00. Isso significa que os caminhos "anuncia zero-copy" e
# "anuncia XDP nativo sem zero-copy" -- os dois que realmente importam para
# quem for medir AF_XDP -- nao podem ser exercitados aqui por hardware nenhum.
# Sem teste, a primeira vez que eles rodariam de verdade seria no dia em que
# uma NIC Intel ou Mellanox fosse instalada.
#
# E o precedente e concreto: a versao anterior de ferramental/af-xdp/xdp-zerocopy.sh tinha
# o veredito inteiro dentro do ramo que exige root, e por isso NUNCA foi
# executado por ninguem sem privilegio. Um erro ali passaria despercebido
# indefinidamente.
#
# Por isso a decisao foi separada da coleta: `classe_de_xdploader`,
# `texto_veredito` e `diagnostico_modulo` recebem tudo por argumento, e
# `xdp-features.py --decodificar` decodifica uma bitmask SEM abrir socket.
# Nada aqui toca netlink, sysfs, modulo de kernel ou rede -- roda em
# milissegundos, em qualquer maquina, sem privilegio: a definicao de L1 neste
# projeto. Isso nao e promessa, e medicao:
#
#     $ strace -e trace=socket python3 ferramental/af-xdp/xdp-features.py --decodificar 0x23
#       chamadas socket(): 0
#     $ strace -e trace=socket python3 ferramental/af-xdp/xdp-features.py enp8s0
#       socket(AF_NETLINK, SOCK_RAW|SOCK_CLOEXEC, NETLINK_GENERIC) = 3
#
# O modo que este teste usa nao abre socket nenhum; o modo de consulta abre.
#
# O QUE ESTE TESTE NAO PROVA
#
# Que o bind com XDP_ZEROCOPY funciona numa placa que anuncia a capacidade.
# Isso exige a placa e CAP_NET_RAW, e esta registrado como pendente. Nem prova
# que o parser de `xdp-loader features` casa com a saida real da ferramenta: o
# texto de referencia usado aqui foi RECONSTRUIDO do binario xdp-tools 1.6.2
# (`strings -n 2 /usr/sbin/xdp-loader`, formato `%s:%s%s` com "yes"/"no"
# coladas), mais uma captura antiga que hoje nao esta publicada em lugar
# nenhum. A procedencia completa, com o comando que reproduz o dump, esta no
# comentario de `campo_xdploader` em ferramental/af-xdp/lib-xdp.sh. Nao foi possivel
# rodar a ferramenta ao escrever isto (`sudo -n true` -> "interactive
# authentication is required").
#
# Este teste tambem NAO cobre a camada netlink de ferramental/af-xdp/xdp-features.py --
# parse de TLV, truncamento, ext_ack, sequencia. Isso e
# ferramental/af-xdp/l1_xdp_netlink.sh, que nasceu depois e por um motivo concreto:
# oito mutacoes deliberadas naquele codigo passavam por ESTE arquivo sem uma
# falha.
#
# O que ele prova e que a REGRA DE DECISAO -- qual classe sai de cada resposta,
# e qual texto sai de cada classe -- esta correta antes de a placa chegar.
set -u

# shellcheck source=lib-xdp.sh
. "$(dirname "$0")/lib-xdp.sh"



falhas=0
# Bloco que nao pode ser exercitado nesta maquina conta separado de falha:
# nao e erro, e ausencia de cobertura -- e a saida final tem que dizer isso em
# vez de imprimir "todos os testes passaram".
lacunas=0
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
nao_contem() {
    if grep -qi -- "$2" <<<"$3"; then
        echo "  FALHA - $1 (encontrou '$2', que nao deveria estar la)"
        falhas=$((falhas + 1))
    else
        echo "  ok    - $1"
    fi
}

echo "== L1: decisao do diagnostico AF_XDP zero-copy =="

# --- leitura do bloco KEY=VALUE do helper ------------------------------------
bloco='FONTE=netlink
IFACE=enp8s0
IFINDEX=7
XDP_FEATURES=0x0
XDP_FEATURES_NOMES=
XDP_BASIC=nao
VEREDITO=sem-xdp'

check "xdp_valor le a primeira chave"      "$(xdp_valor FONTE "$bloco")"   "netlink"
check "xdp_valor le uma chave do meio"     "$(xdp_valor IFINDEX "$bloco")" "7"
check "xdp_valor le a ultima chave"        "$(xdp_valor VEREDITO "$bloco")" "sem-xdp"
check "xdp_valor devolve vazio em chave ausente" "$(xdp_valor NAOEXISTE "$bloco")" ""
check "xdp_valor devolve vazio em valor vazio"   "$(xdp_valor XDP_FEATURES_NOMES "$bloco")" ""
# Prefixo nao pode casar: XDP_FEATURES e XDP_FEATURES_NOMES sao chaves distintas
# e a busca e por igualdade, nao por 'comeca com'.
check "xdp_valor nao confunde chave com prefixo de outra" \
    "$(xdp_valor XDP_FEATURES "$bloco")" "0x0"

# --- parser de xdp-loader features -------------------------------------------
#
# INCIDENTE. Estas duas amostras citavam um "bloco publicado" em
# trilha/04-projeto-final/README.md, nas linhas 43 a 45. Aquele bloco EXISTIA
# ali e foi removido quando o documento passou a usar ferramental/af-xdp/xdp-features.py;
# hoje aquelas linhas trazem saida de outra ferramenta, em outro formato. A
# ancora apontava em silencio para o lugar errado desde o dia em que foi
# escrita.
#
# A citacao foi reescrita SEM a forma `arquivo:N-M` de proposito: assim ela e
# a narrativa de uma ancora morta, e nao uma ancora nova. Como
# ferramental/qualidade/verificar-ancoras.py avisa, nao ha como distinguir uma ancora de uma
# mencao a uma ancora -- e este comentario foi cobrado como citacao na
# primeira vez que rodou contra a arvore.
#
# A procedencia verdadeira, com o comando que a reproduz, esta no comentario
# de `campo_xdploader` em ferramental/af-xdp/lib-xdp.sh: formato `%s:%s%s` lido de
# `strings -n 2 /usr/sbin/xdp-loader` (xdp-tools 1.6.2), mais uma captura hoje
# nao publicada. As amostras abaixo sao, portanto, RECONSTRUIDAS -- e o
# alinhamento por espacos e arbitrario de proposito, ja que o parser tem que
# ignora-lo.
loader_sem_xdp='NETDEV_XDP_ACT_BASIC:         no
NETDEV_XDP_ACT_REDIRECT:      no
NETDEV_XDP_ACT_NDO_XMIT:      no
NETDEV_XDP_ACT_XSK_ZEROCOPY:  no
NETDEV_XDP_ACT_HW_OFFLOAD:    no
NETDEV_XDP_ACT_RX_SG:         no
NETDEV_XDP_ACT_NDO_XMIT_SG:   no'
loader_com_zc='NETDEV_XDP_ACT_BASIC:         yes
NETDEV_XDP_ACT_REDIRECT:      yes
NETDEV_XDP_ACT_NDO_XMIT:      yes
NETDEV_XDP_ACT_XSK_ZEROCOPY:  yes
NETDEV_XDP_ACT_HW_OFFLOAD:    no
NETDEV_XDP_ACT_RX_SG:         yes
NETDEV_XDP_ACT_NDO_XMIT_SG:   yes'

check "campo_xdploader extrai BASIC de saida sem XDP" \
    "$(campo_xdploader NETDEV_XDP_ACT_BASIC "$loader_sem_xdp")" "no"
check "campo_xdploader extrai ZEROCOPY de saida com ZC" \
    "$(campo_xdploader NETDEV_XDP_ACT_XSK_ZEROCOPY "$loader_com_zc")" "yes"
check "campo_xdploader devolve vazio em campo ausente" \
    "$(campo_xdploader NETDEV_XDP_ACT_INVENTADO "$loader_com_zc")" ""

check "resposta_xdploader traduz yes"      "$(resposta_xdploader yes)" "sim"
check "resposta_xdploader traduz no"       "$(resposta_xdploader no)"  "nao"
check "resposta_xdploader nao inventa em valor vazio"   "$(resposta_xdploader '')"     "desconhecida"
check "resposta_xdploader nao inventa em valor estranho" "$(resposta_xdploader talvez)" "desconhecida"

# --- classe a partir do fallback: o ramo que nunca rodou sem root ------------
check "ZC=sim vira zero-copy"                "$(classe_de_xdploader sim nao)" "zero-copy"
check "ZC=sim vence, mesmo com BASIC ausente" "$(classe_de_xdploader sim desconhecida)" "zero-copy"
# O caso desta maquina, e o mais severo: BASIC=no nao e "nao tem zero-copy",
# e "nao tem XDP nenhum". Confundir os dois muda a conclusao do material.
check "BASIC=nao vira sem-xdp"               "$(classe_de_xdploader nao nao)" "sem-xdp"
check "ZC=nao com BASIC=sim vira nativo-sem-zc" \
    "$(classe_de_xdploader nao sim)" "nativo-sem-zc"
check "tudo desconhecido vira inconclusivo"  "$(classe_de_xdploader desconhecida desconhecida)" "inconclusivo"
check "sem argumento nenhum vira inconclusivo" "$(classe_de_xdploader)" "inconclusivo"

# Integracao das duas metades: da saida crua ate a classe.
check "saida sem XDP percorre parser+classe ate sem-xdp" \
    "$(classe_de_xdploader \
        "$(resposta_xdploader "$(campo_xdploader NETDEV_XDP_ACT_XSK_ZEROCOPY "$loader_sem_xdp")")" \
        "$(resposta_xdploader "$(campo_xdploader NETDEV_XDP_ACT_BASIC "$loader_sem_xdp")")")" \
    "sem-xdp"
check "saida com ZC percorre parser+classe ate zero-copy" \
    "$(classe_de_xdploader \
        "$(resposta_xdploader "$(campo_xdploader NETDEV_XDP_ACT_XSK_ZEROCOPY "$loader_com_zc")")" \
        "$(resposta_xdploader "$(campo_xdploader NETDEV_XDP_ACT_BASIC "$loader_com_zc")")")" \
    "zero-copy"

# --- selecao de modo ---------------------------------------------------------
check "alvo que so e interface -> interface" "$(classificar_alvo enp8s0 sim nao)" "interface"
check "alvo que so e driver -> driver"       "$(classificar_alvo i40e nao sim)"   "driver"
check "alvo que e os dois -> interface"      "$(classificar_alvo veth sim sim)"   "interface"
check "alvo que nao e nenhum -> desconhecido" "$(classificar_alvo xpto nao nao)"  "desconhecido"
check "predicados ausentes -> desconhecido"  "$(classificar_alvo xpto)"           "desconhecido"

# --- motivo: 'inconclusivo' nunca pode sair mudo -----------------------------
for c in 0 2 3 4 5 126 127 200; do
    m=$(motivo_netlink "$c")
    if [ -n "$m" ]; then
        echo "  ok    - motivo_netlink($c) diz alguma coisa"
    else
        echo "  FALHA - motivo_netlink($c) saiu vazio"
        falhas=$((falhas + 1))
    fi
done
contem "motivo do codigo 3 nomeia a familia netlink" "netdev" "$(motivo_netlink 3)"
contem "motivo do codigo 127 nomeia o python3"       "python3" "$(motivo_netlink 127)"

# --- heuristica do modulo ----------------------------------------------------
contem "heuristica com 0 chamadas fala em baixa probabilidade" \
    "baixa probabilidade" "$(interpretar_heuristica 0)"
contem "heuristica com chamadas fala em indicio" \
    "indicio" "$(interpretar_heuristica 7)"
# ASSERCAO CORRIGIDA. A primeira versao deste teste era
#     nao_contem "..." "prova a ausencia total" "$(interpretar_heuristica 0)"
# e FALHOU -- corretamente. A frase da heuristica e "isto NAO prova a ausencia
# total", que contem a substring procurada. O `nao_contem` estava perguntando
# se a palavra aparece, quando o que importa e se a RESSALVA aparece. Uma
# asserção que procura substring nunca distingue afirmação de negação; aqui a
# forma certa e exigir a negação inteira.
contem "heuristica com 0 chamadas mantem a ressalva de nao provar ausencia" \
    "nao prova a ausencia total" "$(interpretar_heuristica 0)"

# --- rotulo da tabela publicada ----------------------------------------------
#
# Os cinco pares abaixo sao os numeros medidos e PUBLICADOS na tabela de
# trilha/04-projeto-final/README.md. NAO ha numero de linha aqui, de proposito,
# e a razao esta em dois incidentes seguidos:
#
#   1. a citacao original dizia "69-73", que era onde a tabela ficava antes de
#      o documento crescer, e passou a cair no meio de um blockquote sobre
#      privilegio;
#   2. a correcao disso trocou por "139-143" -- e JA NASCEU ERRADA: 139 e uma
#      linha em branco, 140 e o cabecalho, 141 os separadores, e so 142 e 143
#      sao duas das cinco linhas. As cinco estao em 142-146. Dois agentes
#      escreveram numeros diferentes para o mesmo alvo na mesma rodada.
#
# Numero de linha em comentario e a coisa que este projeto mais viu envelhecer
# calada. A localizacao aqui e por CONTEUDO, que nao envelhece:
#
#     grep -n '| driver |' trilha/04-projeto-final/README.md
#
# (Isto tambem nao e mais verdade: `ferramental/qualidade/verificar-ancoras.py` passou a ler
# comentario de .sh e .py na mesma rodada em que este comentario dizia que
# "nada verifica ancora de linha escrita em comentario de shell". Se uma
# ancora `arquivo.md:N-M` for escrita aqui, ela SERA cobrada.)
#
# Se a coleta mexer nos flags do `nm` ou nos greps, a tabela muda e este bloco
# e o alarme.
check "r8169 (0/0/0) e 'sem XDP nenhum'"     "$(diagnostico_modulo 0 0 0)"   "sem XDP nenhum"
check "i40e (37/7/13) e 'XDP + zero-copy'"   "$(diagnostico_modulo 37 7 13)" "XDP + zero-copy"
check "ice (83/7/13) e 'XDP + zero-copy'"    "$(diagnostico_modulo 83 7 13)" "XDP + zero-copy"
check "ixgbe (38/8/12) e 'XDP + zero-copy'"  "$(diagnostico_modulo 38 8 12)" "XDP + zero-copy"
check "mlx5_core (59/8/43) e 'XDP + zero-copy'" "$(diagnostico_modulo 59 8 43)" "XDP + zero-copy"
# Terceiro caso, sem exemplo entre os cinco drivers medidos: modulo com codigo
# XDP e sem nenhuma chamada ao nucleo XSK. Sintetico, e declarado como tal.
check "modulo com xdp_ e sem xsk_ e 'XDP sem zero-copy'" \
    "$(diagnostico_modulo 58 0 0)" "XDP sem zero-copy"

# INCIDENTE. Os cinco pares acima NAO distinguem o 2o argumento (chamadas ao
# nucleo XSK) do 3o (codigo xsk_ proprio): em todos eles chamadas>0 acontece
# EXATAMENTE quando proprios>0. Medido -- trocando `$2` por `$3` na primeira
# linha de `diagnostico_modulo`:
#
#     $ sed -i 's/chamadas=${2:-0}/chamadas=${3:-0}/' ferramental/af-xdp/lib-xdp.sh
#     $ bash ferramental/af-xdp/l1_xdp.sh | tail -2
#       L1: todos os testes passaram
#
# Seis assercoes, nenhuma falha, e a semantica do rotulo invertida. O
# comentario de lib-xdp.sh chegava a afirmar que a tabela publicada "e o teste
# de aceitacao deste rotulo"; nao e -- ela aceita as duas leituras.
#
# Os dois casos abaixo separam as semanticas, um de cada lado. Sao SINTETICOS
# e declarados como tais: nenhum dos cinco drivers medidos os apresenta, e o
# que se afirma aqui nao e "existe driver assim", e sim "a decisao pertence ao
# 2o argumento". Contrato de posicao de argumento se fixa por construcao, nao
# por amostra -- e a amostra era justamente o que faltava distinguir.
check "chamada ao nucleo XSK sem codigo proprio ja e 'XDP + zero-copy'" \
    "$(diagnostico_modulo 58 7 0)" "XDP + zero-copy"
check "codigo xsk_ proprio SEM chamada ao nucleo nao basta para zero-copy" \
    "$(diagnostico_modulo 58 0 13)" "XDP sem zero-copy"

# --- texto do veredito -------------------------------------------------------
contem "veredito sem-xdp cita NETDEV_XDP_ACT_BASIC" \
    "NETDEV_XDP_ACT_BASIC" "$(texto_veredito sem-xdp)"
contem "veredito sem-xdp explica o modo generico (SKB)" \
    "SKB" "$(texto_veredito sem-xdp)"
contem "veredito zero-copy lembra que a prova e o bind real" \
    "bind real" "$(texto_veredito zero-copy)"
contem "veredito nativo-sem-zc diz que a copia continua" \
    "copia" "$(texto_veredito nativo-sem-zc)"
contem "veredito sem-atributo explica que o fallback le o mesmo atributo" \
    "mesmo atributo" "$(texto_veredito sem-atributo)"

# O defeito que motivou a reescrita, virado asserção: "inconclusivo" tem que
# dizer o que faltou, e nao pode ser lido como "a placa nao suporta".
inconclusivo=$(texto_veredito inconclusivo "python3 nao encontrado")
contem "veredito inconclusivo repete o motivo recebido" \
    "python3 nao encontrado" "$inconclusivo"
contem "veredito inconclusivo nega explicitamente a leitura errada" \
    "NAO significa" "$inconclusivo"
contem "veredito inconclusivo aponta o bind real como saida" \
    "CAP_NET_RAW" "$inconclusivo"
check "classe desconhecida cai no ramo inconclusivo" \
    "$(texto_veredito xpto | head -1)" \
    "$(texto_veredito inconclusivo | head -1)"

# --- decodificacao de bitmask, no codigo que roda em producao ----------------
#
# `--decodificar` nao abre socket: e a mesma funcao que decodifica a resposta
# do kernel, alimentada por argumento. Por isso o caminho "zero-copy anunciado"
# fica testado sem existir placa que o anuncie.
if [ "$falhas" -ne 0 ]; then
    echo "L1 shell: $falhas falha(s)"
    exit 1
fi
echo 'L1 shell: todas as assercoes executadas passaram; bitmask e teste separado'
