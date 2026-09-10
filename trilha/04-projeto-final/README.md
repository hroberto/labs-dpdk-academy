# Projeto final

> **Nível 10** do [plano de estudo](../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: todos os módulos anteriores

> **Esqueleto.** Registra escopo, compromissos e restrições de ambiente já
> conhecidas; o conteúdo ainda não foi escrito.

## Objetivo

Consolidar o material num sistema executável, documentado e medido, e usá-lo para
responder à pergunta que atravessa o projeto inteiro: **quando o DPDK compensa, e
quando não compensa.**

## O sistema

O cenário que aparece nos fundamentos e no módulo de runtime é o candidato
natural: um **receptor de *market data***, com o feed handler como processo
primário e um consumidor como secundário. Ele já tem peças escritas e testadas —
livro de ofertas, detecção de perda por número de sequência, travessia entre
processos medida — em
[`docs/02-runtime-dpdk/medicoes/`](../../docs/02-runtime-dpdk/medicoes/).

Isto é sugestão de continuidade, não obrigação. Se outro domínio ensinar melhor o
que falta ensinar, o outro domínio vence: o objeto de estudo é o DPDK.

## As três comparações

| Abordagem | O que ela custa | O que ela entrega |
|---|---|---|
| **DPDK** | hugepages, núcleos dedicados, driver ligado ao processo, 123 ms para subir | menor latência e maior taxa de pacotes |
| **C++23 sobre sockets** | syscall e cópia por pacote | roda em qualquer lugar, sem privilégio |
| **AF_XDP** | requisitos de driver e de kernel | *bypass* parcial mantendo driver e modelo de segurança do kernel |

## Restrição de ambiente que precisa ser dita antes

Registrada agora para não virar promessa quebrada depois:

**A máquina de referência não consegue medir AF_XDP — e o caso é pior do que
"sem zero-copy".** Consultado com privilégio, o próprio netdev responde:

```
NETDEV_XDP_ACT_BASIC:         no
NETDEV_XDP_ACT_REDIRECT:      no
NETDEV_XDP_ACT_XSK_ZEROCOPY:  no
```

`BASIC: no` significa que a NIC **não tem XDP nativo nenhum** — não é o caso de
"tem XDP, falta zero-copy". Aqui o AF_XDP só funciona em **modo genérico (SKB)**,
em que o eBPF roda *depois* da alocação do `sk_buff`, dentro da pilha: o mais
lento dos modos, e o que menos representa AF_XDP. Na prática, `xdpsock -N`
também falha, não apenas `-z`.

O módulo confirma independentemente: **zero símbolos `xdp_`** no `r8169`, contra
**37** no `i40e`. Isso importa porque a interface aqui está *down*, e um leitor
poderia atribuir o "no" ao link caído — a evidência do módulo descarta isso.

Verifique na sua máquina com:

```bash
./scripts/xdp-zerocopy.sh              # driver da interface padrão
./scripts/xdp-zerocopy.sh i40e ice     # drivers nomeados
```

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
> 1. **símbolos no módulo** — heurística, o que o script faz sem privilégio;
> 2. **`NETDEV_XDP_ACT_XSK_ZEROCOPY`** anunciada pelo netdev — o script consulta
>    via `xdp-loader features`, mas isso **exige root**;
> 3. **bind real com `XDP_ZEROCOPY`** — a única prova. Com o `xdpsock`:
>    `sudo xdpsock -i <iface> -q 0 -N -z -r`. Rodar **sem** `-z` não prova nada:
>    há fallback silencioso para modo cópia.

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

## Entregáveis

- aplicação DPDK funcional, com documento, código e testes L1 e L2
- arquitetura documentada, incluindo as decisões que **não** foram tomadas e por quê
- benchmark reprodutível, com ambiente declarado e ressalvas explícitas
- comparação com as duas alternativas, cada uma no cenário em que é justa
- análise crítica final: o que o projeto inteiro demonstrou, e o que ficou aberto

## Navegação

| | |
|---|---|
| **Anterior** | [03 — Performance e observabilidade](../03-performance/) |
| **Índice** | [Trilha](../README.md) · [Plano de estudo](../../docs/plano-estudo-dpdk.md) · [Roadmap](../../ROADMAP.md) |
