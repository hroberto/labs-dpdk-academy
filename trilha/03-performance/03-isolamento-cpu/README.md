# Tópico 03 — Afinidade não é isolamento

> **Parte A: o ruído do sistema operacional, sem rede.** O que se mede aqui não
> depende de NIC, de gerador de tráfego nem de reiniciar a máquina. A parte que
> depende — `imissed` observado acontecendo — está declarada na §8 e aguarda o
> hardware, como o módulo de RX/TX.

Uma thread fixada com `sched_setaffinity` não sai da CPU. Isso não é o mesmo que
ter a CPU. O sistema continua executando trabalho ali: tique do escalonador,
callbacks de RCU, *workqueues* por CPU, IPIs vindos de outras CPUs e
interrupções de dispositivo.

Este tópico mede **quanto** disso acontece nesta máquina, **qual** fonte causa
cada parada, e **quando** uma parada passa a custar pacote.

---

## 1. Fundamento: o limiar em que uma parada custa algo

Uma parada de 10 µs é irrelevante num servidor web e fatal num plano de dados —
e a diferença não é opinião, é aritmética.

A 10 Gbit/s com quadro mínimo, cada quadro ocupa `64 + 20 = 84 bytes` na linha
(7 de preâmbulo, 1 de delimitador e 12 de intervalo entre quadros, conforme a
[IEEE 802.3][ieee8023]). São 672 bits, ou **67,2 ns por quadro** — o mesmo
orçamento da [§1 do módulo 01](../../../docs/01-fundamentos/README.md#1-o-orçamento-quanto-tempo-existe-por-pacote).

Enquanto o polling está parado, os quadros continuam chegando e ocupam
descritores. O anel de RX absorve `N × 67,2 ns` antes do primeiro descarte:

| Descritores | Janela |
|---:|---:|
| 512 | 34,4 µs |
| 1024 | 68,8 µs |
| 2048 | 137,6 µs |
| 4096 | 275,3 µs |

> **A janela é cota inferior, e isso muda o que se pode concluir.** O FIFO
> interno da NIC também absorve, e nenhum driver o expõe. Uma parada **abaixo**
> desta janela seguramente não custa pacote; uma **acima** pode ainda assim não
> custar. Medir a janela efetiva é o exercício 3, e exige a placa.

A conta está em [`gap_hist.c`](gap_hist.c) e é verificada em L1 — é aritmética,
não medição, e o teste a confere com lápis.

---

## 2. Mecanismo: quem interrompe uma CPU que já tem dono

`sched_setaffinity` resolve **um** problema: a thread não migra. Não resolve o
inverso — o kernel continua tendo trabalho a fazer naquela CPU.

| Fonte | Onde aparece | O que a remove |
|---|---|---|
| Outras tarefas, balanceamento | `ctx-switches`, `migrations` | partição `isolated` de cpuset, ou `isolcpus=domain` |
| Tique do escalonador | `LOC` em `/proc/interrupts` | `nohz_full` — exige **uma** tarefa executável, e resta tique residual |
| Callbacks de RCU | kthreads `rcuo*` | `rcu_nocbs` |
| IRQ de dispositivo | vetor numerado em `/proc/interrupts` | `/proc/irq/*/smp_affinity`, `irqaffinity=`, `isolcpus=managed_irq` |
| *Workqueues* por CPU | `ps -eLo psr,comm` | máscara de `workqueue` |
| `vmstat_update` | `osnoise` | `vm.stat_interval` |
| **IPI de invalidação de TLB** | `TLB` em `/proc/interrupts` | **nenhum parâmetro** — ver §2.1 |
| IPI de função e de reagendamento | `CAL`, `RES` | isolamento mais disciplina |
| Watchdogs | `NMI` | `nmi_watchdog=0`, `nosoftlockup` — com perda de diagnóstico |
| SMI de firmware | só `hwlat` | nenhum, do lado do sistema operacional |
| Estados C e P | latência de saída de ocioso | governor `performance`, limite de estado C |
| Irmão SMT ocupado | não aparece como interrupção | deixar o irmão ocioso, ou desligar SMT |

A última linha já está medida neste repositório: a
[§5.1.1 do módulo 01](../../../docs/01-fundamentos/README.md#511-smt-duas-cpus-lógicas-não-são-dois-núcleos)
mostra **2,29×** de tempo por operação quando o irmão SMT está ocupado, contra
**3%** quando o vizinho está em núcleo físico distinto.

### 2.1 A fonte que nenhuma linha de boot remove

Todos os mecanismos acima controlam **quem mais usa a CPU**. Há um caso em que
quem interrompe é o próprio processo.

Quando uma thread altera o mapeamento de memória — `munmap`, `mprotect`,
`madvise(MADV_DONTNEED)` — o kernel precisa invalidar o TLB de **toda** CPU que
esteja executando aquele espaço de endereçamento. Ele faz isso por IPI, e a CPU
isolada recebe como qualquer outra.

A thread não migrou, o escalonador não a tocou, nenhum dispositivo interrompeu —
e houve parada. A sonda produz o efeito de propósito quando recebe uma CPU de
provocação: uma thread **dela mesma** passa a alterar mapeamento noutra CPU, e o
contador `TLB` sobe de **0 para 38 135** em trinta segundos (§6.2).

> **O que remove é disciplina, não configuração.** Não alterar mapeamento de
> memória no caminho quente. É a razão de o DPDK alocar tudo na inicialização, e
> de a [§2.3 do módulo 02](../../../docs/02-runtime-dpdk/README.md#23-o-que-isso-decide-na-arquitetura)
> concluir que o processo deve ser longevo.

### 2.2 O que transfere para fora do DPDK

Nada nesta seção é específico de plano de dados. Um laço de polling em qualquer
framework — motor de casamento, leitor de barramento, laço de jogo — enfrenta as
mesmas fontes. O que muda entre domínios é só o limiar: a janela do anel aqui, o
prazo de resposta lá.

---

## 3. Implementação

| Arquivo | Papel |
|---|---|
| [`gap_hist.h`](gap_hist.h) / [`gap_hist.c`](gap_hist.c) | histograma em potências de dois, aritmética da janela — **sem DPDK** |
| [`procstat.h`](procstat.h) / [`procstat.c`](procstat.c) | leitura de `/proc/interrupts` por CPU e por vetor — **sem DPDK** |
| [`stall_probe.c`](stall_probe.c) | a sonda: laço de relógio, histograma, delta de interrupções |
| [`ipi_provoker.c`](ipi_provoker.c) | o mesmo trabalho num **processo separado** — é o controle negativo |

O provocador de verdade é uma **thread da própria sonda**, ligada por
`stall_probe <cpu> <s> <limiar> <cpu_provocador>`. O programa separado existe
para o contraste: mesmo trabalho, mesma CPU, **espaço de endereçamento
diferente**. A §6 mostra que a diferença entre os dois é total.

> **Essa distinção não estava no primeiro desenho, e custou uma coleta.** O
> provocador nasceu como programa separado, e o controle positivo falhou: o
> `TLB` não subiu. A causa está na §2.1 — o IPI vai às CPUs que executam o
> **mesmo** espaço de endereçamento. O defeito virou o controle.

A separação é deliberada, e é a mesma do
[tópico de mempool](../../01-fundamentos/02-mempool-ring/README.md#41-a-estrutura-de-configuração-e-seus-invariantes):
a aritmética e o parser não precisam de máquina para serem testados, e por isso
têm teste L1 em milissegundos.

```bash
./scripts/build-all.sh
./build/trilha/03-performance/03-isolamento-cpu/stall_probe 2 10
```

### 3.1 Por que histograma em potências de dois, e por que o percentil é um piso

Uma parada do sistema não tem escala única: as frequentes estão no
microssegundo, as raras três ordens de grandeza acima. Balde linear fino
desperdiça memória na cauda; balde largo esconde o corpo. Potência de dois dá
resolução relativa constante, e 64 baldes cobrem tudo que cabe em `uint64_t`.

O preço é que o percentil sai **quantizado**. O programa devolve o **piso** do
balde que o contém, e não interpola:

```
p99,9 floor: 16384 ns      <- a amostra está em [16384, 32768)
max stall:   18304 ns      <- este é exato
```

Interpolar dentro do balde afirmaria uma precisão que o histograma não tem. O
**maior** é guardado sem quantização porque é o número que decide se a janela
foi excedida — e para esse não se aceita aproximação.

### 3.2 Por que `CLOCK_MONOTONIC` e não o TSC bruto

O TSC é mais barato de ler, e seria a escolha óbvia num laço apertado. A razão
que pesou mais é a **conversão**: o contador conta ticks, e transformar ticks
em nanossegundos exige saber a que taxa ele anda.

Nesta CPU o TSC **não** varia com o governor — `/proc/cpuinfo` traz
`constant_tsc` e `nonstop_tsc`, e a [§2.2 do módulo 02](../../../docs/02-runtime-dpdk/README.md#22-por-que-essa-espera-existe-e-quando-ela-não-acontece)
registra os dois. O problema é outro: falta `tsc_known_freq`, então **ninguém
publica a taxa** e quem quiser converter precisa calibrá-la. É por isso que a
EAL gasta 100 ms fazendo exatamente isso na inicialização.

Uma sonda que calibrasse por conta própria herdaria o erro da calibração, e o
erro entra na conta justamente na cauda, que é o que este tópico mede.

`clock_gettime(CLOCK_MONOTONIC)` custa dezenas de nanossegundos pelo vDSO —
ordem de grandeza **abaixo** das paradas que se procura. Se a leitura custasse
o mesmo que o fenômeno, o instrumento dominaria a medição, que é o defeito que
o [tópico de mempool](../../01-fundamentos/02-mempool-ring/README.md) recusa
publicar.

---

## 4. Hipótese, registrada antes da medição

> **H1.** Com apenas afinidade, a maior parada observada excede pelo menos uma
> das janelas da tabela da §1.
>
> **H2.** O tique do escalonador (`LOC`) é a fonte mais frequente no perfil de
> afinidade pura, e cai a zero — ou a um resíduo — sob `nohz_full`.
>
> **H3.** O `ipi_provoker` eleva o contador `TLB` da CPU da sonda em **todos**
> os perfis, inclusive no mais isolado.

**Refutação de cada uma:**

| | Refutada se |
|---|---|
| H1 | a maior parada ficar abaixo de todas as janelas, mesmo sob carga |
| H2 | `LOC` não for a fonte dominante, ou não cair com `nohz_full` |
| H3 | algum perfil zerar `TLB` com o provocador ativo |

A terceira é a que este tópico existe para demonstrar, e é a que contraria a
expectativa comum de que isolamento resolve.

### 4.1 Desfecho

| | Desfecho |
|---|---|
| H1 | **confirmada** — 5 de 20 execuções excedem a janela de 512 descritores |
| H2 | **metade confirmada** — `LOC` domina; a queda sob `nohz_full` não foi testada |
| H3 | **confirmada**, e com contraste que a fortalece |

A metade de H2 que falta exige reiniciar, e fica declarada como não testada em
vez de inferida. **Uma hipótese registrada e não testada não vira confirmada por
plausibilidade.**

---

## 5. Perfis

Cumulativos. Os dois primeiros **não exigem reiniciar**, e são os únicos que
esta Parte A executa.

| Perfil | Acrescenta | Exige reboot |
|---|---|---|
| P0 | só afinidade | não |
| P1 | + afinidade de IRQ, `vm.stat_interval` | não |
| P2 | + governor `performance`, limite de estado C | não |
| P3 | + `isolcpus=domain` ou partição de cpuset | **sim** |
| P4 | + `nohz_full` + `rcu_nocbs` | **sim** |
| P5 | irmão SMT ocioso × irmão carregado | não |

> **Por que P0–P2 e P5 primeiro.** Eles respondem a maior parte de H1 e toda a
> H3 sem tocar na linha de boot. E respondem a uma dívida que este material já
> declarou: a [§ de limitações do ramo](../README.md) diz que *"isolar ajuda
> continua sendo teoria no material"*.

> **P2 foi coletado; P1 continua de fora.** Os dois exigem privilégio, e a
> máquina de referência pede senha. O P2 foi obtido numa coleta dedicada e o
> desfecho está na §6.6.1: **nenhum efeito detectável sobre a cauda nesta
> máquina**, o que não é o mesmo que efeito nulo — com 20 execuções por braço,
> um efeito moderado passaria despercebido. O P1 —
> afinidade de IRQ e `vm.stat_interval` — segue pendente.

> **E as sessenta execuções dizem algo sobre o quanto o P1 ainda importa
> aqui.** Um vetor numerado de dispositivo apareceu na CPU medida **uma única
> vez**: o vetor 114 (`snd_hda_intel`, áudio HDMI), com 40 interrupções, numa
> execução da coleta B. Nas outras cinquenta e nove, os únicos rótulos foram
> `LOC`, `TLB`, `CAL`, `NMI` e `PMI` — nenhum deles endereçável por afinidade
> de IRQ. Numa máquina com NIC ativa o quadro seria outro, e é por isso que o
> P1 continua na lista em vez de ser descartado.

---

## 6. Medição

**Sete coletas de modo texto**, de 24 e 25 de setembro de 2026, cada uma com
quatro células × cinco repetições × 30 s, ordem das células permutada a cada
repetição. São **140 execuções**. Máquina declarada exclusiva, sem sessão
gráfica — boot em `multi-user.target`. CPU medida: 2 (irmão SMT: 14).
Provocador na CPU 4.

| Coleta | maior parada, mediana | acima de 34,4 µs | maior observada |
|---|---:|---:|---:|
| `2026-09-24-0955-jedec4800-canal-unico-texto` | 22,1 µs | 1/20 | 38,6 µs |
| `2026-09-24-1237-jedec4800-canal-duplo-texto` | 21,5 µs | 1/20 | 35,1 µs |
| `2026-09-24-1917-expo6000-canal-duplo` | 22,6 µs | 2/20 | 43,5 µs |
| `2026-09-25-0046-expo6000-canal-duplo` | 21,9 µs | 1/20 | 36,6 µs |
| `2026-09-25-1317-expo6000-canal-duplo` | 22,0 µs | 1/20 | 39,6 µs |
| `2026-09-25-1547-jedec4800-canal-duplo` | 22,1 µs | 2/20 | 46,1 µs |
| `2026-09-25-1720-expo6000-canal-duplo` | 22,1 µs | 1/20 | 55,7 µs |

A maior parada mal se move entre as sete: a mediana fica entre 21,5 e 22,6 µs,
e as coletas atravessam duas configurações de memória — 4800 e 6000 MT/s, canal
único e duplo. **O canal de memória não aparece na cauda**, e é esse o resultado
que a §6.6 vai precisar.

**As tabelas por célula agregam as sete coletas**, 35 execuções por célula:

| Célula | limiar | maior parada | paradas ≥ limiar | preempções | `TLB` | `CAL` | `LOC` |
|---|---:|---:|---:|---:|---:|---:|---:|
| P0 — só afinidade | 2 µs | 21,7 µs | 285 | 160 | 0 | 12 | 60 048 |
| P0 + provocador **thread** | 1 µs | 21,8 µs | 21 734 | 145 | 37 940 | 37 956 | 60 030 |
| P0 + provocador **processo** | 2 µs | 22,0 µs | 300 | 145 | 0 | 0 | 60 033 |
| P5 — irmão SMT carregado | 2 µs | 23,1 µs | 350 | 136 | 0 | 6 | 60 019 |

> **A coluna de contagem não é comparável entre linhas, e a tabela diz por quê.**
> A sonda usa limiar de **1 µs** na célula do provocador em thread e de **2 µs**
> nas outras três — o provocador produz paradas curtas, e um limiar de 2 µs
> deixaria de contá-las. Somar ou comparar as quatro contagens diretamente é
> somar respostas a perguntas diferentes, e por isso o limiar é coluna e não
> nota de rodapé.

#### As nove coletas de 23/09, e por que a tabela delas continua aqui

Antes do protocolo de modo texto, o tópico mediu nove coletas em 23/09/2026,
cada uma declarando o estado da máquina em que correu. Elas foram **removidas
do histórico** em 24/09 — os diretórios colidiam no nome e um deles carregava a
configuração de memória errada — e não são recoletáveis: as duas mais extremas
exigiriam desfazer decisões de hardware.

A tabela fica porque é o **instrumento da §6.6**: uma coleta sozinha mede; um
par que difere em uma variável decide. Foi ela que tornou o confundimento
visível, e reescrevê-la com números de hoje apagaria a razão de a investigação
ter existido. Nenhum número dela sustenta conclusão do tópico — quem sustenta
são as sete coletas arquivadas acima.

| | Estado da máquina | maior parada, mediana | acima de 34,4 µs |
|---|---|---:|---:|
| **A** | canal único; swap 2,01 GiB, disponível 4,89 GiB | 515,5 µs | 16/20 |
| **B** | canal duplo; `performance`, C3 desabilitado | 29,0 µs | 3/20 |
| **C** | canal duplo; `powersave`, C3 ativo | 25,2 µs | 5/20 |
| **C′** | idem C, 91 min depois | 24,1 µs | 1/20 |
| **E′** | idem C, 101 min depois | 24,6 µs | 3/20 |
| **D** | idem C + pressão de memória confinada a um cgroup | 30,9 µs | 7/20 |
| **E** | idem C + pressão global: swap 2,19 GiB, disponível 5,08 GiB | 153,9 µs | 11/20 |
| **E″** | idem E: swap 2,51 GiB, disponível 4,87 GiB | 24,0 µs | 1/20 |
| **T** | **sem sessão gráfica** — boot em `multi-user.target` | **21,5 µs** | **1/20** |

<!-- cita-retratado: 24,8 24.8 26,6 26.6 515,5 515.5 153,9 153.9 29,0 29.0 25,2 25.2 24,1 24.1 24,6 24.6 30,9 30.9 24,0 24.0 26,3 26.3 24,9 24.9 19,7 19.7 31,6 31.6 752,9 752.9 660,4 660.4 631,6 631.6 -->

> **A linha A já foi superada por medição.** O canal único FOI medido em modo
> texto, em `2026-09-24-0955-jedec4800-canal-unico-texto`: mediana de
> **22,1 µs**, com **1/20** acima do limiar — indistinguível do canal duplo. Os
> 515,5 µs não eram o canal; eram a sessão gráfica, e a subseção *"O
> confundimento entre memória e reinício, resolvido"* mede isso com p = 0,433.

> **A coleta E′ foi planejada como braço com pressão e correu sem nenhuma.** A
> condição de parada do consumidor de memória era absoluta — "alocar até haver
> 2 GiB em swap" — e o swap já estava nesse patamar por resíduo da coleta
> anterior. Ela nasceu satisfeita, nada foi alocado, e a campanha correu com
> 22,97 GiB disponíveis. O braço é válido; o que ele mede é a condição **sem
> pressão**, e é assim que entra nas contas.

### 6.1 H1: a afinidade não segura a cauda

**Nove das 140 execuções** têm a maior parada acima da janela de 512
descritores, e a maior observada foi **55,7 µs** — **1,6 vez** essa janela, e
um quinto da janela de 4096 descritores. H1 se sustenta: basta uma parada acima
da janela para que a afinidade sozinha não garanta o orçamento. Mas a margem é
estreita, e dizer *quanto* ela é estreita é parte do resultado.

A distribuição é **contínua**. As 140 execuções vão de 13,5 a 55,7 µs sem
intervalo vazio: a menor das nove acima da janela é de 35,1 µs, encostada nela.
Não há dois modos, e não há nada separado por ordem de grandeza.

> **As coletas de 23/09 mostravam outra coisa, e é dela que a §6.6 trata.** Lá a
> distribuição era bimodal — quinze execuções entre 15,7 e 31,6 µs, e três na
> casa das centenas: 631,6, 660,4 e 752,9 µs, sem nada entre 40 e 631 µs. Dois
> modos disjuntos indicam um **evento discreto** que ocorre ou não ocorre, e
> cuja duração é propriedade dele, não da carga. Nas 140 execuções de modo
> texto esse modo alto **não aparece nenhuma vez**, e a §6.6 identifica o
> evento: o *power gating* da GPU. O que resta aqui, de 35 a 56 µs, é outra
> coisa — e não é o que estourava o orçamento por vinte e duas vezes.

#### 6.1.1 O braço gráfico, e o que ele replica

As coletas de 23/09 foram removidas do histórico, e por isso o parágrafo acima
as cita sem poder mostrá-las. Em 26/09/2026 a condição foi medida de novo, com
**árvore limpa**, kernel atual e *governor* fixo — a coleta
`2026-09-25-2346-expo6000-canal-duplo`, que existe para responder um
[pré-registro do módulo 01][prereg] sobre outra grandeza e serve aqui como
braço.

| | modo texto | com sessão gráfica |
|---|---:|---:|
| execuções | 140 (7 coletas) | 20 (1 coleta) |
| maior parada, mediana | 22,0 µs | **26,4 µs** |
| acima da janela de 34,4 µs | 9/140 | **5/20** |
| maior observada | 55,7 µs | **784,1 µs** |

A diferença nas medianas é de 20% (`p = 0,008` por teste de postos), e o que
importa está na última linha: **o modo alto volta**. As vinte execuções dão
quinze entre 17,4 e 31,8 µs e depois 86,7, 360,4, 494,9, 749,0 e 784,1 µs.

**A coleta C, de 23/09, dava quinze no modo baixo e 5/20 acima da janela, com
máximo de 752,9 µs.** Os dois números centrais se repetem numa coleta feita
três dias depois, noutro kernel, com binário de árvore limpa e *governor*
fixado. A leitura da §6.6 — que o modo alto é o *power gating* da GPU, e não o
canal de memória, nem o estado C3, nem a pressão de memória — ganha a réplica
que as coletas removidas não podiam mais dar.

> **Uma ressalva sobre a palavra "bimodal".** A coleta C sugeria dois modos
> disjuntos, com nada entre 40 e 631 µs. O braço novo tem 86,7 e 360,4 no meio
> do vão. A separação entre o corpo e a cauda continua clara — um fator de 2,7
> entre a maior do corpo e a menor da cauda —, mas "nada no meio" era da
> amostra de vinte, não do mecanismo. O que sustenta o argumento da §6.6 é a
> **atribuição por evento** do rastro, não a forma do histograma.

[prereg]: ../../../docs/01-fundamentos/metodologia.md#71-pré-registro-a-coleta-gráfica-de-controle

### 6.2 H3: o escopo do IPI é o espaço de endereçamento, não a CPU

É o resultado mais limpo do tópico, e sai da comparação entre duas células que
diferem em **uma** coisa:

| | trabalho | CPU | espaço de endereçamento | `TLB` |
|---|---|---|---|---:|
| provocador **thread** | `mmap`/`munmap` de 8 MiB | 4 | **o mesmo** da sonda | 37 940 |
| provocador **processo** | idem | 4 | distinto | **0** |

Mesmo trabalho, mesma CPU, mesmo volume de memória. A diferença é de qual
espaço de endereçamento a thread faz parte, e o efeito **desaparece por
completo**.

As sete coletas atravessam duas configurações de memória e dois números de
canais. O contraste não se move:

| | 0955 4800 1c | 1237 4800 2c | 1917 6000 2c | 0046 6000 2c | 1317 6000 2c | 1547 4800 2c | 1720 6000 2c |
|---|---:|---:|---:|---:|---:|---:|---:|
| provocador **thread** | 39 091 | 37 912 | 38 344 | 38 266 | 37 940 | 37 778 | 37 756 |
| provocador **processo** | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

A faixa do lado da thread é de 1 335 contagens sobre 38 mil — **3,5%** entre
coletas, e 5,4% entre as 35 execuções — enquanto **nenhuma** das 140 execuções
registrou mais de uma contagem do lado do processo. Um efeito que ignora tudo
que faz a cauda se mexer é propriedade do mecanismo, não do estado da
máquina.

É por isso que nenhum parâmetro de boot alcança essa fonte: ela não vem de fora
do processo. O que a remove é não alterar mapeamento no caminho quente.

### 6.3 A fonte que se pode contar não é a que mais dói

O provocador injeta **37 940** IPIs de TLB por execução, contra **zero** no P0
limpo, e a célula dele registra **21 734** paradas acima de 1 µs. E ainda assim
a mediana da maior parada é **indistinguível** da do P0: 21,8 µs contra
21,7 µs, com p = 0,37 num teste de postos sobre as 35 execuções de cada uma.

> **As duas contagens de parada não se comparam entre si**, pelo limiar
> diferente que a tabela da §6 publica. O que se compara aqui é o que a §6
> mede com a mesma régua nas duas células: os IPIs de TLB, que vão de zero a
> trinta e oito mil, e a maior parada, que não se move.

Trinta e oito mil IPIs de TLB produzem trinta e oito mil paradas **curtas**. A
fonte mais fácil de instrumentar é a que menos importa para o orçamento, e a
relação se repete nas sete coletas — inclusive, como mostra a §6.6, quando a
mediana era vinte vezes maior.

A consequência prática é sobre o método, não sobre o TLB: **contar eventos de
uma fonte não mede o que ela custa**. Um painel que some interrupções por
segundo classificaria o provocador como o problema dominante, e estaria
apontando para o lugar errado.

### 6.4 Afinidade não impede preempção, e isso é medido

A sonda sofre entre **2,7 e 5,8 trocas de contexto involuntárias por segundo**
nas 140 execuções, com a thread fixada. A maior parada, na mesma amostra, varia
por um fator de 4,1.

`sched_setaffinity` impede que a thread **migre**. Não impede que o escalonador
a **tire da CPU** em favor de outra tarefa executável: a sonda é `SCHED_OTHER`
como qualquer processo. O contador de `/proc/self/status` mostra isso sem
ambiguidade, e custa uma leitura por execução.

> **O que este número NÃO estabelece.** A correlação de posto entre contagem de
> preempções e maior parada é **ρ = −0,02** nas 140 execuções — ausência de
> relação, não relação fraca. A contagem não carrega **duração**, e uma
> preempção longa conta igual a uma curta. Afirmar que a maior parada *é* uma
> preempção exigiria `osnoise`, que atribui fonte por evento.

O ρ de −0,02 é, por si, informação sobre o mecanismo: a **frequência** com que
a thread perde a CPU não acompanha a cauda em nada. Se a maior parada fosse
simplesmente "uma preempção qualquer", as execuções com mais preempções teriam
paradas maiores, e não têm. O que produz a cauda é mais raro que uma preempção
comum, e distingui-lo exige instrumento por evento.

### 6.5 O que a célula P5 decidiu, e o que ela continua sem decidir

Com cinco repetições por célula, esta comparação não separava. Com as **35
execuções** de cada célula nas sete coletas, ela separa: a mediana com o irmão
carregado é de **23,1 µs** contra **21,7 µs** do P0 limpo, e um teste de postos
dá **p = 0,0015**, com o irmão carregado produzindo a maior parada em 72% dos
pares. O efeito existe e é **pequeno**: 1,5 µs de mediana, 6,8%, e as duas
células ficam bem abaixo da janela de 34,4 µs.

> **Esta comparação é *post hoc*, e isso limita o que ela autoriza.** As sete
> coletas foram desenhadas para medir cada célula, não para testar esta
> diferença, e nenhum critério de refutação foi registrado antes. O p diz que a
> diferença não é ruído de amostragem; ele não a confirma como hipótese. Para
> isso seria preciso pré-registrar e recoletar — e o tamanho do efeito não
> justifica a campanha.

A
[§5.1.1 do módulo 01](../../../docs/01-fundamentos/README.md#511-smt-duas-cpus-lógicas-não-são-dois-núcleos)
mede **2,29×** de efeito do irmão sobre **vazão**. Aqui, sobre **cauda**, o
efeito é de 6,8% — trinta vezes menor. **São perguntas diferentes, e a
diferença de magnitude é o resultado**: o irmão SMT disputa unidades de
execução o tempo todo, e isso domina a vazão; a maior parada é governada por
evento raro, que a disputa por ALU mal toca.

O que a célula continua sem decidir é o **mecanismo**: se o 1,5 µs a mais vem
de o irmão atrasar a própria sonda ou de ele aumentar a chance de preempção,
esta medição não separa. Seriam precisos `osnoise` e atribuição por evento —
o mesmo instrumento que a §6.4 pede.

### 6.6 A busca pela fonte do modo alto

A §6.1 estabelece o que se procura: um evento discreto, de centenas de
microssegundos, que ocorre em algumas execuções e não em outras. As §6.2 a §6.4
eliminam as fontes que o tópico sabe instrumentar — IPI de TLB produz paradas
curtas, e a taxa de preempção não acompanha o modo alto.

Cada candidato abaixo foi submetido a **uma intervenção de variável única**,
com o critério de refutação fixado antes da coleta.

#### 6.6.1 Estado C profundo — não sustentado

A latência de saída do C3 nesta máquina é de **350 µs**, a mesma ordem de
grandeza do modo alto. O mecanismo proposto: a preempção tira a sonda da CPU, a
CPU fica ociosa, o `cpuidle` desce ao estado profundo, e a volta cobra os
350 µs. Todos os elos são plausíveis, e juntos explicariam o modo alto sem
precisar de fonte nova.

**Intervenção:** governor `performance` e todo estado com latência ≥ 20 µs
desabilitado nas 24 CPUs, o que nesta máquina desliga o C3 e preserva o C2
(18 µs). Coleta B contra coleta C, sem nenhuma outra diferença.

**Desfecho: não sustentado.** 3/20 contra 5/20, medianas de 29,0 e 25,2 µs,
Mann-Whitney **p = 0,304**. O modo alto permanece com o C3 desligado.

O desfecho dizia **eliminado**, e era forte demais. `p = 0,304` significa que
estes dados não distinguem os dois regimes — não que os regimes sejam iguais.
Com 20 execuções por braço, um efeito real de tamanho moderado passaria
despercebido com facilidade, e **ausência de significância não é evidência de
ausência**. A §6.6.3 já usava a palavra certa para o mesmo tipo de desfecho;
estas duas não usavam.

O que está demonstrado é o que a intervenção mostrou: desligar o C3 não fez o
modo alto desaparecer. Eliminar a hipótese exigiria o `cpuidle` instrumentado
por evento, que é o que o parágrafo seguinte pede.

A cadeia falha em algum elo — ou a CPU não chega a descer ao C3 nesse
intervalo, ou desce e a volta não custa o que a tabela de latência declara. Os
dois casos são distinguíveis, e exigem `cpuidle` instrumentado por evento.

#### 6.6.2 Disputa de CPU por outras tarefas — não sustentado

Uma tarefa executável concorrente explicaria paradas longas sem aparecer em
`/proc/interrupts`: a sonda perde a CPU e espera a fatia da outra.

**Evidência:** o `sysstat` registrou **fila de execução igual a 1** tanto na
coleta A quanto na C, com carga média de 1,69 e 1,10. A coleta A tem 16/20 de
modo alto e a C tem 5/20, com a mesma fila.

**Desfecho: não sustentado.** A fila de execução não distingue os dois regimes.

E ela não teria como distinguir, mesmo que a disputa existisse. O desfecho
desta medição é a **maior parada em janelas curtas**, e a fila de execução do
`sysstat` é uma agregação com resolução de segundos: uma tarefa executável que
dispute a CPU por dezenas de microssegundos, exatamente na janela do evento
extremo, não move essa média. O indicador é agregado e o fenômeno é pontual.

O que está demonstrado é que **o indicador agregado não sustenta a hipótese** —
não que a disputa não ocorra. Distingui-las exige atribuição temporal por
evento, como a §6.5 faz com o `osnoise`.

#### 6.6.3 Pressão de memória como estado — não sustentado

A coleta A correu com **2,01 GiB em swap e 4,89 GiB disponíveis** de um total
de 14,20 GiB. A coleta C, sem pressão alguma. O mecanismo proposto: memória
escassa produz recuperação de página, conclusão de E/S de swap e trabalho de
`kswapd`, e algum desses é o evento discreto.

**Intervenção:** um consumidor de memória reproduz o estado de A na máquina
atual, sem reiniciar e sem trocar hardware. Duas variantes, porque o mecanismo
proposto tem dois componentes separáveis:

| | como | o que isola |
|---|---|---|
| **D** | consumidor com teto de 6 GiB num cgroup, alocando 12 GiB | há recuperação de página, mas o sistema fora do cgroup não tem memória escassa |
| **E** | consumidor global até `MemAvailable` ≈ 4,9 GiB com ~2 GiB em swap | reproduz o estado global de A |

**Primeiro resultado:** E deu 11/20 e mediana de 153,9 µs, contra 5/20 e
25,2 µs da C — Mann-Whitney **p = 0,028**. D não alcançou significância
(7/20, p = 0,160).

**A réplica derruba o resultado.** Uma segunda coleta sob o mesmo estado —
E″, com 2,51 GiB em swap e 4,87 GiB disponíveis — deu **1/20 e mediana de
24,0 µs**, indistinguível da condição sem pressão (p = 0,269). As duas células
com pressão diferem **entre si** com p = 0,0007, mais do que qualquer uma
difere da condição sem pressão.

Agrupando os três braços sem pressão (n = 60, mediana 24,8 µs, 9/60) contra os
dois com pressão (n = 40, mediana 26,6 µs, 12/40): **p = 0,156**.

**Desfecho: não sustentado.** O estado de memória, reproduzido duas vezes, não
reproduz o efeito duas vezes.

> **Por que a primeira coleta parecia decidir.** Com 20 pontos por braço, o
> teste tem pouco poder, e um braço que calha de conter vários eventos do modo
> alto produz p abaixo de 0,05 sem que a intervenção tenha causado nada. O
> valor de 0,028 não estava errado como aritmética; ele estava errado como
> evidência, e só a réplica podia mostrar isso. **Um par de coletas não é um
> experimento.**

#### 6.6.4 Atividade de recuperação — explica E contra E″, não explica A

E e E″ tinham estado de memória equivalente e desfechos opostos, o que obriga a
procurar o que diferia entre elas. O `sysstat` responde:

| | E (11/20) | E″ (1/20) | razão |
|---|---:|---:|---:|
| `pgscan` de `kswapd` por segundo | 1 112,6 | 279,3 | 4,0× |
| `pgscan` direto por segundo | 443,2 | 182,6 | 2,4× |
| `pgsteal` por segundo | 1 566,4 | 557,5 | 2,8× |
| `pswpout` por segundo | 691,3 | 123,6 | 5,6× |

A causa da diferença é do próprio procedimento: em E o consumidor teve de
paginar 2,19 GiB do zero; em E″ o swap já estava ocupado por resíduo, e restou
paginar 0,32 GiB. Estado igual, trabalho desigual.

Isso sugere que o que importa é a **atividade** de recuperação, não a condição
estática — e a coleta E corrobora de outra forma: o modo alto decai ao longo
dos dez minutos, com a memória mantida constante.

```
  E, maior parada por repeticao (us)
  rep 1:  689  742  714  502      <- todas no modo alto
  rep 2:  734  773  795   29
  rep 3:   35   28   22  273
  rep 4:  670  452   27   23
  rep 5:   28   23   26   25      <- nenhuma
```

Estado constante com efeito decrescente é assinatura de atividade transiente,
não de condição estática.

**Mas a hipótese morre na coleta que a motivou.** Durante os dez minutos da
coleta A, o `sysstat` registrou `pgscan = 0` e `pgsteal = 0` — **nenhuma
atividade de recuperação** — e A tem 16/20 de modo alto:

| | atividade de recuperação | acima da janela |
|---|---|---:|
| A | nenhuma | 16/20 |
| E | alta | 11/20 |
| E″ | moderada | 1/20 |
| C, C′, E′ | nenhuma | 9/60 |

A e E″ têm atividade baixa e desfechos opostos. A atividade de recuperação
distingue E de E″ e **não distingue A de C**, que é o par que precisava de
explicação.

**Desfecho: descritivo, não causal.** A observação fica registrada porque é
medida e porque orienta o próximo instrumento; ela não é proposta como causa.

#### 6.6.5 Identificação da fonte por rastreamento de eventos

Os quatro candidatos anteriores foram eliminados por ausência de correlação.
Esse método não permite confirmação: a contagem agregada por vetor e por
processo demonstra que determinado suspeito não estava presente, mas não
atribui um evento individual a uma origem.

A atribuição por evento requer instrumento específico. O tracer `osnoise`,
integrado ao kernel e exposto pela ferramenta `rtla`, mede a mesma grandeza
que a sonda deste tópico — intervalos em que a CPU é subtraída da tarefa
corrente — e classifica cada ocorrência em cinco categorias: hardware, NMI,
IRQ, softirq e thread.

A concordância entre os dois instrumentos foi verificada previamente, em três
grandezas independentes:

| Grandeza | `osnoise` (kthread) | `stall_probe` (processo) |
|---|---:|---:|
| maior parada única | 717 µs | 632–834 µs |
| eventos de thread por segundo | 8,45 | 7,2 |
| IRQ por segundo | 1 999 | ≈ 2 000 (`LOC`) |

Trata-se de dois programas distintos, um executando em espaço de kernel e
outro em espaço de usuário, que convergem nas três medidas.

##### Atribuição por função

Configurado com limiar de parada, o `osnoise` registra os eventos que ocuparam
a CPU no instante da maior parada observada. Duas capturas independentes
produziram o mesmo resultado:

```
kworker/2:2  workqueue_execute_start: function amdgpu_device_delay_enable_gfx_off [amdgpu]
kworker/2:2  thread_noise: kworker/2:2  duration 808492 ns
```

A função pertence ao driver `amdgpu` e executa a reativação do *power gating*
do bloco gráfico. A GPU integrada desativa o subsistema GFX em ociosidade; após
cada período de uso, o driver agenda trabalho diferido para reativá-lo, e a
transição consome centenas de microssegundos. A execução ocorre em *workqueue*
por CPU — categoria já listada na tabela da §2, para a qual nenhum parâmetro de
linha de boot oferece remoção.

A distribuição por função, em treze segundos de rastreamento:

| Função | n | Maior | Soma |
|---|---:|---:|---:|
| `amdgpu_device_delay_enable_gfx_off` | 12 | 808,5 µs | 2 455 µs |
| `vmstat_update` | 7 | 74,2 µs | 291 µs |
| `psi_avgs_work` | 78 | 51,9 µs | 334 µs |
| `blk_mq_timeout_work` | 1 | 8,8 µs | 8,8 µs |
| `pci_pme_list_scan` | 5 | 8,2 µs | 35,8 µs |

As doze execuções da função do `amdgpu` totalizam duração superior à soma das
noventa e uma restantes. Nenhuma das demais funções excede 75 µs.

##### Padrão temporal

Os eventos de maior duração apresentam periodicidade de um segundo e duração
decrescente. O padrão é reprodutível nas duas capturas:

```
  rastro de 29 s            rastro de 13 s
  0,20 s -> 333 us          0,26 s -> 325 us
  1,21 s -> 294 us          1,26 s -> 276 us
  2,22 s -> 243 us          2,27 s -> 171 us
  3,22 s -> 216 us          3,28 s -> 200 us
  4,23 s -> 183 us          4,29 s -> 174 us
  5,24 s -> 110 us          (cessa)
  (silencio)                (silencio)
  13,30 s -> 707 us         11,34 s -> 808 us
```

A interpretação compatível com o comportamento documentado do driver é o
reagendamento do trabalho: a reativação é tentada, não se completa enquanto há
processamento gráfico pendente, e é reagendada a intervalos de um segundo, com
duração decrescente até a conclusão. Em ambas as capturas o padrão foi
precedido por atividade de terminal, que envolve redesenho de tela.

##### Registro independente no journal do kernel

Durante o período de investigação, o kernel emitiu de forma autônoma:

```
kernel: workqueue: dm_irq_work_func [amdgpu] hogged CPU for >10000us 7 times,
        consider switching to WQ_UNBOUND
```

A função referida pertence ao mesmo driver e executa trabalho distinto. A
duração registrada — superior a dez milissegundos — excede em uma ordem de
grandeza o maior evento medido neste tópico. O registro coincidiu com
interrupção momentânea da interface gráfica observada na sessão.

##### Ruído de hardware

A §8 listava a interrupção SMI de firmware como não observável sem o tracer
`hwlat`. O `osnoise` classifica ruído de hardware em coluna própria e
registrou valor nulo em dez minutos de coleta. A hipótese de SMI é, portanto,
eliminada nesta máquina, e a limitação correspondente é retirada.

#### 6.6.6 Intervenção: coleta sem sessão gráfica

A identificação da função não constitui, por si, demonstração de causalidade.
O critério adotado nas subseções anteriores exige intervenção de variável
única: suprimir o suspeito e verificar se o efeito desaparece.

A supressão do driver `amdgpu` por lista negra inviabilizaria o console. A
alternativa adotada foi suspender a sessão gráfica, mantendo o restante do
sistema em configuração idêntica. A máquina foi reiniciada em uma entrada de
GRUB configurada para `systemd.unit=multi-user.target`, sem gerenciador de
display, e a coleta foi executada por console de texto.

**Pré-registro.** Escrito antes da execução, no cabeçalho de
`ferramental/qualidade/campanha.sh`:

> Predição: se a origem do modo alto é o `amdgpu`, o `osnoise` em modo texto
> registra máximo de thread abaixo de 100 µs, a função
> `amdgpu_device_delay_enable_gfx_off` não aparece entre os eventos, e as
> paradas acima da janela caem a zero ou próximo de zero.
>
> Refutação: se o máximo permanecer em centenas de microssegundos, ou se as
> paradas acima da janela persistirem na mesma proporção, a origem não é a
> sessão gráfica, e a atribuição está incorreta.

**Resultado.** As duas medidas se deslocaram na direção prevista:

| Grandeza | Com sessão gráfica | Modo texto |
|---|---:|---:|
| `osnoise`, máximo de thread | 711 µs | **25 µs** |
| `stall_probe`, maior parada | 805 µs | **41 µs** |
| paradas acima da janela (40 µs) | 37 | **0** |
| `amdgpu_device_delay_enable_gfx_off` | 12 ocorrências | **ausente** |

A distribuição bimodal descrita na §6.6 não se manifesta na ausência da sessão
gráfica. O modo alto — o conjunto de paradas entre 40,0 µs e 631,6 µs — desaparece
integralmente. A predição não foi refutada em nenhuma das quatro grandezas.

O achado é a conclusão da cadeia iniciada na §6.6: a distribuição bimodal
observada nas coletas anteriores era produzida pela reativação do *power
gating* da GPU integrada, agendada em *workqueue* por CPU e, portanto, não
removível por isolamento de CPU, `nohz_full` ou afinidade de interrupções.

##### Convergência dos instrumentos após a intervenção

A §6.6.4 registrava discordância não resolvida entre os dois instrumentos: o
`osnoise` previa ruído suficiente para afetar 84 % das células, enquanto a
sonda observava afetação em 15 %. A divergência, de fator 5,6, foi atribuída
provisoriamente a diferença de metodologia.

Em modo texto a discordância não se reproduz: ambos os instrumentos registram
valores da mesma ordem (25 µs e 41 µs). A divergência era, portanto,
propriedade da fonte, não dos instrumentos. O `osnoise` executa uma thread que
não consome CPU útil; a sonda executa uma carga que ocupa a CPU
continuamente. Uma CPU saturada por tarefa de usuário recebe menos trabalho
diferido de *workqueue* do que uma CPU que alterna entre ociosidade e
atividade — o que reduz a frequência de reativação do *power gating* e,
consequentemente, a exposição da sonda ao fenômeno.

#### 6.6.7 Intervenção: desligar o *power gating* com a sessão gráfica viva

A §6.6.6 suprime a sessão gráfica inteira e observa o modo alto desaparecer.
Isso não distingue duas explicações: a reativação do *power gating* do bloco
GFX, ou a sessão gráfica produzindo o efeito por outro caminho — caso em que o
`gfx_off` nomeado pelo rastro seria sintoma, e não causa.

A intervenção que separa as duas é desligar o GFXOFF **mantendo a sessão
gráfica ativa**. Ela é feita em tempo de execução, sem reinício, escrevendo uma
palavra de 32 bits em `/sys/kernel/debug/dri/*/amdgpu_gfxoff`: palavra nula
chama `amdgpu_gfx_off_ctrl(adev, false)` e desliga; palavra não nula religa.

> **A interface exige quatro bytes binários, não texto.**
> `amdgpu_debugfs_gfxoff_write` rejeita, antes de tocar na GPU, qualquer escrita
> cujo tamanho ou deslocamento não seja múltiplo de quatro — `test $0x3,%dl`
> seguido de `movq $-22`. Uma escrita de um byte devolve `EINVAL`, e ler esse
> `EINVAL` como "o arquivo é somente leitura" é o erro que manteve esta seção
> em aberto por um dia. O modo `0400` também não impede: `CAP_DAC_OVERRIDE`
> abre o arquivo, e por isso a recusa veio de dentro do *handler*.
>
> `amdgpu_gfx_off_ctrl` é contagem de pedidos (`gfx_off_req_count`), não
> interruptor: cada desligamento exige exatamente um religamento, e só ao zerar
> a contagem o driver reenfileira o trabalho atrasado em `system_percpu_wq`.

##### Desenho

Pares alternados **ligado / desligado** de 30 s na mesma CPU, repetidos — não um
antes-e-depois. Cada janela desligada tem uma ligada imediatamente antes e
outra depois, de modo que deriva térmica ou de carga atinge os dois braços no
mesmo intervalo. Duas coletas, oito pares no total.

Programa: `ferramental/qualidade/experimento-gfxoff.sh`, com o pré-registro no
cabeçalho. Apuração: `ferramental/qualidade/analisar-gfxoff.py`.

##### Atribuição por função, fechada

Com o evento `workqueue:workqueue_execute_start` habilitado, o rastro do estado
ligado nomeia a função e a casa com o ruído:

```
kworker/2:3-446 [002] .....  8044.528193: workqueue_execute_start:
    function amdgpu_device_delay_enable_gfx_off [amdgpu]
kworker/2:3-446 [002] d..2.  8044.528640: thread_noise: kworker/2:3:446
    start 8044.528192820 duration 446878 ns
```

O ruído de thread começa no instante em que a função inicia, no mesmo
`kworker`. No estado desligado, **nenhum evento ≥ 300 µs em 120 s** de sessão
gráfica ativa.

> **O evento precisa ser pedido.** O `rtla` habilita apenas os próprios eventos
> — `irq_noise`, `softirq_noise`, `thread_noise`, `sample_threshold` —, e um
> rastro sem `workqueue:workqueue_execute_start` mostra que um `kworker` ocupou
> a CPU sem dizer o que ele executava. Numa captura anterior havia 696 606 ns
> de `kworker/2:3` e zero ocorrências de `gfx` em 31 127 linhas: isso mede a
> ausência do evento, não a da função.

##### Resultado quantitativo

| coleta | ciclo | ligado | desligado |
|---|---:|---:|---:|
| 00:15 | 1 | 762 µs | 26 µs |
| 00:15 | 2 | 849 µs | 25 µs |
| 00:15 | 3 | 586 µs | 24 µs |
| 00:27 | 1 | 310 µs | 22 µs |
| 00:27 | 2 | 482 µs | 25 µs |
| 00:27 | 3 | 38 µs | 102 µs |
| 00:27 | 4 | 25 µs | 20 µs |
| 00:27 | 5 | 117 µs | 98 µs |

| medida | valor |
|---|---|
| teste do sinal, 8 pares | 7 a favor, p = 0,0703 |
| janelas com evento ≥ 300 µs, ligado | 5 de 8 |
| janelas com evento ≥ 300 µs, desligado | 0 de 8 |
| Fisher exato bilateral | **p = 0,0256** |
| maior observado, ligado | 849 µs |
| maior observado, desligado | 102 µs |

##### Por que o desfecho publicado é dicotômico, e não a mediana

Três das cinco células ligadas da segunda coleta deram 38, 25 e 117 µs — o modo
alto não apareceu nelas. **A célula não falhou; o evento não aconteceu nela.**
A reativação do *power gating* é um evento raro e grande: o driver só a agenda
depois de um período de uso da GPU, e uma janela de 30 s sem transição mede
outro ruído qualquer.

Segue daí que `Max Single` numa janela curta **não é uma grandeza estável**, e
que comparar medianas entre os braços dilui o efeito com as janelas em que não
havia o que suprimir. O desfecho que corresponde ao mecanismo é se a janela teve
ou não um evento da ordem das centenas de microssegundos — e por esse desfecho
a separação é completa: cinco de oito contra zero de oito.

A primeira coleta, isolada, daria três de três com separação de trinta vezes. A
segunda tem sobreposição entre os braços, e duas células desligadas (98 e
102 µs) ficam acima de duas células ligadas. As duas entram; publicar apenas a
que confirma seria escolher o resultado.

##### O que isto estabelece, e o que não

Estabelece, **por intervenção**, que o modo alto vem da reativação do *power
gating* do bloco GFX, e não da sessão gráfica por outro caminho: a sessão
permaneceu viva nos dois braços, e só o GFXOFF mudou.

Não estabelece a magnitude do efeito com precisão — oito pares, `n` pequeno, e
o desfecho é uma taxa de ocorrência que dependeria de quanto a GPU é usada na
janela. Nem generaliza para outra plataforma: uma máquina, GPU integrada AMD,
driver `amdgpu`.

Há ainda uma ressalva de interpretação que o resultado positivo torna inócua,
mas que vale registrar: `amdgpu_gfx_off_ctrl` começa com um teste de suporte e
retorna sem efeito quando o bit não está presente. Numa plataforma em que o
teste falhasse, o braço desligado seria indistinguível do ligado — e o desfecho
a reportar seria "sem efeito observável", não "hipótese refutada".

### 6.7 Síntese dos candidatos e limitações remanescentes

| Candidato | Desfecho | Evidência |
|---|---|---|
| IPI de invalidação de TLB | produz paradas **curtas** | §6.2, §6.3 |
| preempção comum | taxa não acompanha o modo alto | §6.4 |
| estado C profundo | **eliminado** | B × C, p = 0,304 |
| disputa de CPU | **eliminado** | fila de execução = 1 em A e C |
| pressão de memória como estado | **não sustentado** | réplica E″, p = 0,269 |
| atividade de recuperação | descritivo, não causal | §6.6.4 |
| SMI de firmware | **eliminado** | `HW = 0` em dez minutos |
| ***workqueue* do driver `amdgpu`** | **confirmado** | §6.6.5, §6.6.6 |

A fonte constava da tabela da §2 desde o início, na linha *"Workqueues por
CPU"*. O elemento ausente não era a hipótese, e sim o instrumento capaz de
atribuir um evento individual a uma origem. Contagem agregada por vetor e por
processo — método das oito primeiras coletas — permite eliminar candidatos por
correlação ausente, mas não identifica o ocupante da CPU.

As quatro eliminações anteriores não são redundantes em relação ao achado
final. Duas delas apresentavam ordem de grandeza compatível com o fenômeno: a
latência de saída do estado C3 é de 350 µs, e o modo alto alcançava 800 µs.
A compatibilidade de escala, isoladamente, não estabelece causa; sua aceitação
teria produzido atribuição incorreta acompanhada de valores corretos.

#### Implicações para o protocolo de coleta

As coletas deste tópico, e as campanhas publicadas anteriormente, declaram
*"máquina exclusiva, navegador fechado"*. A medição demonstra que essa condição
não elimina a sessão gráfica: o compositor, o servidor de display e o driver da
GPU permanecem ativos e produzem, isoladamente, eventos de até 808 µs a
intervalos de poucos segundos.

O efeito sobre os resultados publicados é limitado pelo desenho estatístico
adotado. O projeto reporta **mediana com dispersão**, não média. Um evento raro
de 800 µs desloca em pouco a mediana de uma coleta com bilhões de amostras: os
três braços sem pressão agrupados (C, C′ e E′, n = 60) dão mediana de 24,8 µs
contra 21,5 µs em modo texto — redução de 13 % em uma métrica composta
inteiramente por cauda. Em métricas de corpo da distribuição, o deslocamento
esperado é menor.

**Esses 13 % não medem o efeito da sessão gráfica; medem o efeito dela numa
sessão ociosa.** A tabela da §6 registra nove coletas na mesma máquina: oito
ficam entre 21,5 e 30,9 µs, e a coleta **A** fica em **515,5 µs**, vinte vezes
as demais. A distância entre 24,8 µs e 515,5 µs excede em uma ordem de grandeza
a distância entre 24,8 µs e o modo texto — e as duas pontas foram medidas com
sessão gráfica ativa.

A leitura que os dados sustentam é que a contribuição da sessão gráfica **não é
constante aditiva**: depende de quanto a sessão trabalhou durante a coleta. O
§6.6.5 dá o mecanismo — a reativação do *power gating* é agendada por atividade
gráfica, e nos dois rastros o padrão periódico foi precedido de redesenho de
tela. Uma coleta que corre com a sessão parada paga 13 %; quanto paga uma que
corre com a sessão em uso não está medido, e a coleta A é compatível com valor
muito maior.

A especificação foi corrigida em `metodologia.md`: coletas cuja grandeza de
interesse seja dispersão, jitter ou cauda de distribuição devem ser executadas
em modo texto.

#### O confundimento entre memória e reinício, resolvido

A versão anterior desta seção registrava como limitação permanente que as
coletas A e C diferiam em duas variáveis — configuração de memória e reinício
— e que separá-las exigiria a remoção física de um módulo, intervenção que não
estava disponível. A remoção foi feita em 24/09/2026, e o par foi medido.

**O desenho.** Quatro células, fatorial de perfil de memória por número de
módulos, todas em modo texto, com a configuração da BIOS conferida por programa
contra o que o nome da coleta declara. As duas células a 4800 MT/s correm a
campanha de isolamento completa e diferem **apenas** no número de módulos.

```
  celula                      mediana   maior   acima da janela
  ------------------------   --------  ------  ----------------
  4800 MT/s, canal unico       22,1 us  38,6 us          1 / 20
  4800 MT/s, canal duplo       21,5 us  35,1 us          1 / 20

  Mann-Whitney  U = 229   z = +0,784   p = 0,433
```

As duas distribuições são unimodais entre 14 e 38 µs. Não há modo alto em
nenhuma das duas.

**O desfecho.** A diferença entre canal único e canal duplo é de 0,6 µs e não
se sustenta ao nível de 5 %. Para comparação, as coletas A e C — as mesmas
duas configurações de memória, medidas com sessão gráfica — diferiam em
490 µs, de 515,5 para 25,2 µs.

A configuração de memória não produz o efeito que lhe era atribuído. A
hipótese registrada em 23/09, de que a diferença A×C vinha da atividade da
sessão gráfica e não da memória, fica **sustentada**: com a sessão gráfica
ausente, a variável que restava deixa de produzir efeito mensurável.

> **O que isso custou e o que ensinou.** A atribuição anterior não era
> arbitrária — configuração de memória era a única variável conhecida quando
> ela foi escrita. O erro não estava em atribuir; estava em atribuir a única
> variável observada sem declarar que havia uma não observada. O `ambiente.txt`
> passou a ser gravado por isso.

**O fatorial, de passagem.** As quatro células medem também o que cada fator
compra, e o mecanismo confere:

| fator | 1 núcleo | 4 núcleos | 12 núcleos |
|---|---:|---:|---:|
| canal, a 4800 (1 → 2 módulos) | −8,4 % | −37,6 % | −44,6 % |
| velocidade, a 2 módulos (4800 → 6000) | −11,0 % | −12,1 % | −26,3 % |

Dobrar canais compra **banda**: o efeito cresce com o paralelismo e é quase
nulo num núcleo só. Aumentar a frequência compra **latência e banda**: o efeito
é aproximadamente constante nos núcleos baixos e cresce nos altos. O acesso
isolado (`K = 1`), que mede latência pura, move −12,6 % com a velocidade.

#### Questões em aberto

- **Natureza do trabalho executado pelo `gfx_off`** durante centenas de
  microssegundos. O rastreamento identifica a função de entrada, não as
  operações internas.
- **Magnitude do efeito da desativação do *power gating*.** A intervenção foi
  executada (§6.6.7) e separa a atribuição "GPU" da atribuição "sessão
  gráfica": com a sessão viva, desligar o GFXOFF elimina as janelas com evento
  de centenas de microssegundos — cinco de oito contra zero de oito, Fisher
  exato p = 0,0256. O que permanece indeterminado é a **magnitude**: oito
  pares, e o desfecho é uma taxa de ocorrência que depende de quanto a GPU é
  usada na janela, grandeza que este desenho não controla.

  Dois dos três caminhos de desativação levantados em 24/09/2026 continuam
  fechados, e ficam registrados porque a falha de cada um é informativa:

  | caminho | desfecho |
  |---|---|
  | `amdgpu.pg_mask=0` na linha de boot | **tela preta.** É máscara, e zero apaga também os flags do bloco de display |
  | máscara com apenas o bit de `GFX_PG` | o valor vive em `amd_shared.h`, e os `linux-headers` instalados trazem apenas `Makefile` e `Kconfig` sob `drivers/` — nenhum cabeçalho |
  | `debugfs`, `amdgpu_gfxoff` | **é o que funcionou.** Ver §6.6.7 |

  Os contadores `amdgpu_gfxoff_count` e `amdgpu_gfxoff_residency` continuam sem
  servir: a leitura não retorna em dois segundos. Isso é consistente com a
  própria hipótese — ler o estado do bloco GFX exige acordá-lo —, mas travar é
  o oposto de medir. A intervenção não precisou deles.
- **Magnitude do deslocamento entre sessão gráfica e modo texto.** A
  comparação foi feita uma vez, em 24/09: dez dos 198 rótulos passaram de 5 %,
  e a leitura dos dez está na §6.7 — sete são artefato da métrica ou do regime
  de frequência, não da sessão gráfica. Uma comparação não é uma série, e a
  separação entre os dois efeitos não foi medida com desenho próprio.
- **Generalidade do achado.** A medição foi obtida em uma máquina, com GPU
  integrada AMD e driver `amdgpu`. Plataformas com GPU discreta ou com outro
  driver não estão cobertas por esta evidência.

---

## 7. Validação

```bash
./scripts/test-all.sh l1     # aritmética da janela e parser, sem privilégio
./scripts/test-all.sh l2     # a sonda roda e relata de forma coerente
```

**L1** ([`tests/test_l1.cpp`](tests/test_l1.cpp)) confere o que não depende de
máquina: os 67,2 ns por quadro, o escalonamento da janela com descritores e
taxa, a classificação em baldes, e as três formas de linha que
`/proc/interrupts` tem — inclusive a armadilha de a descrição do vetor virar
contagem numa quinta CPU inexistente.

**L2** ([`tests/l2_run.sh`](tests/l2_run.sh)) não afirma nada sobre o **valor**
das paradas. Esse valor depende da máquina e é o objeto da medição; um teste que
exigisse um limite seria medição disfarçada de asserção, e falharia em máquina
carregada pelo motivo certo. O que ele verifica é o contrato: a sonda mede,
classifica, relata a janela, recusa parâmetro inválido com código distinto, e
**declara** quando `/proc/interrupts` não está legível em vez de calar.

---

## 8. Limitações

- **Não há `imissed` aqui.** O elo entre parada e pacote perdido exige NIC fora
  do kernel, e esta máquina não a tem — o mesmo bloqueio do módulo de RX/TX. A
  janela da §1 é a ponte teórica, e está declarada como cota inferior.
- **P3 e P4 exigem reinício e permanecem sem coleta.** O procedimento é
  viável por entrada de GRUB de boot único, o mesmo mecanismo empregado na
  coleta em modo texto (§6.6.6).
- **A sonda mede uma CPU por vez.** Ruído correlacionado entre CPUs, que
  importa num pipeline de vários lcores, não aparece.
- **A fonte do modo alto está estabelecida; o que ela faz, não.** Trata-se do
  trabalho `amdgpu_device_delay_enable_gfx_off`, executado em *workqueue* por
  CPU (§6.6.5). A supressão da sessão gráfica o elimina nos dois instrumentos
  (§6.6.6), e a desativação do *power gating* com a sessão gráfica **mantida**
  também o elimina (§6.6.7) — o que fecha a atribuição por intervenção.
  Permanecem indeterminadas as operações que a função executa durante centenas
  de microssegundos: o rastreamento nomeia a função de entrada, não o trabalho
  interno.
- **As coletas com sessão gráfica estão sujeitas a uma fonte de ruído não
  declarada no protocolo.** A condição "máquina exclusiva, navegador fechado"
  não exclui o compositor, o servidor de display e o driver da GPU. O efeito
  sobre as medianas publicadas é limitado — a mediana da maior parada variou
  13 % entre as duas condições (§6.7) —, mas percentis altos e máximos medidos
  nessa condição incorporam a fonte.
- **O deslocamento entre sessão gráfica e modo texto foi medido uma vez.** Em
  24/09, dez dos 198 rótulos passaram de 5 %; a leitura está na §6.7 e a maior
  parte é artefato da métrica ou do regime de frequência. Uma comparação não
  é uma série.
- **O regime de frequência muda com a condição, e isso não é controlado.** Com
  sessão gráfica a CPU mede a 5,56–5,61 GHz; em modo texto parte de 4,33 GHz e
  sobe durante a execução, porque nada a esquenta antes. Modo texto não é
  apenas "mais limpo": ele troca o regime, e a §1.2 da
  [metodologia dos fundamentos](../../../docs/01-fundamentos/metodologia.md)
  manda declarar qual dos dois se mediu.
- **Vinte execuções por braço dão pouco poder.** O braço E produziu p = 0,028
  contra a condição sem pressão e a réplica não confirmou (§6.6.3). Nenhuma
  conclusão deste tópico repousa sobre um único par de coletas.
- **P1 exige privilégio** que a máquina de referência pede por senha. **P2 foi
  coletado** e o desfecho está na §6.6.1.

---

## 9. Referências

- [`isolcpus`, `nohz_full`, `rcu_nocbs`, `irqaffinity`][kparams] — parâmetros de
  linha de comando do kernel
- [Modo sem tique][nohz] — o que `nohz_full` faz e o que ele não faz
- [kthreads por CPU][kthreads] — como reduzir trabalho de kernel numa CPU
- [cgroup v2, partições de cpuset][cgroup] — isolamento sem linha de boot
- [Rastreador `osnoise`][osnoise] e [`timerlat`][timerlat] — atribuição de fonte
- [Detector `hwlat`][hwlat] — latência de firmware, invisível ao sistema
- [IEEE 802.3][ieee8023] — a sobrecarga de 20 bytes por quadro

[kparams]: https://docs.kernel.org/admin-guide/kernel-parameters.html
[nohz]: https://docs.kernel.org/timers/no_hz.html
[kthreads]: https://docs.kernel.org/admin-guide/kernel-per-CPU-kthreads.html
[cgroup]: https://docs.kernel.org/admin-guide/cgroup-v2.html
[osnoise]: https://docs.kernel.org/trace/osnoise-tracer.html
[timerlat]: https://docs.kernel.org/trace/timerlat-tracer.html
[hwlat]: https://docs.kernel.org/trace/hwlat_detector.html
[ieee8023]: https://standards.ieee.org/ieee/802.3/7071/

---

## 10. Exercícios

1. Calcule a janela para 25 GbE com quadro de 64 B e 2048 descritores. Compare
   com a de 10 GbE: o que acontece com a margem quando o enlace acelera?
2. Rode `stall_probe` por 60 s em P0 e identifique as três fontes de maior
   delta. Alguma surpreende?
3. Rode `ipi_provoker` noutra CPU e observe o contador `TLB` da CPU da sonda.
   Qual parâmetro de boot resolveria? Por que nenhum resolve?
4. Compare P5 com o irmão SMT ocioso e carregado. O efeito aparece como
   interrupção? Se não, onde aparece — e o que isso diz sobre usar
   `/proc/interrupts` como única evidência?
5. A sonda usa `CLOCK_MONOTONIC`. Troque por `rte_rdtsc` e explique o que
   precisaria mudar no programa para o resultado continuar válido sob governor
   `powersave`.
