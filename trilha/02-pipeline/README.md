# Módulo 02 — Pipeline e processamento em lote

> **Níveis 5 e 6** do [plano de estudo](../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [01 — Fundamentos práticos](../01-fundamentos/), em especial
> [02 — Mempool, ring e lote](../01-fundamentos/02-mempool-ring/)

> **Esqueleto.** Este arquivo ainda não é o módulo: ele registra escopo,
> pré-requisitos e compromissos já assumidos, para que quem escrever o conteúdo
> não colida com o que já existe nem repita o que já foi entregue.

## Objetivo

Organizar o tratamento de pacotes como um **caminho de dados com estágios**, e
tratar o que aparece quando os estágios têm velocidades diferentes: filas,
contrapressão e a escolha entre latência e vazão.

## Onde este módulo começa

O tópico [02-mempool-ring](../01-fundamentos/02-mempool-ring/) já entregou peças
que este módulo **não deve reapresentar**:

- o ciclo de vida do objeto (emprestar do pool, devolver ao pool);
- a curva do tamanho de lote, medida (ganho grande até 8, marginal até 32,
  regressão em 128);
- o custo de atravessar domínio de cache, medido (de 4,0 a 4,8 vezes);
- a demonstração de que **paralelizar pode piorar** quando o trabalho por pacote
  não paga o repasse.

O ponto de partida daqui é a frase que aquele tópico deixa em aberto: *"quando a
fila enche, o produtor recebe recusa em vez de bloquear — isso é backpressure
explícito"*. O que fazer com essa recusa é o assunto deste módulo.

## Compromissos já publicados

Estes links já existem em documentos escritos e apontam para cá. Quem escrever o
módulo precisa honrá-los:

| Origem | O que foi prometido |
|---|---|
| [02-mempool-ring §3](../01-fundamentos/02-mempool-ring/README.md) | tratamento de *backpressure* de verdade, além do laço de repetição |
| [02-mempool-ring §6](../01-fundamentos/02-mempool-ring/README.md) | o que fazer quando o produtor nunca dorme |
| [Alternativa C++23 §3](../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md) | a comparação honesta de desempenho, que só existe com NIC |

## Submódulos

| Submódulo | Nível | Assunto |
|---|---|---|
| [01 — RX/TX burst](01-rx-tx-burst/) | 6 | recepção e transmissão reais, descritores, mbuf |
| [02 — Batching e backpressure](02-batching-backpressure/) | 5 | profundidade de fila, recusa, latência contra vazão |

> **Sobre a numeração.** O submódulo 01 é do nível 6 e o 02 é do nível 5 — a
> ordem dos diretórios não segue a dos níveis, e isso é intencional: o
> backpressure só faz sentido depois de existir uma fonte real de pacotes, que é
> o que o RX/TX traz. Se a ordem for revista, revise também esta nota.

## Entregáveis

- pipeline executável com estágios separados e fila entre eles
- documentação com o framework do projeto: fundamento, mecanismo, trade-offs,
  implementação, validação, limitações
- testes L1 (lógica de estágio, sem EAL) e L2 (pipeline sob o runtime)
- alternativa em C++23 puro para o mesmo problema, com contrato verificado
- análise crítica: em que ponto um estágio a mais deixa de compensar

## Navegação

| | |
|---|---|
| **Anterior** | [01 — Fundamentos práticos](../01-fundamentos/) |
| **Próximo** | [03 — Performance e observabilidade](../03-performance/) |
| **Índice** | [Trilha](../README.md) · [Plano de estudo](../../docs/plano-estudo-dpdk.md) |
