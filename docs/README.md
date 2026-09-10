# Documentação do projeto

Este diretório centraliza a base didática e a documentação técnica do projeto DPDK Academy.

## Objetivo

Fornecer uma trilha de estudo estruturada para quem deseja aprender DPDK de forma prática e profunda, com:

- fundamentos teóricos do sistema e da rede
- entendimento do mecanismo interno do DPDK
- exemplos em C e C++23
- comparação com implementações puras em C++23
- foco em arquitetura, desempenho e engenharia de software

## Seções

| Seção | Nível do plano | Estado |
|---|---|---|
| [00 — Visão geral](00-visao-geral/) | — | **escrito**: [posicionamento, pré-requisitos, método e ambiente de medição](00-visao-geral/README.md), mais o [ferramental](00-visao-geral/ferramental.md) |
| [01 — Fundamentos](01-fundamentos/) | 1 e 2 | **escrito**, com [medições reproduzíveis](01-fundamentos/medicoes/) e [confronto com a literatura](01-fundamentos/README.md#10-confronto-com-a-literatura) |
| [02 — Runtime do DPDK](02-runtime-dpdk/) | 3 | **escrito**, com [medições do runtime](02-runtime-dpdk/medicoes/) e exemplo [primário/secundário](02-runtime-dpdk/README.md#4-processos-primário-e-secundário) de *market data* |
| [03 — Mempool, ring e mbuf](03-mempool-ring-mbuf/) | 4 | **escrito**, com [medições](03-mempool-ring-mbuf/medicoes/) de alocação, anel e [anatomia do mbuf](03-mempool-ring-mbuf/README.md#2-o-mbuf-quatro-números-que-parecem-redundantes) |
| [Plano de estudo](plano-estudo-dpdk.md) | todos | mapa mestre dos **10** níveis |

A teoria vive aqui em `docs/`; a prática executável vive em
[`trilha/`](../trilha/README.md), onde cada tópico reúne documento, código e
testes no mesmo diretório.

## Níveis de ensino

A lista canônica é a do [plano de estudo](plano-estudo-dpdk.md); esta é um resumo
para orientação rápida, e precisa concordar com ele.

1. Fundamentos de sistema — Linux, memória, cache, NUMA, execução
2. Fundamentos de rede e plano de dados
3. [EAL][cEAL] e ambiente do runtime
4. Mempool, mbuf, ring e ciclo de dados
5. Pipeline de processamento e design de software
6. RX/TX, I/O e projeto consciente do hardware
7. NUMA, cache e desempenho real
8. Observabilidade e qualidade
9. Virtualização e o caminho até a nuvem
10. Projeto final e as alternativas ao DPDK

## Alinhamento com a trilha

A estrutura dos módulos em [../trilha](../trilha) foi pensada para refletir exatamente os níveis descritos no plano mestre em [plano-estudo-dpdk.md](plano-estudo-dpdk.md). A intenção é manter a progressão didática coerente e evitar contradições entre documentação e módulos.

## Filosofia didática

A documentação prioriza:

- conceito antes da API
- mecanismo antes da otimização
- prática antes de performance "mágica"
- arquitetura e trade-offs antes de exemplos simplistas
- fontes confiáveis, exemplos executáveis e análise crítica

## Público-alvo

- iniciantes em DPDK
- profissionais de software e sistemas
- desenvolvedores em C/C++
- pessoas que querem aprender alto desempenho, arquitetura e plano de dados

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
