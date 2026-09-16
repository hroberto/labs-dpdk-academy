# Módulo 03 — Performance e observabilidade

> **Nível 8** do [plano de estudo](../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [02 — Pipeline](../02-pipeline/)

Medir com rigor e enxergar o que está acontecendo dentro de um programa de plano
de dados — as duas coisas que separam "ficou mais rápido" de "sei por que ficou
mais rápido".

## Estado deste módulo

| Submódulo | Estado |
|---|---|
| [01 — Benchmarking](01-benchmarking/) | **escrito** — o custo da falta de rigor, medido |
| [02 — Observabilidade](02-observabilidade/) | **escrito** — telemetria exercitada contra processos vivos |

Os dois foram escritos sem depender de hardware que esta máquina não tem, o que
os torna reproduzíveis por qualquer leitor.

## Este módulo é peculiar: o projeto já usa o que ele ensina

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

O trabalho aqui foi transformar prática em conteúdo ensinável, e medir o que
ainda era suposição.

## O que os dois submódulos estabeleceram

**A ressalva metodológica cobra menos do que parece — e o que cobra é outra
coisa.** Doze execuções com a frequência de partida variando **9×** (0,61 a
5,62 GHz) produziram **4,6%** de amplitude no resultado. Já a **primeira
execução após ociosidade** mediu ~**30%** a mais, em três observações
independentes. Fixar o governor ajuda pouco; descartar a primeira execução ajuda
muito — o contrário do que a ressalva sugere.

**A telemetria está ligada por padrão**, apesar de a ajuda da EAL mostrar
`--telemetry` e `--no-telemetry` lado a lado como se uma ligasse e outra
desligasse. A que muda alguma coisa é `--no-telemetry`.

**O perfilador de CPU não vê o descarte na NIC.** Quando falta descritor, nenhuma
instrução do processo executa — não há pilha para amostrar. O contador
(`imissed`) é legível pela telemetria com o programa rodando.

## Compromissos já publicados

| Origem | O que foi adiado para cá | Estado |
|---|---|---|
| [Ferramental](../../docs/00-visao-geral/ferramental.md) | adoção de `google-benchmark` | **aberto** — declarado nas limitações do submódulo 01 |
| [02-mempool-ring §3](../01-fundamentos/02-mempool-ring/README.md) | medição rigorosa, com controle de frequência e aquecimento | **respondido de outro jeito** — o submódulo 01 mediu que o controle de frequência importa pouco aqui, e o aquecimento entre processos importa muito |
| [Fundamentos §7](../../docs/01-fundamentos/README.md) | tratamento formal de jitter | **aberto** |

A segunda linha merece nota: o compromisso era *fixar* frequência e aquecimento,
e o que se entregou foi a **medição de quanto cada um custa**. É menos do que se
prometeu em execução e mais do que se prometeu em entendimento — quem seguisse a
promessa ao pé da letra gastaria a tarde no controle que quase não muda o
resultado.

## Um bloco do nível 8 que ainda não tem dono

O plano mestre inclui, no nível 8, **segurança de memória em plano de dados** —
sanitizers, o que eles custam, e o que não pegam em código que faz aritmética de
ponteiro sobre memória compartilhada. Nenhum submódulo reivindica isso hoje.
Registrado aqui para não se perder; quando for escrito, decide-se se vira um
terceiro submódulo ou uma seção de `02-observabilidade`.

## O que ainda falta

- **`google-benchmark`**, prometido no ferramental e não adotado;
- **jitter tratado formalmente** — hoje há p99 publicado, não análise de cauda;
- **isolamento de núcleo medido**: esta máquina não tem `isolcpus`, e conferir o
  ganho exige reiniciar. "Isolar ajuda" continua sendo teoria no material;
- **`imissed` observado acontecendo**: o mecanismo está demonstrado com
  `net_null`, que não tem descritor de hardware — o valor exige a placa fora do
  kernel;
- **teste automatizado de telemetria**: seria L3, e não existe.

## Navegação

| | |
|---|---|
| **Anterior** | [02 — Pipeline](../02-pipeline/) |
| **Próximo** | [04 — Projeto final](../04-projeto-final/) |
| **Índice** | [Trilha](../README.md) · [Plano de estudo](../../docs/plano-estudo-dpdk.md) |
