# Submódulo 01 — RX/TX em lote

> **Nível 6** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [02 — Mempool, ring e lote](../../01-fundamentos/02-mempool-ring/)

> **Esqueleto.** Registra escopo e compromissos; o conteúdo ainda não foi
> escrito.

## Objetivo

Trazer pacotes **de verdade** para dentro do projeto. Até aqui todo pacote foi
sintético; a partir daqui existe NIC, DMA, descritores e [`rte_mbuf`][guiambuf].

## Por que este é o tópico mais aguardado da trilha

Quatro documentos já escritos adiam questões para cá, e nenhuma delas se resolve
sem tráfego real:

| Origem | Questão adiada |
|---|---|
| [Alternativa C++23](../../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md) | a comparação de desempenho honesta: hoje o DPDK "perde" porque o teste remove tudo pelo qual ele cobra |
| [02-mempool-ring §6](../../01-fundamentos/02-mempool-ring/README.md) | [`rte_mbuf`][guiambuf], que ainda não apareceu |
| [02-mempool-ring §2](../../01-fundamentos/02-mempool-ring/README.md) | a semântica **oposta** de [`rte_eth_tx_burst()`][apitxburst]: ela assume a posse do que aceitou |
| [Fundamentos §6](../../../docs/01-fundamentos/README.md#6-a-nic-por-dentro-dma-descritores-e-filas) | descritores, anéis de RX/TX e IOMMU, descritos mas nunca exercitados |

## Escopo

- configuração de porta, filas de RX e TX
- [`rte_pktmbuf_pool_create()`][apipoolcreate] e o nó NUMA da porta
- recepção e transmissão em lote, e o que os retornos significam
- a diferença de posse entre ring e TX, que é fonte de *double free*
- descarte: quando o pacote não é transmitido, quem o devolve

## Restrições de ambiente, verificadas

> **Esta seção já publicou três impedimentos, e dois eram falsos.** Foram
> registrados por precaução, antes de qualquer verificação — e precaução não
> conferida vira folclore igual a otimismo não conferido. A revisão de
> 2026-09-10 checou os três contra a máquina de referência.

**O que era falso.**

- *"A NIC não tem PMD, então o módulo precisa de `--vdev` como caminho
  principal."* O DPDK 25.11 traz `librte_net_r8169.so`, PMD nativo para a
  família RTL8125/8126, e o par PCI `10ec:8125` — o desta placa — está na
  imagem do driver. Confira com:

  ```bash
  ls /usr/lib/*/dpdk/pmds-*/librte_net_r8169.so
  lspci -n -s 08:00.0        # 08:00.0 0200: 10ec:8125
  ```

- *"O grupo IOMMU compartilhado complica o `vfio-pci` sem `unsafe_interrupts`."*
  O grupo 17 tem dois membros, e o segundo é uma **ponte**: `03:07.0`, um *PCIe
  Switch Downstream Port* em `pcieport`. O VFIO permite esse driver, então o
  grupo tem um único *endpoint* — a própria NIC. Não há necessidade de
  `unsafe_interrupts`.

  ```bash
  ls /sys/kernel/iommu_groups/17/devices/
  lspci -k -s 03:07.0 | grep 'Kernel driver'
  ```

**O que permanece verdadeiro, e é a restrição real.** A RTL8125 está num link
**PCIe Gen2 x1**, teto de cerca de 0,5 GB/s — abaixo de 10 GbE por limite de
barramento, antes de qualquer consideração de software
([Fundamentos §6.2](../../../docs/01-fundamentos/README.md#62-o-barramento-também-tem-orçamento)).

Isso limita as **afirmações de desempenho**, não o ensino: configuração de porta
e filas, descritores, `rx_burst`/`tx_burst`, retorno parcial, posse de mbuf no TX
e contadores funcionam todos. O que esta máquina **não** pode fazer é demonstrar
taxa de linha de 10 GbE, e o módulo precisa dizer isso em vez de contornar.

## Capacidades da NIC de referência, medidas

Não são previsão: saíram de `sudo ./scripts/diagnostico-nic.sh`, que binda,
sonda com `testpmd` e devolve a placa ao kernel. O PMD **reivindicou** o
dispositivo — `Driver name: net_r8169`, firmware `0x00000b99` —, o que encerra
a dúvida que esta seção carregava.

| Capacidade | Valor | O que decide no módulo |
|---|---|---|
| **Filas RX / TX máximas** | **1 e 1** | não há multi-fila, e portanto não há RSS efetivo nem escala por fila |
| Descritores por fila | 64 a 4096, alinhamento 64 | há espaço para o experimento de tamanho de anel |
| MTU | 1500 (mín. 68, **máx. 9172**) | *jumbo frames* são possíveis |
| Segmentos por pacote | até 64 | mbuf encadeado é exercitável |
| `Device capabilities` | `0x0` | nenhuma capacidade opcional |
| VLAN offload | tudo `off` | *offload* aqui é assunto de outra placa |
| Endereços MAC | 1 | sem filtragem por MAC múltiplo |
| RSS | chave de 40 B, tabela de 128 | **inerte**: RSS distribui entre filas, e só há uma |
| Link | `down`, `speed None` | não há cabo conectado nesta máquina |

### O limite que mais pesa não é o barramento

Eu esperava que a restrição dominante fosse o teto de PCIe Gen2 x1. Não é: é a
**fila única**.

Uma placa com uma fila de RX e uma de TX não permite ensinar a parte do RX/TX
que mais importa para plano de dados — distribuir tráfego entre filas com RSS,
dar uma fila por lcore, e medir a escala disso. A tabela acima lista RSS com
chave e tabela de redirecionamento, e isso engana: **RSS reparte entre filas, e
com uma fila não há o que repartir.**

Consequências, e nenhuma é fatal:

- o caminho de **uma fila** — configuração de porta, descritores,
  `rx_burst`/`tx_burst`, retorno parcial, posse de mbuf — é ensinável aqui, com
  hardware de verdade, DMA de verdade e IOMMU de verdade;
- **multi-fila e RSS** precisam de outra placa, ou de `--vdev=net_null`, que
  aceita quantas filas você pedir por ser software. É o inverso do que se
  supõe: o dispositivo virtual serve para o que o hardware **não** cobre, e não
  como substituto de baixa qualidade;
- **link `down`** significa que RX/TX de tráfego real exige cabo. Sem ele dá
  para configurar a porta, alocar filas e ler contadores — não para receber.

### O que muda quando houver hardware adequado

As limitações acima são físicas: não há o que consertar por software. O que dá
para fazer é **deixar pronto**, e está.

[`scripts/diagnostico-nic.sh`](../../../scripts/diagnostico-nic.sh) recebe o BDF
como argumento e não sabe nada sobre esta placa: numa NIC com várias filas ele
produz a mesma tabela com os valores dela. Rodar

```bash
sudo ./scripts/diagnostico-nic.sh 0000:XX:00.0
```

numa máquina apropriada é o suficiente para saber, antes de escrever qualquer
código, o que aquele hardware permite ensinar.

**O hardware já está definido:** uma **Mellanox ConnectX-4 Lx 25 GbE dual-port
SFP28**, prevista para semanas. Quando chegar, esta seção e a tabela de
capacidades são revisadas com os números dela.

O que ela fecha, e que a Realtek não permite:

| Pendente hoje | O que a ConnectX-4 Lx traz |
|---|---|
| RSS e distribuição entre filas | várias filas de RX/TX — RSS deixa de ser inerte |
| uma fila por lcore, e a escala disso | idem, com núcleos sobrando |
| *offloads* de checksum, TSO, LRO | `Device capabilities` deixa de ser `0x0` |
| `rte_flow` | o `mlx5` é a implementação de referência de *flow rules* em hardware |
| taxa de linha | 25 GbE por porta, contra o teto de ~0,5 GB/s do PCIe Gen2 x1 daqui |
| SR-IOV e *Virtual Functions* | destrava também a [Etapa 6](../../../ROADMAP.md) |

### O procedimento muda, e este é o ponto que mais engana

**A ConnectX-4 Lx não se prepara com `vfio-pci`.** O PMD `mlx5` é um driver
**bifurcado**: a documentação do DPDK diz que *"the same device is managed by
both kernel and DPDK drivers"*. A interface continua visível no `ip link`, o
`dpdk-devbind.py` não é usado, e
[`scripts/preparar-nic.sh`](../../../scripts/preparar-nic.sh) — construído para
o caminho `vfio-pci` — **é a ferramenta errada para ela**.

O que ela exige no lugar é a pilha de userspace do RDMA:

```bash
# Debian/Ubuntu
sudo apt install rdma-core libibverbs1 ibverbs-providers
ibv_devinfo                    # deve listar a placa
```

Nesta máquina `libibverbs.so.1` e `libmlx5.so.1` já existem, e `librdmacm.so.1`
**falta** — é o que precisa entrar antes da placa. O PMD `librte_net_mlx5.so` já
está presente no DPDK 25.11 instalado.

**A ferramenta já sabe disso, e foi testada antes da placa.**
[`scripts/lib-nic.sh`](../../../scripts/lib-nic.sh) classifica o dispositivo
pelo *vendor* PCI (`0x15b3` → bifurcado) e os dois scripts herdam a decisão:

- `preparar-nic.sh` **recusa** bindar uma placa bifurcada, com a explicação do
  porquê, em vez de quebrá-la;
- `diagnostico-nic.sh` pula as etapas de `modprobe`/bind, verifica `rdma-core`
  e `ibv_devinfo` no lugar delas, e não tenta "restaurar" uma placa que nunca
  saiu do kernel;
- `preparar-nic.sh --status` mostra o modelo de cada NIC da máquina.

A classificação recebe o *vendor* como argumento em vez de ler o `sysfs`,
justamente para ser testável **sem** o hardware — e é:
[`scripts/tests/l1_lib_nic.sh`](../../../scripts/tests/l1_lib_nic.sh) roda em L1,
em milissegundos, com 15 asserções. Sem ele, a primeira execução do caminho
Mellanox seria no dia da instalação, e um erro ali significaria bindar ao
`vfio-pci` uma placa que não pode ser bindada.

Consequência didática, e ela é boa: o módulo passa a ter **dois modelos de
driver** para ensinar em vez de um — o de captura total (`vfio-pci`, a placa sai
do kernel) e o bifurcado (`mlx5`, kernel e DPDK convivem, com isolamento
configurável por `rte_flow_isolate()`). Essa distinção é estrutural em DPDK e
hoje não aparece em lugar nenhum do material.

Até a placa chegar, o material deve dizer que não mediu — e não preencher a
lacuna com o `net_null`, que responderia qualquer coisa sem provar nada.

### Nota de reprodutibilidade

`/dev/vfio/17` é `crw------- root:root`. Rodando como root não importa, mas a
trilha inteira roda sem privilégio até aqui — este é o primeiro tópico que
quebra essa propriedade, e o módulo precisa dizer isso em vez de assumir.
`ulimit -l` nesta máquina é 8192 KB; como root não morde, mas é o limite que
derruba VFIO sem privilégio.

**Consequência para o desenho do módulo.** A NIC física passa a ser o caminho
principal, e o dispositivo virtual, a alternativa sem privilégio — a inversão do
que esta seção dizia antes. E cada um precisa declarar o que prova:

| Caminho | Prova | Não prova |
|---|---|---|
| NIC física + `vfio-pci` | descritores, DMA, PCIe, link, `xstats`, *offloads* reais | taxa de linha de 10 GbE (teto do barramento) |
| `--vdev=net_null` | fluxo de mbuf, semântica de burst, posse | descritor, DMA, PCIe — devolve pacotes vazios e libera tudo no TX |
| `--vdev=net_tap` | integração com a pilha do kernel | caminho de dados rápido: paga syscall e cópia, o oposto do que se mede |

**Sequência de binding, reversível.** `enp8s0` está DOWN e não é a interface de
gerência desta máquina — a rota default vai por Wi-Fi —, então tirá-la do kernel
não custa acesso. Confirme isso na *sua* máquina antes de rodar:

```bash
./scripts/preparar-nic.sh --status        # o que existe, sem alterar nada
sudo ./scripts/preparar-nic.sh 08:00.0    # binda, com as travas
sudo ./scripts/preparar-nic.sh --desfazer 08:00.0
```

[`scripts/preparar-nic.sh`](../../../scripts/preparar-nic.sh) recusa antes de
tentar quando a interface carrega a rota default, quando ela tem IP, quando o
IOMMU está desligado, quando há outro *endpoint* no grupo IOMMU, e avisa quando
nenhum PMD reivindica o par PCI. O `dpdk-devbind.py` sozinho não faz nada disso
— ele avisa em alguns casos e obedece em todos.

A saída nesta máquina, com as travas passando:

```
  ok    - enp8s0 nao carrega a rota default (wlp7s0)
  ok    - enp8s0 sem endereco IP configurado
  ok    - IOMMU ativo
  info  - grupo 17: 0000:03:07.0 (pcieport) - ponte ou livre, nao impede
  ok    - grupo IOMMU 17 tem a NIC como unico endpoint
  ok    - PMD encontrado para 10ec:8125: librte_net_r8169.so
```

## Fora do escopo

- *Offload* e [`rte_flow`][guiaflow] — designados à
  [Etapa 4.5](../../../ROADMAP.md) e não mais órfãos; se entrarem neste
  submódulo, entram como seção declarada, nunca de contrabando.
- Virtualização e SR-IOV, que são o nível 9.

## Entregáveis

- programa de RX/TX na NIC física, com o dispositivo virtual como caminho
  alternativo para quem não puder bindar
- documentação no framework do projeto
- L1 sobre a lógica de tratamento; L2 sobre o caminho com a EAL e o vdev
- a comparação de desempenho que os documentos anteriores adiaram

## Navegação

| | |
|---|---|
| **Anterior** | [02 — Mempool, ring e lote](../../01-fundamentos/02-mempool-ring/) |
| **Próximo** | [02 — Batching e backpressure](../02-batching-backpressure/) |
| **Módulo** | [02 — Pipeline](../README.md) |

[guiambuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html
[guiaflow]: https://doc.dpdk.org/guides/prog_guide/ethdev/flow_offload.html
[apitxburst]: https://doc.dpdk.org/api/rte__ethdev_8h.html#a83e56cabbd31637efd648e3fc010392b
[apipoolcreate]: https://doc.dpdk.org/api/rte__mbuf_8h.html#a8f4abb0d54753d2fde515f35c1ba402a
