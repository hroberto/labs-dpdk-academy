# Plano de estudo: DPDK para iniciantes e avançados

## Objetivo

Este plano foi pensado para construir uma base sólida em DPDK, com foco em:

- aprendizado incremental
- profundidade técnica
- prática com código executável
- conexão com C++23 e engenharia de software
- visão crítica de arquitetura, latência, throughput e custo operacional

## Filosofia

O DPDK não deve ser visto apenas como uma biblioteca de rede. Ele é um conjunto de mecanismos para:

- controlar memória de forma previsível
- reduzir overhead do kernel
- explorar hardware e NUMA de forma consciente
- dimensionar pipelines de pacotes e processamento de dados

O estudo deve caminhar em três dimensões simultâneas:

1. teoria e arquitetura
2. mecanismo e API do DPDK
3. prática com benchmark, medição e projeto

## Estrutura do plano

### Nível 1 — Fundamentos de sistema

Objetivo: preparar o terreno para entender DPDK.

Temas:
- Linux, user-space vs kernel-space
- memória virtual e física
- cache, NUMA, memória contígua
- processos, threads, CPU affinity
- I/O, polling e interrupções
- noções de packet processing

Entregáveis:
- leitura de arquitetura de memória e CPU
- resumo de diferenças entre kernel e user-space networking
- análise de trade-offs de polling x interrupção

### Nível 2 — Fundamentos de rede e dados de plano de dados

Objetivo: entender o problema que o DPDK resolve.

Temas:
- redes de alta taxa e pacotes
- throughput, taxa de perda, latência, jitter
- NIC, DMA, ring buffers, queues
- packet lifecycle: RX, parse, decision, TX
- overhead de syscall, contexto de kernel e custo operacional

Entregáveis:
- diagrama de pipeline de rede
- comparação entre stack tradicional e arquitetura de dados de alto desempenho

### Nível 3 — EAL e ambiente do runtime

Objetivo: dominar a base de execução do DPDK.

[EAL][cEAL] significa Environment Abstraction Layer, ou camada de abstração do ambiente. É a camada que prepara o processo para rodar em user-space com controle direto sobre memória, threads, I/O e recursos do sistema. A EAL abstrai detalhes do host e permite que o DPDK configure CPU, memória, NUMA, [hugepages][cHuge] e drivers sem depender do modelo tradicional do kernel.

Temas:
- [`rte_eal_init()`][apiealinit]
- argumentos da EAL
- hugepages
- lcores (*logical cores*): threads criadas pela EAL e fixadas a CPUs lógicas
- contagem e seleção de lcores
- sockets e NUMA
- inicialização e cleanup
- uso de `--in-memory` em ambiente controlado

Entregáveis:
- programa mínimo funcionando
- leitura de logs e comportamento do runtime
- análise de ambiente e requisitos de host
- compreensão do papel da EAL no início da execução do programa DPDK

### Nível 4 — Mempool, mbuf, ring e ciclo de dados

Objetivo: entender os blocos fundamentais do modelo de dados do DPDK.

Temas:
- [`rte_mempool`][guiamempool]
- [`rte_ring`][guiaring]
- [`rte_mbuf`][guiambuf]
- lifetimes e ownership
- allocation-free hot paths
- lote e burst processing
- devolução de objetos ao pool

Entregáveis:
- exemplo de producer/consumer com ring
- exemplo de pool de objetos e ciclo completo de uso
- comparação com C++23 puro em pipeline em memória

### Nível 5 — Pipeline de processamento e design de software

Objetivo: projetar software de dados com disciplina arquitetural.

Temas:
- software modular
- separação de responsabilidades
- lógica de processamento e I/O
- backpressure e filas
- sincronização e concorrência
- design por batch
- hot path vs control path

Entregáveis:
- pipeline de pacotes com etapas bem definidas
- análise de bottlenecks
- desenho de arquitetura de módulos

### Nível 6 — RX/TX, I/O e hardware-aware design

Objetivo: avançar para a camada de I/O do DPDK e entender as decisões de hardware.

Temas:
- RX/TX burst
- interfaces de rede
- enqueue/dequeue em lote
- NIC, queues e drivers
- uso de descriptors e memory locality
- trade-offs entre batching, latência e throughput

Temas de **descarregamento para a NIC** (*offload*) — o trabalho que não chega
a custar ciclo de CPU porque a placa já o fez:
- RSS (*Receive Side Scaling*): múltiplas filas de hardware alimentadas por
  hash de 5-tupla, uma por lcore, sem coordenação em software
- descarregamento de soma de verificação (RX e TX)
- TSO (*TCP Segmentation Offload*) e LRO (*Large Receive Offload*)
- [`rte_flow`][guiaflow]: programar regras de classificação, filtragem, espelhamento e
  redirecionamento no comutador da própria NIC, antes de o pacote chegar à CPU
- capacidades por dispositivo: [`rte_eth_dev_info_get()`][apidevinfo] e a negociação de quais
  offloads estão disponíveis

Entregáveis:
- arquitetura de um forwarder simples
- benchmark comparativo com variantes de batch
- levantamento das offloads suportadas pela NIC disponível, com o que muda no
  código quando cada uma é ativada

> **Restrição do ambiente de referência.** A NIC desta máquina (Realtek RTL8125)
> suporta *checksum offload* e TSO, mas reporta `large-receive-offload: off
> [fixed]` e `receive-hashing: off [fixed]` — ou seja, **não faz LRO nem RSS**.
> RSS e `rte_flow` podem ser estudados e codificados aqui, mas não medidos: para
> isso é preciso NIC de servidor (Intel E810/X710, NVIDIA ConnectX). Verifique a
> sua com `ethtool -k <iface>`.

### Nível 7 — NUMA, cache e desempenho real

Objetivo: aprender a pensar em performance de forma correta.

Temas:
- NUMA awareness
- localidade de memória
- cache line e **falso compartilhamento** (o defeito mais comum do modelo por
  lcore) — ver [01-fundamentos §4.2.1](01-fundamentos/README.md)
- contention
- CPU affinity e contenção entre fluxos SMT do mesmo núcleo
- prefetch e uso de contíguos
- efeito de estratificação de dados na CPU

Temas do **barramento**, que fica fora da conta quando se olha só CPU e memória
— já cobertos em [01-fundamentos §6.2](01-fundamentos/README.md):
- vazão do PCIe por geração e largura, e o teto que ela impõe antes de qualquer
  software
- sobrecarga de TLP (*Transaction Layer Packet*) para quadros pequenos
- ajuste de *Max Payload Size*, *Max Read Request Size* e *Relaxed Ordering*
- IOTLB: a falta de tradução do lado do dispositivo, e por que hugepages
  beneficiam também a NIC

Entregáveis:
- análise de perf de pipeline
- documentação de observações de memória e CPU
- comparação entre múltiplas estratégias de processamento

### Nível 8 — Observabilidade e qualidade

Objetivo: ir além do código funcional.

Temas:
- `perf`, `VTune`, `gprof`
- sanitizers
- `clang-tidy` e `clang-format`
- testes de unidade e integração
- benchmark automation
- qualidade e manutenção em software de alto desempenho

Temas de **segurança de memória em espaço de usuário**, consequência direta de
abrir mão do isolamento do kernel:
- o que se perde: em user-space, um estouro de leitura ao interpretar um
  cabeçalho corrompe a memória do processo **inteiro** — inclusive o mempool e
  o estado de outros lcores. Não há barreira entre o parser e o resto
- o ponto cego das ferramentas: o AddressSanitizer intercepta o alocador do
  sistema, mas objetos de `rte_mempool` vivem em hugepages geridas pela EAL e
  ficam fora do seu alcance (ver [ferramental §5](00-visao-geral/ferramental.md))
- validação de pacote malformado no caminho quente: verificar comprimento antes
  de indexar, nunca confiar em campo de tamanho vindo da rede, e fazê-lo dentro
  do orçamento de ciclos
- defesa em profundidade quando o sanitizer não alcança: `rte_mempool` com
  *cookies* de depuração (`RTE_LIBRTE_MEMPOOL_DEBUG`), páginas-guarda e
  auditoria dos pontos de parsing

Entregáveis:
- roteiro de coleta de perf
- checklist de qualidade para código DPDK
- instruções para benchmark reprodutível
- rotina de parsing defensivo com custo medido, comparada à versão ingênua

### Nível 9 — Virtualização e o caminho até a nuvem

Objetivo: sair do metal puro, que é onde aplicações DPDK raramente rodam em
produção.

Temas:
- SR-IOV: dividir uma NIC física em *Virtual Functions* entregues diretamente a
  máquinas virtuais ou contêineres, cada uma com suas filas
- `virtio-net` e `vhost-user`: o caminho de alta velocidade entre convidado e
  hospedeiro, sem passar pela emulação
- Open vSwitch com DPDK como comutador de plano de dados
- o que muda em contêiner: hugepages compartilhadas, `--socket-mem`, permissões
  de `/dev/vfio`, e por que privilégios costumam ser exigidos
- memif e PMDs virtuais para compor topologias sem hardware dedicado

Entregáveis:
- laboratório com dois processos DPDK conversando por `virtio`/`vhost-user`
- análise do custo adicional de cada camada de virtualização

> Praticável na máquina de referência: os PMDs `virtio`, `vhost`, `memif` e
> `net_tap` estão presentes na instalação. SR-IOV exige NIC com suporte a VF.

### Nível 10 — Projeto final e as alternativas ao DPDK

Objetivo: consolidar o conhecimento e situar o DPDK entre as opções reais.

A comparação com **C++23 puro** (pilha do kernel via sockets) mostra o custo das
abstrações do sistema operacional. Mas a comparação que a indústria realmente
faz hoje é outra: **DPDK contra [AF_XDP][cAfxdp]**.

O AF_XDP contorna a pilha de rede **mantendo o driver do kernel**. Não exige [PMD][cPMD]
em espaço de usuário, não retira a NIC do sistema operacional, preserva o modelo
de segurança — e entrega uma fração significativa do desempenho. É o meio-termo
que não existia quando o DPDK foi criado, e ignorá-lo torna a análise datada.

Temas:
- pipeline completo em DPDK
- pipeline equivalente em C++23 puro sobre sockets — o custo do caminho do kernel
- pipeline equivalente em **AF_XDP** — kernel bypass sem abrir mão do kernel
- eixos de comparação: vazão, latência, custo de desenvolvimento, operação,
  segurança e o que cada abordagem exige do ambiente
- o PMD `net_af_xdp` do próprio DPDK, que permite usar AF_XDP por baixo da API
  do DPDK — e o que isso revela sobre onde está o custo

Entregáveis:
- projeto executável com documentação
- benchmark das três abordagens, com metodologia declarada
- análise arquitetural: quando cada uma é a escolha correta, e por quê

#### Como o AF_XDP funciona

Vale ter o mecanismo claro antes de comparar, porque a diferença com o DPDK está
justamente nele. O AF_XDP é uma família de sockets do Linux, introduzida no
kernel 4.18, que entrega pacotes a espaço de usuário **sem desvincular a NIC do
sistema operacional**. Em vez de contornar o kernel, ele abre um caminho rápido
*dentro* dele.

**1. O gatilho, no driver.** Ao receber um pacote, o kernel executa um programa
eBPF no ponto mais baixo do driver — antes de alocar `sk_buff`, antes da pilha.
Se o programa devolve `XDP_REDIRECT`, o pacote desvia direto para um socket
`AF_XDP`.

**2. UMEM: memória compartilhada.** Aplicação e kernel compartilham uma região
pré-alocada, a **UMEM**. É ela que permite dispensar a cópia entre kernel e
usuário — o mesmo princípio dos mbufs em hugepages do DPDK, com outra
implementação.

**3. Quatro filas sem trava**, que trocam descritores em vez de dados:

```mermaid
sequenceDiagram
    autonumber
    participant A as aplicação
    participant K as kernel

    Note over A,K: UMEM — região compartilhada; as filas trocam DESCRITORES, não dados

    A->>K: Fill Ring — buffers vazios da UMEM
    K-->>A: RX Ring — pacotes recebidos
    A->>K: TX Ring — pacotes a transmitir
    K-->>A: Completion Ring — buffers liberados
```

**As quatro filas trocam descritores, não pacotes.** O dado permanece na UMEM o
tempo todo; o que atravessa a fronteira é o índice de quem o possui agora — que é
exatamente o que dispensa a cópia.

A simetria com `rte_ring` não é coincidência: é o mesmo padrão produtor/consumidor
sem trava do [Nível 4](#nível-4--mempool-mbuf-ring-e-ciclo-de-dados), aqui
atravessando a fronteira usuário/kernel em vez de núcleos.

#### DPDK e AF_XDP lado a lado

| Critério | DPDK | AF_XDP |
|---|---|---|
| Relação com o kernel | ignora completamente | caminho rápido dentro dele |
| Driver | PMD exclusivo em user-space | driver padrão do Linux |
| A NIC no sistema | some (`vfio-pci`) | continua visível e administrável |
| Tráfego não crítico | a aplicação trata **tudo** | eBPF filtra; o resto segue para a pilha nativa |
| Ferramental | perde `tcpdump`, `iproute2` no caminho de dados | `ip`/`ethtool` continuam; ver ressalva |
| Curva de aprendizado | alta: hugepages, NUMA, binding | média: API de sockets |
| Teto de desempenho | maior | menor, mas próximo com zero-copy |

Duas ressalvas que a tabela sozinha esconde:

**Zero-copy depende do driver.** Sem suporte nativo, o AF_XDP cai em *copy mode*
e em XDP genérico, que roda o eBPF já depois da alocação de `sk_buff` — perdendo
a maior parte do ganho. Verificável no módulo do driver:

```bash
./scripts/xdp-zerocopy.sh              # o driver da interface padrão
./scripts/xdp-zerocopy.sh i40e ice     # drivers nomeados, para comparar
```

O script existe porque a forma direta erra em silêncio: módulos do kernel vêm
comprimidos, o `nm` recusa o arquivo e o `grep -c` devolve `0` — a mesma resposta
que daria um driver realmente sem suporte.

**O `tcpdump` não vê o que foi redirecionado.** A interface continua
administrável, e o tráfego *não* redirecionado segue normalmente pela pilha —
mas o pacote que o eBPF desviou nunca chega ao ponto onde o `tcpdump` escuta. A
vantagem real é coexistência de tráfego, não observabilidade total.

> **Praticabilidade na máquina de referência — e o limite honesto.** O PMD
> `net_af_xdp` está presente, com `libxdp` 1.6.2, `libbpf` 1.6.3 e kernel 7.0.
> Mas a NIC é uma Realtek RTL8125 com driver `r8169`, que **não tem suporte a
> XDP nativo nem a zero-copy** — verificado: zero símbolos `xsk_*` no módulo,
> contra 7 no `i40e`, 7 no `ice` e 8 no `ixgbe`. Aqui o AF_XDP roda em modo
> genérico com cópia, o que serve para aprender a API e ver o fluxo funcionando,
> **mas não para medir**. A comparação de desempenho do Nível 10 exige NIC com
> XDP nativo — Intel i40e/ice/ixgbe ou NVIDIA mlx5.

#### O caso híbrido que revela onde está o custo

O DPDK inclui o PMD `net_af_xdp`, que permite escrever a aplicação com
`rte_mbuf` e `rte_ring` normalmente, mas com AF_XDP como *backend* em vez de um
PMD de hardware. Comparar essa configuração com o DPDK sobre `vfio-pci`
**isola** o custo: mesma API, mesma estrutura de dados, só muda o caminho até a
NIC. É o experimento mais informativo dos três.

## Mapeamento para a trilha

- [../docs/00-visao-geral](../docs/00-visao-geral) -> visão geral e contexto
- [../docs/01-fundamentos](../docs/01-fundamentos) -> níveis 1 e 2
- [../docs/02-runtime-dpdk](../docs/02-runtime-dpdk) -> nível 3
- [../docs/03-mempool-ring-mbuf](../docs/03-mempool-ring-mbuf) -> nível 4
- [../trilha/01-fundamentos](../trilha/01-fundamentos) -> implementação dos níveis 1 a 4
- [../trilha/02-pipeline](../trilha/02-pipeline) -> níveis 5 e 6
- [../trilha/03-performance](../trilha/03-performance) -> nível 8
- virtualização (nível 9) -> módulo ainda não criado
- [../trilha/04-projeto-final](../trilha/04-projeto-final) -> nível 10

## Estratégia de estudos

- Estudar um tema por vez
- Sempre conectar teoria, API e benchmark
- Ler a documentação do DPDK como referência, mas validar em exemplos executáveis
- Implementar pequenos módulos e estudar um pipeline completo
- Comparar com versões em C++23 para construir engenharia crítica

## Recomendação de cronograma

### Etapa 1 — 2 a 4 semanas
- Níveis 1 a 3

### Etapa 2 — 4 a 6 semanas
- Níveis 4 a 6

### Etapa 3 — 4 a 6 semanas
- Níveis 7 a 8

### Etapa 4 — 4 a 6 semanas
- Níveis 9 e 10

## Resultado esperado

Ao final, o estudante deve ser capaz de:

- compreender o runtime do DPDK
- configurar e rodar programas de dados em ambiente DPDK
- explicar mempool, ring, mbuf e lifecycle de pacote
- dimensionar pipelines em termos reais de throughput, latência e custo
- comparar DPDK com a pilha do kernel (C++23 sobre sockets) e com AF_XDP,
  sabendo em que cenário cada abordagem é a escolha correta
- escrever documentação técnica com rigor e profundidade

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
[guiamempool]: https://doc.dpdk.org/guides/prog_guide/mempool_lib.html
[guiaring]: https://doc.dpdk.org/guides/prog_guide/ring_lib.html
[guiambuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html
[guiaflow]: https://doc.dpdk.org/guides/prog_guide/ethdev/flow_offload.html
[apidevinfo]: https://doc.dpdk.org/api/rte__ethdev_8h.html#a47933dd514cda48f158117ddfa139658

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cAfxdp]: https://doc.dpdk.org/guides/nics/af_xdp.html
[cPMD]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html
