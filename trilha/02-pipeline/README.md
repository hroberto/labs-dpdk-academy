# Módulo 02 — Pipeline e processamento em lote

*Read this in [English](README.en.md).*

> **Níveis 5 e 6** do [plano de estudo](../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [01 — Fundamentos práticos](../01-fundamentos/), em especial
> [02 — Mempool, ring e lote](../01-fundamentos/02-mempool-ring/)

Organizar o tratamento de pacotes como um **caminho de dados com estágios**, e
tratar o que aparece quando os estágios têm velocidades diferentes: filas,
contrapressão e a escolha entre latência e vazão.

## Estado deste módulo

**Metade entregue, e a metade que falta depende de hardware.**

| Submódulo | Nível | Estado |
|---|---|---|
| [01 — RX/TX burst](01-rx-tx-burst/) | 6 | escopo e ambiente medidos; **espera a placa sair do kernel** |
| [02 — Batching e contrapressão](02-batching-backpressure/) | 5 | **escrito**, com a superfície profundidade × lote medida |

O submódulo 01 não é esqueleto — tem as capacidades da NIC de referência
medidas com ferramenta real — e não é conteúdo acabado. O que o trava é uma
linha: `enp8s0` tem `IFF_UP` ligado, e a trava de captura recusa. Um
`sudo ip link set enp8s0 down` destrava, e a decisão é de quem opera a máquina.

> **Sobre a numeração.** O submódulo 01 é do nível 6 e o 02 é do nível 5 — a
> ordem dos diretórios não segue a dos níveis, e isso é intencional: a
> contrapressão só faz sentido depois de existir uma fonte real de pacotes, que é
> o que o RX/TX traz. A ironia é que o 02 ficou pronto primeiro, porque não
> precisa da placa. Se a ordem for revista, revise também esta nota.

## Onde este módulo começa

O tópico [02-mempool-ring](../01-fundamentos/02-mempool-ring/) já entregou peças
que este módulo **não deve reapresentar**:

- o ciclo de vida do objeto (emprestar do pool, devolver ao pool);
- a curva do tamanho de lote, medida — e ela **depende do modo**: com um lcore o
  ganho é grande até 8, marginal até 32 e **regride** em 128; com dois lcores no
  mesmo bloco de cache **não regride**, e 128 e 256 são os melhores pontos. O
  lote é o antídoto para o custo de travessia, e sem travessia esse benefício
  não existe;
- o custo de atravessar domínio de cache, medido (de 4,0 a 4,8 vezes);
- a demonstração de que **paralelizar pode piorar** quando o trabalho por pacote
  não paga o repasse.

> Este parágrafo já publicou a curva sem o qualificador — *"regressão em 128"*,
> como se valesse sempre. A fonte sempre separou os dois modos; foi a compressão
> para índice que perdeu a distinção, e o submódulo 02, medindo com dois lcores,
> encontrou o lote 128 como melhor ponto. Um índice que resume uma medição pode
> criar uma falsidade que o documento de origem não tem.

O ponto de partida daqui é a frase que aquele tópico deixa em aberto: *"quando a
fila enche, o produtor recebe recusa em vez de bloquear — isso é backpressure
explícito"*. O que fazer com essa recusa é o assunto do submódulo 02.

## O que o submódulo 02 estabeleceu

**Contrapressão não é decidida pela fila.** O anel tem capacidade
`profundidade − 1`, e o pool tem 4095 objetos. Quando a capacidade alcança o
pool, o anel passa a caber tudo o que existe e não tem mais como encher:

| Capacidade | vs. pool | Houve recusa? |
|---|---|---|
| 1 023 | menor | **sim**, em todas as execuções |
| 2 047 | menor | **sim**, em todas as execuções |
| **4 095** | **igual** | **não — zero, sempre** |

A fronteira cai exatamente onde a aritmética manda. É a **razão** entre pool e
fila que governa, e não a profundidade sozinha — com pool maior, a mesma
profundidade volta a recusar.

**O lote pesa mais que a profundidade.** Na profundidade 256, ir de lote 8 para
128 leva de **8,4 para 4,4 ns** (mediana de 7 execuções, faixas sem sobreposição);
aprofundar no mesmo lote move muito menos, e as faixas se tocam.

> A contagem de recusas **não** entra aqui, e a razão está na retratação do
> submódulo: oito execuções da mesma configuração deram de 118 626 a 286 625 --
> 128% de amplitude. Ela responde **se houve** contrapressão, não **quanta**.
> <!-- retratado: referencia -->
> <!-- Este bloco não retrata nada: ele CITA a retratação do submódulo. Os dois
>      números são contagens de objetos recusados. -->

## Compromissos já publicados

Estes links existem em documentos escritos e apontam para cá:

| Origem | O que foi prometido | Estado |
|---|---|---|
| [02-mempool-ring §3](../01-fundamentos/02-mempool-ring/README.md) | tratamento de *backpressure* de verdade, além do laço de repetição | **parcial** — das três políticas, só o descarte foi medido |
| [02-mempool-ring §6](../01-fundamentos/02-mempool-ring/README.md) | o que fazer quando o produtor nunca dorme | **atendido** — `pipeline_ring.c -t` encerra por prazo de progresso e declara o que descartou |
| [Alternativa C++23 §3](../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md) | a comparação honesta de desempenho, que só existe com NIC | **aberto** — depende do submódulo 01 |

## O que ainda falta

- **bloquear e empurrar para trás**: descritas no submódulo 02, sem experimento;
- **descarte com critério** — qual pacote sacrificar — exige metadado que
  `struct packet` não carrega;
- **contrapressão que chega até a NIC**, que é submódulo 01;
- **alternativa em C++23 puro** para o mesmo problema de contrapressão;
- **análise de quando um estágio a mais deixa de compensar** — os fundamentos já
  têm a medição ("paralelizar pode piorar"); falta a generalização para pipeline
  de N estágios.

## Navegação

| | |
|---|---|
| **Anterior** | [01 — Fundamentos práticos](../01-fundamentos/) |
| **Próximo** | [03 — Performance e observabilidade](../03-performance/) |
| **Índice** | [Trilha](../README.md) · [Plano de estudo](../../docs/plano-estudo-dpdk.md) |
