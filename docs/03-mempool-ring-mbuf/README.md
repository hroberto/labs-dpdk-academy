# Mempool, ring e mbuf — o modelo de dados do DPDK

> **Nível 4** do [plano de estudo](../plano-estudo-dpdk.md) ·
> Pré-requisitos: [02 — Runtime do DPDK](../02-runtime-dpdk/README.md) e o tópico
> prático [02 — Mempool, ring e lote](../../trilha/01-fundamentos/02-mempool-ring/)

O [módulo de runtime](../02-runtime-dpdk/README.md) mostrou a EAL reservando
memória e nomeando regiões. Este trata do que se coloca dentro dela: as três
estruturas sobre as quais todo programa DPDK é construído, e que respondem a três
perguntas diferentes.

| Estrutura | Pergunta que responde |
|---|---|
| [`rte_mempool`][guiamempool] | de onde vem um objeto, sem alocar no caminho quente |
| [`rte_mbuf`][guiambuf] | como um pacote é representado |
| [`rte_ring`][guiaring] | como um objeto passa de um estágio para outro |

O [tópico prático](../../trilha/01-fundamentos/02-mempool-ring/) já exercita as
três e mede o efeito do lote. Este módulo faz o que o tópico não faz: **abre as
estruturas**, mede o custo de cada operação, e trata o `rte_mbuf`, que até aqui
só foi prometido.

> **In English.** The three structures every DPDK program is built on, opened
> up and measured. `malloc/free` at **2.18 ns** against **0.98 ns** for a
> mempool with a per-lcore cache — and **10.45 ns** without it, which is *slower
> than malloc*: the cache is nearly the whole advantage. Also: the four sizing
> rules, three of which fail silently; SP/SC against MP/MC rings; the mbuf's
> four length fields and why testing with 64-byte frames never reveals the bug.
> Failure axis: `rte_mempool_get_bulk()` is all-or-nothing, and a drained pool
> turns a naive retry loop into a livelock.

## Ao final deste módulo, você será capaz de

1. **justificar o mempool com números**, e não com o folclore de que `malloc()`
   custa dezenas de nanossegundos;
2. **dimensionar o cache por lcore** sabendo que sem ele o mempool perde para a
   biblioteca padrão;
3. **prever o efeito do lote** em cada estrutura — e que ele muda de sinal entre
   mempool e `malloc`;
4. **manipular um `rte_mbuf` sem corromper o pacote**, distinguindo `buf_len`,
   `data_off`, `data_len` e `pkt_len`;
5. **escrever código que trata pacote segmentado**, e explicar por que testar com
   quadro de 64 bytes nunca revela o defeito;
6. **escolher entre `_bulk` e `_burst`** pelo contrato, não pelo desempenho, e
   tratar o retorno parcial;
7. **decidir entre SP/SC e MP/MC** sabendo que o custo existe mesmo sem disputa,
   e que o lote o dilui.

## Índice

1. [Por que não usar `malloc()` — a resposta medida](#1-por-que-não-usar-malloc--a-resposta-medida)
2. [O mbuf: quatro números que parecem redundantes](#2-o-mbuf-quatro-números-que-parecem-redundantes)
3. [O anel: o preço da generalidade](#3-o-anel-o-preço-da-generalidade)
4. [As três juntas: o ciclo de vida de um pacote](#4-as-três-juntas-o-ciclo-de-vida-de-um-pacote)
5. [Validação: reproduza na sua máquina](#5-validação-reproduza-na-sua-máquina)
6. [Quando dá errado](#6-quando-dá-errado)
7. [Limitações deste documento](#7-limitações-deste-documento)
8. [Referências externas](#8-referências-externas)
9. [Navegação](#9-navegação)

---

## 1. Por que não usar `malloc()` — a resposta medida

O tópico prático abre com a afirmação de que `malloc()` "pode tomar dezenas de
nanossegundos". É a justificativa de existir do mempool, e circula em quase todo
material de DPDK. Vale medir, porque o resultado **não é o que a afirmação
sugere**.

O programa [`medicoes/custo-alocacao.c`](medicoes/custo-alocacao.c) compara os
dois na mesma máquina, com a mesma metodologia dos demais programas do projeto.

```
  --- um objeto por vez, em NANOSSEGUNDOS POR OBJETO ---

  medicao                              mediana  p25-p75 (IQR)   amplitude min-max  disp    CV
  ---------------------------------- ---------  --------------- ----------------- ----- -----
  malloc/free                             2.18  2.16-2.18       2.14-2.23           0.9%   1.0%  
  mempool get/put, com cache             0.981  0.977-0.983     0.973-0.991         0.6%   0.5%  
  mempool get/put, SEM cache             10.45  10.44-10.50     10.43-10.63         0.5%   0.5%  
```

```
  frequencia do nucleo 0 durante a medicao: 5.56 -> 5.56 GHz
  razoes, que NAO dependem da frequencia:
    mempool com cache e 2.23x mais rapido que malloc
    o cache por lcore vale 10.7x (com cache contra sem cache)
    sem o cache, o mempool fica 4.8x mais LENTO que o malloc
```

> **Por que o programa publica razões, e não só nanossegundos.** Sem fixar a
> frequência do processador — e este projeto não a fixa, como suas
> [limitações](../00-visao-geral/README.md#5-o-ambiente-de-medição) declaram —,
> os valores absolutos mudam entre execuções: o mesmo binário deu 2,19 ns e
> 2,77 ns para o `malloc`, conforme o turbo engatasse. As **razões** ficaram
> idênticas (2,23× nas duas). É por isso que este módulo afirma "duas vezes mais
> rápido" e não "0,98 nanossegundos": a razão é a afirmação; o nanossegundo é
> circunstância.

**`malloc()` custa 2,18 ns, não dezenas.** Alocar e liberar repetidamente um
objeto do mesmo tamanho é o caso em que a glibc é boa: o alocador tem um cache
por thread, e o par cai nele. A afirmação corrente superestima o adversário — e
uma justificativa que superestima o adversário é frágil, porque desmorona quando
alguém mede.

O mempool ganha, mas por **2,2 vezes**, não por ordem de grandeza. E a terceira
linha explica de onde vem o ganho.

### 1.1 O cache por lcore é quase todo o ganho

Um mempool tem duas camadas: um anel comum, compartilhado, e um **cache por
lcore** que serve de amortecedor. Criando o mesmo pool com `cache_size = 0`, a
operação passa de **0,98 ns para 10,45 ns** — dez vezes mais cara, e cinco vezes
mais cara que o `malloc()`.

A leitura importa mais que o número: **sem o cache por lcore, o mempool perde
para a biblioteca padrão.** O que ele oferece não é uma estrutura de dados
mágica; é a mesma ideia da glibc — um cache por thread — dimensionada para o
plano de dados e livre de sincronização por não haver thread migrando entre
lcores. Quem cria mempool com cache zero "para simplificar" está desligando
justamente aquilo pelo qual escolheu o mempool.

### 1.2 Quatro regras de dimensionamento, três delas silenciosas

Criar um mempool exige escolher `n` (quantos objetos) e `cache_size`. A
documentação de `rte_mempool_create` declara quatro restrições sobre esse par, e
**três falham em silêncio** — o pool é criado, funciona, e desperdiça:

| Regra, como a documentação a enuncia | O que acontece se violada |
|---|---|
| *"the optimum size (in terms of memory usage) is when n is a power of two minus one"* | desperdício de memória |
| `cache_size` ≤ `RTE_MEMPOOL_CACHE_MAX_SIZE` (512 no 25.11) | **criação falha** |
| `cache_size` ≤ `n / 1.5` | **criação falha** |
| *"choose cache_size to have n modulo cache_size == 0"* | *"some elements will always stay in the pool and will never be used"* |

A quarta é a mais fácil de violar sem perceber — e o programa de medição deste
próprio módulo a violava. Ele usava `n = 4095` com `cache_size = 256`: os dois
limites passam, `n` está na forma ótima, e ainda assim **255 objetos ficavam
inalcançáveis**, porque 4095 % 256 = 255.

A correção não foi trocar 256 por outro número escolhido a olho. As regras viraram
código puro em [`medicoes/sizing.c`](medicoes/sizing.c), testado
sem EAL, e o programa passou a **derivar** o cache:

```
  cache por lcore ........ 455 objetos (derivado, nao escolhido a olho)
    escolhido ............ sem ressalvas
    o obvio (256) seria .. n nao e multiplo do cache (objetos presos) -> 255 objetos presos
```

> Repare que 455 não é um número que ocorreria a ninguém. Ele é o maior divisor
> de 4095 que cabe no teto de 512 — e é essa aritmética, não a intuição, que
> satisfaz as quatro regras ao mesmo tempo.

### 1.3 O lote muda de sinal entre os dois

Este é o resultado principal da seção, e não aparece em nenhuma comparação
publicada:

```
  --- em LOTE, ns por objeto: os dois lados variam em sentidos opostos ---

  lote          malloc/free   mempool bulk      razao
  -----         -----------   ------------      -----
  1                 2.39 ns       1.837 ns       1.3x
  8                 2.55 ns       0.629 ns       4.1x
  32               12.39 ns       0.450 ns      27.6x
  128              19.64 ns       0.523 ns      37.5x
```

Pedir mais objetos de uma vez **barateia** cada objeto no mempool (1,84 → 0,45 ns)
e **encarece** no `malloc` (2,39 → 19,64 ns). A razão entre os dois vai de 1,3×
para 37,5×.

Isso é decisivo porque o plano de dados **é** processamento em lote. A
[§3 do tópico prático](../../trilha/01-fundamentos/02-mempool-ring/README.md)
mediu que o lote é o que amortiza o custo de atravessar núcleos; aqui se vê que
ele também é o que separa as duas abordagens. Comparar mempool e `malloc` objeto
a objeto — que é como a comparação costuma ser feita — mede justamente o regime
em que a diferença é menor.

> **Por que o `malloc` piora com o lote.** O mecanismo está dentro do alocador da
> glibc, e este documento **não o investiga**: afirmar sem verificar é o que ele
> está corrigindo. O que se sustenta é a observação — o degrau aparece entre 16 e
> 32 objetos vivos simultâneos — e a consequência de engenharia.

> **Uma armadilha de medição que muda o resultado.** A glibc tem um caminho
> rápido enquanto o processo tem uma thread só (`__libc_single_threaded`). Medir
> `malloc` num programa mono-thread produz um número que não existe em servidor
> algum. O programa mantém uma thread de ruído viva, **fixada num núcleo físico
> distinto**, pelo mesmo motivo que os fundamentos passaram a fazê-lo depois de
> descartar uma medição inválida. Sem fixá-la, a medição saiu bimodal: p25 de
> 10,5 ns contra p75 de 25,4 ns na mesma medição.

---

## 2. O mbuf: quatro números que parecem redundantes

O [`rte_mbuf`][guiambuf] é a estrutura que carrega um pacote. Ela foi prometida
pelo tópico prático e adiada; é aqui que aparece.

A dificuldade não está na API, está em quatro campos que parecem dizer a mesma
coisa: `buf_len`, `data_off`, `data_len` e `pkt_len`. Confundi-los produz
**corrupção silenciosa** — o pacote sai com bytes a mais, a menos, ou com lixo no
começo, e nada acusa erro.

O programa [`medicoes/anatomia-mbuf.c`](medicoes/anatomia-mbuf.c) não descreve o
layout: imprime o da versão instalada.

```
  sizeof(struct rte_mbuf) ..... 128 bytes (2 linhas de cache de 64 B)
  RTE_PKTMBUF_HEADROOM ........ 128 bytes reservados ANTES dos dados
  RTE_MBUF_DEFAULT_DATAROOM ... 2048 bytes para o pacote
  RTE_MBUF_DEFAULT_BUF_SIZE ... 2176 bytes (dataroom + headroom)
  elemento (mbuf + buffer) .... 2304 bytes
  + cabecalho do mempool ...... 64 bytes
  = objeto no pool ............ 2368 bytes

  Um pool de 8192 mbufs ocupa cerca de 18.5 MiB so em objetos.
```

**O descritor custa 128 bytes por pacote; o objeto inteiro no pool, 2368.** A
decomposição importa: 2304 são do mbuf e do seu buffer, e **64 são do próprio
mempool** — cabeçalho por objeto, que some numa conta feita a olho. Um pool de
8192 mbufs ocupa 18,5 MiB só em objetos, número que decide dimensionamento e que
raramente aparece antes de a memória acabar.

### 2.1 Duas linhas de cache, e a razão de serem duas

```
    campo          offset  linha de cache
    -----          ------  --------------
    buf_addr            0  0
    data_off           16  0
    refcnt             18  0
    nb_segs            20  0
    port               22  0
    pkt_len            36  0
    data_len           40  0
    buf_len            54  0
    pool               56  0
    next               64  1
```

Todos os campos, menos um, cabem na primeira linha. O que sobrou para a segunda
foi `next` — que só tem valor em pacote segmentado, o caso menos comum. O próprio
cabeçalho do DPDK se refere a ele como *"next pointer in the second cache line"*.

A consequência liga direto à [§4.2 dos fundamentos](../01-fundamentos/README.md#42-cache-e-localidade):
um pacote de um segmento toca **uma** linha de cache por mbuf. A 14,88 milhões de
pacotes por segundo, uma linha a mais por pacote é largura de banda de cache que
não sobra para o pacote em si.

### 2.2 O headroom, e por que ele existe

Os quatro números em movimento, num pacote de 60 bytes encapsulado e depois
desencapsulado:

```
  momento                     buf_len  headroom  data_len   pkt_len  tailroom nb_segs
  --------------------------  -------  --------  --------   -------  --------  ------
  recem-alocado                  2176       128         0         0      2048       1
  append(60) = payload           2176       128        60        60      1988       1
  prepend(14) = ethernet         2176       114        74        74      1988       1
  prepend(20) = tunel            2176        94        94        94      1988       1
  adj(20) = tira o tunel         2176       114        74        74      1988       1
  trim(4) = tira do fim          2176       114        70        70      1992       1
```

Lendo a tabela:

- **`buf_len` nunca muda.** É o tamanho do *buffer*, não do pacote. Quem o usa
  como tamanho do pacote transmite 2176 bytes de lixo.
- **`headroom` encolhe a cada [`rte_pktmbuf_prepend()`][apiprepend]** e cresce a
  cada `adj()`. É o espaço reservado **antes** dos dados, e existe exatamente
  para que encapsular seja escrever num espaço já reservado — não copiar o pacote
  inteiro para abrir lugar. Um túnel, um cabeçalho VLAN, uma etiqueta MPLS: todos
  vivem do headroom.
- **`tailroom` faz o oposto**, no fim do buffer.
- **`data_len` e `pkt_len` andam juntos** — enquanto houver um segmento só.

### 2.3 Segmentação: onde os dois números se separam

```
  momento                     buf_len  headroom  data_len   pkt_len  tailroom nb_segs
  --------------------------  -------  --------  --------   -------  --------  ------
  cabeca da cadeia               2176       114        70       170      1992       2
  segundo segmento               2176         -       100         -         -       -
```

Encadeado um segundo mbuf com [`rte_pktmbuf_chain()`][apichain], `pkt_len` (170)
passa a ser a soma de todos os segmentos, e `data_len` (70) continua sendo só o
que cabe **neste** mbuf.

**É aqui que mais código quebra.** Quem lê `data_len` achando que é o tamanho do
pacote processa apenas o primeiro pedaço — em silêncio, sem erro, e só com
pacotes grandes. Testar com quadros de 64 bytes nunca revela o defeito, porque
pacote pequeno cabe num segmento só.

### 2.4 Posse: quem libera

```
  refcnt do cabeca ............ 1
  objetos livres no pool ...... 1021 de 1023

  apos rte_pktmbuf_free(cabeca):
  objetos livres no pool ...... 1023 de 1023
```

Uma chamada a [`rte_pktmbuf_free()`][apimbuffree] devolveu **os dois** mbufs: ela
percorre a cadeia. Liberar o segundo segmento também, por conta própria,
devolveria o mesmo objeto duas vezes ao pool — e o pool **não reclama**. Ele passa
a entregar o mesmo objeto a dois donos, e o defeito aparece muito depois, longe
da causa.

Isso completa a regra de posse que o tópico prático começou:

| Operação | Quem fica com o objeto |
|---|---|
| `rte_ring_enqueue_burst`, o que **não** coube | você — devolva ao pool |
| `rte_eth_tx_burst`, o que **foi** aceito | o driver — não libere |
| `rte_pktmbuf_free` numa cadeia | a cadeia inteira volta, com uma chamada |

---

## 3. O anel: o preço da generalidade

O tópico prático afirma que o modo MP/MC (vários produtores, vários consumidores)
tem "custo maior por exigir operações atômicas de disputa". Verdadeiro — e a
palavra *disputa* esconde a parte interessante.

O programa [`medicoes/custo-anel.c`](medicoes/custo-anel.c) mede os dois modos
**num lcore só, sem disputa nenhuma**:

```
  lote       SP/SC (ns/obj)   MP/MC (ns/obj) custo MP/MC
  -----      --------------   -------------- -----------
  1                1.539 ns         8.229 ns       435%
  8                0.518 ns         1.259 ns       143%
  32               0.332 ns         0.473 ns        42%
  128              0.288 ns         0.301 ns         5%
```

**O custo não depende de haver disputa.** Com um produtor só, o modo MP/MC ainda
custa 435% a mais no lote 1 — porque a instrução atômica é executada de qualquer
forma. O que se paga não é a contenção; é a *possibilidade* dela.

E o lote resolve: a 128 objetos por chamada, a diferença cai para 5%. É o mesmo
padrão que já apareceu duas vezes neste projeto — o lote diluindo um custo fixo,
seja o de atravessar núcleos, seja o de uma instrução atômica.

A decisão de engenharia que sai daí:

- **Se você sabe que há um produtor e um consumidor, diga.** `RING_F_SP_ENQ` e
  `RING_F_SC_DEQ` não são otimização prematura: são informação que você tem e o
  anel não.
- **Se não sabe, o lote é o antídoto.** MP/MC com lote grande custa quase o mesmo
  que SP/SC.

### 3.1 `_bulk` e `_burst` não são sinônimos

As duas famílias de função diferem no **contrato**, não no desempenho, e a
escolha errada não aparece como lentidão:

```
  anel pedido com 16 posicoes; capacidade real: 15
  (uma posicao fica reservada para distinguir cheio de vazio)

  enfileirados 12 em anel vazio ......... burst aceitou 12, livre=3
  pedindo mais 12 com apenas 3 livres:
    _bulk  aceitou 0  <- tudo ou nada: NADA entrou
    _burst aceitou 3  <- parcial: 3 entraram, 9 ficaram de fora
```

[`rte_ring_enqueue_bulk()`][apienqbulk] devolve, nas palavras da API, *"the number
of objects enqueued, either 0 or n"*. `_burst` aceita parcial e devolve quantos
couberam.

Nenhum dos dois é o certo em abstrato:

| Situação | Família |
|---|---|
| o lote é uma unidade indivisível (fragmentos de um pacote) | `_bulk` |
| cada objeto vale por si, e o que sobrar pode esperar | `_burst` |

O perigo do `_burst` é o retorno: os 9 objetos que não entraram **continuam
sendo seus**. Ignorar esse número é o vazamento clássico que o
[tópico prático](../../trilha/01-fundamentos/02-mempool-ring/README.md) já
documenta — e que, com um pool de 4095 objetos, leva o pipeline a parar em
silêncio.

> Repare também na primeira linha: um anel pedido com 16 posições guarda **15**.
> Uma posição fica reservada para distinguir cheio de vazio. É a mesma razão pela
> qual o tamanho ótimo de um mempool é `2^q - 1`, e não `2^q`.

---

## 4. As três juntas: o ciclo de vida de um pacote

As três estruturas não são independentes: cada uma resolve um trecho do mesmo
percurso.

```mermaid
flowchart LR
    POOL[("pool de mbufs")]
    RX["RX"]
    RING[["ring"]]
    EST["estágio<br/>seguinte"]

    POOL -->|"alloc"| RX
    RX -->|"enqueue"| RING
    RING -->|"dequeue"| EST
    EST -->|"free — volta ao pool"| POOL

    classDef fonte fill:#e8f0fe,stroke:#1a5490,color:#0d2b4e
    classDef fila fill:#fdf6e3,stroke:#b7950b,color:#7d6608
    class POOL fonte
    class RING fila
```

Três invariantes que atravessam o percurso, e que este módulo mediu ou
demonstrou:

1. **Todo objeto retirado tem um destino: voltar ao pool.** Não há coleta
   automática. O ponto de fuga mais comum é o retorno parcial do `_burst`.
2. **O tamanho do lote é botão de desempenho, nunca de semântica.** Ele muda o
   custo por objeto em até 37× contra o `malloc`, em 4× dentro do mempool, e em
   87 pontos percentuais no anel MP/MC — sem alterar o resultado.
3. **`data_len` é do segmento; `pkt_len` é do pacote.** Confundi-los só falha com
   pacote grande.

### Onde isso apareceu no exemplo de market data

O [módulo de runtime](../02-runtime-dpdk/README.md#4-processos-primário-e-secundário)
construiu um anel à mão, em memória compartilhada, para passar ticks entre dois
processos — com índices, máscara e `_Alignas(64)` escritos no código. O
[`rte_ring`][guiaring] é essa mesma estrutura, pronta, com os modos SP/SC e MP/MC
que a seção 3 mediu, e utilizável entre processos pelo mesmo mecanismo de nome da
memzone.

A diferença é que aquele anel carregava `struct tick` — dado de aplicação. Este
módulo trata do caso em que o que circula é **pacote**, e aí a estrutura já não é
livre: é o `rte_mbuf`, com o layout que a NIC e os drivers esperam.

---

## 5. Validação: reproduza na sua máquina

```bash
./scripts/build-all.sh

./build/docs/03-mempool-ring-mbuf/medicoes/custo-alocacao -l 0 --no-huge --file-prefix=alocacao
./build/docs/03-mempool-ring-mbuf/medicoes/anatomia-mbuf  -l 0 --no-huge --file-prefix=mbuf
./build/docs/03-mempool-ring-mbuf/medicoes/custo-anel     -l 0 --no-huge --file-prefix=anel
```

Os três entram na suíte L2, e as regras de dimensionamento têm teste L1:

```bash
./scripts/test-all.sh l1     # regras de dimensionamento, sem EAL
./scripts/test-all.sh l2     # runtime real
```

O L1 ([`medicoes/tests/test_l1_sizing.cpp`](medicoes/tests/test_l1_sizing.cpp))
existe por causa do defeito da [§1.2](#12-quatro-regras-de-dimensionamento-três-delas-silenciosas):
um dos casos é literalmente o par (4095, 256) que este módulo usava, e falha se
alguém o reintroduzir. Ele também trava o valor de `RTE_MEMPOOL_CACHE_MAX_SIZE`
que o material assume — se o DPDK mudar de 512, o teste acusa em vez de o
documento envelhecer calado.

### Exercícios

1. Rode `custo-alocacao` e compare a linha "SEM cache" com a "com cache". Em
   quanto o cache por lcore muda o resultado na sua máquina?
2. Rode o mesmo programa duas vezes seguidas e compare os **nanossegundos** e as
   **razões**. Quais mudaram? Confira a frequência que ele reporta.
3. O `malloc` da sua máquina também piora com o lote? Onde fica o degrau?
4. Em `anatomia-mbuf`, some `headroom + data_len + tailroom`. O resultado é
   `buf_len`? Deveria ser?
5. Ainda em `anatomia-mbuf`: por que `prepend(20)` funciona depois de
   `prepend(14)`, mas falharia se o headroom fosse 16?
6. Em `custo-anel`, qual lote faz a diferença entre SP/SC e MP/MC cair abaixo de
   10% na sua máquina? Compare com o lote ótimo medido no
   [tópico prático](../../trilha/01-fundamentos/02-mempool-ring/README.md).
7. Modifique `custo-anel` para usar `_burst` no lugar de `_bulk` e ignore o
   retorno. Quantas iterações até o programa se comportar errado?

---

## 6. Quando dá errado

> **A pergunta deste módulo:** o que acontece quando o pool esgota no meio de um
> lote, e quando o consumidor não acompanha?

O programa é
[`medicoes/pool-esgotado.c`](medicoes/pool-esgotado.c). Ele não mede tempo:
mede **comportamento na fronteira**, e contagem não precisa de mediana.

```bash
./build/docs/03-mempool-ring-mbuf/medicoes/pool-esgotado -l 0 --no-huge --file-prefix=pool
```

### 6.1 O degrau: `get_bulk` não entrega lote parcial

Com 10 objetos livres num pool de 1023:

| Pedido | Resultado | Entregues | Livres depois |
|---:|---|---:|---:|
| 8 | ok | 8 | 2 |
| 9 | ok | 9 | 1 |
| 10 | ok | 10 | 0 |
| 11 | `-ENOBUFS` | **0** | 10 |
| 12 | `-ENOBUFS` | **0** | 10 |

Pedir 11 com 10 disponíveis devolve **zero**, não dez. Não existe meio-termo:
[`rte_mempool_get_bulk()`][apigetbulk] é tudo ou nada.

A consequência é um erro de programação difícil de ver em revisão de código:

```c
if (rte_mempool_get_bulk(pool, lote, n) != 0)
    continue;          /* parece "tenta de novo"; é uma parada total */
```

Com o pool abaixo de `n`, essa condição é verdadeira **em toda volta**. O laço
gira sem produzir nada, sem erro, sem log, consumindo 100% do núcleo. Não é
lentidão: é *livelock*, e o único sintoma é a vazão indo a zero enquanto o
processo aparenta estar ocupadíssimo.

Para aceitar o que houver é preciso pedir menos, ou usar
[`rte_mempool_get()`][apiget] um objeto por vez — que custa mais por objeto,
justamente o que a §1 mediu.

### 6.2 A regra 4, confrontada — e corrigida

A [§4 do dimensionamento](medicoes/sizing.h) enuncia, a partir da
documentação do DPDK, que com `n % cache_size != 0` alguns objetos *"will
always stay in the pool and will never be used"*. Até aqui isso era **aritmética
testada em L1**, nunca observada num pool de verdade.

Observada, ela não se confirma:

| n | cache | Previsto preso | Obtidos de fato | Confere? |
|---:|---:|---:|---:|---|
| 1023 | 0 | 0 | 1023 | sim |
| 1024 | 256 | 0 | 1024 | sim |
| 4095 | 256 | **255** | **4095** | **não** |
| 1023 | 32 | **31** | **1023** | **não** |

Um consumidor único drenando o pool obtém **todos** os objetos, inclusive os que
a regra dava como perdidos. O mecanismo está no cabeçalho do próprio DPDK: em
`rte_mempool_do_generic_get()`, quando o reabastecimento do cache falha por não
haver objetos para um lote inteiro, o código faz `goto driver_dequeue` e busca
os que faltam **direto do anel de trás**, ignorando o cache.

Então a regra 4 está errada? Não — está mal enunciada. Ela não é uma condição de
**alcançabilidade**; é de **eficiência em regime**, com vários lcores: cada cache
retém objetos que os outros núcleos não enxergam, e a divisibilidade decide se a
reposição acontece em lotes cheios. Vale seguir a regra, só não pelo motivo que
a frase original sugere.

> **Este é o segundo folclore que este módulo derruba medindo.** O primeiro foi
> o custo do `malloc()` na [§1](#1-por-que-não-usar-malloc--a-resposta-medida),
> repetido pela própria trilha até alguém medir 2,18 ns. A diferença é que
> aquele veio da cultura oral da área, e este veio da **documentação oficial** —
> o que é mais desconfortável e mais instrutivo: fonte primária também precisa
> ser confrontada com o comportamento.

### 6.3 O que ainda não foi medido

O caso dos vários lcores — o regime em que a regra 4 realmente atua — **não** é
coberto por este experimento, que usa um consumidor só. Medi-lo exige o mesmo
aparato de [`custo-contencao.c`](medicoes/custo-contencao.c), e fica registrado
aqui como pendência, não como resultado.

Também não é coberto o consumidor lento com o anel cheio: o retorno parcial de
`rte_ring_enqueue_burst()` e o vazamento que ele provoca quando ignorado estão
medidos no [tópico prático](../../trilha/01-fundamentos/02-mempool-ring/README.md#6-quando-dá-errado),
que é onde há um pipeline de verdade para enchê-lo.

## 7. Limitações deste documento

- **As medições são de um lcore só, sem disputa.** É deliberado — o objetivo foi
  isolar o custo das estruturas, não o da coerência de cache entre núcleos, que
  os [fundamentos](../01-fundamentos/README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só)
  já mediram. Com produtor e consumidor em núcleos distintos, os números do anel
  são outros e maiores.
- **As medições publicadas aqui são custo por operação, não latência.** Por isso
  aparecem como mediana com dispersão, e não por percentis. É uma escolha, não
  esquecimento: o que interessa numa operação executada milhões de vezes é o
  custo típico e sua estabilidade. A pergunta de **cauda** — o que acontece com a
  operação que encontra o cache vazio, ou o pool esgotado — é de outra natureza e
  não foi medida neste módulo. Ver a distinção entre desempenho e previsibilidade
  na [§4 da visão geral](../00-visao-geral/README.md#4-como-ler-os-números).
- **O pool está quente em todas as medições.** Nenhum número inclui falta de
  página ou primeira passagem pela memória, que em produção é mais cara.
- **O mecanismo do degrau do `malloc` não foi investigado**, apenas observado.
  Explicar o alocador da glibc está fora do escopo deste projeto.
- **Não há NIC.** Os mbufs deste módulo são alocados e manipulados à mão; nenhum
  veio por DMA. O `rte_mbuf` preenchido por hardware, com os campos de *offload*,
  é assunto do [tópico de RX/TX](../../trilha/02-pipeline/01-rx-tx-burst/).
- **`rte_mempool` tem gestores alternativos** (*mempool handlers*: `stack`,
  `bucket`, e os de hardware) que este módulo não compara. Foi usado o padrão.

---

## 8. Referências externas

**Documentação oficial do DPDK**

- [Mempool Library][guiamempool] — estrutura, cache por lcore e alinhamento
- [Mbuf Library][guiambuf] — layout, segmentação, headroom e metadados
- [Ring Library][guiaring] — o algoritmo do anel, SP/SC e MP/MC

**Deste projeto**

- [01 — Fundamentos](../01-fundamentos/README.md) — cache, falso compartilhamento
  e o orçamento por pacote
- [02 — Runtime do DPDK](../02-runtime-dpdk/README.md) — a memória de onde estes
  objetos saem
- [Tópico prático 02](../../trilha/01-fundamentos/02-mempool-ring/) — o ciclo
  completo em código, com testes L1 e L2
- [Alternativa em C++23](../../trilha/01-fundamentos/02-mempool-ring/alternativas/cpp23/) —
  o mesmo problema sem DPDK

---

## 9. Navegação

| | |
|---|---|
| **Anterior** | [02 — Runtime do DPDK](../02-runtime-dpdk/README.md) |
| **Prático** | [Tópico 02 — Mempool, ring e lote](../../trilha/01-fundamentos/02-mempool-ring/) |
| **Próximo** | [Pipeline e backpressure](../../trilha/02-pipeline/) |
| **Plano** | [Plano de estudo](../plano-estudo-dpdk.md) |

[guiamempool]: https://doc.dpdk.org/guides/prog_guide/mempool_lib.html
[guiaring]: https://doc.dpdk.org/guides/prog_guide/ring_lib.html
[guiambuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html

[apiprepend]: https://doc.dpdk.org/api/rte__mbuf_8h.html#a37b34f8b32723db17b2df80391bfa42d
[apichain]: https://doc.dpdk.org/api/rte__mbuf_8h.html#af52dbeb3951f5b90259d3760128ee139
[apimbuffree]: https://doc.dpdk.org/api/rte__mbuf_8h.html#a1215458932900b7cd5192326fa4a6902
[apienqbulk]: https://doc.dpdk.org/api/rte__ring_8h.html#ab8debfb458e927d559e7ce750048502d
[apiget]: https://doc.dpdk.org/api/rte__mempool_8h.html#a6150c041e889498a08d0e0d0769292cb
[apigetbulk]: https://doc.dpdk.org/api/rte__mempool_8h.html#a0d326354d53ef5068d86a8b7d9ec2d61
