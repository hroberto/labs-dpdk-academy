# AF_XDP — preparação para uma versão futura

> **Este documento não faz parte do projeto final desta versão.** Ele registra o
> trabalho de verificação já feito sobre AF_XDP e as ferramentas construídas para
> ele, para que uma versão futura o retome sem repetir o caminho.

## Por que saiu do projeto final

A comparação DPDK × AF_XDP **não pode ser feita nesta máquina**, e a razão é de
hardware: a NIC de referência não tem XDP nativo nenhum. Isso está verificado e
documentado abaixo.

Enquanto ficou dentro do documento do projeto final, essa impossibilidade ocupava
**mais de 80% do texto** — um documento cujo assunto deveria ser a síntese do que
o curso mediu passava a ser, na prática, o relato do que ele não conseguiu medir.
A verificação continua válida e vale ser preservada; o lugar dela é aqui.

## O que já está pronto para a versão futura

| Ferramenta | O que faz |
|---|---|
| [`ferramental/af-xdp/xdp-zerocopy.sh`](../../ferramental/af-xdp/xdp-zerocopy.sh) | diagnóstico por interface ou por driver, com hierarquia de evidência |
| [`ferramental/af-xdp/xdp-features.py`](../../ferramental/af-xdp/xdp-features.py) | consulta as *features* do netdev |
| [`ferramental/af-xdp/lib-xdp.sh`](../../ferramental/af-xdp/lib-xdp.sh) | funções comuns de detecção |

Numa máquina com NIC adequada, essas ferramentas respondem — antes de escrever
qualquer código — se o experimento é possível e em qual modo.

---

## Restrição de ambiente que precisa ser dita antes

Registrada agora para não virar promessa quebrada depois:

**A máquina de referência não consegue medir AF_XDP — e o caso é pior do que
"sem zero-copy".** O próprio netdev responde, e responde a qualquer usuário —
sem `sudo`, com `CapEff: 0000000000000000`:

```console
$ ./ferramental/af-xdp/xdp-features.py enp8s0
FONTE=netlink
IFACE=enp8s0
IFINDEX=7
XDP_FEATURES=0x0
XDP_FEATURES_NOMES=
XDP_BASIC=nao
XDP_ZEROCOPY=nao
XDP_ZC_MAX_SEGS=
XDP_RX_METADATA=0x0
XDP_RX_METADATA_NOMES=
XSK_FEATURES=0x0
XSK_FEATURES_NOMES=
VEREDITO=sem-xdp
```

> **Ferramenta privilegiada não é o mesmo que dado privilegiado.** Este
> documento já afirmou que a consulta "exige root", e a afirmação vinha de
> `xdp-loader features`, que aborta com *"This program must be run as root."*
> antes de abrir qualquer socket — ele exige privilégio porque carrega eBPF e
> abre mapa BPF, não porque o dado seja restrito. A leitura em si é netlink
> puro, e o kernel **declara** que ela é livre: `NETDEV_CMD_DEV_GET` vem com
> flags `0x0e`, sem o bit `GENL_ADMIN_PERM` que `NETDEV_CMD_BIND_RX` e
> `NETDEV_CMD_NAPI_SET` carregam. Confira com `./ferramental/af-xdp/xdp-features.py
> --politica` — que imprime essa tabela de política **e, logo abaixo dela**, o
> bloco `KEY=VALUE` de todas as interfaces (67 linhas ao todo nesta máquina);
> para ver só a tabela, corte em `head -12`. A regra que ficou: antes de
> escrever "precisa de root", veja se
> quem exige privilégio é a interface do kernel ou o programa que você escolheu
> para falar com ela.

`XDP_BASIC=nao` significa que a NIC **não tem XDP nativo nenhum** — não é o caso de
"tem XDP, falta zero-copy". Aqui o AF_XDP só funciona em **modo genérico (SKB)**,
em que o eBPF roda *depois* da alocação do `sk_buff`, dentro da pilha: o mais
lento dos modos, e o que menos representa AF_XDP. Na prática, `xdpsock -N`
também falha, não apenas `-z`.

Duas evidências independentes descartam a explicação alternativa mais óbvia —
a de que o `0x0` viesse do link caído, já que esta interface está *down*.

A primeira é o módulo: **zero símbolos `xdp_`** no `r8169`, contra **37** no
`i40e`. O `r8169` não tem uma única string `xdp` ou `bpf` no módulo, e o módulo
tem 2072 strings no total — não é o descompressor falhando em silêncio.

A segunda é um controle direto, e é a mais forte das duas: um `veth` **DOWN**
reporta `xdp_features=0x23`. Ou seja, link caído **não** suprime a capacidade
anunciada. Esse mesmo `veth` serve de controle positivo do decodificador —
sem ele, "tudo `0x00`" seria indistinguível de uma ferramenta quebrada:

```console
$ unshare -Urnm -- bash -c 'mount -t sysfs none /sys
    ip link add veth0 type veth peer name veth1
    ip -br link show veth0 | awk "{print \$1, \$2}"
    ./ferramental/af-xdp/xdp-features.py veth0'
veth0@veth1 DOWN
FONTE=netlink
IFACE=veth0
IFINDEX=3
XDP_FEATURES=0x23
XDP_FEATURES_NOMES=NETDEV_XDP_ACT_BASIC NETDEV_XDP_ACT_REDIRECT NETDEV_XDP_ACT_RX_SG
XDP_BASIC=sim
XDP_ZEROCOPY=nao
XDP_ZC_MAX_SEGS=
XDP_RX_METADATA=0x7
XDP_RX_METADATA_NOMES=NETDEV_XDP_RX_METADATA_TIMESTAMP NETDEV_XDP_RX_METADATA_HASH NETDEV_XDP_RX_METADATA_VLAN_TAG
XSK_FEATURES=0x0
XSK_FEATURES_NOMES=
VEREDITO=nativo-sem-zc
```

O `mount -t sysfs` não é decoração: sem ele, `/sys/class/net` dentro do
*namespace* continua listando as interfaces do **host**, e o `veth0` fica
invisível para qualquer ferramenta que use sysfs. O netlink, esse, já responde
certo — ele enxerga o *namespace* de rede, não o de montagem.

O `0x23` não é um número qualquer: é `BASIC | REDIRECT | RX_SG`, e o bit
`NDO_XMIT` (`0x4`) está **ausente** — um decodificador que apenas imprimisse
zeros, ou que casasse a máscara inteira, não produziria justamente esse valor.
A explicação corrente é que o `veth` só anuncia `NDO_XMIT` quando o par tem
programa XDP anexado; **isso não foi verificado aqui**, porque anexar exige
carregar eBPF e `unprivileged_bpf_disabled` está em `2` nesta máquina. Fica
como leitura do comportamento, não como medição.

Verifique na sua máquina com:

```bash
./ferramental/af-xdp/xdp-zerocopy.sh                             # a interface física daqui
./ferramental/af-xdp/xdp-zerocopy.sh r8169 i40e ice ixgbe mlx5_core   # modo comparação
```

Nenhum dos dois exige root. O segundo comando é literalmente o que regenera a
tabela abaixo: antes, cada linha vinha de uma execução separada e de
transcrição manual — que é justamente o passo em que número e texto divergem.

Nesta máquina, e nos drivers Intel para comparação:

| driver | `xdp_` (XDP nativo) | chamadas ao núcleo XSK | código XSK próprio | diagnóstico |
|---|---:|---:|---:|---|
| `r8169` (a NIC daqui) | **0** | 0 | 0 | **sem XDP nenhum** |
| `i40e` | 37 | 7 | 13 | XDP + zero-copy |
| `ice` | 83 | 7 | 13 | XDP + zero-copy |
| `ixgbe` | 38 | 8 | 12 | XDP + zero-copy |
| `mlx5_core` | 59 | 8 | 43 | XDP + zero-copy |

As três colunas separam situações que um único número confundiria:

- **`xdp_`** distingue "não tem XDP" de "tem XDP, falta zero-copy" — a primeira
  coluna é a que classifica a RTL8125.
- **chamadas** são símbolos *indefinidos*: funções do núcleo XSK que o driver
  invoca.
- **código próprio** são funções XSK que ele *define*.

Suporte real tem as três.

> **Por que um script, e não uma linha.** A versão anterior deste documento
> publicava `nm -D .../r8169.ko.zst | grep -c xsk_`. Ela **não funciona**:
> módulos vêm comprimidos com zstd, o `nm` recusa o arquivo, o `grep -c` engole
> o erro e devolve `0`. Rodando no `i40e`, que tem suporte, o resultado também
> era `0` — ou seja, o comando dizia "sem zero-copy" para todo driver do
> sistema, e a conclusão sobre a RTL8125 estava certa por coincidência.

> **E o script prova menos do que parece — nem sequer é condição necessária.**
> Símbolo no módulo é evidência **indireta**: *inlining*, renomeação e mudanças
> de implementação produzem falso negativo. Ele responde "vale a pena tentar?",
> não "isto funciona".
>
> A hierarquia de evidência, da mais fraca para a mais forte:
>
> 1. **símbolos no módulo** — heurística. Não fecha veredito em sentido nenhum,
>    e é a única fonte que cobre um driver **ausente** desta máquina;
> 2. **`NETDEV_XDP_ACT_XSK_ZEROCOPY`** anunciada pelo netdev — o que o driver
>    declarou ao kernel. **A leitura em si não exige privilégio**: o script a
>    faz por netlink genérico. O `xdp-loader features` (esse sim *root-only*) é
>    apenas *fallback*, e a condição que o dispara é a do próprio script: **o
>    fallback só entra quando a fonte primária não fechou o veredito.** É a
>    única fonte que fecha veredito sozinha, e nos dois sentidos: bit ligado
>    significa capacidade anunciada, e `xdp_features = 0` significa nem XDP
>    básico;
> 3. **bind real com `XDP_ZEROCOPY`** — a única prova. Com o `xdpsock`:
>    `sudo xdpsock -i <iface> -q 0 -N -z -r`. Rodar **sem** `-z` não prova nada:
>    há fallback silencioso para modo cópia. Esta é a única etapa que exige
>    privilégio de verdade, e não tem versão parcial: medido, `socket(AF_XDP)`
>    sem `CAP_NET_RAW` falha com `EPERM` antes de qualquer bind.

> **Incidente registrado: este texto já fez a promessa errada uma vez.** O item
> 2 acima dizia que o script "só cai em `xdp-loader features` se a família
> `netdev` não existir no kernel". Isso prometia ao leitor que root nunca seria
> exigido enquanto o kernel fosse moderno — e é falso. Família ausente é apenas
> **um** dos casos em que a fonte primária não fecha o veredito. Os outros:
>
> - o kernel responde, mas **sem** o atributo `xdp_features` (classe
>   `sem-atributo`);
> - a consulta netlink falha, com a família presente;
> - a interface deixa de existir entre a listagem e a consulta;
> - **não há `python3` no `PATH`** — o leitor da bitmask é um script Python;
> - **`xdp-features.py` não está ao lado de `xdp-zerocopy.sh`** — quem copiou só
>   um dos dois arquivos cai aqui.
>
> Os dois últimos não dependem do kernel em nada, e é por isso que "kernel
> moderno o bastante" **não** é garantia de "não vai pedir root". Contraexemplo
> executado nesta máquina, onde a família `netdev` **existe** — a primeira
> linha prova isso:
>
> ```console
> $ ./ferramental/af-xdp/xdp-features.py --politica | head -1
> politica declarada pelo kernel para a familia "netdev" (id=22):
> $ S=/tmp/sem-helper; rm -rf "$S"; mkdir -p "$S"
> $ cp ferramental/af-xdp/xdp-zerocopy.sh ferramental/af-xdp/lib-xdp.sh scripts/lib-apuracao.sh "$S"/   # de propósito, sem o xdp-features.py
> $ "$S"/xdp-zerocopy.sh enp8s0 | sed -n '/^-- Capacidade/,/^-- Heur/p' | head -n -1
> -- Capacidade anunciada pelo netdev --
>   ferramental/af-xdp/xdp-features.py nao encontrado ao lado deste script.
>   fonte primaria (netlink) nao respondeu: ferramental/af-xdp/xdp-features.py nao esta ao lado do script (copie os dois juntos).
>
>   Fallback: xdp-loader features
>   xdp-loader exige root, e a exigencia e DA FERRAMENTA: ele carrega
>   eBPF e abre mapa BPF. O dado em si e livre -- e por isso que a
>   fonte primaria acima nao pediu privilegio nenhum.
>   Se quiser conferir mesmo assim: sudo /tmp/sem-helper/xdp-zerocopy.sh enp8s0
> ```
>
> Repare no que o script **não** fez: ele não escreveu "sem zero-copy". Ele
> nomeou o que faltou. O documento é que tinha transformado "não apurei, e foi
> *isto* que faltou" em "não vai acontecer" — o mesmo defeito que a reescrita do
> script existia para matar, reaparecido no texto em vez de no código.

Sem zero-copy o AF_XDP cai para o modo com cópia, cujo perfil de desempenho é
outro. Comparar DPDK contra AF_XDP em modo cópia e
concluir algo sobre AF_XDP seria repetir o erro que a
[alternativa em C++23](../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md)
já documenta: medir um cenário que remove aquilo pelo qual a tecnologia cobra.

Duas saídas honestas, e o módulo precisa escolher uma explicitamente:

1. medir o que a máquina permite e **rotular o resultado como modo cópia**, sem
   generalizar;
2. tratar AF_XDP como comparação **conceitual**, com números de terceiros
   devidamente atribuídos, e deixar a medição para quem tiver hardware adequado.
