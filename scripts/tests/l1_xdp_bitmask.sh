#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Decodificador puro; registrado separadamente para preservar SKIP por dependência.
set -u
. "$(dirname "$0")/../lib-xdp.sh"
HELPER="$(dirname "$0")/../xdp-features.py"
if ! command -v python3 >/dev/null 2>&1; then
    echo 'SKIP: decodificador exige python3'
    exit 77
fi
if [ ! -e "$HELPER" ]; then
    echo 'SKIP: xdp-features.py ausente'
    exit 77
fi
if [ ! -r "$HELPER" ]; then
    echo 'SKIP: xdp-features.py existe mas nao esta legivel'
    exit 77
fi
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
nao_contem() {
    if grep -qi -- "$2" <<<"$3"; then
        echo "  FALHA - $1 (encontrou '$2', que nao deveria estar la)"
        falhas=$((falhas + 1))
    else
        echo "  ok    - $1"
    fi
}

    dec() { python3 "$HELPER" --decodificar "$@"; }

    check "0x0 -> sem-xdp"        "$(xdp_valor VEREDITO "$(dec 0x0)")" "sem-xdp"
    check "0x1 (BASIC) -> nativo-sem-zc" \
        "$(xdp_valor VEREDITO "$(dec 0x1)")" "nativo-sem-zc"
    check "0x9 (BASIC|ZEROCOPY) -> zero-copy" \
        "$(xdp_valor VEREDITO "$(dec 0x9)")" "zero-copy"
    # O bit 8 sozinho e incoerente (zero-copy sem XDP basico) e o kernel nao o
    # produz. A regra e deliberada: BASIC manda, porque sem XDP nativo nao ha
    # onde o zero-copy acontecer.
    check "0x8 sem BASIC -> sem-xdp (BASIC manda)" \
        "$(xdp_valor VEREDITO "$(dec 0x8)")" "sem-xdp"
    check "'ausente' -> sem-atributo (kernel nao anunciou)" \
        "$(xdp_valor VEREDITO "$(dec ausente)")" "sem-atributo"
    check "decimal 35 e 0x23 dao o mesmo veredito" \
        "$(xdp_valor VEREDITO "$(dec 35)")" "$(xdp_valor VEREDITO "$(dec 0x23)")"

    # O valor de controle positivo desta maquina: um veth reporta 0x23, e
    # 0x23 = BASIC|REDIRECT|RX_SG. O bit NDO_XMIT (0x4) esta ausente de
    # proposito -- veth so o acrescenta quando o par tem programa XDP.
    nomes=$(xdp_valor XDP_FEATURES_NOMES "$(dec 0x23)")
    contem "0x23 lista BASIC"     "NETDEV_XDP_ACT_BASIC"    "$nomes"
    contem "0x23 lista REDIRECT"  "NETDEV_XDP_ACT_REDIRECT" "$nomes"
    contem "0x23 lista RX_SG"     "NETDEV_XDP_ACT_RX_SG"    "$nomes"
    nao_contem "0x23 nao lista NDO_XMIT" "NETDEV_XDP_ACT_NDO_XMIT" "$nomes"

    check "0x7f lista os sete bits conhecidos" \
        "$(xdp_valor XDP_FEATURES_NOMES "$(dec 0x7f)" | wc -w)" "7"
    # Bit que esta tabela nao conhece TEM que aparecer. Engoli-lo e como o
    # material envelhece sem ninguem notar: o kernel ganha um NETDEV_XDP_ACT_*
    # novo e a ferramenta segue imprimindo a lista antiga com cara de completa.
    contem "bit desconhecido e reportado, nao engolido" \
        "BIT_DESCONHECIDO" "$(xdp_valor XDP_FEATURES_NOMES "$(dec 0x80)")"

    # zc_max_segs ausente e a condicao NORMAL de placa sem zero-copy: vazio
    # significa "nao anunciado", jamais "zero segmentos".
    check "zc_max_segs ausente sai vazio" \
        "$(xdp_valor XDP_ZC_MAX_SEGS "$(dec 0x0)")" ""
    check "zc_max_segs anunciado aparece" \
        "$(xdp_valor XDP_ZC_MAX_SEGS "$(dec 0x9 --zc-max-segs 5)")" "5"

    contem "rx_metadata 0x7 lista os tres nomes" \
        "VLAN_TAG" "$(xdp_valor XDP_RX_METADATA_NOMES "$(dec 0x23 --rx-metadata 0x7)")"
    contem "xsk_features 0x2 nomeia TX_CHECKSUM" \
        "TX_CHECKSUM" "$(xdp_valor XSK_FEATURES_NOMES "$(dec 0x9 --xsk 0x2)")"

    # Erro de digitacao nao pode virar 0 em silencio: 0 e uma resposta com
    # significado ("o driver nao anuncia nada"), e o script decidiria com ela.
    dec abacaxi >/dev/null 2>&1
    check "valor invalido sai com codigo 2 (uso incorreto)" "$?" "2"
    python3 "$HELPER" --decodificar 0x1 --flag-inventada 0x1 >/dev/null 2>&1
    check "flag desconhecida sai com codigo 2" "$?" "2"

[ "$falhas" -eq 0 ]
