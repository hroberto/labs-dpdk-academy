# DPDK Academy

Guia de estudo para DPDK com base em engenharia de software, arquitetura de sistemas, C++23 e ensino técnico aprofundado.

*Read this in [English](README.en.md).*

## Objetivo

Este repositório foi pensado para servir como base didática para profissionais iniciantes e avançados que desejam aprender DPDK de forma estruturada, profunda e aplicada.

Ele combina:

- fundamentos teóricos do DPDK e do plano de dados
- arquitetura de software e runtime de alto desempenho
- exercícios práticos em C e C++23
- comparação com implementações puras em C++23
- abordagem crítica de trade-offs e performance
- documentação como fonte de conhecimento técnico

## O que este projeto cobre

- introdução ao DPDK e ao papel do plano de dados
- princípios de alto desempenho e arquitetura de software
- fundamentos do Linux, memória, cache, NUMA e CPU affinity
- [EAL][cEAL], mbuf, mempool, ring e lifecycles de pacotes
- RX/TX, burst, batch processing e polling
- comparação entre DPDK e software puro em C++23
- benchmarking, observabilidade, qualidade e engenharia real

## Estrutura do repositório

- `docs/` — documentação didática e estrutura de estudo
- `trilha/` — módulos organizados por nível de profundidade
- `scripts/` — automação de build e testes
- `subprojects/` — dependências de teste fixadas por hash (arquivos `.wrap`)
- `ROADMAP.md` — visão geral do plano evolutivo do projeto
- `LICENSE` — licença do conteúdo do projeto

Cada tópico da trilha é **autocontido**: documento, código, testes e, quando
existir, a alternativa sem DPDK para o mesmo problema, em `alternativas/` dentro
do próprio tópico. Exemplo:

```
trilha/01-fundamentos/02-mempool-ring/
├── README.md              teoria, mecanismo, trade-offs, exercícios
├── packet.c / packet.h    lógica pura (testável sem DPDK)
├── pipeline_ring.c        runtime: EAL, mempool, ring
├── tests/                 L1 (GoogleTest) e L2 (integração)
└── alternativas/cpp23/    mesmo problema sem DPDK, mesmo contrato
```

## Filosofia de aprendizagem

Este projeto não trata o DPDK como uma ferramenta isolada. Ele busca ensinar:

- teoria e arquitetura antes da API
- mecanismo antes da otimização
- prática executável antes de performance fantasiosa
- design de software antes de micro-otimizações sem contexto
- documentação clara e rigorosa como parte da engenharia
- números medidos e confrontados com a literatura da área, nunca afirmados

## Trilhas de estudo

A trilha principal está em:

- `docs/plano-estudo-dpdk.md`
- `trilha/README.md`
- `ROADMAP.md`

A progressão sugerida é:

1. Fundamentos de sistema e rede
2. Runtime e EAL do DPDK
3. Mempool, ring e mbuf
4. Pipeline de dados e batching
5. NUMA, cache e CPU affinity
6. Benchmarks e observabilidade
7. Projeto final e comparação com C++23 puro

## O que se pressupõe de você

A trilha vai de iniciante a avançado **em DPDK** — não em programação de
sistemas. Espera-se familiaridade com C, Linux, threads, ponteiros e noções de
rede; **não** se espera conhecer NUMA, TLB, hugepages, coerência de cache, IOMMU
ou qualquer coisa do DPDK, que o material ensina do zero.

A lista completa, com o que é ensinado e o que não é, está em
[docs/00-visao-geral](docs/00-visao-geral/README.md#2-o-que-se-pressupõe-do-leitor).

## Requisitos de ferramenta

- Linux x86_64 ou arm64
- GCC 14+ ou Clang 18+ (C11 e C++23; as declarações POSIX vêm de `_GNU_SOURCE`,
  declarado por arquivo — ver [ferramental §2.2](docs/00-visao-geral/ferramental.md))
- **DPDK 23.11 ou mais novo**, com `pkg-config --modversion libdpdk` funcionando
  (Debian/Ubuntu: `dpdk-dev`; Fedora/RHEL: `dpdk-devel`)

  | Release | Estado |
  |---|---|
  | 25.11 | máquina de referência — todos os números publicados vêm dela |
  | 23.11 | CI (Ubuntu 24.04); suíte passa |
  | < 23.11 | não testado; o `meson setup` recusa |

  A faixa não é decorativa: a diferença entre 23.11 e 25.11 já produziu dois
  defeitos que só aparecem em uma das duas — `--in-memory --no-huge` juntos, e
  o código de saída de argumento desconhecido. Ambos estão documentados no
  [tópico 01](trilha/01-fundamentos/01-eal-hello/README.md).
- Meson 1.1+ e Ninja

Opcionais, e só a partir da etapa de benchmarking e qualidade: clang-format,
clang-tidy, sanitizers e perf. Nada da trilha atual depende deles — compilar,
rodar e testar os tópicos 1 a 4 exige apenas a lista acima.

O GoogleTest, usado nos testes L1, é baixado automaticamente pelo Meson e não
precisa ser instalado. Rode `./scripts/check-env.sh` para diagnosticar o
ambiente. As decisões de ferramental estão explicadas em
[docs/00-visao-geral/ferramental.md](docs/00-visao-geral/ferramental.md).

## Uso rápido

```bash
./scripts/check-env.sh      # o que está instalado e o que falta
./scripts/ambiente.sh       # registro do hardware onde os números foram medidos
./scripts/build-all.sh      # configura e compila tudo
./scripts/test-all.sh       # suíte completa
./scripts/test-all.sh l1    # só lógica pura (rápido, sem EAL)
./scripts/test-all.sh l2    # só integração com o runtime
```

## Fluxo recomendado

### 1. Estudo teórico

Comece pela documentação em `docs/` e `trilha/`.

### 2. Prática modular

Cada módulo deve ser executado, entendido e documentado.

### 3. Comparação com C++23 puro

A alternativa em C++23 puro deve ser usada para entender custos, abstrações e arquitetura.

### 4. Benchmark e análise crítica

O objetivo não é só "rodar", mas entender por que a arquitetura funciona e quando a escolha é correta.

## Objetivo final

O projeto busca formar uma base técnica sólida para quem quer:

- aprender DPDK de forma consistente
- compreender software de alto desempenho
- trabalhar com arquitetura de dados e plano de dados (*data plane*)
- comparar DPDK com C++23 puro de forma crítica e didática
- construir documentação profissional e material de estudo real

## Contribuição

Sugestões de módulos, estudos, exemplos e melhorias na didática são bem-vindas.

## Segurança

Como relatar problema, e o que conta como problema neste contexto:
[SECURITY.md](SECURITY.md). Resumo: o ativo a proteger é a **procedência do
conteúdo**, não sigilo — não há segredo aqui. Todo commit é assinado, e a
`main` exige assinatura verificada.

## Licença

Conteúdo publicado para fins educacionais e de estudo.

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
