#!/usr/bin/env python3
"""Le as xdp-features de uma interface SEM ROOT, via netlink generico.

POR QUE ESTE SCRIPT EXISTE

`scripts/xdp-zerocopy.sh` dependia de `xdp-loader features`, que aborta com
"This program must be run as root." antes de abrir qualquer socket. Medido:

    $ id -u                        ->  1000
    $ xdp-loader features enp8s0   ->  "This program must be run as root."  (rc=1)

O efeito era pior do que perder uma seção: o script caía em "Resultado
inconclusivo" e o leitor sem root não descobria NADA -- nem o fato, que o
kernel publica abertamente, de que a Realtek r8169 desta máquina não tem XDP
nativo nenhum. O documento afirmava `BASIC: no` e a ferramenta dizia
"inconclusivo": ferramenta e texto discordando, que é o padrão de erro que
este projeto já corrigiu quatro vezes.

A causa não era o dado ser privilegiado, era a FERRAMENTA ser privilegiada.
`xdp-loader` exige root porque carrega programa eBPF e abre mapa BPF; a
LEITURA de xdp-features é netlink puro, e o kernel declara que ela é livre:

    $ ./scripts/xdp-features.py --politica
      NETDEV_CMD_DEV_GET   0x0e  livre  [CAP_DO|CAP_DUMP|CAP_HASPOL]
      NETDEV_CMD_BIND_RX   0x0b  ROOT (GENL_ADMIN_PERM)

O bit GENL_ADMIN_PERM (0x01, genetlink.h:21) está AUSENTE de DEV_GET e
PRESENTE em BIND_RX. Isso é a política do kernel lida da fonte, não uma
inferência a partir de "rodou e deu certo".

REGRA DERIVADA, e ela vale além deste arquivo: antes de escrever "precisa de
root", verifique se quem exige privilégio é a interface do kernel ou o
programa que você escolheu para falar com ela. Ferramenta privilegiada não é
o mesmo que dado privilegiado.

POR QUE KEY=VALUE, E NÃO JSON

A saída é consumida por `scripts/xdp-zerocopy.sh`, que é bash. JSON exigiria
`jq`: está instalado nesta máquina, e NÃO está na CI -- `.github/workflows/ci.yml`
instala apenas dpdk-dev, pkg-config, ninja-build, python3-pip e g++-14. Um
formato que obriga a instalar um pacote a mais para ler a resposta contraria a
razão de existir deste arquivo, que é justamente remover uma dependência
(xdp-tools) e um privilégio (root).

KEY=VALUE é lido com `awk -F=` sem dependência nenhuma. O chamador NUNCA deve
usar `eval`: os valores vêm do kernel, e `eval` sobre saída de programa é
injeção esperando acontecer. Por isso os nomes de interface são higienizados
aqui (ver `nome_seguro`) -- defesa em profundidade, não substituto da regra.

Toda a saída (stdout e stderr) é ASCII sem acento, porque ela é embutida no
relatório de `xdp-zerocopy.sh`, e a convenção do projeto é que mensagem ao
usuário não leva acento. Comentário e docstring levam.

Só stdlib: socket, struct, os, sys. Nada de pyroute2 ou libbpf -- isto tem que
rodar na máquina de qualquer estudante, inclusive num container sem toolchain.

CÓDIGOS DE SAÍDA (o chamador PRECISA distinguir os quatro)

    0  sucesso
    2  uso incorreto (argumento desconhecido, valor inválido)
    3  o kernel não tem a família netlink "netdev" -> INCONCLUSIVO, jamais
       "a placa não suporta". Colapsar esses dois é o bug original.
    4  erro de netlink na consulta (a família existe, a consulta falhou)
    5  a interface não existe nesta máquina

Uso:
    scripts/xdp-features.py                 # todas as interfaces
    scripts/xdp-features.py enp8s0          # uma interface
    scripts/xdp-features.py --politica      # o que o kernel exige de privilégio
    scripts/xdp-features.py --decodificar 0x23   # decodifica offline, sem netlink
"""

import os
import socket
import struct
import sys

# ---------------------------------------------------------------------------
# Constantes dos headers desta máquina (kernel 7.0.0-31-generic). Cada bloco
# cita arquivo:linha de propósito: quando o kernel mudar, a citação envelhece
# junto e o descompasso fica visível na revisão, em vez de virar número mágico.
# ---------------------------------------------------------------------------

NETLINK_GENERIC = 16          # linux/netlink.h:25

NLM_F_REQUEST = 0x01          # linux/netlink.h:62-73
NLM_F_ROOT = 0x100
NLM_F_MATCH = 0x200
NLM_F_DUMP = NLM_F_ROOT | NLM_F_MATCH
NLM_F_CAPPED = 0x100          # linux/netlink.h:86-87 (mesmos numeros, no ACK)
NLM_F_ACK_TLVS = 0x200

NLMSG_NOOP = 0x1              # linux/netlink.h:112-117
NLMSG_ERROR = 0x2
NLMSG_DONE = 0x3
NLMSG_OVERRUN = 0x4
NLMSG_MIN_TYPE = 0x10

# struct nlmsghdr = u32 len + u16 type + u16 flags + u32 seq + u32 pid = 16
NLMSG_HDRLEN = 16             # linux/netlink.h:98-100
NLA_HDRLEN = 4                # struct nlattr = u16 nla_len + u16 nla_type
NLA_F_NESTED = 1 << 15        # linux/netlink.h:240-246
NLA_F_NET_BYTEORDER = 1 << 14
NLA_TYPE_MASK = ~(NLA_F_NESTED | NLA_F_NET_BYTEORDER) & 0xFFFF

# SOL_NETLINK não está em uapi/linux; vem de asm-generic/socket.h.
SOL_NETLINK = 270
NETLINK_EXT_ACK = 11          # linux/netlink.h:173

NLMSGERR_ATTR_MSG = 1         # linux/netlink.h:150-157
NLMSGERR_ATTR_OFFS = 2
NLMSGERR_ATTR_MISS_TYPE = 5
NLMSGERR_ATTR_MISS_NEST = 6

# A família de CONTROLE é o único id estático que existe. Todas as outras são
# alocadas na ordem em que os módulos se registram no boot -- por isso
# "netdev" PRECISA ser resolvida por nome. Nesta máquina ela saiu 22; fixar
# esse número é o erro que funciona aqui e lê a família errada na máquina
# do leitor.
GENL_ID_CTRL = NLMSG_MIN_TYPE  # genetlink.h:30
GENL_HDRLEN = 4                # genetlink.h:13-19
CTRL_CMD_GETFAMILY = 3         # genetlink.h:44
CTRL_ATTR_FAMILY_ID = 1        # genetlink.h:59-64
CTRL_ATTR_FAMILY_NAME = 2
CTRL_ATTR_VERSION = 3
CTRL_ATTR_MAXATTR = 5
CTRL_ATTR_OPS = 6
CTRL_ATTR_OP_ID = 1            # genetlink.h:74-79
CTRL_ATTR_OP_FLAGS = 2

# genetlink.h:8 -- nome maior que isso é rejeitado pela nla_policy com -EINVAL
# ANTES da busca. Medido: "familia_que_nao_existe" (22 chars) devolve -EINVAL,
# "naoexiste" (9 chars) devolve -ENOENT. Tratar os dois como "não existe"
# esconderia um erro de digitação no código.
GENL_NAMSIZ = 16

GENL_ADMIN_PERM = 0x01         # genetlink.h:21-25
GENL_OP_FLAGS = [
    (0x01, "GENL_ADMIN_PERM"),
    (0x02, "CAP_DO"),
    (0x04, "CAP_DUMP"),
    (0x08, "CAP_HASPOL"),
    (0x10, "GENL_UNS_ADMIN_PERM"),
]

NETDEV_FAMILY_NAME = "netdev"  # linux/netdev.h:10-11
NETDEV_CMD_DEV_GET = 1         # linux/netdev.h:216

NETDEV_CMD_NOMES = {
    1: "NETDEV_CMD_DEV_GET", 5: "NETDEV_CMD_PAGE_POOL_GET",
    9: "NETDEV_CMD_PAGE_POOL_STATS_GET", 10: "NETDEV_CMD_QUEUE_GET",
    11: "NETDEV_CMD_NAPI_GET", 12: "NETDEV_CMD_QSTATS_GET",
    13: "NETDEV_CMD_BIND_RX", 14: "NETDEV_CMD_NAPI_SET",
    15: "NETDEV_CMD_BIND_TX",
}

# linux/netdev.h:88-93
NETDEV_A_DEV_IFINDEX = 1
NETDEV_A_DEV_PAD = 2
NETDEV_A_DEV_XDP_FEATURES = 3
NETDEV_A_DEV_XDP_ZC_MAX_SEGS = 4
NETDEV_A_DEV_XDP_RX_METADATA_FEATURES = 5
NETDEV_A_DEV_XSK_FEATURES = 6

# NETDEV_A_DEV_PAD existe porque xdp_features é u64 e o kernel emite com
# nla_put_u64_64bit(), que insere um atributo de padding para manter o payload
# de 64 bits alinhado em 8. O parser IGNORA esse atributo; tratá-lo como campo
# desconhecido polui o relatório com um falso "atributo que não conheço".

# linux/netdev.h:29-40 (enum netdev_xdp_act)
XDP_ACT = [
    (1 << 0, "NETDEV_XDP_ACT_BASIC"),
    (1 << 1, "NETDEV_XDP_ACT_REDIRECT"),
    (1 << 2, "NETDEV_XDP_ACT_NDO_XMIT"),
    (1 << 3, "NETDEV_XDP_ACT_XSK_ZEROCOPY"),
    (1 << 4, "NETDEV_XDP_ACT_HW_OFFLOAD"),
    (1 << 5, "NETDEV_XDP_ACT_RX_SG"),
    (1 << 6, "NETDEV_XDP_ACT_NDO_XMIT_SG"),
]
XDP_ACT_BASIC = 1 << 0
XDP_ACT_XSK_ZEROCOPY = 1 << 3

# linux/netdev.h:51-55
XDP_RX_META = [
    (1 << 0, "NETDEV_XDP_RX_METADATA_TIMESTAMP"),
    (1 << 1, "NETDEV_XDP_RX_METADATA_HASH"),
    (1 << 2, "NETDEV_XDP_RX_METADATA_VLAN_TAG"),
]

# linux/netdev.h:66-70
XSK_FLAGS = [
    (1 << 0, "NETDEV_XSK_FLAGS_TX_TIMESTAMP"),
    (1 << 1, "NETDEV_XSK_FLAGS_TX_CHECKSUM"),
    (1 << 2, "NETDEV_XSK_FLAGS_TX_LAUNCH_TIME_FIFO"),
]


class ErroNetlink(Exception):
    """NLMSG_ERROR do kernel, com errno e ext_ack já decodificados."""

    def __init__(self, errno_val, ext_msg=None, contexto=""):
        self.errno = errno_val
        self.ext_msg = ext_msg
        nome = os.strerror(abs(errno_val)) if errno_val else "sucesso"
        txt = f"{contexto}: netlink errno {errno_val} ({nome})"
        if ext_msg:
            txt += f' -- ext_ack: "{ext_msg}"'
        super().__init__(txt)


class ErroTruncado(Exception):
    """A mensagem não coube no buffer, ou o header declara mais bytes do que
    chegaram. Nos dois casos o parse PARA -- não se adivinha o resto."""


def alinha4(n):
    return (n + 3) & ~3


# ---------------------------------------------------------------------------
# Atributos (TLV)
# ---------------------------------------------------------------------------

def nla(tipo, payload: bytes) -> bytes:
    """struct nlattr + payload + padding para 4 bytes.

    nla_len conta header + payload SEM o padding final (netlink.h:218-227),
    mas o próximo atributo começa em NLA_ALIGN(nla_len). Errar isso é o bug
    clássico de netlink: o kernel devolve -EINVAL e não diz onde.
    """
    corpo = struct.pack("=HH", NLA_HDRLEN + len(payload), tipo) + payload
    return corpo + b"\x00" * (alinha4(len(corpo)) - len(corpo))


def nla_u32(tipo, valor):
    return nla(tipo, struct.pack("=I", valor))


def nla_str(tipo, texto):
    # NLA_STRING no kernel é NUL-terminada. Sem o \0 a nla_policy de
    # CTRL_ATTR_FAMILY_NAME rejeita com -EINVAL.
    return nla(tipo, texto.encode() + b"\x00")


def parse_attrs(buf: bytes, offset=0):
    """Percorre um bloco de TLVs e devolve {tipo: payload_bytes}.

    Devolve o payload CRU de propósito: quem chama decide se aquilo é u32, u64
    ou string. Decodificar cedo demais aqui é como um parser quebra em silêncio
    no dia em que o kernel muda o tamanho de um campo.

    INCIDENTE. A primeira versão saía do laço em silêncio quando sobravam 1..3
    bytes, aceitando um buffer cortado no meio de um header de atributo. Em
    netlink bem formado TODO TLV é alinhado em 4, logo qualquer sobra É
    truncamento. Verificado cortando um dump real:
        corte em 42 bytes -> "declara 12 bytes, restam 10"
        corte em  2 bytes -> "sobraram 2 bytes soltos"
    Antes da correção o corte de 2 bytes passava sem uma palavra.

    Regressão travada em `scripts/tests/l1_xdp_netlink.sh`, com estas duas
    frases como asserção literal. Ela ficou sem teste até bem depois da
    correção, e nesse intervalo apagar qualquer uma das duas checagens passava
    limpo pela suíte -- o mesmo bug voltando pela mesma porta.
    """
    attrs = {}
    i = offset
    fim = len(buf)
    while i + NLA_HDRLEN <= fim:
        nla_len, nla_type = struct.unpack_from("=HH", buf, i)
        if nla_len < NLA_HDRLEN:
            raise ErroTruncado(f"nla_len={nla_len} invalido no offset {i}")
        if i + nla_len > fim:
            raise ErroTruncado(f"atributo no offset {i} declara {nla_len} "
                               f"bytes, restam {fim - i}")
        attrs[nla_type & NLA_TYPE_MASK] = buf[i + NLA_HDRLEN: i + nla_len]
        i += alinha4(nla_len)
    if i != fim:
        raise ErroTruncado(f"sobraram {fim - i} bytes soltos apos o ultimo "
                           f"atributo (offset {i} de {fim})")
    return attrs


def uint(payload: bytes):
    """u8/u16/u32/u64 conforme o tamanho REAL do payload.

    Não se assume "xdp_features é u64" na hora de desempacotar. O header diz
    que é u64 hoje; o payload diz o que chegou agora. Isso não é preciosismo:
    CTRL_ATTR_FAMILY_ID tem 2 bytes, e desempacotá-lo como u32 lê o atributo
    seguinte junto -- o id da família sairia errado sem erro nenhum.
    """
    n = len(payload)
    if n == 1:
        return payload[0]
    if n == 2:
        return struct.unpack("=H", payload)[0]
    if n == 4:
        return struct.unpack("=I", payload)[0]
    if n == 8:
        return struct.unpack("=Q", payload)[0]
    raise ErroTruncado(f"payload inteiro com tamanho inesperado: {n} bytes")


def flags_nomeadas(valor, tabela):
    """Bitmask -> lista de nomes. Bit que a tabela não conhece é REPORTADO.

    Engolir bit desconhecido é como o material fica desatualizado sem ninguém
    notar: o kernel ganha NETDEV_XDP_ACT_* novo, a placa passa a anunciá-lo, e
    a ferramenta continua imprimindo a lista antiga com cara de completa.
    """
    nomes = [nome for bit, nome in tabela if valor & bit]
    conhecidos = 0
    for bit, _ in tabela:
        conhecidos |= bit
    resto = valor & ~conhecidos
    if resto:
        nomes.append(f"BIT_DESCONHECIDO_0x{resto:x}")
    return nomes


# ---------------------------------------------------------------------------
# Socket
# ---------------------------------------------------------------------------

class Genl:
    """Sessão netlink genérico. Um socket, uma sequência, sem estado global."""

    def __init__(self):
        self.seq = 0
        self.sock = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW,
                                  NETLINK_GENERIC)
        # Buffer generoso: um DUMP numa máquina com muitos veth/container passa
        # do default, e a perda em netlink é SILENCIOSA. Medido: 801 interfaces
        # cabem em 2 datagramas de 32 KiB e 18 KiB.
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
        try:
            # Sem EXT_ACK, um -EINVAL de netlink é indistinguível de outro.
            self.sock.setsockopt(SOL_NETLINK, NETLINK_EXT_ACK, 1)
            self.ext_ack = True
        except OSError:
            self.ext_ack = False   # kernel < 4.12: degrada, não falha
        self.sock.bind((0, 0))     # pid=0 -> o kernel atribui
        self.pid = self.sock.getsockname()[0]

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.sock.close()

    def _envia(self, tipo, flags, cmd, versao, attrs=b""):
        self.seq += 1
        payload = struct.pack("=BBH", cmd, versao, 0) + attrs
        total = NLMSG_HDRLEN + len(payload)
        msg = struct.pack("=IHHII", total, tipo, flags | NLM_F_REQUEST,
                          self.seq, self.pid) + payload
        self.sock.send(msg)
        return self.seq

    def _recebe(self, bufsize=1 << 20):
        """Um datagrama, com recvmsg para poder VER MSG_TRUNC.

        recv() comum truncaria em silêncio: a mensagem cortada tem nlmsg_len
        maior que os bytes recebidos, e um parser ingênuo segue lendo lixo.
        Netlink é datagrama -- o que ficou de fora é PERDIDO, não fica na fila.
        """
        dados, _anc, flags, _addr = self.sock.recvmsg(bufsize)
        if flags & socket.MSG_TRUNC:
            raise ErroTruncado(f"MSG_TRUNC: datagrama maior que o buffer de "
                               f"{bufsize} bytes; os bytes perdidos NAO sao "
                               f"recuperaveis")
        return dados

    def transacao(self, tipo, cmd, versao, attrs=b"", dump=False, contexto=""):
        """Envia e coleta as respostas. Devolve [(cmd, {tipo: payload})].

        NÃO se pede NLM_F_ACK aqui, e isso é deliberado. Num DUMP o kernel
        manda o ACK ANTES dos dados; tratado como fim, o resultado é uma lista
        VAZIA com rc=0. Pior: um ACK pendente de uma transação anterior é lido
        como primeira resposta desta, e TODOS os resultados saem deslocados em
        um -- com aparência perfeitamente plausível. Por isso, além de não
        pedir ACK, a sequência é conferida em _parse_datagrama.
        """
        seq = self._envia(tipo, NLM_F_DUMP if dump else 0, cmd, versao, attrs)
        respostas = []
        terminou = False
        while not terminou:
            parciais, terminou = self._parse_datagrama(
                self._recebe(), seq, dump, contexto or f"cmd {cmd}")
            respostas.extend(parciais)
        return respostas

    def _parse_datagrama(self, buf, seq, dump, contexto=""):
        """Separa PARSE de I/O -- de propósito.

        Um datagrama netlink carrega VÁRIAS mensagens grudadas. Com essa
        lógica dentro do laço de recv() não há como exercitá-la com entrada
        cortada; separada, dá para alimentar bytes arbitrários e conferir que
        o truncamento vira exceção em vez de dado inventado.

        Quem faz isso é `scripts/tests/l1_xdp_netlink.sh`. A frase acima ficou
        um tempo sendo só uma promessa: o código foi refatorado PARA ser
        testável e depois não foi testado, o que é pior do que não refatorar --
        rende a confiança sem render a verificação.
        """
        respostas = []
        terminou = False
        off = 0
        n = len(buf)
        while off < n:
            if n - off < NLMSG_HDRLEN:
                raise ErroTruncado(f"restam {n - off} bytes, menos que um "
                                   f"nlmsghdr ({NLMSG_HDRLEN})")
            mlen, mtype, mflags, mseq, _pid = struct.unpack_from("=IHHII",
                                                                 buf, off)
            if mlen < NLMSG_HDRLEN:
                raise ErroTruncado(f"nlmsg_len={mlen} invalido")
            if off + mlen > n:
                raise ErroTruncado(f"nlmsg_len={mlen} passa do fim do "
                                   f"datagrama ({n - off} bytes restantes)")
            corpo = buf[off + NLMSG_HDRLEN: off + mlen]

            if mseq != seq and mtype != NLMSG_DONE:
                off += alinha4(mlen)   # eco de outra transação nossa
                continue

            if mtype == NLMSG_ERROR:
                err = struct.unpack_from("=i", corpo, 0)[0]
                if err == 0:
                    terminou = True
                    off += alinha4(mlen)
                    continue
                raise ErroNetlink(err, self._ext_ack(corpo, mflags), contexto)
            if mtype == NLMSG_DONE:
                terminou = True
                off += alinha4(mlen)
                continue
            if mtype == NLMSG_NOOP:
                off += alinha4(mlen)
                continue
            if mtype == NLMSG_OVERRUN:
                raise ErroTruncado("NLMSG_OVERRUN: o kernel perdeu mensagens")

            if len(corpo) < GENL_HDRLEN:
                raise ErroTruncado("mensagem sem genlmsghdr")
            gcmd = struct.unpack_from("=BBH", corpo, 0)[0]
            respostas.append((gcmd, parse_attrs(corpo, GENL_HDRLEN)))
            off += alinha4(mlen)
            if not dump:
                terminou = True
        return respostas, terminou

    def _ext_ack(self, corpo, mflags):
        """TLVs de ext_ack -> frase útil.

        Layout (netlink.h:119-131): struct nlmsgerr { int error; struct
        nlmsghdr msg; }, o request ecoado (a menos que NLM_F_CAPPED), e então
        os TLVs de enum nlmsgerr_attrs.

        INCIDENTE. A primeira versão só olhava NLMSGERR_ATTR_MSG (a string) e
        reportava "sem ext_ack" num DEV_GET sem ifindex. O hexdump mostrou que
        o kernel TINHA anexado o diagnóstico -- como NLMSGERR_ATTR_MISS_TYPE=5
        com valor 1, e não como prosa. Família gerada por YNL reporta atributo
        faltante de forma ESTRUTURADA; ler só ATTR_MSG joga fora justamente o
        diagnóstico mais acionável dos dois.

        Regressão travada em `scripts/tests/l1_xdp_netlink.sh`: um corpo de
        erro que traz APENAS MISS_TYPE precisa render a frase inteira.
        """
        if not self.ext_ack or not (mflags & NLM_F_ACK_TLVS):
            return None
        try:
            if mflags & NLM_F_CAPPED:
                tlv_off = 4 + NLMSG_HDRLEN
            else:
                tlv_off = 4 + alinha4(struct.unpack_from("=I", corpo, 4)[0])
            if tlv_off >= len(corpo):
                return None
            attrs = parse_attrs(corpo[tlv_off:])
        except (ErroTruncado, struct.error):
            return None

        partes = []
        msg = attrs.get(NLMSGERR_ATTR_MSG)
        if msg:
            partes.append(msg.rstrip(b"\x00").decode(errors="replace"))
        miss = attrs.get(NLMSGERR_ATTR_MISS_TYPE)
        if miss is not None:
            nome = {NETDEV_A_DEV_IFINDEX: "NETDEV_A_DEV_IFINDEX"}.get(
                uint(miss), f"atributo {uint(miss)}")
            partes.append(f"atributo obrigatorio ausente: {nome}")
        nest = attrs.get(NLMSGERR_ATTR_MISS_NEST)
        if nest is not None:
            partes.append(f"faltando dentro do nest no offset {uint(nest)}")
        offs = attrs.get(NLMSGERR_ATTR_OFFS)
        if offs is not None:
            partes.append(f"offset do atributo invalido: {uint(offs)}")
        return " | ".join(partes) if partes else None


# ---------------------------------------------------------------------------
# Camada netdev
# ---------------------------------------------------------------------------

class Familia:
    def __init__(self, fid, versao, ops):
        self.id = fid
        self.versao = versao
        self.ops = ops      # {cmd_id: flags}


def resolve_familia(g, nome):
    """CTRL_CMD_GETFAMILY -> id da família e a política de cada comando."""
    if len(nome) >= GENL_NAMSIZ:
        raise ValueError(f'nome de familia "{nome}" tem {len(nome)} chars; '
                         f"o limite do kernel e {GENL_NAMSIZ - 1}")
    r = g.transacao(GENL_ID_CTRL, CTRL_CMD_GETFAMILY, 1,
                    nla_str(CTRL_ATTR_FAMILY_NAME, nome),
                    contexto=f'resolver familia "{nome}"')
    if not r:
        raise ErroNetlink(-2, contexto=f'familia "{nome}"')
    attrs = r[0][1]

    ops = {}
    bruto = attrs.get(CTRL_ATTR_OPS)
    if bruto:
        # CTRL_ATTR_OPS é nest de nests: cada filho é um índice (1, 2, 3...)
        # cujo payload traz CTRL_ATTR_OP_ID e CTRL_ATTR_OP_FLAGS.
        for _idx, op_bytes in parse_attrs(bruto).items():
            op = parse_attrs(op_bytes)
            if CTRL_ATTR_OP_ID in op:
                ops[uint(op[CTRL_ATTR_OP_ID])] = (
                    uint(op[CTRL_ATTR_OP_FLAGS])
                    if CTRL_ATTR_OP_FLAGS in op else 0)

    return Familia(uint(attrs[CTRL_ATTR_FAMILY_ID]),
                   uint(attrs[CTRL_ATTR_VERSION])
                   if CTRL_ATTR_VERSION in attrs else 1,
                   ops)


def decodifica_dev(attrs):
    """Atributos crus de um netdev -> dicionário com os campos que importam."""
    d = {"ifindex": None, "xdp_features": None, "zc_max_segs": None,
         "rx_meta": None, "xsk": None, "desconhecidos": {}}
    for tipo, payload in attrs.items():
        if tipo == NETDEV_A_DEV_IFINDEX:
            d["ifindex"] = uint(payload)
        elif tipo == NETDEV_A_DEV_XDP_FEATURES:
            d["xdp_features"] = uint(payload)
        elif tipo == NETDEV_A_DEV_XDP_ZC_MAX_SEGS:
            d["zc_max_segs"] = uint(payload)
        elif tipo == NETDEV_A_DEV_XDP_RX_METADATA_FEATURES:
            d["rx_meta"] = uint(payload)
        elif tipo == NETDEV_A_DEV_XSK_FEATURES:
            d["xsk"] = uint(payload)
        elif tipo == NETDEV_A_DEV_PAD:
            pass    # padding de 64 bits; ver comentário na declaração
        else:
            d["desconhecidos"][tipo] = payload.hex()
    return d


def consulta(g, fam, ifindex=None):
    if ifindex is None:
        r = g.transacao(fam.id, NETDEV_CMD_DEV_GET, fam.versao, dump=True,
                        contexto="DUMP NETDEV_CMD_DEV_GET")
    else:
        r = g.transacao(fam.id, NETDEV_CMD_DEV_GET, fam.versao,
                        nla_u32(NETDEV_A_DEV_IFINDEX, ifindex),
                        contexto=f"NETDEV_CMD_DEV_GET ifindex={ifindex}")
    return [decodifica_dev(a) for _cmd, a in r]


# ---------------------------------------------------------------------------
# Veredito e saída
#
# A partir daqui é lógica PURA: recebe números, devolve texto. É esta parte que
# `scripts/tests/l1_xdp.sh` exercita pela linha de comando (`--decodificar`),
# porque ela é a que decide -- e porque nenhuma placa desta máquina anuncia
# zero-copy, então o caminho positivo só seria exercitado no dia em que a NIC
# chegasse. A camada de netlink acima é coberta por
# `scripts/tests/l1_xdp_netlink.sh`, que importa este arquivo como módulo e
# alimenta bytes arbitrários.
#
# INCIDENTE. Este comentário citava "scripts/tests/l1_xdp_features.sh", arquivo
# que nunca existiu na árvore. Âncora para arquivo inexistente é da mesma
# família das duas âncoras de linha mortas que estavam em lib-xdp.sh e no teste:
# escrita de memória, verdadeira em nenhum momento, e sem nada que a verifique
# (scripts/verificar-ancoras.py só lê .md).
# ---------------------------------------------------------------------------

def veredito_de(features):
    """xdp_features -> classe do veredito. Quatro casos, não dois.

    None não é 0: "o kernel não anunciou o atributo" (família netdev sem
    xdp_features, kernel 6.1/6.2) é INCONCLUSIVO, enquanto 0 é uma resposta
    afirmativa do driver -- ele declarou que não tem capacidade nenhuma.
    Colapsar os dois é o bug que este arquivo veio consertar, em outra forma.
    """
    if features is None:
        return "sem-atributo"
    if not features & XDP_ACT_BASIC:
        return "sem-xdp"
    if features & XDP_ACT_XSK_ZEROCOPY:
        return "zero-copy"
    return "nativo-sem-zc"


def nome_seguro(ifindex):
    """ifindex -> nome de interface higienizado para KEY=VALUE.

    O kernel proíbe '/' e espaço em nome de interface, mas não proíbe tudo o
    mais. Como esta saída é lida por um shell, qualquer byte estranho vira
    '?'. Isto é defesa em profundidade: a regra principal continua sendo o
    chamador NUNCA usar `eval`.
    """
    try:
        bruto = socket.if_indextoname(ifindex)
    except OSError:
        # Corrida real, não hipótese: a interface pode sumir entre o dump e a
        # resolução (veth de container, adaptador USB desconectado).
        return f"if{ifindex}"
    return "".join(c if (c.isascii() and (c.isalnum() or c in "._:@-")) else "?"
                   for c in bruto)


def bloco(dev, fonte="netlink", iface=None):
    """Um netdev -> linhas KEY=VALUE. Chave ausente nunca é chave com lixo."""
    f = dev["xdp_features"]
    linhas = [
        f"FONTE={fonte}",
        f"IFACE={iface if iface is not None else nome_seguro(dev['ifindex'])}",
        f"IFINDEX={dev['ifindex'] if dev['ifindex'] is not None else ''}",
        f"XDP_FEATURES={'' if f is None else f'0x{f:x}'}",
        f"XDP_FEATURES_NOMES={' '.join(flags_nomeadas(f, XDP_ACT)) if f else ''}",
        f"XDP_BASIC={'' if f is None else ('sim' if f & XDP_ACT_BASIC else 'nao')}",
        f"XDP_ZEROCOPY={'' if f is None else ('sim' if f & XDP_ACT_XSK_ZEROCOPY else 'nao')}",
    ]
    # XDP_ZC_MAX_SEGS ausente é a CONDIÇÃO NORMAL em placa sem zero-copy: o
    # kernel só emite esse atributo quando o bit XSK_ZEROCOPY está presente.
    # Observado indiretamente -- XSK_FEATURES=0 É emitido, logo o kernel não
    # omite atributo por valor zero, e o 4 é o único ausente. Vazio aqui
    # significa "não anunciado", jamais "zero segmentos".
    zc = dev["zc_max_segs"]
    linhas.append(f"XDP_ZC_MAX_SEGS={'' if zc is None else zc}")

    rx = dev["rx_meta"]
    linhas.append(f"XDP_RX_METADATA={'' if rx is None else f'0x{rx:x}'}")
    linhas.append("XDP_RX_METADATA_NOMES=" +
                  (" ".join(flags_nomeadas(rx, XDP_RX_META)) if rx else ""))
    xsk = dev["xsk"]
    linhas.append(f"XSK_FEATURES={'' if xsk is None else f'0x{xsk:x}'}")
    linhas.append("XSK_FEATURES_NOMES=" +
                  (" ".join(flags_nomeadas(xsk, XSK_FLAGS)) if xsk else ""))
    if dev["desconhecidos"]:
        linhas.append("ATTRS_DESCONHECIDOS=" +
                      " ".join(f"{t}:{v}" for t, v in
                               sorted(dev["desconhecidos"].items())))
    linhas.append(f"VEREDITO={veredito_de(f)}")
    return linhas


def relatorio_politica(fam):
    """Imprime, por comando, se o kernel exige privilégio administrativo.

    Esta é a PROVA formal de que a leitura não precisa de root, e ela vem do
    kernel -- não de "a chamada deu certo com um usuário que por acaso tinha
    permissão". Vale como material didático: o mesmo relatório mostra que
    BIND_RX e NAPI_SET, que ESCREVEM, exigem GENL_ADMIN_PERM.
    """
    print(f"politica declarada pelo kernel para a familia "
          f'"{NETDEV_FAMILY_NAME}" (id={fam.id}):')
    for cmd in sorted(fam.ops):
        flags = fam.ops[cmd]
        priv = "ROOT (GENL_ADMIN_PERM)" if flags & GENL_ADMIN_PERM else "livre"
        print(f"  {NETDEV_CMD_NOMES.get(cmd, f'cmd {cmd}'):<32} "
              f"0x{flags:02x}  {priv:<24} "
              f"[{'|'.join(flags_nomeadas(flags, GENL_OP_FLAGS))}]")
    print(f"  (uid={os.getuid()} euid={os.geteuid()})")


def valor_inteiro(txt):
    """"0x23", "35" ou "0b100011" -> int; "ausente" -> None.

    Erro de digitação NÃO pode virar 0: aqui 0 é uma resposta com significado
    ("o driver não anuncia capacidade nenhuma"), e o chamador decide com ela.

    "ausente" é o único texto aceito, e existe para uma coisa só: representar
    "o kernel não anunciou o atributo", que é caso distinto de zero e não tem
    como ser produzido por nenhuma placa desta máquina. Sem ele, a classe
    `sem-atributo` -- justamente a que separa INCONCLUSIVO de "não suporta" --
    ficaria sem teste.
    """
    if txt == "ausente":
        return None
    return int(txt, 0)


def main():
    argv = sys.argv[1:]
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0

    # --decodificar existe para o teste L1: exercita a decodificação de
    # bitmask e o veredito SEM abrir socket nenhum. Sem ele, a única forma de
    # testar o caminho "zero-copy anunciado" seria ter a placa -- que é
    # exatamente a espera que o projeto se recusa a aceitar (ver o caso da
    # Mellanox em scripts/lib-nic.sh).
    if "--decodificar" in argv:
        dev = {"ifindex": None, "xdp_features": None, "zc_max_segs": None,
               "rx_meta": None, "xsk": None, "desconhecidos": {}}
        campos = {"--decodificar": "xdp_features", "--rx-metadata": "rx_meta",
                  "--xsk": "xsk", "--zc-max-segs": "zc_max_segs"}
        i = 0
        while i < len(argv):
            if argv[i] not in campos:
                print(f'erro: argumento desconhecido "{argv[i]}" em '
                      f"--decodificar", file=sys.stderr)
                return 2
            if i + 1 >= len(argv):
                print(f"erro: {argv[i]} exige um valor", file=sys.stderr)
                return 2
            try:
                dev[campos[argv[i]]] = valor_inteiro(argv[i + 1])
            except ValueError:
                print(f'erro: "{argv[i + 1]}" nao e um numero '
                      f"(use 0x23, 35 ou 0b100011)", file=sys.stderr)
                return 2
            i += 2
        print("\n".join(bloco(dev, fonte="decodificacao", iface="")))
        return 0

    politica = "--politica" in argv
    argv = [a for a in argv if a != "--politica"]
    for a in argv:
        if a.startswith("-"):
            print(f'erro: argumento desconhecido "{a}". Use --help.',
                  file=sys.stderr)
            return 2
    if len(argv) > 1:
        print("erro: informe no maximo uma interface.", file=sys.stderr)
        return 2
    alvo = argv[0] if argv else None

    with Genl() as g:
        try:
            fam = resolve_familia(g, NETDEV_FAMILY_NAME)
        except (ErroNetlink, ErroTruncado, OSError) as e:
            # Código próprio, e é o coração do conserto: "não deu para saber"
            # NÃO é "a placa não suporta". No genl-ctrl, família ausente e nome
            # errado devolvem o mesmo -ENOENT, então o único veredito honesto
            # aqui é INCONCLUSIVO.
            print(f"erro: {e}", file=sys.stderr)
            print('erro: este kernel nao expoe a familia netlink "netdev" '
                  "(veio no 6.1; xdp_features, no 6.3). Sem ela, esta fonte "
                  "nao responde -- o veredito e INCONCLUSIVO, nao 'sem XDP'.",
                  file=sys.stderr)
            return 3

        if politica:
            relatorio_politica(fam)
            print()

        if alvo is None:
            try:
                devs = consulta(g, fam)
            except (ErroNetlink, ErroTruncado) as e:
                print(f"erro: {e}", file=sys.stderr)
                return 4
            devs.sort(key=lambda d: d["ifindex"] or 0)
            for n, d in enumerate(devs):
                if n:
                    print()
                print("\n".join(bloco(d)))
            return 0

        try:
            idx = socket.if_nametoindex(alvo)
        except OSError:
            print(f'erro: a interface "{alvo}" nao existe nesta maquina.',
                  file=sys.stderr)
            return 5
        try:
            devs = consulta(g, fam, ifindex=idx)
        except ErroNetlink as e:
            # -ENODEV aqui é corrida: a interface existia no if_nametoindex e
            # sumiu antes do DEV_GET. Reportar como 5 mantém o significado.
            print(f"erro: {e}", file=sys.stderr)
            return 5 if e.errno == -19 else 4
        except ErroTruncado as e:
            print(f"erro: {e}", file=sys.stderr)
            return 4
        if not devs:
            print(f'erro: o kernel nao respondeu nada para "{alvo}".',
                  file=sys.stderr)
            return 4
        print("\n".join(bloco(devs[0], iface=alvo)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
