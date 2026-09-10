# Runtime do DPDK — a EAL como sistema de execução

> **Nível 3** do [plano de estudo](../plano-estudo-dpdk.md) ·
> Pré-requisito: [Fundamentos](../01-fundamentos/README.md) e o tópico prático
> [01 — Inicialização da EAL](../../trilha/01-fundamentos/01-eal-hello/)

O tópico 01 da trilha mostra um programa mínimo subindo a [EAL][cEAL] e
encerrando. Este módulo trata do que vem depois dessa primeira execução: como o
runtime se comporta como **sistema**, o que ele custa, o que ele deixa no host,
e quais decisões ele impõe a quem vai colocar um processo de plano de dados em
produção e mantê-lo lá.

O exemplo condutor é o mesmo dos fundamentos: um **servidor de *market data***,
que recebe o *feed* de uma bolsa com ativo de alta movimentação. Ele foi
escolhido na [§6.2 dos fundamentos](../01-fundamentos/README.md#62-o-barramento-também-tem-orçamento)
como o caso canônico de latência ultrabaixa, e serve bem aqui porque força todas
as perguntas deste nível de uma vez: quanto tempo o processo leva para ficar
pronto, onde a memória é reservada, como uma estratégia lê o livro sem copiar
dado, e o que acontece quando um dos processos cai no meio do pregão.

> **In English.** The DPDK runtime as a system, not an API tour. Measures
> `rte_eal_init()` at **123 ms** against **0.30 ms** for cleanup — two orders of
> magnitude between birth and death, which is why a DPDK process is a
> long-running service. Covers the EAL memory model, lcore identity and states,
> IOVA, and a working primary/secondary pair sharing memory at the **same
> virtual address**. Failure axis: when the primary is killed, the secondary
> never finds out — the memory outlives its owner and nothing signals.

## Ao final deste módulo, você será capaz de

1. **explicar o que `rte_eal_init()` decide** antes da primeira linha da sua
   lógica executar, e medir quanto isso custa;
2. **diagnosticar por que a EAL não sobe** distinguindo hugepage ausente de
   hugepage inacessível — que exigem correções diferentes;
3. **escolher entre `--in-memory`, `--no-huge` e hugetlbfs** sabendo o que cada
   um desliga;
4. **projetar um sistema em processos primário e secundário**, e dizer o que
   atravessa a fronteira e o que não atravessa;
5. **isolar instâncias na mesma máquina** com `--file-prefix`, e explicar a regra
   de listas de lcore disjuntas;
6. **mapear lcores a CPUs explicitamente**, e não confundir identificador de
   lcore com número de CPU;
7. **justificar por que um processo DPDK é serviço de longa duração**, a partir
   do custo medido de inicialização.

## Índice

1. [O que este módulo acrescenta às fontes existentes](#1-o-que-este-módulo-acrescenta-às-fontes-existentes)
2. [O custo de existir: quanto a EAL leva para nascer](#2-o-custo-de-existir-quanto-a-eal-leva-para-nascer)
3. [O modelo de memória da EAL](#3-o-modelo-de-memória-da-eal)
4. [Processos primário e secundário](#4-processos-primário-e-secundário)
5. [lcores: identidade, mapeamento e estados](#5-lcores-identidade-mapeamento-e-estados)
6. [IOVA: o endereço que o dispositivo enxerga](#6-iova-o-endereço-que-o-dispositivo-enxerga)
7. [Encerramento: o que fica para trás](#7-encerramento-o-que-fica-para-trás)
8. [Síntese: o runtime do feed handler](#8-síntese-o-runtime-do-feed-handler)
9. [Validação: reproduza na sua máquina](#9-validação-reproduza-na-sua-máquina)
10. [Quando dá errado](#10-quando-dá-errado)
11. [Limitações deste documento](#11-limitações-deste-documento)
12. [Referências externas](#12-referências-externas)
13. [Navegação](#13-navegação)

---

## 1. O que este módulo acrescenta às fontes existentes

Material sobre a EAL não falta. Há a documentação oficial, há uma tradição forte
de *análise de código-fonte* (源码分析) em chinês, e há dezenas de tutoriais em
inglês. Antes de escrever mais um, vale dizer onde os existentes são melhores
que este documento — e onde eles envelheceram.

**Onde as fontes existentes são melhores.** A documentação oficial é a
autoridade e deve ser a primeira parada; nada aqui a substitui. E a tradição
chinesa de análise de código-fonte cobre um terreno que este módulo não tenta
cobrir: a sequência interna de `rte_eal_init()`, função por função, com os nomes
das estruturas internas. Para quem precisa depurar a EAL, esse material é mais
útil do que qualquer coisa escrita aqui.

**Onde elas envelheceram.** O DPDK muda a API com frequência, e material técnico
não se corrige sozinho. Os pontos abaixo foram **verificados nesta máquina**,
contra o DPDK 25.11 instalado, e cada um deles aparece com a forma antiga em
material ainda muito citado:

| O que mudou | Forma antiga, ainda comum | Forma atual (25.11) | Consequência de copiar a antiga |
|---|---|---|---|
| Vocabulário de lcore | *master* / *slave*, 主核 / 从核 | *main* / *worker* | `--master-lcore` é rejeitado: `ARGPARSE: unknown argument --master-lcore!`, saída 234 |
| Iterador de lcores | `RTE_LCORE_FOREACH_SLAVE` | `RTE_LCORE_FOREACH_WORKER` | não compila |
| Obter o lcore principal | `rte_get_master_lcore()` | [`rte_get_main_lcore()`][apimainlcore] | não compila |
| Estados do lcore | `WAIT`, `RUNNING`, `FINISHED` | `WAIT`, `RUNNING` | código que espera `FINISHED` nunca o vê |
| Memória por nó | [`--socket-mem`][optlinux] | [`--numa-mem`][optlinux] (`--socket-mem` virou apelido) | ainda funciona, mas a documentação atual está sob o outro nome |

As três primeiras linhas vêm da renomeação feita no **DPDK 20.11**, que as notas
de versão registram assim: *"Replaced the function `rte_get_master_lcore()` with
`rte_get_main_lcore()`. The old function is deprecated"*, e *"`RTE_LCORE_FOREACH_SLAVE`
is replaced with `RTE_LCORE_FOREACH_WORKER`"* ([notas de versão 20.11][rel2011]).
A quarta é verificável no cabeçalho instalado: `enum rte_lcore_state_t` tinha
três valores na [API 19.11][api1911] e tem **dois** em 25.11.

**Três assuntos que quase nenhuma fonte cobre.** Não por descuido: eles exigem
medir ou testar, e não aparecem lendo o código-fonte.

1. **Quanto custa `rte_eal_init()`.** É um número que decide arquitetura, e não
   se encontra publicado. A [§2](#2-o-custo-de-existir-quanto-a-eal-leva-para-nascer)
   mede, e mostra que 83% dele nesta máquina não é trabalho — é uma espera.
2. **Quais opções da EAL são mutuamente incompatíveis.** Tutoriais apresentam
   [`--in-memory`][optmem] e [`--no-huge`][optdebug] como atalhos convenientes para rodar sem
   privilégio. Ambos **desligam o suporte a processo secundário**, e a maior
   parte do material não diz isso. A [§4.5](#45-o-que-desliga-o-modelo-multiprocesso-sem-avisar)
   demonstra as duas falhas.
3. **Onde a EAL grava seus arquivos de runtime.** Praticamente todo tutorial diz
   `/var/run/dpdk`. Para um usuário comum, o caminho é outro, e a
   [§3.2](#32-o-que-a-eal-deixa-no-host) mostra qual.

Há também uma armadilha de nomenclatura que sobrevive em qualquer versão:
[`rte_lcore_to_cpu_id()`][apitocpuid] **não devolve o número da CPU**. Está na
[§5.1](#51-lcore-não-é-cpu).

> Este documento é uma leitura crítica, não uma correção de terceiros. Ele não
> nomeia autores nem artigos: o objetivo é dar ao leitor o critério para avaliar
> o material que encontrar, começando por uma pergunta simples — *para qual
> versão do DPDK isto foi escrito?*

---

## 2. O custo de existir: quanto a EAL leva para nascer

O tópico 01 descreve o que [`rte_eal_init()`][apiealinit] faz. A pergunta deste
módulo é outra: **quanto tempo isso leva**, e o que esse tempo implica.

O programa [`medicoes/custo-init.c`](medicoes/custo-init.c) mede. A metodologia
é imposta pelo próprio objeto de estudo: `rte_eal_init()` não é reentrante — a
segunda chamada no mesmo processo devolve `EALREADY` —, então **cada amostra
exige um processo**. O programa faz `fork()` por amostra; o filho inicializa,
cronometra e devolve o resultado por um *pipe*; o pai apenas agrega.

```
== Custo de inicializar e encerrar a EAL ==

  configuracao medida: -l 0 --in-memory
  amostras: 11 (uma por processo; rte_eal_init nao e reentrante)

  valores em MILISSEGUNDOS

  medicao                              mediana  p25-p75 (IQR)   amplitude min-max  disp    CV
  ---------------------------------- ---------  --------------- ----------------- ----- -----
  rte_eal_init()                         123.1  122.4-123.1     121.3-123.9         0.6%   0.6%  
  rte_eal_cleanup()                      0.082  0.079-0.102     0.071-0.147        28.6%  25.9% !

  Leitura:
    Em 10 GbE com quadros de 64 B chega 1 pacote a cada 67,2 ns.
    A janela de 123 ms da inicializacao equivale a 2 milhoes de pacotes
    nao atendidos. Por isso o processo de plano de dados sobe uma vez
    e fica de pe: reinicia-lo em producao nao e uma operacao barata.
```

Subir a EAL custa **123 ms**; encerrá-la custa **0,08 ms** — três ordens de
grandeza menos. A assimetria é o primeiro fato relevante: nascer é caro, morrer
é barato.

### 2.1 De onde vêm os 123 ms

A primeira hipótese natural é que o custo esteja na memória ou na varredura de
dispositivos. As duas estão erradas:

| Configuração | `rte_eal_init()` mediana |
|---|---|
| `-l 0 --in-memory` | 120,0 ms |
| `-l 0 --in-memory --no-pci` | 122,3 ms |
| `-l 0 --no-huge --in-memory --no-pci` | 120,7 ms |

Desligar a varredura PCI não muda nada. Trocar hugepages por memória comum não
muda nada. Usar quatro lcores em vez de um não muda nada. O custo é **um piso
fixo**, e um piso fixo com dispersão de 0,6% não parece trabalho: parece espera.

**Trabalhando ou esperando?** A distinção é o problema, e a medição anterior não
consegue fazê-la: 123 ms de relógio de parede são idênticos nos dois casos.
Escolher o instrumento certo aqui é metade da lição.

Um perfilador de CPU — `perf`, por exemplo — é a escolha errada, e por um motivo
que vale entender: ele **amostra a CPU**, e processo dormindo não consome CPU.
Ele mostraria ausência de trabalho durante os 100 ms e deixaria o tempo decorrido
sem explicação. Perfilador enxerga trabalho; o que se procura aqui é espera.

O `strace` responde exatamente nesse eixo. Ele intercepta a fronteira com o
kernel — a mesma da [§2 dos fundamentos](../01-fundamentos/README.md#2-a-fronteira-user-space--kernel-space) —
e a opção `-T` informa quanto tempo cada chamada ficou bloqueada. Como a hipótese
já estava formada, o filtro `-e trace=clock_nanosleep` reduz milhares de chamadas
à única que interessa:

```console
$ strace -T -e trace=clock_nanosleep ./hello_dpdk -l 0 --in-memory --no-huge --no-pci
...
clock_nanosleep(CLOCK_REALTIME, 0, {tv_sec=0, tv_nsec=100000000}, NULL) = 0 <0.100083>
```

Uma única espera de **exatamente 100 ms**. Ela é a calibração da frequência do
TSC, e está no código da EAL — `lib/eal/linux/eal_timer.c`, função
`get_tsc_freq()`, que declara `struct timespec sleeptime = {.tv_nsec = NS_PER_SEC / 10 }`,
com o comentário `/* 1/10 second */` ([fonte][fonteeal]). O DPDK mede o TSC
contra o relógio do sistema durante um décimo de segundo para descobrir sua
frequência — a mesma que [`rte_get_tsc_hz()`][apitschz] devolve depois, e que
todo código que converte ciclos em nanossegundos usa.

**Ou seja: 100 dos 123 ms, 83% do custo de inicializar a EAL nesta máquina, não
são trabalho — são uma medição de relógio.**

> **O que o `strace` não resolveu.** Ele mostrou *que* há uma espera de 100 ms e
> *onde* ela ocorre; **por que** ela existe veio de ler o código da EAL, e a
> condição em que ela é dispensada, da [§2.2](#22-por-que-essa-espera-existe-e-quando-ela-não-acontece).
> E ele não produziu nenhum dos números publicados aqui: instrumentar cada
> chamada de sistema tem custo próprio, que distorceria a medição. Os 123 ms vêm
> de [`custo-init.c`](medicoes/custo-init.c); o `strace` entrou depois, para
> explicá-los. Medir e diagnosticar são passos distintos, com ferramentas
> distintas.

### 2.2 Por que essa espera existe, e quando ela não acontece

A calibração é condicional. O mesmo arquivo tem:

```c
if (arch_hz && is_tsc_known_freq())
    return arch_hz;
```

`is_tsc_known_freq()` procura o sinalizador `tsc_known_freq` em `/proc/cpuinfo`.
Quando o kernel já sabe a frequência do TSC — porque a leu do hardware, e não
por estimativa —, o DPDK confia nela e **pula os 100 ms**. Nesta máquina o
sinalizador não existe:

```console
$ grep -o 'constant_tsc\|nonstop_tsc\|tsc_known_freq' /proc/cpuinfo | sort -u
constant_tsc
nonstop_tsc
```

Há `constant_tsc` e `nonstop_tsc` — o TSC é confiável —, mas não
`tsc_known_freq`. Por isso a calibração roda.

A consequência prática é que **o número 123 ms não é uma propriedade do DPDK**:
é uma propriedade desta combinação de CPU e kernel. Em uma máquina que exponha
`tsc_known_freq`, o mesmo `rte_eal_init()` custaria algo perto de 23 ms. Medir na
sua máquina é parte do exercício, e o programa aceita as opções da EAL
diretamente para isso.

### 2.3 O que isso decide na arquitetura

Um custo de partida de dezenas a centenas de milissegundos elimina uma classe
inteira de desenhos:

- **Não existe processo DPDK por requisição, por conexão ou por tarefa.** O
  modelo é serviço de longa duração; qualquer coisa que suba e desça o runtime
  com frequência paga o custo todas as vezes.
- **Reiniciar em produção é um evento, não uma rotina.** Voltando ao exemplo:
  reiniciar o *feed handler* durante o pregão significa 123 ms sem receber, mais
  o tempo de reassinar o *feed* e reconstruir o livro. A [§7 dos
  fundamentos](../01-fundamentos/README.md#7-métricas-o-vocabulário-para-não-se-enganar)
  trata latência por percentis justamente porque eventos raros e caros são o que
  define o comportamento observado — e 123 ms é um evento caríssimo num sistema
  cujo requisito se mede em microssegundos.
- **A separação entre o que reinicia e o que não reinicia vira decisão de
  projeto.** É exatamente o argumento para o modelo multiprocesso da
  [§4](#4-processos-primário-e-secundário): manter de pé o processo que não pode
  cair, e deixar reiniciável o que muda com frequência.

> **Uma ressalva honesta.** 123 ms mede `rte_eal_init()` isolada. Uma aplicação
> real ainda vai configurar portas, alocar mempools e filas, e subir os
> trabalhadores — trabalho que este número não inclui. O tempo total até o
> primeiro pacote processado é maior, não menor.

---

## 3. O modelo de memória da EAL

O tópico 01 diz que a EAL "reserva memória". Este módulo precisa ser mais
específico, porque é dessa especificidade que dependem os processos secundários,
o alinhamento NUMA e o comportamento operacional do host.

### 3.1 Memzone: memória com nome

O `malloc()` devolve um ponteiro. Um ponteiro é válido **dentro de um processo**,
e some quando ele termina. Isso basta para quase todo software, e não basta aqui.

A EAL oferece a **memzone**: uma região de memória contígua, reservada nas
páginas que a EAL administra, identificada por um **nome**. Reserva-se com
[`rte_memzone_reserve()`][apimzreserve] e recupera-se com
[`rte_memzone_lookup()`][apimzlookup]:

```c
/* no processo que cria */
const struct rte_memzone *mz =
    rte_memzone_reserve("academia_feed_marketdata", tamanho, rte_socket_id(), 0);

/* em OUTRO processo, que apenas se anexa */
const struct rte_memzone *mz = rte_memzone_lookup("academia_feed_marketdata");
```

Três propriedades importam:

**O nome é o contrato.** É a única coisa que os dois processos precisam combinar
previamente. Não há socket, porta, nem caminho de arquivo na aplicação — há uma
cadeia de caracteres. Toda estrutura de alto nível do DPDK que é compartilhável
entre processos (mempool, ring, tabela de hash) é construída sobre esse mesmo
mecanismo de nomeação.

**O nó NUMA é escolhido na reserva, não descoberto depois.** O terceiro argumento
é o *socket id*. Passar [`rte_socket_id()`][apisocketid] reserva no nó do lcore
atual; num servidor de *market data* o valor correto é o nó **da NIC**, para que
placa, memória e núcleo fiquem no mesmo nó — a exigência que fecha a tabela de
configuração da [§6.2 dos fundamentos](../01-fundamentos/README.md#62-o-barramento-também-tem-orçamento).
A alternativa `SOCKET_ID_ANY` deixa a EAL escolher, o que é aceitável em
laboratório e não é em produção.

**A memzone conhece seu endereço físico.** A estrutura devolvida traz `addr` (o
endereço virtual) e `iova` (o endereço que um dispositivo usaria para DMA). Essa
segunda coluna é o assunto da [§6](#6-iova-o-endereço-que-o-dispositivo-enxerga).

### 3.2 O que a EAL deixa no host

Uma memzone precisa sobreviver ao processo que a criou para que outro processo a
encontre. A EAL consegue isso gravando arquivos, e é útil saber onde:

```console
$ ./estado-lcore -l 0 --no-huge --file-prefix=demo_estrutura &
$ find /run/user/1000/dpdk/demo_estrutura -type f
  $XDG_RUNTIME_DIR/dpdk/demo_estrutura/fbarray_nohugemem
  $XDG_RUNTIME_DIR/dpdk/demo_estrutura/fbarray_memzone
  $XDG_RUNTIME_DIR/dpdk/demo_estrutura/config
```

Dois detalhes que costumam surpreender:

**O caminho não é `/var/run/dpdk`.** Quase todo material diz que é, e para
`root` é mesmo. Para um usuário comum, a EAL usa o diretório de runtime da
sessão — `$XDG_RUNTIME_DIR/dpdk/<prefixo>/`, que nesta máquina resolve para
`/run/user/1000/dpdk/<prefixo>/`. Quem procura no lugar errado conclui que a EAL
não gravou nada.

**Os arquivos permanecem depois que o processo sai.** Ao listar o diretório após
o encerramento, `config`, `fbarray_memzone` e `fbarray_nohugemem` continuam lá.
Isso é intencional — um secundário pode subir depois —, mas significa que
execuções repetidas acumulam diretórios de runtime, e que um processo morto de
forma abrupta deixa estado para trás. É o assunto da
[§7](#7-encerramento-o-que-fica-para-trás).

O `mp_socket` que aparece no log da EAL (`EAL: Multi-process socket
/run/user/1000/dpdk/academia/mp_socket`) vive no mesmo diretório: é o canal por
onde primário e secundários trocam mensagens de controle — não dados.

### 3.3 Os três graus de "não deixar rastro"

Existem três opções da EAL que reduzem o que fica no host, e elas são
frequentemente confundidas porque as descrições se parecem. Elas não são
equivalentes:

| Opção | O que ela remove | Processo secundário continua possível? |
|---|---|---|
| [`--huge-unlink`][optmem] | os arquivos de hugepage, ao sair | **sim** (nas variantes `existing`/`never`) |
| [`--no-shconf`][optmem] | os arquivos de configuração compartilhada | **não** |
| `--in-memory` | tudo: nada é gravado em sistema de arquivos | **não** |

`--in-memory` é a mais forte, e a própria ajuda da EAL declara o efeito colateral
sem meias palavras:

```
--in-memory   DPDK should not create shared mmap files in filesystem
              (disables secondary process support)
```

É a opção que o tópico 01 usa, e que boa parte do material recomenda como atalho
para "rodar sem sujeira". O atalho é legítimo — e desliga metade deste módulo.

### 3.4 Reservar memória por nó

Por padrão a EAL reserva o que encontrar disponível. Duas opções dão controle:

- **`-m <MB>`** — total a reservar, sem dizer de onde.
- **`--numa-mem <lista>`** — quanto reservar em **cada nó**, na ordem dos nós:
  `--numa-mem 2048,2048` pede 2 GiB em cada um de dois nós.

Em máquina de um nó, como a de referência deste projeto, as duas fazem
praticamente a mesma coisa. Em máquina de vários soquetes, `--numa-mem` é a
opção que impede o cenário descrito na
[§4.3 dos fundamentos](../01-fundamentos/README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só):
o processo reservar tudo no nó errado e pagar acesso remoto em cada pacote.

> **Cuidado com a nomenclatura.** No DPDK 25.11 o nome canônico é `--numa-mem`;
> `--socket-mem` continua funcionando, mas a ajuda o descreve como
> `Alias for --numa-mem`. Material escrito antes dessa mudança usa apenas o nome
> antigo — que não está errado, apenas não é mais o nome principal.

---

## 4. Processos primário e secundário

Este é o assunto central do módulo, e o que nenhum outro tópico do projeto
cobre. É também onde o exemplo de *market data* deixa de ser ilustração e passa
a ser a justificativa do desenho.

### 4.1 Por que dois processos

Considere a mesa de operações. De um lado, o **feed handler**: recebe o
multicast da bolsa, normaliza cada atualização e mantém o livro. Do outro, as
**estratégias**: leem o livro e decidem. Um desenho ingênuo põe tudo num
processo só, com threads. Três forças empurram na direção contrária:

**Isolamento de falha.** Uma estratégia é código que muda toda semana. Um
ponteiro inválido nela derruba o processo inteiro — e com ele o *feed handler*,
que perde a assinatura e o livro. Separando os processos, a estratégia cai
sozinha.

**Ciclos de vida diferentes.** A estratégia é recompilada e reiniciada várias
vezes ao dia; o *feed handler* deveria subir uma vez. A [§2](#2-o-custo-de-existir-quanto-a-eal-leva-para-nascer)
dá o número que torna isso concreto: cada reinício custa 123 ms de EAL. Reiniciar
só o que precisa ser reiniciado deixa de ser preferência e vira requisito.

**Fronteiras organizacionais.** Times diferentes, permissões diferentes, às vezes
linguagens diferentes. O processo é a unidade que o sistema operacional sabe
isolar.

O preço é que a comunicação deixa de ser uma variável compartilhada e passa a
exigir memória compartilhada explícita. É exatamente o que a EAL oferece — e sem
cópia, o que a distingue de um *pipe* ou de um socket local.

### 4.2 Como o secundário encontra a memória

A EAL classifica cada processo em um de dois papéis, escolhido por
[`--proc-type`][optmulti]:

| Papel | Pode criar memória compartilhada | Pode se anexar à existente |
|---|---|---|
| **primário** (`--proc-type=primary`, padrão) | sim | — |
| **secundário** (`--proc-type=secondary`) | **não** | sim |

A documentação oficial resume: *"secondary processes, which cannot initialize
shared memory, but can attach to pre-initialized shared memory and create objects
in it"* ([guia de multiprocesso][cmultiproc]).

O mecanismo é o descrito na [§3.2](#32-o-que-a-eal-deixa-no-host): o primário
registra em arquivos mapeados quais hugepages usa e em quais endereços virtuais
as mapeou; o secundário lê esses arquivos e **recria o mesmo mapeamento**. O
resultado é a propriedade que faz todo o modelo funcionar:

> A mesma região aparece no **mesmo endereço virtual** nos dois processos.

Isso é o que permite ler uma estrutura compartilhada como se fosse local, sem
traduzir deslocamentos. É também o que torna a partida do secundário sensível ao
ASLR — ver [§4.4](#44-o-que-não-atravessa-a-fronteira).

O exemplo deste módulo são dois binários independentes:

- [`medicoes/feed-primario.c`](medicoes/feed-primario.c) — reserva a memzone,
  publica ticks num anel e espera o consumo;
- [`medicoes/feed-secundario.c`](medicoes/feed-secundario.c) — encontra a memzone
  pelo nome, consome os ticks, reconstrói o livro e mede a latência da travessia.

O contrato entre eles é um cabeçalho, [`medicoes/feed.h`](medicoes/feed.h), e o
que ele decide vale a pena ler:

```c
struct feed_compartilhado {
    /* --- escrito SÓ pelo produtor (primário) --- */
    _Alignas(FEED_LINHA) _Atomic uint64_t publicados;

    /* --- escrito SÓ pelo consumidor (secundário) --- */
    _Alignas(FEED_LINHA) _Atomic uint64_t consumidos;
    ...
};
```

O `_Alignas(64)` separando `publicados` de `consumidos` não é zelo decorativo. É
a correção direta do problema medido na
[§4.2.1 dos fundamentos](../01-fundamentos/README.md#421-falso-compartilhamento-o-erro-mais-comum-de-quem-escreve-plano-de-dados),
onde duas variáveis na mesma linha de cache levaram uma operação de 8 ns para
53 ns. Aqui o erro seria pior: a linha disputada atravessaria a fronteira de
processo, e o sintoma apareceria como "o DPDK multiprocesso é lento", sem
qualquer pista do motivo real.

O outro detalhe do contrato é a ausência de ponteiros. `struct tick` guarda
apenas inteiros de tamanho fixo, e o anel é indexado por posição, nunca por
endereço. Ainda que a EAL prometa o mesmo endereço virtual dos dois lados,
depender disso na estrutura de dados troca uma garantia forte (índice) por uma
frágil.

### 4.3 `--file-prefix`: o isolamento entre instâncias

Nada impede que a mesma máquina rode dois sistemas DPDK independentes — a
instância de produção e a de simulação do dia anterior, por exemplo. Sem
separação, as duas disputariam os mesmos arquivos de runtime e as mesmas
hugepages.

[`--file-prefix`][optlinux] é essa separação. Ele nomeia o conjunto de arquivos de runtime,
e portanto define **o grupo**: processos com o mesmo prefixo se enxergam;
processos com prefixos diferentes são invisíveis entre si. A documentação
oficial descreve a opção como a que permite *"processes that do not want to
co-operate to have different memory regions"*, e é explícita quanto à regra
correspondente: *"secondary processes must use the same `--file-prefix`
parameter as the primary process whose shared memory they are connecting to"*
([guia de multiprocesso][cmultiproc]).

Traduzindo para o exemplo:

```bash
# instância de produção
./feed-primario   -l 0 --file-prefix=producao  ...
./feed-secundario -l 1 --file-prefix=producao  --proc-type=secondary

# instância de simulação, na MESMA máquina, sem interferir
./feed-primario   -l 2 --file-prefix=replay    ...
./feed-secundario -l 3 --file-prefix=replay    --proc-type=secondary
```

Há uma segunda regra, fácil de violar e difícil de diagnosticar: processos que
compartilham memória precisam de **listas de lcores disjuntas**. A documentação
não deixa margem — *"All DPDK processes running as a single application and
using shared memory must have distinct corelist arguments"*. Repare que o
exemplo acima respeita isso: `-l 0` e `-l 1` para produção, `-l 2` e `-l 3` para
o replay.

### 4.4 O que não atravessa a fronteira

O modelo compartilha memória, não o processo. Algumas coisas ficam de fora, e a
seção de limitações do guia oficial as lista:

- **Interrupções só funcionam no primário.** O secundário não recebe eventos de
  interrupção do dispositivo.
- **Ponteiros de função entre binários diferentes não são suportados.** Guardar
  um `void (*)(void)` numa estrutura compartilhada e chamá-lo do outro lado é
  comportamento indefinido: os dois binários são compilados separadamente e não
  têm o mesmo mapa de endereços de código.
- **A versão do DPDK precisa ser a mesma** nos dois processos, e as opções de
  dispositivo ([`--allow`][optdev] / [`--block`][optdev]) precisam coincidir quando o secundário
  acessa dispositivos físicos.
- **O ASLR atrapalha.** Como o secundário precisa recriar exatamente os mesmos
  mapeamentos, a aleatorização do espaço de endereços torna a partida dele, nas
  palavras da própria documentação, *"generally unreliable"* — e o guia é honesto
  quanto ao remédio: desligar o ASLR *"may help getting more consistent mappings,
  but not necessarily more reliable"*.

Esse último ponto merece leitura calma, porque é o principal argumento contra
usar o modelo multiprocesso onde ele não é necessário. Ele não é um mecanismo de
IPC de uso geral: é uma otimização com requisitos de ambiente.

### 4.5 O que desliga o modelo multiprocesso sem avisar

Aqui está o ponto operacional mais útil deste módulo, e o menos documentado.

As duas opções que tutoriais recomendam para "rodar sem privilégio" —
`--in-memory` e `--no-huge` — são incompatíveis com processo secundário. A
primeira avisa; a segunda, não.

**Com `--in-memory`** a ajuda da EAL declara o efeito, como visto na
[§3.3](#33-os-três-graus-de-não-deixar-rastro). Não há arquivo a mapear, logo não
há como um segundo processo se anexar.

**Com `--no-huge` não há aviso nenhum.** O primário sobe normalmente, cria a
memzone, imprime tudo o que se espera. O secundário falha:

```console
$ ./probe -l 0 --no-huge --file-prefix=academia --no-pci &      # primário
PROBE: init ok, consumiu 5 args, proc_type=PRIMARY
PROBE: memzone criada em 0x1040f2f80 (iova=0x1040f2f80), dormindo 8s

$ ./probe -l 1 --no-huge --file-prefix=academia --no-pci --proc-type=secondary
EAL: Cannot init memory
PROBE: init falhou: Cannot allocate memory
```

O motivo é o mesmo por baixo: `--no-huge` faz a EAL usar memória anônima comum,
que não é respaldada por arquivo e portanto não é mapeável por outro processo. A
mensagem `Cannot init memory` não menciona `--no-huge` em momento algum.

Isso leva a um triângulo de compromissos que vale memorizar:

| Modo | Hugepages reais | Processo secundário | Exige privilégio |
|---|---|---|---|
| `--in-memory` | **sim** (via `memfd`) | não | **não** |
| `--no-huge` | não | não | **não** |
| hugetlbfs + `--file-prefix` | **sim** | **sim** | escrita no hugetlbfs |

A primeira linha surpreende e é verificável: com `--in-memory`, a EAL obtém
hugepages sem precisar de acesso de escrita a `/dev/hugepages`, usando
`memfd_create` com `MFD_HUGETLB`. Dá para observar o efeito no contador do
kernel enquanto o processo roda:

```console
$ grep HugePages_Free /proc/meminfo     # antes
HugePages_Free:     1024
$ grep HugePages_Free /proc/meminfo     # durante, com --in-memory
HugePages_Free:     1023
$ grep HugePages_Free /proc/meminfo     # depois de sair
HugePages_Free:     1024
```

Uma hugepage de 2 MB é retirada do pool e devolvida no encerramento. É por isso
que `--in-memory` é um bom padrão para estudo: dá memória real sem exigir
privilégio. O que ele não dá é o modelo multiprocesso — e é essa a troca.

Para os exercícios da terceira linha, o projeto traz
[`scripts/preparar-hugepages.sh`](../../scripts/preparar-hugepages.sh), que monta
um `hugetlbfs` próprio com o dono correto em vez de rodar tudo como `root`:

```bash
sudo mount -t hugetlbfs -o pagesize=2M,uid=$(id -u) nodev /mnt/huge-academia
```

A escolha é deliberada. Rodar processo de plano de dados como `root` porque um
diretório tem modo `0755` é resolver um problema de permissão criando um de
segurança.

### 4.6 Quanto custa atravessar a fronteira

Com o requisito satisfeito, o exemplo roda e a pergunta que sobra é a única que
interessa a quem vai adotar o modelo: **quanto custa um dado sair de um processo
e chegar ao outro?**

O produtor carimba cada tick com `rte_rdtsc()` — a leitura direta do contador de
ciclos, cuja forma portável na API é [`rte_get_tsc_cycles()`][apitsccycles] —
imediatamente antes de publicá-lo; o consumidor lê o carimbo e o compara com o próprio relógio. Duzentos
mil ticks, produtor no lcore 0 e consumidor no lcore 1:

```
  --- travessia entre processos, por tick (nanossegundos) ---

  medicao                           minimo   mediana       p75       p99  amostras
  ------------------------------ --------- --------- --------- ---------  -------
  publicacao -> observacao           10.02     20.04     30.06     40.08   200000

    resolucao do instrumento: 11.8 ns (uma sondagem do consumidor).
    amostras degeneradas: 0 de 200000 (TSC alinhado entre os dois nucleos)
    Os valores acima sao LIMITE SUPERIOR: entre duas sondagens o
    consumidor esta cego, entao a travessia real cabe dentro do
    ultimo passo. Diferencas menores que 11.8 ns nao sao mensuraveis aqui.
```

**Dez nanossegundos no melhor caso, quarenta no p99.** Para dimensionar: o
orçamento de um pacote de 64 B em 10 GbE é de 67,2 ns
([§1 dos fundamentos](../01-fundamentos/README.md#1-o-orçamento-quanto-tempo-existe-por-pacote)).
A travessia de processo consome de 15% a 60% desse orçamento — cara o bastante
para não ser feita por pacote sem pensar, barata o bastante para viabilizar a
separação entre *feed handler* e estratégia, que é o que se ganha em troca.

Três observações metodológicas, e a terceira é a que impede uma conclusão errada:

**Nenhuma cópia acontece.** O tick é escrito uma vez, na memória compartilhada, e
lido de lá. O que os 10 ns medem é a linha de cache migrando de um núcleo para o
outro — não uma travessia de kernel, não um `memcpy`. Um `pipe` ou um socket
local no mesmo cenário custaria duas cópias e duas travessias de fronteira de
privilégio.

**Os dois relógios precisavam estar alinhados, e o programa verifica.** Produtor e
consumidor rodam em núcleos diferentes e comparam carimbos do TSC. Se os
contadores estivessem defasados, a subtração produziria valores impossíveis. O
programa conta esses casos e publica a contagem: **0 de 200 000**.

**Todos os valores são múltiplos de ~10 ns, e isso não é coincidência.** O
consumidor descobre um tick novo ao *sondar*; entre duas sondagens ele está cego.
O passo dessa régua é o custo de uma iteração do laço de espera — que o programa
mede e publica: 11,8 ns, dominado por [`rte_pause()`][apipause], que nesta CPU
custa cerca de 55 ciclos. Ou seja, a tabela diz "o tick foi visto na 1ª, 2ª, 3ª ou
4ª sondagem depois de publicado", e os valores são **limite superior** da
travessia real.

> Isto é o mesmo fenômeno da [§5.2 dos fundamentos](../01-fundamentos/README.md#52-polling-a-pergunta-que-o-plano-de-dados-responde-de-outro-jeito),
> visto do outro lado. Lá, polling aparece como a escolha que troca CPU por
> latência determinística. Aqui ele aparece como o **instrumento de medida**: um
> consumidor que sonda não consegue resolver diferenças menores que o próprio
> período de sondagem. Publicar a resolução junto com o resultado é o que separa
> medição de número decorativo.

---

## 5. lcores: identidade, mapeamento e estados

O tópico 01 define lcore (*logical core*) como uma thread criada pela EAL e
fixada a uma CPU lógica. Este módulo trata das três confusões que essa definição
não resolve sozinha.

### 5.1 lcore não é CPU

O identificador de lcore do DPDK e o número da CPU do sistema são coisas
diferentes que coincidem por padrão. Com `-l 0-3`, o lcore 2 roda na CPU 2 — e é
justamente essa coincidência que esconde a distinção até o dia em que ela
importa.

O programa [`medicoes/estado-lcore.c`](medicoes/estado-lcore.c) mostra as duas
colunas lado a lado. Com `-l 0-3`:

```
  lcore    CPU(s) reais   papel        indice no no   no NUMA 
  -----    ------------   -----        ------------   ------- 
  0        0              principal    0              0       
  1        1              trabalhador  1              0       
  2        2              trabalhador  2              0       
  3        3              trabalhador  3              0       
```

Com `--lcores '0@6,1@7,2@18'`, a mesma máquina:

```
  lcore    CPU(s) reais   papel        indice no no   no NUMA 
  -----    ------------   -----        ------------   ------- 
  0        6              principal    0              0       
  1        7              trabalhador  1              0       
  2        18             trabalhador  2              0       
```

O lcore 0 agora executa na CPU 6. E repare na quarta coluna: ela **não** mudou.

Essa quarta coluna vem de [`rte_lcore_to_cpu_id()`][apitocpuid], e o nome da
função engana. A documentação da própria API diz o que ela devolve: *"Return the
id of the lcore on a socket starting from zero"* — um **índice relativo ao nó
NUMA**, não o número da CPU. Quem usa esse valor para fixar uma thread, escolher
onde direcionar uma IRQ ou decidir afinidade acaba com o trabalho no núcleo
errado, e o único sintoma é o desempenho.

A função que devolve a CPU real é [`rte_lcore_cpuset()`][apicpuset], que entrega
o conjunto de CPUs ao qual o lcore está fixado — a terceira coluna da tabela.

A sintaxe de [`--lcores`][optlcore] importa em máquina com topologia relevante. A da
[§4.3 dos fundamentos](../01-fundamentos/README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só)
tem dois CCDs, e a comunicação entre eles custou de 83 a 123 ns contra 17,5 ns
dentro do mesmo CCD. Com [`-l`][optlcore], os lcores caem onde os números mandarem; com
`--lcores`, o mapeamento é escolhido — e é assim que se garante que produtor e
consumidor de um mesmo anel fiquem no mesmo domínio de cache.

### 5.2 A máquina de estados tem dois estados, não três

Um lcore trabalhador recebe trabalho por
[`rte_eal_remote_launch()`][apiremotelaunch] e é aguardado por
[`rte_eal_wait_lcore()`][apiwaitlcore]. Entre os dois, seu estado é observável
por [`rte_eal_get_lcore_state()`][apilcorestate].

A observação direta, na saída de `estado-lcore`:

```
  apos rte_eal_init:     lcore 1: WAIT     lcore 2: WAIT     lcore 3: WAIT    
  apos remote_launch:    lcore 1: RUNNING  lcore 2: RUNNING  lcore 3: RUNNING 
  durante o trabalho:    lcore 1: RUNNING  lcore 2: RUNNING  lcore 3: RUNNING 

  valores devolvidos pelos trabalhadores:
    lcore 1 -> 107
    lcore 2 -> 207
    lcore 3 -> 307

  apos wait_lcore:       lcore 1: WAIT     lcore 2: WAIT     lcore 3: WAIT    
```

Dois pontos:

**Depois de `rte_eal_init()`, os trabalhadores já estão em `WAIT`.** Não é um
estado ocioso genérico: é a inicialização que os coloca ali. O cabeçalho da API é
literal — *"It puts the WORKER lcores in the WAIT state"*. Os lcores existem
antes de a aplicação pedir qualquer coisa.

**Não existe `FINISHED`.** O estado volta a `WAIT` por conta própria. Isso é
mudança de versão, não detalhe de implementação: a [API 19.11][api1911] declara
três valores — `WAIT`, `RUNNING`, `FINISHED` — e descreve `rte_eal_wait_lcore()`
como a função que, encontrando um lcore em `FINISHED`, o *"switch[es] to the WAIT
state"*. Em 25.11 o enum tem dois valores, e o cabeçalho instalado descreve a
função sem qualquer menção a um terceiro estado.

O que **não** mudou é a razão de chamar `rte_eal_wait_lcore()`: ela é o canal de
retorno. O valor devolvido pela função do trabalhador chega ao lcore principal
por ali — na saída acima, `107`, `207` e `307`. Ignorar esse retorno é descartar
o único resultado que o trabalhador tinha como entregar.

### 5.3 Lcores de serviço

Há uma terceira categoria além de principal e trabalhador. `-S` / [`--service-corelist`][optlcore]
reserva lcores para **service cores** — tarefas de fundo que bibliotecas do DPDK
registram para rodar periodicamente, sem que a aplicação as chame.

Ela merece menção aqui por um motivo operacional: se a aplicação não reservar
lcores de serviço e alguma biblioteca precisar de um, o trabalho vai competir com
o caminho quente. Num sistema em que o requisito é a cauda da latência, trabalho
de fundo não anunciado é exatamente o tipo de coisa que produz um p99 que
ninguém consegue explicar.

---

## 6. IOVA: o endereço que o dispositivo enxerga

Uma NIC que escreve por DMA na memória do processo precisa de um endereço. Esse
endereço não é necessariamente o mesmo que a CPU usa, e o DPDK chama o que o
dispositivo usa de **IOVA** (*I/O virtual address*). A EAL escolhe entre dois
modos na inicialização, e reporta a escolha:

```
EAL: Selected IOVA mode 'VA'
```

| Modo | O que o dispositivo recebe | Exige |
|---|---|---|
| **PA** (*physical address*) | endereço físico real | acesso a `/proc/self/pagemap`, tipicamente privilégio; memória fisicamente contígua |
| **VA** (*virtual address*) | endereço virtual, traduzido pela IOMMU | IOMMU ativa, com o dispositivo em um grupo utilizável |

O modo VA é o que torna viável rodar plano de dados sem privilégio, e depende
diretamente da IOMMU descrita na
[§6.1 dos fundamentos](../01-fundamentos/README.md#61-iommu-como-entregar-dma-a-um-processo-sem-abrir-o-sistema).
A IOMMU traduz o endereço que o dispositivo apresenta, do mesmo modo que a MMU
traduz o da CPU — e, como toda tradução, tem sua própria cache e seu próprio
custo de falha, que é o IOTLB discutido lá.

Consultar o modo em tempo de execução é uma linha,
[`rte_eal_iova_mode()`][apiiovamode], e forçá-lo é `--iova-mode=pa|va`. Forçar
raramente é a resposta certa: quando a EAL escolhe PA numa máquina que deveria
usar VA, o problema costuma estar na IOMMU (desligada na BIOS, ou sem
`amd_iommu=on` / `intel_iommu=on` na linha de comando do kernel), e o modo é o
sintoma, não a causa.

Na saída do exemplo de *market data* aparece um detalhe instrutivo: com
`--no-huge`, a memzone reportou `addr` e `iova` **iguais** (`0x1040f2f80` nos
dois). Faz sentido — em modo VA, o endereço que o dispositivo usa *é* o virtual.
Já em modo PA os dois valores seriam diferentes, e a diferença seria justamente o
trabalho que a EAL faz para descobrir o endereço físico de cada página.

---

## 7. Encerramento: o que fica para trás

[`rte_eal_cleanup()`][apiealclean] custa 0,08 ms — três ordens de grandeza menos
que a inicialização. Sendo tão barato, a pergunta é o que acontece quando ele
não é chamado.

**A ordem importa.** Recursos criados sobre a memória da EAL devem ser liberados
**antes** dela:

```c
rte_memzone_free(mz);
rte_eal_cleanup();
```

Inverter é usar memória já devolvida. Numa aplicação com portas configuradas, o
encerramento correto começa antes disso ainda: parar as portas, fechá-las, e só
então limpar a EAL.

**E em multiprocesso entra uma restrição a mais, que só aparece executando.**
Liberar uma memzone compartilhada não é uma operação local: ela dispara uma
sincronização com os processos secundários (`mp_malloc_sync`). Se algum deles já
estiver encerrando, a requisição não é respondida:

```
EAL: Fail to recv reply for request /run/user/1000/dpdk/academia/mp_socket_...:mp_malloc_sync
EAL: Could not send sync request to secondary process
```

Nada é corrompido, mas a mensagem denuncia encerramento fora de ordem. A regra
que resolve tem duas partes, e a segunda é a que costuma faltar:

1. **O primário sai por último.** Ele é dono da memória e do socket de controle.
2. **"Por último" significa depois de o processo secundário ter SUMIDO**, não
   depois de ele ter terminado de ler. Entre uma coisa e outra o secundário ainda
   está desmontando seus mapeamentos — e é exatamente nessa janela que a
   sincronização falha.

O exemplo deste módulo espera as duas coisas: um sinal na memória compartilhada
("terminei de ler") e o desaparecimento do socket de controle do secundário no
diretório de runtime ("saí"). Com as duas, o encerramento fica silencioso. Em
produção, quem garante essa ordem costuma ser o orquestrador que para os
secundários antes de parar o primário — a EAL não faz isso por conta própria.

**O que sobra quando o processo morre de forma abrupta.** Um `SIGKILL` não
executa `rte_eal_cleanup()`. Ficam:

- os arquivos de runtime em `$XDG_RUNTIME_DIR/dpdk/<prefixo>/`, incluindo o
  `mp_socket`;
- os arquivos de hugepage em `/dev/hugepages/<prefixo>map_*`, e portanto as
  hugepages ainda contabilizadas como em uso;
- eventualmente, um dispositivo ainda vinculado ao processo morto.

A consequência prática é a de sempre em sistemas com estado externo ao processo:
subir de novo com o mesmo `--file-prefix` pode encontrar o estado antigo. Por
isso o teste L2 deste módulo usa um prefixo derivado do PID
(`academia_l2_$$`) e remove o diretório ao final — cada execução é uma instância
nova, sem herdar nada.

Vale registrar a assimetria completa, porque ela explica a escolha de arquitetura
da [§2.3](#23-o-que-isso-decide-na-arquitetura):

| Operação | Custo mediano | Ordem de grandeza |
|---|---|---|
| `rte_eal_init()` | 123 ms | 10⁵ µs |
| `rte_eal_cleanup()` | 0,082 ms | 10¹ µs |
| orçamento por pacote em 10 GbE, quadro de 64 B | 67,2 ns | 10⁻¹ µs |

Um processo de plano de dados passa a vida inteira operando na terceira linha.
Ele só toca a primeira uma vez — e é por isso que ela pode custar o que custa.

---

## 8. Síntese: o runtime do feed handler

Reunindo as decisões deste módulo no exemplo condutor, a linha de comando de um
*feed handler* de *market data* deixa de ser uma lista de opções e passa a ser um
conjunto de escolhas justificadas:

```bash
# --lcores '0@2,1@3'      lcores no MESMO domínio de cache   (§5.1)
# --numa-mem 4096         memória no nó da NIC               (§3.4)
# --file-prefix=producao  isola esta instância               (§4.3)
# --huge-dir=/mnt/huge-md hugetlbfs próprio, sem root        (§4.5)
# -a 0000:c1:00.0         só a NIC do feed
./feed-primario \
    --lcores '0@2,1@3' \
    --numa-mem 4096 \
    --file-prefix=producao \
    --huge-dir=/mnt/huge-md \
    -a 0000:c1:00.0 \
    -- 200000 cadencia
```

> **Por que os comentários estão acima, e não ao lado.** A versão anterior deste
> bloco punha `\` seguido de espaços e `#` na mesma linha, e **não funcionava se
> copiada**: a barra invertida escapa o espaço, não a quebra de linha. O `bash`
> executa `./feed-primario '--lcores' ' '` e trata a linha seguinte como um
> comando novo. Uma continuação de linha exige que a `\` seja o **último**
> caractere da linha.

| Escolha | Por quê | Onde foi estabelecido |
|---|---|---|
| lcores mapeados explicitamente | evita o custo de atravessar domínio de cache | [§5.1](#51-lcore-não-é-cpu) |
| memória reservada por nó | evita acesso remoto por pacote | [§3.4](#34-reservar-memória-por-nó) |
| `--file-prefix` nomeado | permite produção e replay na mesma máquina | [§4.3](#43---file-prefix-o-isolamento-entre-instâncias) |
| hugetlbfs próprio | multiprocesso sem rodar como `root` | [§4.5](#45-o-que-desliga-o-modelo-multiprocesso-sem-avisar) |
| processo único e longevo | inicializar custa 123 ms | [§2.3](#23-o-que-isso-decide-na-arquitetura) |
| secundário para a estratégia | isolamento de falha e ciclo de vida próprio | [§4.1](#41-por-que-dois-processos) |

Nenhuma dessas opções é sobre desempenho de código. Todas são sobre **o
ambiente** — que é precisamente a definição da EAL: *Environment Abstraction
Layer*.

---

## 9. Validação: reproduza na sua máquina

Todos os números deste documento vêm de programas em
[`medicoes/`](medicoes/), compilados junto com o projeto.

```bash
./scripts/build-all.sh
```

**Custo de inicialização** — troque as opções e compare:

```bash
./build/docs/02-runtime-dpdk/medicoes/custo-init -l 0 --in-memory
./build/docs/02-runtime-dpdk/medicoes/custo-init -l 0 --no-huge --in-memory --no-pci
```

**O que a EAL decidiu, e os estados do lcore**:

```bash
./build/docs/02-runtime-dpdk/medicoes/estado-lcore -l 0-3 --in-memory
./build/docs/02-runtime-dpdk/medicoes/estado-lcore --lcores '0@6,1@7' --in-memory
```

**Primário e secundário** — exige hugetlbfs gravável:

```bash
./scripts/preparar-hugepages.sh
export DPDK_ACADEMY_HUGE_DIR=/mnt/huge-academia
./scripts/test-all.sh l2
```

Sem esse requisito, o teste informa o que falta e é contado como **pulado**
(`SKIP`), não como sucesso: falta de privilégio no host não é defeito do código,
mas também não é verificação feita.

**Testes:**

```bash
./scripts/test-all.sh l1    # lógica do livro de ofertas, sem EAL
./scripts/test-all.sh l2    # runtime real
```

O L1 ([`medicoes/tests/test_l1_order_book.cpp`](medicoes/tests/test_l1_order_book.cpp))
cobre a lógica de *market data* sem tocar no DPDK: perda de datagrama,
retransmissão repetida, cancelamento de nível e a estabilidade do layout de
`struct tick`, que atravessa a fronteira de processo.

O **L3** ([`medicoes/tests/l3_multiprocesso.sh`](medicoes/tests/l3_multiprocesso.sh))
verifica o que só existe com dois processos, inclusive que a memzone aparece no
mesmo endereço virtual dos dois lados.

> **Por que L3, e não L2.** Este teste exige do host algo que ele precisa
> conceder: hugetlbfs com permissão de escrita. Onde faltar, ele sai com o
> código **77**, que o Meson reporta como `SKIP` e conta em separado.
>
> Ele saía com **0**, e o Meson reportava `OK` — com as nove verificações do
> script **não avaliadas**. No runner do CI o requisito nunca existe, então este
> teste jamais verificou coisa alguma e sempre apareceu verde. Um teste que
> passa sem testar é pior que um teste ausente: ele consome a confiança que
> deveria construir.

### Exercícios

1. Rode `custo-init` e confira se a sua máquina tem `tsc_known_freq` em
   `/proc/cpuinfo`. O tempo de `rte_eal_init()` bate com a previsão da
   [§2.2](#22-por-que-essa-espera-existe-e-quando-ela-não-acontece)?
2. Confirme a espera de 100 ms com
   `strace -T -e trace=clock_nanosleep`. Ela aparece mais de uma vez?
3. Suba `feed-primario` sem nenhum secundário. O que ele faz depois de 15 s, e
   por que o tempo de espera precisa ser generoso?
4. Suba o secundário **sem** `--proc-type=secondary`. Leia a mensagem: por que
   `--proc-type=auto` seria pior do que o erro?
5. Suba dois primários com o mesmo `--file-prefix`. Qual é o erro, e ele diz o
   que fazer?
6. Rode `feed-primario` em modo `rajada` em vez de `cadencia` e compare a mediana
   com o p99 da travessia. O que mudou, e por quê?
7. Em máquina de vários domínios de cache, coloque produtor e consumidor em CCDs
   diferentes com `--lcores` e refaça a medição da travessia. Compare com os
   valores da [§4.3 dos fundamentos](../01-fundamentos/README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só).

---

## 10. Quando dá errado

> **A pergunta deste módulo:** o que acontece quando o processo primário morre
> com secundários ainda vivos?

A [§4](#4-processos-primário-e-secundário) mostrou o caminho feliz: o secundário
encontra a memzone pelo nome, mapeia no mesmo endereço virtual, lê sem cópia. O
modelo é elegante justamente porque o secundário não precisa saber nada sobre o
primário além do `--file-prefix`.

Essa mesma independência é o problema.

### 10.1 O experimento

[`medicoes/tests/l3_primario_morre.sh`](medicoes/tests/l3_primario_morre.sh)
sobe o par, espera o secundário se anexar, e mata o primário com **SIGKILL** —
morte súbita, sem encerramento ordenado, como faria o *OOM killer* ou uma falha
de hardware.

```
== L3: o primario morre, o secundario continua ==

  ok    - secundario anexou-se a memoria do primario

  matando o primario (SIGKILL, sem encerramento ordenado)...
  ok    - primario morreu por sinal (codigo 137, esperado != 0)
  ok    - secundario sobreviveu a morte do primario (nao houve segfault)
  ok    - secundario NAO detectou a morte apos 5s: segue esperando
  ok    - secundario nao emitiu nenhum aviso de produtor ausente
  ok    - secundario nao concluiu: ficou no laco 'while (lidos < total)'
  ok    - so um sinal externo encerra o secundario
```

### 10.2 O que se aprende disso

**A memória sobrevive ao dono.** As páginas do hugetlbfs continuam mapeadas e
legíveis depois que o processo que as reservou deixou de existir. O secundário
não perde o mapeamento e não recebe `SIGSEGV`: ele continua lendo, e o que lê é
o **último estado publicado**, indefinidamente.

**Nada avisa.** Não há batimento cardíaco, contrato de *liveness* nem sinal. O
secundário fica preso em [`while (lidos < total)`](medicoes/feed-secundario.c#L126),
esperando dados que não virão. O processo não travou por defeito — ele espera
correta e indefinidamente por um produtor que não existe mais.

**Isto é pior que um *crash*.** Um processo que morre é observável: o supervisor
percebe, o alerta dispara, alguém age. Um consumidor que continua servindo dados
velhos com aparência de dados novos não é observável de fora — e num servidor de
*market data*, operar sobre um livro de ofertas congelado é pior do que não
operar.

> **A responsabilidade é da aplicação, e o DPDK não a assume.** Detectar produtor
> ausente exige número de sequência, *timestamp* de publicação ou *watchdog* — os
> três construídos por você. O modelo multiprocesso do DPDK entrega
> compartilhamento de memória, não um contrato de disponibilidade.

### 10.3 O que este experimento não cobre

Não é medido aqui o caso do **secundário** morrer com o primário vivo, nem o de
um primário que reinicia e tenta recriar uma memzone cujo nome ainda existe.
Ambos ficam registrados como pendência, não como resultado.

Também não há supervisor: o teste mata e observa, não tenta recuperar.
Recuperação coordenada — quem reinicia primeiro, como o secundário sabe que
pode reconectar, o que fazer com o estado obsoleto — é assunto de arquitetura
operacional, e não cabe num módulo de runtime.

## 11. Limitações deste documento

- **Nenhuma NIC é envolvida.** Os ticks são gerados por um PRNG determinístico. O
  objeto de estudo é o runtime; recepção real é o nível 4.
- **Máquina de um nó NUMA.** Tudo que este documento diz sobre `--numa-mem` e
  alinhamento de nó é raciocínio apoiado nos fundamentos, não medição local. Em
  máquina de um soquete, a opção não tem o que separar.
- **A travessia entre processos foi medida com produtor e consumidor no mesmo
  domínio de cache** (lcores 0 e 1, ambos no CCD 0). Em CCDs diferentes o custo
  sobe, e por quanto é o exercício 7 — o tópico prático mediu de 4,0 a 4,8 vezes
  para a travessia análoga dentro de um processo.
- **A resolução da medição de travessia é ~12 ns**, um período de sondagem do
  consumidor. Diferenças menores não são observáveis com este instrumento, e os
  valores publicados são limite superior, não o custo exato.
- **123 ms é desta máquina.** É o resultado de uma CPU sem `tsc_known_freq` com
  este kernel, e a [§2.2](#22-por-que-essa-espera-existe-e-quando-ela-não-acontece)
  explica por quê. Não use o número como característica do DPDK.
- **A comparação com outras fontes é sobre versões, não sobre autores.** O que a
  [§1](#1-o-que-este-módulo-acrescenta-às-fontes-existentes) documenta são
  mudanças de API verificáveis; material escrito antes delas estava correto
  quando foi escrito.

---

## 12. Referências externas

**Documentação oficial do DPDK**

- [Environment Abstraction Layer][cEAL] — o capítulo de referência do runtime
- [Multi-process Support][cmultiproc] — modelo primário/secundário, limitações e
  requisitos, incluindo as citações sobre ASLR e `--file-prefix`
- [EAL parameters][cparams] — lista normativa das opções de linha de comando
- [Release Notes 20.11][rel2011] — a renomeação master/slave para main/worker
- [API 19.11 de `rte_launch.h`][api1911] — o enum de três estados, para
  comparação
- [Requisitos de sistema][cHuge] — hugepages e configuração de host

**Código-fonte citado**

- [`lib/eal/linux/eal_timer.c`][fonteeal] — `get_tsc_freq()` e a espera de 100 ms

**Deste projeto**

- [Fundamentos](../01-fundamentos/README.md) — orçamento por pacote, cache,
  NUMA, falso compartilhamento e métricas
- [Tópico 01 — Inicialização da EAL](../../trilha/01-fundamentos/01-eal-hello/) —
  o programa mínimo e o contrato de `rte_eal_init()`
- [Mapa de links do DPDK](../../scripts/mapa-links-dpdk.md) — registro canônico
  dos símbolos citados

---

## 13. Navegação

| | |
|---|---|
| **Anterior** | [01 — Fundamentos](../01-fundamentos/README.md) |
| **Prático** | [Tópico 01 — Inicialização da EAL](../../trilha/01-fundamentos/01-eal-hello/) |
| **Próximo** | [03 — Mempool, ring e mbuf](../03-mempool-ring-mbuf/) |
| **Plano** | [Plano de estudo](../plano-estudo-dpdk.md) |

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
[apiealclean]: https://doc.dpdk.org/api/rte__eal_8h.html#a7a745887f62a82dc83f1524e2ff2a236
[apiiovamode]: https://doc.dpdk.org/api/rte__eal_8h.html#a1e1ff16a6096013452673ea31ea16aa8
[apimzreserve]: https://doc.dpdk.org/api/rte__memzone_8h.html#a58c7cd707097b56e3ca29fb3c172565e
[apimzlookup]: https://doc.dpdk.org/api/rte__memzone_8h.html#ac7fc18c445135eb2e91a1f2ab989cdde
[apiremotelaunch]: https://doc.dpdk.org/api/rte__launch_8h.html#a2bf98eda211728b3dc69aa7694758c6d
[apiwaitlcore]: https://doc.dpdk.org/api/rte__launch_8h.html#ae9500e1d35bd4cfb95d18c0be863cb1e
[apilcorestate]: https://doc.dpdk.org/api/rte__launch_8h.html#a66d883d90f6112489b69c996a2f6f2ab
[apitocpuid]: https://doc.dpdk.org/api/rte__lcore_8h.html#acbf23499dc0b2d223e4d311ad5f1b04e
[apicpuset]: https://doc.dpdk.org/api/rte__lcore_8h.html#a830bea1c9dda2c18d04252f297e25721
[apimainlcore]: https://doc.dpdk.org/api/rte__lcore_8h.html#a5449c6ee062fe3641520374152ce6c67
[apisocketid]: https://doc.dpdk.org/api/rte__lcore_8h.html#a7c8da4664df26a64cf05dc508a4f26df
[apitschz]: https://doc.dpdk.org/api/rte__cycles_8h.html#ae016e608f344823e677819d8f04264c5
[apitsccycles]: https://doc.dpdk.org/api/rte__cycles_8h.html#a34aaedfb8b9fa4f83d4cb3108cda2041
[apipause]: https://doc.dpdk.org/api/rte__pause_8h.html#ad59aa7777c93d3cfd5f10617a3acd1c5

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cmultiproc]: https://doc.dpdk.org/guides/prog_guide/multi_proc_support.html
[cparams]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html

[optlcore]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#lcore-related-options
[optmem]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#memory-related-options
[optmulti]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#multiprocessing-related-options
[optdev]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#device-related-options
[optdebug]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#debugging-options
[optlinux]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#linux-specific-eal-parameters

[rel2011]: https://doc.dpdk.org/guides/rel_notes/release_20_11.html
[api1911]: https://doc.dpdk.org/api-19.11/rte__launch_8h.html
[fonteeal]: https://github.com/DPDK/dpdk/blob/v25.11/lib/eal/linux/eal_timer.c
