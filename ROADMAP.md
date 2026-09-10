# Roadmap do projeto

## Visão estratégica

Este projeto tem como objetivo construir uma base concreta e didática para estudo profissional de DPDK, cobrindo desde os fundamentos até arquiteturas de pipeline de dados em alto desempenho.

## Etapas

### Etapa 1 — Base conceitual
- Linux, memória, cache, NUMA
- user-space e kernel-space
- redes e pacotes
- performance e latência

### Etapa 2 — Runtime do DPDK
- [EAL][cEAL]
- lcore
- [hugepages][cHuge]
- pools e filas
- lifecycle de pacote

### Etapa 3 — Módulos fundamentais
- mempool
- ring
- mbuf
- burst processing
- producer/consumer

### Etapa 4 — Arquitetura de software
- pipeline de dados
- modularização
- hot path e control path
- limites e trade-offs

### Etapa 4.5 — RX/TX e ethdev

Inserida entre a 4 e a 5 depois de uma revisão de 2026-09-10 constatar que o
ROADMAP saltava do nível 5 para o 8: **não havia etapa que se comprometesse com
`rte_eth_dev_configure()`**, embora quatro documentos adiem perguntas para ela e
o [plano](docs/plano-estudo-dpdk.md) prometa as *offloads* como entregável do
nível 6. Era possível executar o roadmap inteiro sem nunca configurar uma porta.

Vem antes da Etapa 5 por dependência, não por preferência: *backpressure* só se
mede com fonte real de pacotes, como o próprio
[módulo de pipeline](trilha/02-pipeline/README.md) já argumenta, e a comparação
de desempenho adiada por quatro documentos precisa de RX/TX para existir.

- configuração de porta e filas, descritores, `rx_burst` / `tx_burst`
- o retorno parcial do TX e a inversão de posse que ele cria — no anel o que
  **não** coube é seu; no TX o que **foi aceito** não é mais seu
- `stats` e `xstats`: onde cada perda é contabilizada
- *offloads* e [`rte_flow`][cflow] — designados a esta etapa, e não mais órfãos
- a pergunta de falha do [eixo](#etapa-75--eixo-de-falha-executado-nos-módulos-escritos):
  o que acontece quando não há mbuf para receber

**O hardware desta máquina serve, ao contrário do que o material publicou.**
A revisão verificou os três impedimentos registrados e nenhum se sustenta:

| Impedimento publicado | Verificação |
|---|---|
| a NIC exigiria `--vdev` por falta de PMD | o DPDK 25.11 traz `librte_net_r8169.so`, e o par `10ec:8125` está na imagem do PMD |
| o grupo IOMMU compartilhado complicaria o `vfio-pci` | o outro membro do grupo 17 é uma ponte PCIe em `pcieport`, driver permitido pelo VFIO — o grupo tem um único *endpoint* |
| binding derrubaria o acesso à máquina | `enp8s0` está DOWN e sem conexão; a rota default vai por Wi-Fi |

**Sondado de ponta a ponta** com `scripts/diagnostico-nic.sh`, que binda, roda
`testpmd` e devolve a placa ao kernel: o PMD reivindica o dispositivo
(`Driver name: net_r8169`, firmware `0x00000b99`). A dúvida está encerrada.

A sondagem revelou o limite que de fato manda, e **não é o barramento**: a placa
expõe **uma** fila de RX e **uma** de TX. Isso não impede o caminho de fila
única — porta, descritores (64 a 4096), `rx_burst`/`tx_burst`, retorno parcial,
posse de mbuf —, mas impede RSS e escala por fila, que é a parte do RX/TX que
mais importa em plano de dados. O `--vdev=net_null` passa a servir para o que o
hardware **não** cobre (multi-fila), e não como substituto de baixa qualidade.

**Hardware a caminho:** uma **Mellanox ConnectX-4 Lx 25 GbE dual-port SFP28**,
prevista para semanas. Ela fecha os gaps de multi-fila, RSS, *offloads*,
`rte_flow` e taxa de linha, e destrava também a Etapa 6 por trazer SR-IOV. A
chegada dela é uma **revisão** desta etapa e da tabela de capacidades em
[01-rx-tx-burst](trilha/02-pipeline/01-rx-tx-burst/README.md), não um módulo
novo.

E ela muda o procedimento: o PMD `mlx5` é **bifurcado** — kernel e DPDK
gerenciam o mesmo dispositivo —, então não usa `vfio-pci` nem
`scripts/preparar-nic.sh`. Exige `rdma-core`, que nesta máquina está
incompleto (`librdmacm` ausente). O ganho didático é ter os **dois modelos de
driver** para ensinar, em vez de um.

Permanecem verdadeiros o teto de PCIe Gen2 x1 (~0,5 GB/s, impede taxa de linha
de 10 GbE) e o link `down` por falta de cabo — dá para configurar porta e ler
contadores, não para receber tráfego. E este é o primeiro tópico da trilha que
**exige privilégio**: `/dev/vfio/17` é `root:root`.

[cflow]: https://doc.dpdk.org/guides/prog_guide/ethdev/flow_offload.html

### Etapa 5 — Benchmarking e qualidade
- perf e VTune
- sanitizers
- clang-tidy e clang-format
- testes e CI

### Etapa 6 — Virtualização
- SR-IOV e *Virtual Functions*
- `virtio-net` e `vhost-user`
- contêineres e o que muda neles

### Etapa 7 — Projeto final
- app DPDK funcional
- comparação com as alternativas: C++23 sobre sockets e AF_XDP
- documentação e análise de desempenho

### Etapa 7.5 — Eixo de falha (executado nos módulos escritos)

Revisão editorial de 2026-09-09 identificou a maior lacuna do material: ele
responde muito bem a *"o que acontece quando tudo funciona?"* e quase nada a
**"o que acontece quando algo dá errado?"**

A evidência estava na estrutura dos próprios documentos: os cinco módulos
escritos tinham **todos** uma seção *Limitações*, e **nenhum** tinha seção que
respondesse o que o software faz quando o recurso acaba, a fila enche ou o
processo vizinho morre.

São coisas diferentes, e é por isso que a primeira não cobria a segunda:
*Limitações* registra **o que os números não autorizam concluir**; o eixo de
falha registra **o que o sistema faz fora do caminho feliz**.

Hoje os cinco têm as duas — é o que esta etapa entregou, e se confere assim:

```bash
grep -l '^## .*Limitaç'          docs/0*/README.md trilha/01-fundamentos/*/README.md | wc -l  # 5
grep -l '^## .*Quando dá errado' docs/0*/README.md trilha/01-fundamentos/*/README.md | wc -l  # 5
```

A correção **não** é criar uma trilha paralela de sistemas críticos, nem adotar
FMEA e árvore de falhas, que são instrumentos de segurança funcional (IEC 61508)
desproporcionais a um guia de estudo. É acrescentar uma pergunta recorrente a
cada módulo, respondida com experimento, no mesmo padrão do resto.

**Nos módulos que já existem.** É aqui que a etapa começa, porque a pergunta
pode ser respondida hoje, com o código que já está escrito:

| Módulo | Pergunta de falha | Experimento que a responde |
|---|---|---|
| [Fundamentos §11](docs/01-fundamentos/README.md#11-quando-dá-errado) | o que acontece quando o orçamento por pacote estoura? | [`orcamento-estourado.c`](docs/01-fundamentos/medicoes/orcamento-estourado.c) — varre ρ de 0,50 a 1,58 e mostra que a cauda degrada antes da mediana |
| [Runtime §10](docs/02-runtime-dpdk/README.md#10-quando-dá-errado) | o que acontece quando o primário morre com secundários vivos? | [`l3_primario_morre.sh`](docs/02-runtime-dpdk/medicoes/tests/l3_primario_morre.sh) — SIGKILL no primário; 7 asserções sobre o que o secundário **não** percebe |
| [Mempool §6](docs/03-mempool-ring-mbuf/README.md#6-quando-dá-errado) | o que acontece quando o pool esgota no meio de um lote? | [`pool-esgotado.c`](docs/03-mempool-ring-mbuf/medicoes/pool-esgotado.c) — o degrau tudo-ou-nada, e a regra 4 confrontada e corrigida |
| [Tópico 01 §6](trilha/01-fundamentos/01-eal-hello/README.md#6-quando-dá-errado) | o que acontece quando a EAL não sobe? | [`tests/l2_run.sh`](trilha/01-fundamentos/01-eal-hello/tests/l2_run.sh) — os dois caminhos, e só um chega ao seu código |
| [Tópico 02 §6](trilha/01-fundamentos/02-mempool-ring/README.md#6-quando-dá-errado) | o que o retorno **parcial** obriga a fazer? | [`pipeline_ring_vazado`](trilha/01-fundamentos/02-mempool-ring/pipeline_ring.c) — o mesmo fonte sem a devolução, que a suíte exige que falhe |

**Nos módulos que ainda não existem**, a pergunta nasce junto com o texto, e não
depois — é mais barato escrever assim do que voltar para acrescentar:

| Módulo pendente | Pergunta de falha |
|---|---|
| [RX/TX](trilha/02-pipeline/01-rx-tx-burst/README.md) | o que acontece quando não há mbuf para receber? |
| [Pipeline](trilha/02-pipeline/README.md) | como a contrapressão chega até a NIC, e o que ela derruba antes |

Cada uma leva naturalmente a *overload*, *starvation*, exaustão, detecção,
isolamento, degradação e recuperação — sem formalismo importado.

**Critério de pronto — cumprido para os cinco módulos escritos.** A regra era
responder cada pergunta **com experimento executável** — programa, número medido
e teste —, nunca em prosa: descrever um modo de falha sem provocá-lo é o tipo de
folclore que o resto do material se recusa a repetir.

Dois resultados da execução merecem registro, porque mudaram o material:

- **A regra 4 de dimensionamento estava mal enunciada.** A documentação do DPDK
  diz que objetos fora do múltiplo do cache *"will never be used"*;
  `pool-esgotado.c` mede um consumidor único obtendo **todos** eles, pelo caminho
  `driver_dequeue`. A regra vale por eficiência, não por alcançabilidade, e
  [`sizing.h`](docs/03-mempool-ring-mbuf/medicoes/sizing.h) foi
  corrigido. É o segundo folclore que este material derruba medindo — e o
  primeiro vindo de fonte primária, não da cultura oral.
- **Dezesseis asserções não estavam sendo executadas.** Os dois testes L3 de
  multiprocesso exigiam `DPDK_ACADEMY_HUGE_DIR` exportado à mão e saíam com 77
  numa máquina que tinha hugetlbfs gravável. Pular por falta de requisito é
  correto; pular por falta de variável de ambiente é cobertura perdida em
  silêncio. Resolvido por autodetecção em
  [`lib-hugetlbfs.sh`](docs/02-runtime-dpdk/medicoes/tests/lib-hugetlbfs.sh).

Junto disso, três itens da mesma revisão, aceitos e pendentes:

- **requisitos mensuráveis** antes do benchmark (vazão, p99, jitter, perda,
  tempo de partida), para que medir deixe de ser "ver quanto dá" e passe a ser
  "o sistema satisfaz o requisito?";
- **injeção de falha** como técnica de validação, ao lado dos testes L1/L2/L3. O
  teste negativo do tópico 02 já é um caso disso e serve de modelo:
  `pipeline_ring_vazado` é o mesmo fonte com a devolução do retorno parcial
  removida, e a suíte **exige que ele falhe** — uma verificação que nunca falhou
  é indistinguível de uma que nunca dispara;
- **segurança como propriedade de arquitetura** — pacote malformado, exaustão de
  recurso, fronteira de privilégio, VFIO —, e não só ausência de estouro de
  buffer.

O que foi **recusado** na mesma revisão, e por quê:

| Recusado | Por quê |
|---|---|
| formalismo de FMEA e árvore de falhas (FTA) | são instrumentos de segurança funcional (IEC 61508), dimensionados para sistemas em que a falha mata. Num guia de estudo custam mais cerimônia do que ensinam, e deslocam o esforço da pergunta ("o que quebra?") para o preenchimento da planilha |
| template obrigatório de 16 seções por experimento | engessa módulo curto e módulo longo no mesmo molde. O percurso já declarado em [visão geral §3](docs/00-visao-geral/README.md#3-o-método) — problema, mecanismo, trade-offs, implementação, medição, confronto, decisão — cumpre o papel sem contar seções |
| marcação FATO / MEDIÇÃO / INFERÊNCIA em todo o texto | a distinção é necessária e **já é feita**, na linguagem, pela convenção de [visão geral §4](docs/00-visao-geral/README.md#4-como-ler-os-números). Etiquetar cada frase troca leitura por burocracia e ainda dá falsa precisão: o rótulo vira ritual e para de ser pensado |

### Etapa 8 — Adequação para alcance internacional
> **Deliberadamente a última etapa.** Decidido em 2026-09-09: a adequação para
> inglês só começa depois de o conteúdo em português estar maduro, para evitar
> perda de conteúdo e retrabalho.

O que está decidido sobre **como** fazer, quando chegar a hora:

- **Assimetria deliberada, não projeto bilíngue.** Corpo didático em português;
  superfície de descoberta em inglês.
- **Em inglês:** `README.en.md`, um resumo curto por tópico, identificadores do
  código, e `description` + `topics` do repositório.
  **Feito em 2026-09-10, exceto `description`/`topics`,** que dependem do
  repositório existir remotamente. Os identificadores migraram numa passada
  verificada pela suíte: a saída dos programas e a prosa continuam em português,
  e é isso que a assimetria significa na prática. Nomes de caso de GoogleTest
  ficaram em português por serem **prosa** — são frases lidas no relatório de
  teste (`ResultadoIndependeDoLote.DezPacotesSempreSomam695Bytes`), não símbolos
  que alguém chama.
- **Não traduzir** a prosa didática. O valor deste material são os números
  medidos; uma versão em inglês defasada faz o leitor concluir que *os números
  não são confiáveis*, não que a tradução está atrasada.
- **Descartado:** `docs/pt-br/` + `docs/en/` — a pasta `docs/` é árvore de build
  (tem `meson.build` e 16 dos 23 testes), e 12 READMEs vivem em `trilha/` junto
  do código, pela regra de manter documento e código no mesmo tópico. Descartados
  também a tradução automática por Action e o site estático, por ora.
- **Reabrir `docs/en/` completo** só se aparecer uma segunda pessoa que assuma a
  manutenção do inglês.

**Pré-requisito para começar esta etapa:** o conteúdo em português precisa estar
maduro. Hoje, 7 dos 19 documentos ainda são esqueletos, de 62 a 98 linhas — todos
em `trilha/02-pipeline/`, `trilha/03-performance/` e `trilha/04-projeto-final/`.

> Contagens envelhecem em silêncio, e estas já envelheceram uma vez. Para
> reconferir sem confiar neste parágrafo:
>
> ```bash
> grep -rlE '^> \*\*Esqueleto\.\*\*' docs trilha --include='*.md' | wc -l   # esqueletos
> find docs trilha -name '*.md' | wc -l                                     # documentos
> ```

## Objetivo final

Produzir um material técnico e pedagógico capaz de servir como referência para:

- iniciantes em DPDK
- profissionais em software e sistemas
- estudantes interessados em alto desempenho, redes e arquitetura
- pessoas que desejam aprofundar em C++23 e engenharia de software para plano de dados

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
