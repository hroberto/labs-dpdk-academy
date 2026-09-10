# Trilha de aprendizagem

Esta trilha organiza o estudo do DPDK em módulos progressivos, alinhados ao plano mestre em [docs/plano-estudo-dpdk.md](../docs/plano-estudo-dpdk.md).

## Teoria e prática, e como uma chama a outra

O estudo tem duas metades, e elas vivem em lugares diferentes de propósito:

- **`docs/`** — a teoria: o problema, o mecanismo e os números que sustentam as
  decisões. Lê-se antes.
- **`trilha/`** (aqui) — a prática: código executável, testes e exercícios.
  Roda-se depois, e volta-se à teoria quando o resultado surpreender.

Um tópico da trilha sem o módulo de teoria correspondente vira receita; um módulo
de teoria sem o tópico vira leitura. A tabela abaixo liga os dois.

## Mapeamento com o plano mestre

| Nível | Teoria em `docs/` | Prática aqui | Estado |
|---|---|---|---|
| 1 — fundamentos de sistema | [01 — Fundamentos](../docs/01-fundamentos/README.md) | — | **escrito** |
| 2 — rede e plano de dados | [01 — Fundamentos](../docs/01-fundamentos/README.md) | — | **escrito** |
| 3 — [EAL][cEAL] e runtime | [02 — Runtime do DPDK](../docs/02-runtime-dpdk/README.md) | [01-eal-hello/](01-fundamentos/01-eal-hello/) | **escrito** |
| 4 — mempool, ring e mbuf | [03 — Mempool, ring e mbuf](../docs/03-mempool-ring-mbuf/README.md) | [02-mempool-ring/](01-fundamentos/02-mempool-ring/) | **escrito** |
| 5 — pipeline e design | — | [02-pipeline/](02-pipeline/) | esqueleto |
| 6 — RX/TX, burst e hardware | — | [02-pipeline/01-rx-tx-burst/](02-pipeline/01-rx-tx-burst/) | esqueleto |
| 7 — NUMA, cache e desempenho | [01 — Fundamentos §4 e §5](../docs/01-fundamentos/README.md#4-memória-onde-o-desempenho-realmente-se-decide) | a definir | teoria escrita; prática pendente |
| 8 — observabilidade e qualidade | — | [03-performance/](03-performance/) | esqueleto |
| 9 — virtualização, SR-IOV, [vhost-user][cVhost] | — | — | não iniciado |
| 10 — projeto final e alternativas ([AF_XDP][cAfxdp]) | — | [04-projeto-final/](04-projeto-final/) | esqueleto |

## Estrutura atual

| Diretório | Conteúdo | Estado |
|---|---|---|
| [01-fundamentos/](01-fundamentos/) | inicialização da EAL; mempool, ring e batching, com alternativa em C++23 | **dois tópicos completos**, com testes L1 e L2 |
| [02-pipeline/](02-pipeline/) | batching, backpressure, RX/TX | esqueleto |
| [03-performance/](03-performance/) | benchmarking e observabilidade | esqueleto |
| [04-projeto-final/](04-projeto-final/) | consolidação e comparação com as alternativas | esqueleto |

## O cenário que atravessa os módulos

Onde ajuda a fixar o conceito, os exemplos se apoiam num mesmo cenário: um
**servidor de *market data***, que recebe o *feed* de uma bolsa. Ele aparece nos
[fundamentos](../docs/01-fundamentos/README.md#62-o-barramento-também-tem-orçamento)
como o caso extremo de latência ultrabaixa, e no
[módulo de runtime](../docs/02-runtime-dpdk/README.md) como o sistema que
justifica separar processos.

É **embasamento, não camisa de força**. O objeto de estudo é o DPDK, e quando um
conceito pede outro exemplo, o outro exemplo é usado — os tópicos de
`01-fundamentos/`, por exemplo, trabalham com pacotes genéricos, e está certo
assim: o que eles ensinam não fica mais claro chamando o pacote de *tick*.

## Filosofia

A trilha combina:

- didática técnica
- estudo progressivo
- comparação com C++23 puro
- aplicação direta em exemplos executáveis
- foco em engenharia real e trade-offs

## Objetivo pedagógico

A cada módulo, o estudante deve ser capaz de:

- compreender o conceito dentro do plano geral
- entender o mecanismo interno do DPDK
- reconhecer limitações e trade-offs
- implementar ou adaptar um exemplo
- documentar as conclusões técnicas

## Estado do material

Os níveis 1 a 4 têm conteúdo real, dos dois lados: teoria em `docs/`, prática em
`trilha/`, com código, testes e medições reproduzíveis. Do nível 5 em diante, os diretórios existem com esqueletos que
registram escopo e pré-requisitos, para que o trabalho futuro não colida com o
que já foi escrito. A tabela de estado acima é mantida junto com o material — se
divergir do que existe em disco, o disco é que está certo, e a tabela precisa de
correção.

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cVhost]: https://doc.dpdk.org/guides/nics/vhost.html
[cAfxdp]: https://doc.dpdk.org/guides/nics/af_xdp.html
