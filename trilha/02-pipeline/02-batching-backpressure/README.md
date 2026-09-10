# Submódulo 02 — Batching e contrapressão

> **Nível 5** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [01 — RX/TX em lote](../01-rx-tx-burst/)

> **Esqueleto.** Registra escopo e compromissos; o conteúdo ainda não foi
> escrito.

## Objetivo

Responder à pergunta que o tópico de mempool deixa em aberto: **o que fazer
quando a fila enche.**

## O que já foi entregue, e não deve ser refeito

O dimensionamento de lote **já tem resposta medida** em
[02-mempool-ring §3](../../01-fundamentos/02-mempool-ring/README.md): ganho
grande até 8, marginal até 32, regressão em 128, e o efeito muda de escala quando
o lote atravessa domínio de cache. Repetir esse experimento aqui seria trabalho
duplicado.

O que **falta** é o outro lado: o lote é escolhido pelo programa, mas a chegada
não é. Quando o produtor é a rede, ele não aceita recusa — o pacote não some
porque a fila encheu, ele some porque ninguém o leu a tempo.

## Escopo

- profundidade de fila: o que se ganha e o que se perde ao aumentá-la
- as três respostas possíveis à fila cheia — descartar, bloquear, empurrar para
  trás — e quando cada uma é correta
- descarte com critério: qual pacote descartar quando é preciso descartar algum
- a diferença entre contrapressão **dentro** do processo e contrapressão que
  chega até a NIC
- latência contra vazão: por que aumentar a fila melhora um e piora o outro

## Um contraste que vale a pena

O tópico de mempool conta "tentativas com fila cheia" e repete. Num sistema onde
o produtor é uma bolsa transmitindo por multicast, essa opção não existe: o
datagrama que não foi lido está perdido, e o que se detecta depois é um **salto
no número de sequência** — o mecanismo que o
[módulo de runtime](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário)
já implementa e testa.

Vale registrar a distinção porque ela costuma se confundir:

| | Fila cheia no ring interno | Perda no transporte |
|---|---|---|
| Quem sofre | o produtor, que recebe recusa | o consumidor, que nunca vê o dado |
| Detecção | retorno da função de enfileiramento | descontinuidade de sequência |
| Resposta | tentar de novo, descartar, ou empurrar para trás | pedir retransmissão, ou seguir com o livro incompleto |

## Entregáveis

- experimento que satura o consumidor de propósito e mede o comportamento sob
  fila cheia, com as três políticas
- documentação de trade-offs no framework do projeto
- L1 sobre a política de descarte; L2 sobre o pipeline saturado
- comparação com a abordagem em C++23 puro

## Navegação

| | |
|---|---|
| **Anterior** | [01 — RX/TX em lote](../01-rx-tx-burst/) |
| **Próximo** | [03 — Performance e observabilidade](../../03-performance/) |
| **Módulo** | [02 — Pipeline](../README.md) |
