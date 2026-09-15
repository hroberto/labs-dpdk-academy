#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L1 da camada NETLINK de ferramental/af-xdp/xdp-features.py.
#
# POR QUE ESTE ARQUIVO NASCEU
#
# INCIDENTE. As ~380 linhas de netlink de `ferramental/af-xdp/xdp-features.py` nao tinham
# UMA assercao sequer. `ferramental/af-xdp/l1_xdp.sh` cobria a decisao (lib-xdp.sh) e
# o decodificador de bitmask, chamado pela linha de comando -- nada abaixo
# disso. Medido, mutando o arquivo e rodando a suite L1 que existia:
#
#     mutacao deliberada                                        suite L1
#     parse_attrs sem a checagem `i + nla_len > fim`            PASSOU
#     parse_attrs sem a checagem `i != fim`                     PASSOU
#     parse_attrs somando nla_len em vez de alinha4(nla_len)    PASSOU
#     uint lendo u64 como u32                                   PASSOU
#     _recebe ignorando MSG_TRUNC                               PASSOU
#     _ext_ack descartando NLMSGERR_ATTR_MISS_TYPE              PASSOU
#     nome_seguro deixando passar byte hostil                   PASSOU
#     resolve_familia aceitando nome acima de GENL_NAMSIZ       PASSOU
#
# Oito mutacoes, nenhuma pega. O agravante e que o proprio codigo dizia estar
# preparado para o teste: a docstring de `_parse_datagrama` justifica separar
# PARSE de I/O dizendo que assim "da para alimentar bytes arbitrarios e
# conferir que o truncamento vira excecao em vez de dado inventado". O
# refatorador fez a parte dele e ninguem alimentou byte nenhum.
#
# Pior ainda: os dois blocos "INCIDENTE" de xdp-features.py -- em `parse_attrs`
# e em `_ext_ack` -- narram bugs REAIS ja corrigidos, com as frases que a
# correcao passou a emitir. Bug corrigido sem teste de regressao volta. Aqui
# essas frases viraram assercao literal, incluindo os numeros medidos na epoca
# ("declara 12 bytes, restam 10" e "sobraram 2 bytes soltos").
#
# POR QUE OS BYTES SAO MONTADOS A MAO
#
# Os TLVs e os nlmsghdr deste teste sao construidos com `struct.pack` local, e
# NAO com `mod.nla()`. Se o teste montasse a entrada com o mesmo codigo que
# pretende verificar, um erro de alinhamento no construtor cancelaria o erro
# simetrico no parser e os dois passariam de maos dadas. O construtor tem
# assercao propria, e ela e um ida-e-volta explicito (`nla` -> `parse_attrs`),
# declarado como tal.
#
# O QUE ESTE TESTE NAO PROVA
#
# Nao fala com o kernel: nenhum socket e aberto, e isso e verificado (o modulo
# e importado com `socket.socket` substituido por uma sentinela que aborta se
# chamada). Em troca:
#   - nao prova que o kernel ENTREGA MSG_TRUNC quando deveria; prova que, se a
#     flag chegar, `_recebe` para em vez de seguir lendo lixo;
#   - nao prova que NETDEV_CMD_DEV_GET e mesmo livre de root neste kernel;
#     prova que `resolve_familia` le a flag GENL_ADMIN_PERM do lugar certo. A
#     prova da politica real e `ferramental/af-xdp/xdp-features.py --politica` rodando;
#   - nao prova que a resposta real do kernel tem o layout usado aqui. O layout
#     vem dos headers citados linha a linha em xdp-features.py.
#
# QUANDO FALTA python3
#
# O teste sai com 77 -- o codigo que o Meson le como SKIP -- e NAO com 0.
# Passar sem ter rodado e exatamente o defeito que este conjunto de arquivos
# existe para combater: "nao consegui apurar" nao pode ser impresso com a mesma
# cara de "esta correto". Antes de sair, ele nomeia o que ficou sem cobertura.
#
# REGISTRO NO MESON
#
# JA REGISTRADO, suite ['l1','scripts'], sem gate de python3. Confira por
# conteudo, nao por numero de linha:
#
#     grep -n l1_xdp_netlink meson.build
#
# INCIDENTE deste paragrafo: ele dizia "Arquivo NOVO. Precisa ser registrado",
# e trazia o bloco pronto para colar -- enquanto o dono do meson.build fazia o
# registro na MESMA rodada. Quem abrisse este teste leria uma pendencia
# inexistente, e a consequencia declarada aqui ("as assercoes rodam so a mao,
# nao pela suite nem pela CI") era falsa. Pendencia que ja foi resolvida e
# continua escrita e desinformacao, nao historico.
set -u

aqui="$(dirname "$0")"
HELPER="$aqui/xdp-features.py"

# APURACAO-OK: mesma justificativa do teste vizinho -- a mensagem diz "nao
# esta legivel", que cobre ENOENT e EACCES sem afirmar qual dos dois e, e o
# teste sai igual nos dois casos.
if [ ! -r "$HELPER" ]; then
    echo "  FALHA - ferramental/af-xdp/xdp-features.py nao esta legivel em '$HELPER'"
    echo "          (o teste vive ao lado do que ele testa; copie os dois juntos)"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "== L1: camada netlink de xdp-features.py =="
    echo "  SKIP  - python3 ausente do PATH; NADA abaixo foi exercitado."
    echo "  SKIP    Ficaram sem cobertura, em ferramental/af-xdp/xdp-features.py:"
    echo "  SKIP      parse_attrs           (truncamento de TLV, alinhamento NLA)"
    echo "  SKIP      uint                  (u64 lido como u64, nao como u32)"
    echo "  SKIP      Genl._parse_datagrama (mensagens grudadas, seq, NLMSG_ERROR)"
    echo "  SKIP      Genl._recebe          (MSG_TRUNC)"
    echo "  SKIP      Genl._ext_ack         (NLMSGERR_ATTR_MISS_TYPE estruturado)"
    echo "  SKIP      resolve_familia       (GENL_NAMSIZ, id de 2 bytes, ops)"
    echo "  SKIP      nome_seguro           (nome de interface hostil)"
    echo "  SKIP      veredito_de           ('nao anunciou' x 'anunciou zero')"
    echo "  SKIP    Isto e SKIP, nao sucesso: instale python3 para cobrir."
    # 77 e o codigo que o Meson interpreta como SKIP no protocolo 'exitcode'.
    exit 77
fi

XDP_FEATURES_PY="$HELPER" python3 - <<'PY'
import importlib.util
import os
import signal
import socket
import struct
import sys

CAMINHO = os.environ["XDP_FEATURES_PY"]

# --- importacao sob vigilancia ----------------------------------------------
#
# O cabecalho de l1_xdp.sh afirma que o teste L1 nao abre socket. Afirmacao
# vira medicao: durante o import, socket.socket e uma sentinela que aborta. Se
# alguem mover a criacao do socket para o nivel do modulo, o teste morre aqui
# com a razao escrita, em vez de virar um L1 que toca a rede em silencio.
_socket_real = socket.socket


def _sentinela(*a, **k):
    raise AssertionError(
        "ferramental/af-xdp/xdp-features.py abriu socket durante o import: "
        f"socket.socket{a!r}. O modulo tem que ser importavel sem tocar "
        "netlink -- e o que torna este teste L1.")


# Sem isto, o import deixa scripts/__pycache__/xdp-features.cpython-*.pyc no
# diretorio de codigo do projeto. Um teste L1 nao escreve na arvore que testa:
# alem da sujeira, ele passaria a falhar num checkout somente-leitura.
sys.dont_write_bytecode = True

socket.socket = _sentinela
try:
    spec = importlib.util.spec_from_file_location("xdp_features", CAMINHO)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
finally:
    socket.socket = _socket_real

falhas = 0
total = 0
abortadas = 0


def _ok(nome):
    global total
    total += 1
    print(f"  ok    - {nome}")


def _falha(nome, detalhe):
    global falhas, total
    total += 1
    falhas += 1
    print(f"  FALHA - {nome} ({detalhe})")


def check(nome, obtido, esperado):
    if obtido == esperado:
        _ok(nome)
    else:
        _falha(nome, f"esperado {esperado!r}, obtido {obtido!r}")


def checkf(nome, fn, esperado):
    """check() para expressao que PODE estourar.

    Uma regressao no parser costuma se manifestar como excecao, nao como valor
    diferente. Com `check(nome, A(bytes), esperado)` a excecao sobe e mata a
    rodada inteira -- o defeito aparece, mas leva junto as outras ~100
    assercoes, e some a informacao de o que MAIS quebrou. Medido: a mutacao
    "somar nla_len em vez de alinha4(nla_len)" abortava o arquivo na quinta
    assercao.
    """
    try:
        obtido = com_prazo(fn)
    except Exception as e:                                   # noqa: BLE001
        _falha(nome, f"estourou {type(e).__name__}: {e}")
        return
    check(nome, obtido, esperado)


def erra(nome, excecao, trecho, fn):
    """Exige a excecao CERTA e que a mensagem NOMEIE o que faltou.

    Conferir so o tipo nao basta neste arquivo. Quando se remove a checagem
    `i + nla_len > fim` de parse_attrs, o truncamento ainda estoura -- mas la
    embaixo, no `i != fim`, com a frase errada e um numero negativo. Um teste
    que aceitasse "levantou ErroTruncado" aprovaria a regressao. Por isso o
    trecho da mensagem e parte da assercao: a diferenca entre "nao sei" e
    "nao" mora justamente no texto que diz O QUE faltou.
    """
    try:
        com_prazo(fn)
    except excecao as e:
        if trecho.lower() in str(e).lower():
            _ok(nome)
        else:
            _falha(nome, f"mensagem nao contem {trecho!r}: {str(e)!r}")
    except Exception as e:                                   # noqa: BLE001
        _falha(nome, f"excecao {type(e).__name__} em vez de "
                     f"{excecao.__name__}: {e}")
    else:
        _falha(nome, f"nao levantou {excecao.__name__}")


class TempoEsgotado(Exception):
    pass


def com_prazo(fn, segundos=5):
    """Roda fn com relogio: laco infinito vira EXCECAO, nao silencio.

    Usado por TODAS as assercoes que executam codigo do modulo (`erra`,
    `nao_erra`, `checkf`), e nao so pela que tem "laco infinito" no nome --
    ver o comentario em s_parse_attrs, que registra por que a primeira versao
    disto nao funcionou.

    INCIDENTE. A assercao chamada "nla_len zero e recusado (e nao vira laco
    infinito)" NAO conseguia detectar o laco infinito: ela VIRAVA o laco
    infinito. Sem a guarda `nla_len < NLA_HDRLEN`, `alinha4(0)` e 0, o indice
    nunca avanca, e o teste roda para sempre. O que o operador via nao era uma
    falha nomeada -- era ZERO BYTE de saida, indefinidamente, sem nem as ~80
    assercoes que ja haviam passado. E a mesma classe do incidente fundador
    vista do outro lado: ausencia de saida lida como "ainda rodando", quando a
    informacao real e "a guarda sumiu".

    Sob o Meson o `timeout : 30` ao menos falhava, sem dizer QUAL assercao; e a
    forma publicada de rodar (`bash ferramental/af-xdp/l1_xdp_netlink.sh`) nao tinha
    prazo nenhum. O relogio fica AQUI, junto da assercao que precisa dele.

    SIGALRM interrompe laco de bytecode puro (o interpretador confere sinais
    entre instrucoes), que e exatamente a forma deste laco.
    """
    anterior = signal.signal(signal.SIGALRM, _estourou)
    signal.setitimer(signal.ITIMER_REAL, segundos)
    try:
        return fn()
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, anterior)


def _estourou(sig, frame):                                   # noqa: ARG001
    raise TempoEsgotado(
        "nao terminou no prazo: a guarda que impede o laco infinito sumiu")


def nao_erra(nome, fn):
    try:
        com_prazo(fn)
    except Exception as e:                                   # noqa: BLE001
        _falha(nome, f"levantou {type(e).__name__}: {e}")
    else:
        _ok(nome)


def executa(titulo, fn):
    """Roda uma secao isolada: excecao inesperada e FALHA, nao fim da rodada.

    Mesma razao de checkf, um nivel acima -- e a razao vale duas vezes num
    teste de parser, onde a forma tipica da regressao e "estourou onde nao
    devia" e a informacao util esta nas OUTRAS secoes.

    INCIDENTE do DENOMINADOR. Quando uma secao aborta, as assercoes restantes
    DELA simplesmente nao rodam, e a linha final reportava o total ALCANCADO
    como se fosse o total ESPERADO: medido, uma mutacao no ramo u16 fez a
    saida virar "3 falha(s) em 95 assercoes" contra 110 na linha de base --
    treze assercoes desapareceram da conta e nenhuma linha dizia isso. E o
    mesmo "silencio lido como cobertura" que este conjunto combate, com o
    denominador no lugar do numerador. Nao ha total esperado gravado a mao (um
    numero desses envelhece calado, que e o defeito vizinho); o que ha e o
    AVISO de que o denominador encolheu.
    """
    print("")
    print(f"-- {titulo} --")
    try:
        fn()
    except Exception as e:                                   # noqa: BLE001
        _falha(f"secao abortada: {titulo}",
               f"excecao inesperada {type(e).__name__}: {e}")
        global abortadas
        abortadas += 1


# --- montadores de bytes, independentes do codigo sob teste -----------------

def tlv(tipo, payload, declara=None, pad=True):
    """struct nlattr montado a mao. `declara` mente sobre nla_len de proposito."""
    n = 4 + len(payload) if declara is None else declara
    corpo = struct.pack("=HH", n, tipo) + payload
    return corpo + (b"\x00" * (-len(corpo) % 4) if pad else b"")


def nlmsg(mtype, flags, seq, payload, declara=None, pad=True):
    """struct nlmsghdr + payload, com o mesmo direito de mentir no nlmsg_len."""
    n = 16 + len(payload) if declara is None else declara
    corpo = struct.pack("=IHHII", n, mtype, flags, seq, 0) + payload
    return corpo + (b"\x00" * (-len(corpo) % 4) if pad else b"")


def genl(cmd, versao, attrs=b""):
    return struct.pack("=BBH", cmd, versao, 0) + attrs


A = mod.parse_attrs
U = mod.uint
U32 = struct.Struct("=I").pack
U64 = struct.Struct("=Q").pack


# ---------------------------------------------------------------------------
# parse_attrs
# ---------------------------------------------------------------------------

def s_attrs_bem_formados():
    checkf("buffer vazio nao e erro, e ausencia de atributos",
           lambda: A(b""), {})
    checkf("dois atributos alinhados saem inteiros",
           lambda: A(tlv(1, U32(7)) + tlv(3, U64(0x23))),
           {1: U32(7), 3: U64(0x23)})
    checkf("atributo de payload vazio e valido (nla_len == NLA_HDRLEN)",
           lambda: A(tlv(6, b"")), {6: b""})
    checkf("offset pula o genlmsghdr",
           lambda: A(genl(1, 1, tlv(1, U32(7))), offset=mod.GENL_HDRLEN),
           {1: U32(7)})

    # ALINHAMENTO NLA. nla_len conta header+payload SEM o padding, mas o
    # proximo atributo comeca em NLA_ALIGN(nla_len). Com payload de 3 bytes,
    # nla_len=7 e o proximo TLV comeca em 8. Duas coisas tem que valer ao mesmo
    # tempo: o payload devolvido tem 3 bytes (padding nao e dado) e o segundo
    # atributo e encontrado. Somar nla_len cru pula para o offset 7 e le lixo.
    checkf("payload de 3 bytes: padding nao vira dado, e o proximo TLV e achado",
           lambda: A(tlv(9, b"abc") + tlv(2, b"\x01\x02")),
           {9: b"abc", 2: b"\x01\x02"})
    checkf("tres payloads de tamanho impar seguidos continuam alinhando",
           lambda: A(tlv(1, b"a") + tlv(2, b"bc") + tlv(3, b"def")),
           {1: b"a", 2: b"bc", 3: b"def"})

    # NLA_F_NESTED e NLA_F_NET_BYTEORDER moram nos dois bits altos do nla_type.
    # Sem a mascara, um nest vira o tipo 32774 e some do dicionario.
    checkf("NLA_F_NESTED e removido do tipo",
           lambda: list(A(tlv(6 | mod.NLA_F_NESTED, U32(0)))), [6])
    checkf("NLA_F_NET_BYTEORDER e removido do tipo",
           lambda: list(A(tlv(4 | mod.NLA_F_NET_BYTEORDER, U32(0)))), [4])

    # Ida-e-volta pelo construtor do proprio modulo. Declarado como tal: aqui
    # os dois lados sao do codigo sob teste, entao isto cobre `nla`/`nla_str`,
    # nao `parse_attrs`.
    checkf("nla_u32 -> parse_attrs devolve os 4 bytes",
           lambda: A(mod.nla_u32(1, 0xDEADBEEF) + mod.nla_str(2, "netdev"))[1],
           U32(0xDEADBEEF))
    checkf("nla_str -> parse_attrs devolve a string NUL-terminada",
           lambda: A(mod.nla_u32(1, 0xDEADBEEF) + mod.nla_str(2, "netdev"))[2],
           b"netdev\x00")


def s_attrs_truncados():
    # INCIDENTE, primeira metade. "corte em 42 bytes -> 'declara 12 bytes,
    # restam 10'". Reproduzido com o mesmo formato: um u32 (8 bytes de TLV)
    # seguido de um u64 (12 bytes de TLV), cortado 2 bytes antes do fim.
    buf = tlv(1, U32(7)) + tlv(3, U64(0x23))
    check("o buffer de referencia tem 20 bytes (8 + 12)", len(buf), 20)
    erra("corte no MEIO de um atributo diz quanto declarou e quanto restou",
         mod.ErroTruncado, "declara 12 bytes, restam 10", lambda: A(buf[:18]))
    erra("...e nomeia o offset onde parou",
         mod.ErroTruncado, "offset 8", lambda: A(buf[:18]))

    # INCIDENTE, segunda metade. "corte em 2 bytes -> 'sobraram 2 bytes
    # soltos'". Antes da correcao o laco saia em silencio com 1..3 bytes
    # sobrando, e o buffer cortado virava um dicionario de aparencia perfeita.
    # Em netlink bem formado TODO TLV e alinhado em 4: qualquer sobra E
    # truncamento.
    erra("2 bytes soltos apos o ultimo atributo sao truncamento, nao sobra",
         mod.ErroTruncado, "sobraram 2 bytes soltos",
         lambda: A(tlv(1, U32(7)) + b"\x0c\x00"))
    erra("1 byte solto tambem",
         mod.ErroTruncado, "sobraram 1 bytes soltos",
         lambda: A(tlv(1, U32(7)) + b"\x0c"))
    erra("3 bytes soltos tambem",
         mod.ErroTruncado, "sobraram 3 bytes soltos",
         lambda: A(tlv(1, U32(7)) + b"\x0c\x00\x08"))
    erra("...e a mensagem localiza a sobra (offset X de Y)",
         mod.ErroTruncado, "offset 8 de 10",
         lambda: A(tlv(1, U32(7)) + b"\x0c\x00"))

    # nla_len menor que o proprio header nunca e um atributo: aceitar seria
    # laco infinito ou payload negativo.
    erra("nla_len abaixo de NLA_HDRLEN e recusado",
         mod.ErroTruncado, "nla_len=2 invalido",
         lambda: A(tlv(1, U32(0), declara=2)))
    # As DUAS assercoes acima dependem do relogio que `erra` embute, e nao so
    # a de nla_len=0: com a guarda removida, `declara=2` ja entra em laco --
    # o indice avanca 4 e cai num nla_len=0 dentro do MESMO buffer. Foi assim
    # que a primeira tentativa de travar isto falhou, envolvendo em `com_prazo`
    # so a assercao que tem "laco infinito" no nome, enquanto a vizinha, sem
    # relogio, travava antes de chegar nela.
    erra("nla_len zero e recusado (e nao vira laco infinito)",
         mod.ErroTruncado, "nla_len=0 invalido",
         lambda: A(tlv(1, U32(0), declara=0)))


# ---------------------------------------------------------------------------
# uint
# ---------------------------------------------------------------------------

def s_uint():
    checkf("u8", lambda: U(b"\x2a"), 42)
    # INCIDENTE: as tres assercoes de u16 deste arquivo usavam o valor 22
    # (0x0016), cujo byte ALTO e zero -- ler o payload de 2 bytes como u8
    # devolve 22 igual, e a mutacao `return payload[0]` passava. E o mesmo
    # defeito de "amostra que nao distingue" que este conjunto ja corrigiu em
    # `diagnostico_modulo` (cinco pares em que duas colunas andavam juntas),
    # reincidindo no mesmo lote de mudancas. O valor de teste passou a ter os
    # DOIS bytes significativos; o 22 continua presente logo abaixo, porque e
    # o id real da familia netdev nesta maquina e vale como caso concreto.
    checkf("u16", lambda: U(struct.pack("=H", 0xBEEF)), 0xBEEF)
    checkf("u16 com byte alto nao nulo nao vira u8",
           lambda: U(b"\x16\x01"), 0x0116)
    checkf("u32", lambda: U(U32(0xDEADBEEF)), 0xDEADBEEF)
    checkf("u64", lambda: U(U64(0x23)), 0x23)

    # O caso que o comentario de `uint` promete e que nenhum teste cobria:
    # CTRL_ATTR_FAMILY_ID chega com 2 bytes. Se o codigo assumisse u32, o id da
    # familia sairia errado -- e a consulta iria para OUTRA familia netlink,
    # com resposta plausivel.
    checkf("id de familia de 2 bytes nao vira lixo", lambda: U(b"\x16\x00"), 22)
    # ...e o mesmo id com byte alto ocupado, para que a assercao acima nao
    # dependa do acaso de 22 caber em um byte.
    checkf("id de familia acima de 255 e lido inteiro", lambda: U(b"\x2c\x01"), 300)

    # u64 lido como u32 e o modo mais elegante de inventar dado: os 32 bits
    # baixos de 0x1_0000_0009 sao 0x9 = BASIC|XSK_ZEROCOPY. A ferramenta
    # anunciaria "zero-copy" com toda a confianca, tendo jogado fora o bit que
    # ela nao conhece -- justamente o bit que `flags_nomeadas` existe para
    # reportar.
    checkf("u64 com bit acima de 32 nao e truncado para u32",
           lambda: U(U64(0x100000009)), 0x100000009)
    checkf("...e o bit alto sobrevive ate a lista de nomes",
           lambda: [n for n in mod.flags_nomeadas(U(U64(0x100000009)),
                                                  mod.XDP_ACT)
                    if "DESCONHECIDO" in n],
           ["BIT_DESCONHECIDO_0x100000000"])

    for n in (0, 3, 5, 7, 16):
        erra(f"payload de {n} bytes nao e inteiro reconhecido",
             mod.ErroTruncado, f"{n} bytes", lambda n=n: U(b"\x00" * n))


# ---------------------------------------------------------------------------
# Genl._parse_datagrama  --  a funcao que foi separada PARA ser testada assim
# ---------------------------------------------------------------------------

class GenlFalso(mod.Genl):
    """Genl sem __init__: nenhum socket, nenhum bind, nenhum netlink.

    Herda os metodos reais; so o construtor e trocado. E por isso que o codigo
    sob teste aqui e literalmente o que roda em producao.
    """

    def __init__(self, ext_ack=True, sock=None):   # noqa: D107
        self.seq = 1
        self.pid = 4242
        self.ext_ack = ext_ack
        self.sock = sock


FAM = 22          # id de familia qualquer >= NLMSG_MIN_TYPE
g = GenlFalso()


def s_datagrama_bem_formado():
    um = nlmsg(FAM, 0, 1, genl(1, 1, tlv(1, U32(7))))
    resp, fim = g._parse_datagrama(um, 1, False, "teste")
    check("resposta unica: devolve (cmd, attrs)", resp, [(1, {1: U32(7)})])
    check("resposta unica sem dump: termina", fim, True)

    # A RAZAO DE EXISTIR desta funcao: um datagrama netlink carrega VARIAS
    # mensagens grudadas. Um laco que lesse so a primeira perderia interfaces
    # inteiras num DUMP -- em silencio, com rc=0.
    tres = (nlmsg(FAM, 0, 1, genl(1, 1, tlv(1, U32(7)))) +
            nlmsg(FAM, 0, 1, genl(1, 1, tlv(1, U32(8)))) +
            nlmsg(mod.NLMSG_DONE, 0, 1, struct.pack("=i", 0)))
    resp, fim = g._parse_datagrama(tres, 1, True, "teste")
    check("duas mensagens grudadas no MESMO datagrama saem as duas",
          [U(a[1]) for _c, a in resp], [7, 8])
    check("NLMSG_DONE no fim do datagrama termina o dump", fim, True)

    # Sequencia. A docstring de `transacao` explica que um eco de outra
    # transacao lido como resposta desta desloca TODOS os resultados em um --
    # com aparencia plausivel. Aqui o eco vem primeiro, e tem que ser
    # descartado.
    com_eco = (nlmsg(FAM, 0, 99, genl(1, 1, tlv(1, U32(111)))) +
               nlmsg(FAM, 0, 1, genl(1, 1, tlv(1, U32(7)))) +
               nlmsg(mod.NLMSG_DONE, 0, 1, struct.pack("=i", 0)))
    resp, _f = g._parse_datagrama(com_eco, 1, True, "teste")
    check("mensagem de outra sequencia e descartada, nao desloca o resultado",
          [U(a[1]) for _c, a in resp], [7])

    # NLMSG_DONE com sequencia alheia ainda termina: e a excecao explicita no
    # `if mseq != seq and mtype != NLMSG_DONE`.
    _r, fim = g._parse_datagrama(
        nlmsg(mod.NLMSG_DONE, 0, 99, struct.pack("=i", 0)), 1, True, "teste")
    check("NLMSG_DONE de outra sequencia ainda encerra o dump", fim, True)

    # NLMSG_NOOP e enchimento; ignorar e o comportamento certo, desde que a
    # mensagem seguinte continue sendo lida.
    resp, _f = g._parse_datagrama(
        nlmsg(mod.NLMSG_NOOP, 0, 1, b"") + um, 1, True, "teste")
    check("NLMSG_NOOP e pulado sem engolir a mensagem seguinte",
          [U(a[1]) for _c, a in resp], [7])

    # ACK (NLMSG_ERROR com error == 0) nao e resposta: e fim.
    resp, fim = g._parse_datagrama(
        nlmsg(mod.NLMSG_ERROR, 0, 1, struct.pack("=i", 0) + b"\x00" * 16),
        1, False, "teste")
    check("NLMSG_ERROR com errno 0 e ACK: zero respostas", resp, [])
    check("...e termina", fim, True)


def s_datagrama_cortado():
    erra("datagrama menor que um nlmsghdr",
         mod.ErroTruncado, "menos que um nlmsghdr",
         lambda: g._parse_datagrama(b"\x00" * 8, 1, False, "teste"))
    erra("...e a mensagem diz quantos bytes restaram",
         mod.ErroTruncado, "restam 8 bytes",
         lambda: g._parse_datagrama(b"\x00" * 8, 1, False, "teste"))
    erra("nlmsg_len menor que o header e recusado",
         mod.ErroTruncado, "nlmsg_len=8 invalido",
         lambda: g._parse_datagrama(nlmsg(FAM, 0, 1, b"\x00" * 8, declara=8),
                                    1, False, "teste"))
    erra("nlmsg_len maior que o datagrama e recusado",
         mod.ErroTruncado, "passa do fim",
         lambda: g._parse_datagrama(nlmsg(FAM, 0, 1, genl(1, 1), declara=64),
                                    1, False, "teste"))
    erra("mensagem sem genlmsghdr e recusada",
         mod.ErroTruncado, "sem genlmsghdr",
         lambda: g._parse_datagrama(nlmsg(FAM, 0, 1, b"\x01\x02"),
                                    1, False, "teste"))
    erra("NLMSG_OVERRUN diz que o kernel PERDEU mensagens",
         mod.ErroTruncado, "perdeu mensagens",
         lambda: g._parse_datagrama(nlmsg(mod.NLMSG_OVERRUN, 0, 1, U32(0)),
                                    1, False, "teste"))

    # Truncamento DENTRO dos atributos de uma mensagem bem formada por fora: o
    # nlmsghdr fecha certo e o corpo esta cortado. Tem que estourar tambem.
    corpo_cortado = genl(1, 1, tlv(3, U64(0x23))[:10])
    erra("corpo com TLV cortado estoura mesmo com nlmsg_len coerente",
         mod.ErroTruncado, "declara 12 bytes, restam 10",
         lambda: g._parse_datagrama(nlmsg(FAM, 0, 1, corpo_cortado),
                                    1, False, "teste"))


def _erro_netlink():
    g._parse_datagrama(
        nlmsg(mod.NLMSG_ERROR, 0, 1,
              struct.pack("=i", -22) + b"\x00" * 16), 1, False, "contexto X")


def s_nlmsg_error():
    erra("errno -22 vira ErroNetlink", mod.ErroNetlink, "netlink errno -22",
         _erro_netlink)
    erra("...com o strerror junto, nao so o numero",
         mod.ErroNetlink, "invalid argument", _erro_netlink)
    erra("...e com o contexto de quem pediu", mod.ErroNetlink, "contexto X",
         _erro_netlink)
    try:
        _erro_netlink()
    except mod.ErroNetlink as e:
        check("ErroNetlink preserva o errno para quem decide o codigo de saida",
              e.errno, -22)
    else:
        _falha("ErroNetlink preserva o errno", "nao levantou ErroNetlink")


# ---------------------------------------------------------------------------
# Genl._recebe  --  MSG_TRUNC
# ---------------------------------------------------------------------------

class SockFalso:
    """recvmsg de mentira. Exercita o TRATAMENTO da flag, nao a entrega dela.

    O kernel setar MSG_TRUNC de verdade exigiria um datagrama maior que o
    buffer -- ou seja, netlink real, que este teste se recusa a tocar. O que se
    afirma aqui e mais modesto, e e o que estava sem cobertura: SE a flag
    chegar, `_recebe` para. Antes deste teste, apagar o `if` inteiro passava.
    """

    def __init__(self, dados, flags):
        self.dados = dados
        self.flags = flags
        self.bufsize = None

    def recvmsg(self, bufsize):
        self.bufsize = bufsize
        return (self.dados, [], self.flags, None)


def s_recebe():
    g_ok = GenlFalso(sock=SockFalso(b"\x01\x02\x03\x04", 0))
    checkf("sem MSG_TRUNC, os bytes passam intactos",
           lambda: g_ok._recebe(4096), b"\x01\x02\x03\x04")
    check("o bufsize pedido chega ao recvmsg", g_ok.sock.bufsize, 4096)

    g_tr = GenlFalso(sock=SockFalso(b"\x01\x02\x03\x04", socket.MSG_TRUNC))
    erra("MSG_TRUNC vira excecao, e nao um datagrama menor",
         mod.ErroTruncado, "MSG_TRUNC", lambda: g_tr._recebe(4096))
    erra("...dizendo que os bytes perdidos NAO sao recuperaveis",
         mod.ErroTruncado, "nao sao recuperaveis", lambda: g_tr._recebe(4096))
    erra("...e nomeando o buffer que ficou pequeno",
         mod.ErroTruncado, "4096 bytes", lambda: g_tr._recebe(4096))


# ---------------------------------------------------------------------------
# Genl._ext_ack  --  REGRESSAO do segundo INCIDENTE
# ---------------------------------------------------------------------------

def corpo_err(errno_val, tlvs, eco=None, eco_len=None):
    """struct nlmsgerr { int error; struct nlmsghdr msg; } + eco + TLVs.

    Sem NLM_F_CAPPED o kernel ecoa o request inteiro, e o parser pula
    alinha4(nlmsg_len ecoado) -- por isso `eco_len` pode ser menor que o eco.
    """
    if eco is None:
        eco = b"\x00" * 16
        eco_len = 16
    cab = struct.pack("=IHHII", eco_len, 0, 0, 0, 0)
    return struct.pack("=i", errno_val) + cab + eco[16:] + tlvs


def s_ext_ack():
    ack_tlvs = mod.NLM_F_ACK_TLVS
    capped = mod.NLM_F_CAPPED

    # INCIDENTE, narrado em xdp-features.py: a primeira versao so olhava
    # NLMSGERR_ATTR_MSG e reportava "sem ext_ack" num DEV_GET sem ifindex. O
    # hexdump mostrou que o kernel TINHA anexado o diagnostico -- como
    # NLMSGERR_ATTR_MISS_TYPE=5 com valor 1, e nao como prosa.
    so_miss = corpo_err(-22, tlv(mod.NLMSGERR_ATTR_MISS_TYPE,
                                 U32(mod.NETDEV_A_DEV_IFINDEX)))
    checkf("MISS_TYPE sozinho e traduzido para o nome do atributo",
           lambda: g._ext_ack(so_miss, ack_tlvs | capped),
           "atributo obrigatorio ausente: NETDEV_A_DEV_IFINDEX")

    so_msg = corpo_err(-22, tlv(mod.NLMSGERR_ATTR_MSG, b"nao deu\x00"))
    checkf("ATTR_MSG sozinho vira a frase, sem o NUL final",
           lambda: g._ext_ack(so_msg, ack_tlvs | capped), "nao deu")

    os_dois = corpo_err(-22, tlv(mod.NLMSGERR_ATTR_MSG, b"nao deu\x00") +
                        tlv(mod.NLMSGERR_ATTR_MISS_TYPE, U32(1)))
    checkf("prosa e diagnostico estruturado aparecem os DOIS",
           lambda: g._ext_ack(os_dois, ack_tlvs | capped),
           "nao deu | atributo obrigatorio ausente: NETDEV_A_DEV_IFINDEX")

    desconhecido = corpo_err(-22, tlv(mod.NLMSGERR_ATTR_MISS_TYPE, U32(7)))
    checkf("atributo faltante que a tabela nao conhece sai pelo numero",
           lambda: g._ext_ack(desconhecido, ack_tlvs | capped),
           "atributo obrigatorio ausente: atributo 7")

    nest = corpo_err(-22, tlv(mod.NLMSGERR_ATTR_MISS_NEST, U32(20)))
    checkf("MISS_NEST diz o offset do nest",
           lambda: g._ext_ack(nest, ack_tlvs | capped),
           "faltando dentro do nest no offset 20")

    offs = corpo_err(-22, tlv(mod.NLMSGERR_ATTR_OFFS, U32(12)))
    checkf("ATTR_OFFS diz onde o atributo invalido estava",
           lambda: g._ext_ack(offs, ack_tlvs | capped),
           "offset do atributo invalido: 12")

    # Sem CAPPED, o request inteiro vem ecoado e o parser tem que pular
    # alinha4(nlmsg_len). Caso REAL de desalinhamento: um request cujo ultimo
    # atributo e nla_str("netdev") tem nla_len=11, o buffer carrega 12, e o
    # nlmsg_len fica 16+4+11 = 31 -- impar de proposito.
    eco_real = b"\x00" * 16 + genl(3, 1) + mod.nla_str(2, "netdev")
    sem_capped = corpo_err(-2, tlv(mod.NLMSGERR_ATTR_MSG, b"familia\x00"),
                           eco=eco_real, eco_len=31)
    checkf("sem NLM_F_CAPPED, o eco desalinhado e pulado com alinha4",
           lambda: g._ext_ack(sem_capped, ack_tlvs), "familia")

    checkf("sem a flag NLM_F_ACK_TLVS nao ha ext_ack a ler",
           lambda: g._ext_ack(so_miss, 0), None)
    checkf("com NETLINK_EXT_ACK desligado no socket, nao se inventa ext_ack",
           lambda: GenlFalso(ext_ack=False)._ext_ack(so_miss,
                                                     ack_tlvs | capped), None)
    checkf("TLVs alem do fim do corpo: None, sem estourar",
           lambda: g._ext_ack(struct.pack("=i", -22) + b"\x00" * 16,
                              ack_tlvs | capped), None)
    # Este `None` e deliberado e limitado: ext_ack e ENFEITE de um erro que ja
    # vai ser levantado com errno e contexto. Engolir o TLV podre nao esconde o
    # erro -- esconde so a explicacao extra. Fora daqui, engolir excecao e
    # proibido neste conjunto de arquivos.
    checkf("TLV podre nao derruba o relato do erro principal",
           lambda: g._ext_ack(corpo_err(-22, b"\xff\xff"),
                              ack_tlvs | capped), None)


# ---------------------------------------------------------------------------
# resolve_familia
# ---------------------------------------------------------------------------

class GDeMentira:
    """Duck-type de Genl com uma resposta enlatada. Nao abre socket."""

    def __init__(self, resposta):
        self.resposta = resposta
        self.pedidos = []

    def transacao(self, tipo, cmd, versao, attrs=b"", dump=False, contexto=""):
        self.pedidos.append((tipo, cmd, versao, attrs, dump, contexto))
        return self.resposta


def op(cmd, flags=None):
    corpo = tlv(mod.CTRL_ATTR_OP_ID, U32(cmd))
    if flags is not None:
        corpo += tlv(mod.CTRL_ATTR_OP_FLAGS, U32(flags))
    return corpo


def _resposta_ctrl():
    # CTRL_ATTR_OPS e nest de nests: cada filho e um indice cujo payload traz
    # OP_ID e OP_FLAGS. A terceira op vem SEM flags de proposito.
    ops_nest = (tlv(1, op(mod.NETDEV_CMD_DEV_GET, 0x0E)) +
                tlv(2, op(13, 0x03)) +
                tlv(3, op(14)))
    return [(mod.CTRL_CMD_GETFAMILY, {
        mod.CTRL_ATTR_FAMILY_ID: struct.pack("=H", 22),
        mod.CTRL_ATTR_VERSION: U32(1),
        mod.CTRL_ATTR_OPS: ops_nest,
    })]


def s_resolve_familia():
    fam = mod.resolve_familia(GDeMentira(_resposta_ctrl()), "netdev")
    # CTRL_ATTR_FAMILY_ID chega com 2 BYTES; e o caso que o comentario de
    # `uint` cita e que nenhum teste exercitava.
    check("id de familia de 2 bytes e lido como 22", fam.id, 22)
    check("versao da familia", fam.versao, 1)
    check("ops sai como {cmd: flags}", fam.ops,
          {mod.NETDEV_CMD_DEV_GET: 0x0E, 13: 0x03, 14: 0})

    # A afirmacao central do arquivo -- "a leitura nao precisa de root" -- vira
    # assercao aqui. Ressalva honesta: isto prova que a flag e LIDA do lugar
    # certo, nao que este kernel a publica assim.
    check("DEV_GET sem GENL_ADMIN_PERM e classificado como livre",
          bool(fam.ops[mod.NETDEV_CMD_DEV_GET] & mod.GENL_ADMIN_PERM), False)
    check("BIND_RX com GENL_ADMIN_PERM e classificado como ROOT",
          bool(fam.ops[13] & mod.GENL_ADMIN_PERM), True)
    check("op sem CTRL_ATTR_OP_FLAGS assume 0, e nao some da tabela",
          fam.ops[14], 0)

    sem_versao = [(mod.CTRL_CMD_GETFAMILY, {
        mod.CTRL_ATTR_FAMILY_ID: struct.pack("=H", 22)})]
    checkf("familia sem CTRL_ATTR_VERSION assume 1",
           lambda: mod.resolve_familia(GDeMentira(sem_versao), "netdev").versao,
           1)

    # GENL_NAMSIZ. Medido e citado no arquivo: nome de 22 chars devolve -EINVAL
    # da nla_policy ANTES da busca, e -EINVAL e -ENOENT sao coisas diferentes.
    # Barrar antes de enviar mantem a distincao, em vez de transformar erro de
    # digitacao em "a familia nao existe".
    erra("nome acima de GENL_NAMSIZ e barrado antes de ir ao kernel",
         ValueError, "o limite do kernel e 15",
         lambda: mod.resolve_familia(GDeMentira([]), "familia_que_nao_existe"))
    erra("...e a mensagem diz quantos caracteres vieram",
         ValueError, "tem 22 chars",
         lambda: mod.resolve_familia(GDeMentira([]), "familia_que_nao_existe"))
    erra("exatamente GENL_NAMSIZ chars ja e demais (o NUL conta)",
         ValueError, "tem 16 chars",
         lambda: mod.resolve_familia(GDeMentira([]), "a" * 16))
    nao_erra("15 chars passam (a fronteira do outro lado)",
             lambda: mod.resolve_familia(
                 GDeMentira([(mod.CTRL_CMD_GETFAMILY,
                              {mod.CTRL_ATTR_FAMILY_ID: b"\x16\x00"})]),
                 "a" * 15))

    erra("kernel que nao responde nada vira ErroNetlink, nao AttributeError",
         mod.ErroNetlink, 'familia "netdev"',
         lambda: mod.resolve_familia(GDeMentira([]), "netdev"))

    gd = GDeMentira(_resposta_ctrl())
    mod.resolve_familia(gd, "netdev")
    check("o nome vai NUL-terminado no CTRL_ATTR_FAMILY_NAME",
          gd.pedidos[0][3], mod.nla_str(mod.CTRL_ATTR_FAMILY_NAME, "netdev"))
    check("a resolucao usa a familia de CONTROLE, o unico id estatico",
          gd.pedidos[0][0], mod.GENL_ID_CTRL)


# ---------------------------------------------------------------------------
# nome_seguro
# ---------------------------------------------------------------------------

_indextoname_real = socket.if_indextoname
PERMITIDOS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
                 "0123456789._:@-")


def com_nome(bruto, fn):
    """Roda `fn` com if_indextoname devolvendo `bruto`. Restaura sempre."""
    socket.if_indextoname = lambda _i: bruto
    try:
        return fn()
    finally:
        socket.if_indextoname = _indextoname_real


def s_nome_seguro():
    checkf("nome comum passa inteiro",
           lambda: com_nome("enp8s0", lambda: mod.nome_seguro(7)), "enp8s0")
    checkf("todos os caracteres da lista branca sobrevivem",
           lambda: com_nome("veth-1_2.3:4@ns", lambda: mod.nome_seguro(7)),
           "veth-1_2.3:4@ns")
    checkf("metacaracter de shell vira '?'",
           lambda: com_nome("eth0; rm -rf /", lambda: mod.nome_seguro(7)),
           "eth0??rm?-rf??")
    checkf("substituicao de comando vira '?'",
           lambda: com_nome("veth0$(id)`x`", lambda: mod.nome_seguro(7)),
           "veth0??id??x?")
    # isascii() e uma checagem SEPARADA de isalnum(): 'e' com acento e
    # alfanumerico para o Python e nao e ASCII. Sem o isascii, ele passaria.
    checkf("alfanumerico nao-ASCII tambem vira '?'",
           lambda: com_nome("eth0é", lambda: mod.nome_seguro(7)), "eth0?")
    checkf("byte de controle vira '?'",
           lambda: com_nome("eth0\x07\x00", lambda: mod.nome_seguro(7)),
           "eth0??")

    for hostil in ("a\nb", "a b", "a$b", "a`b", "a'b", 'a"b', "a\\b", "a;b",
                   "a|b", "a&b", "a>b", "a\tb", "a*b", "a=b"):
        saida = com_nome(hostil, lambda: mod.nome_seguro(7))
        if set(saida) <= PERMITIDOS | {"?"} and len(saida) == len(hostil):
            _ok(f"nome hostil {hostil!r} sai so com caracteres da lista branca")
        else:
            _falha(f"nome hostil {hostil!r}", f"saiu {saida!r}")

    def _some(_i):
        raise OSError(19, "No such device")

    socket.if_indextoname = _some
    try:
        checkf("interface que sumiu entre o dump e a resolucao vira 'ifN'",
               lambda: mod.nome_seguro(17), "if17")
    finally:
        socket.if_indextoname = _indextoname_real

    # A consequencia pratica da higienizacao, medida no formato de saida: um
    # nome de interface NAO pode forjar uma linha KEY=VALUE. Sem isso, quem
    # controlasse o nome de um veth escreveria o proprio veredito no relatorio
    # -- e `xdp_valor` devolve a PRIMEIRA ocorrencia, entao a linha forjada,
    # que vem antes, venceria a verdadeira.
    dev = {"ifindex": 7, "xdp_features": 0, "zc_max_segs": None,
           "rx_meta": None, "xsk": None, "desconhecidos": {}}
    linhas = com_nome("a\nVEREDITO=zero-copy", lambda: mod.bloco(dev))
    check("nome de interface nao consegue forjar uma segunda linha VEREDITO",
          [ln for ln in linhas if ln.startswith("VEREDITO=")],
          ["VEREDITO=sem-xdp"])
    check("...e o nome forjado fica contido na linha IFACE",
          [ln for ln in linhas if ln.startswith("IFACE=")],
          ["IFACE=a?VEREDITO?zero-copy"])


# ---------------------------------------------------------------------------
# veredito_de: a distincao que o projeto inteiro defende
# ---------------------------------------------------------------------------

def s_veredito():
    check("atributo ausente -> sem-atributo (INCONCLUSIVO)",
          mod.veredito_de(None), "sem-atributo")
    check("atributo presente valendo 0 -> sem-xdp (o driver RESPONDEU)",
          mod.veredito_de(0), "sem-xdp")
    check("BASIC -> nativo-sem-zc", mod.veredito_de(0x1), "nativo-sem-zc")
    check("BASIC|XSK_ZEROCOPY -> zero-copy", mod.veredito_de(0x9), "zero-copy")


print("== L1: camada netlink de xdp-features.py ==")

executa("parse_attrs: TLVs bem formados", s_attrs_bem_formados)
executa("parse_attrs: REGRESSAO dos truncamentos narrados no INCIDENTE",
        s_attrs_truncados)
executa("uint: o tamanho REAL do payload manda", s_uint)
executa("_parse_datagrama: bytes arbitrarios, como a docstring prometia",
        s_datagrama_bem_formado)
executa("_parse_datagrama: entrada cortada nao vira dado inventado",
        s_datagrama_cortado)
executa("_parse_datagrama: NLMSG_ERROR vira ErroNetlink com errno legivel",
        s_nlmsg_error)
executa("_recebe: MSG_TRUNC e perda IRRECUPERAVEL, nao um datagrama menor",
        s_recebe)
executa("_ext_ack: o diagnostico ESTRUTURADO nao pode ser descartado",
        s_ext_ack)
executa("resolve_familia: nome, id de 2 bytes e politica de privilegio",
        s_resolve_familia)
executa("nome_seguro: nome de interface e entrada hostil ate prova em contrario",
        s_nome_seguro)
executa("veredito_de: 'nao anunciou' e 'anunciou zero' sao classes distintas",
        s_veredito)

print("")
if abortadas:
    print(f"  ATENCAO: {abortadas} secao(oes) abortaram. O numero abaixo e o de")
    print("           assercoes ALCANCADAS, nao o de esperadas: as que vinham")
    print("           depois do ponto de aborto nem chegaram a rodar.")
if falhas:
    print(f"L1 netlink: {falhas} falha(s) em {total} assercoes")
    sys.exit(1)
print(f"L1 netlink: todas as {total} assercoes passaram")
PY
