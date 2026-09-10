# Módulo 03 — Performance e observabilidade

> **Nível 8** do [plano de estudo](../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [02 — Pipeline](../02-pipeline/)

> **Esqueleto.** Registra escopo e compromissos; o conteúdo ainda não foi
> escrito.

## Objetivo

Medir com rigor e enxergar o que está acontecendo dentro de um programa de plano
de dados — as duas coisas que separam "ficou mais rápido" de "sei por que ficou
mais rápido".

## O que o projeto já pratica, e este módulo precisa formalizar

Este módulo é peculiar: **o projeto já usa boa parte do que ele vai ensinar.**
Todas as medições de [`docs/01-fundamentos/medicoes/`](../../docs/01-fundamentos/medicoes/)
e [`docs/02-runtime-dpdk/medicoes/`](../../docs/02-runtime-dpdk/medicoes/) seguem
uma metodologia comum, implementada em `statistics.h`:

- mediana e intervalo interquartil em vez de média, porque
  [média mente](../../docs/01-fundamentos/README.md#7-métricas-o-vocabulário-para-não-se-enganar)
  na presença de cauda;
- dispersão robusta como selo de confiança, em vez de coeficiente de variação;
- percentis para latência, com p99 publicado;
- **declaração da resolução do instrumento** junto do resultado — o módulo de
  runtime mede o próprio período de sondagem para não exibir precisão que não
  tem.

O trabalho aqui é transformar prática em conteúdo ensinável, e cobrir o que ainda
falta.

## Compromissos já publicados

| Origem | O que foi adiado para cá |
|---|---|
| [Ferramental](../../docs/00-visao-geral/ferramental.md) | adoção de `google-benchmark` |
| [02-mempool-ring §3](../01-fundamentos/02-mempool-ring/README.md) | medição rigorosa, com controle de frequência e aquecimento |
| [Fundamentos §7](../../docs/01-fundamentos/README.md) | tratamento formal de jitter |

## Escopo

| Submódulo | Assunto |
|---|---|
| [01 — Benchmarking](01-benchmarking/) | medir sem se enganar: metodologia, repetição, ambiente controlado |
| [02 — Observabilidade](02-observabilidade/) | enxergar o programa rodando: contadores, telemetria, perfis |

## Um bloco do nível 8 que ainda não tem dono

O plano mestre inclui, no nível 8, **segurança de memória em plano de dados** —
sanitizers, o que eles custam, e o que não pegam em código que faz aritmética de
ponteiro sobre memória compartilhada. Nenhum submódulo reivindica isso hoje.
Registrado aqui para não se perder; quando for escrito, decide-se se vira um
terceiro submódulo ou uma seção de `02-observabilidade`.

## Navegação

| | |
|---|---|
| **Anterior** | [02 — Pipeline](../02-pipeline/) |
| **Próximo** | [04 — Projeto final](../04-projeto-final/) |
| **Índice** | [Trilha](../README.md) · [Plano de estudo](../../docs/plano-estudo-dpdk.md) |
