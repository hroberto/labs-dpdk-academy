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

O TSC é mais barato de ler, e seria a escolha óbvia num laço apertado. Duas
razões pesaram mais: ele exige conhecer a frequência para converter, e essa
frequência muda com o governor — a mesma armadilha que a
[§2.2 do módulo 02](../../../docs/02-runtime-dpdk/README.md#22-por-que-essa-espera-existe-e-quando-ela-não-acontece)
documenta na calibração da EAL.

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
> desfecho está na §6.6.1: **efeito nulo sobre a cauda nesta máquina**. O P1 —
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

Oito coletas de 2026-09-23, cada uma com quatro células × cinco repetições ×
30 s, ordem das células permutada a cada repetição. Máquina declarada
exclusiva; navegador fechado. CPU medida: 2 (irmão SMT: 14). Provocador na
CPU 4.

Cada coleta declara o estado da máquina em que correu. A diferença entre elas
é o instrumento da §6.6: uma coleta sozinha mede; um par que difere em uma
variável decide.

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

> **A coleta E′ foi planejada como braço com pressão e correu sem nenhuma.** A
> condição de parada do consumidor de memória era absoluta — "alocar até haver
> 2 GiB em swap" — e o swap já estava nesse patamar por resíduo da coleta
> anterior. Ela nasceu satisfeita, nada foi alocado, e a campanha correu com
> 22,97 GiB disponíveis. O braço é válido; o que ele mede é a condição **sem
> pressão**, e é assim que entra nas contas.

**A coleta C é a publicada nas tabelas por célula abaixo.** Medianas de cinco
execuções:

| Célula | maior parada | preempções | paradas > 2 µs | `TLB` | `CAL` | `LOC` |
|---|---:|---:|---:|---:|---:|---:|
| P0 — só afinidade | 26,3 µs | 228 | 563 | 0 | 1 | 59 974 |
| P0 + provocador **thread** | 24,9 µs | 215 | 24 186 | **38 375** | 38 377 | 59 998 |
| P0 + provocador **processo** | 19,7 µs | 153 | 326 | **0** | 1 | 60 000 |
| P5 — irmão SMT carregado | 31,6 µs | 203 | 909 | 0 | 0 | 59 984 |

### 6.1 H1: a afinidade não segura a cauda

**Cinco das vinte execuções** da coleta C têm a maior parada acima da janela de
512 descritores, e a maior observada foi **752,9 µs** — 22 vezes essa janela, e
ainda **2,7 vezes** a janela de 4096 descritores. H1 se sustenta: basta uma
parada acima da janela para que a afinidade sozinha não garanta o orçamento.

O que a coleta mostra com mais força é a **forma** da distribuição, não a
contagem. Quinze execuções ficam entre 15,7 e 40,0 µs, e cinco saltam para a
casa das centenas. Não há nada entre 40 µs e 630 µs: a distribuição é
**bimodal**, com dois modos separados por mais de uma ordem de grandeza e nada
no meio.

Isso restringe o mecanismo antes de qualquer medição adicional. Uma cauda
contínua indicaria acúmulo de muitas fontes pequenas, cada uma somando um
pouco. Dois modos disjuntos indicam um **evento discreto** que ocorre ou não
ocorre, e cuja duração é propriedade dele, não da carga. A §6.6 persegue esse
evento.

A separação entre os modos se mantém nas oito coletas. O que muda entre elas é
**com que frequência** o modo alto acontece — de 1/20 a 16/20 — e não onde ele
fica.

### 6.2 H3: o escopo do IPI é o espaço de endereçamento, não a CPU

É o resultado mais limpo do tópico, e sai da comparação entre duas células que
diferem em **uma** coisa:

| | trabalho | CPU | espaço de endereçamento | `TLB` |
|---|---|---|---|---:|
| provocador **thread** | `mmap`/`munmap` de 8 MiB | 4 | **o mesmo** da sonda | 38 375 |
| provocador **processo** | idem | 4 | distinto | **0** |

Mesmo trabalho, mesma CPU, mesmo volume de memória. A diferença é de qual
espaço de endereçamento a thread faz parte, e o efeito **desaparece por
completo**.

As oito coletas atravessam duas configurações de memória, dois governors e
quatro condições de pressão. O contraste não se move:

| | A | B | C | C′ | E′ | D | E | E″ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| provocador **thread** | 38 135 | 38 104 | 38 375 | 38 342 | 38 385 | 38 294 | 38 206 | 38 221 |
| provocador **processo** | 0 | 1 | 0 | 0 | 1 | 0 | 0 | 1 |

A faixa do lado da thread é de 281 contagens sobre 38 mil — **0,7%** — enquanto
a maior parada variou por um fator de 21 entre as mesmas coletas. Um efeito que
ignora tudo que faz a cauda se mexer é propriedade do mecanismo, não do estado
da máquina.

É por isso que nenhum parâmetro de boot alcança essa fonte: ela não vem de fora
do processo. O que a remove é não alterar mapeamento no caminho quente.

### 6.3 A fonte que se pode contar não é a que mais dói

O provocador multiplica por **43** as paradas acima de 2 µs — de 563 para
24 186 — e ainda assim a célula dele tem mediana de maior parada **abaixo** da
do P0 limpo: 24,9 µs contra 26,3 µs.

Trinta e oito mil IPIs de TLB produzem trinta e oito mil paradas **curtas**. A
fonte mais fácil de instrumentar é a que menos importa para o orçamento, e a
relação se repete em todas as coletas, inclusive naquelas em que as medianas
são vinte vezes maiores.

A consequência prática é sobre o método, não sobre o TLB: **contar eventos de
uma fonte não mede o que ela custa**. Um painel que some interrupções por
segundo classificaria o provocador como o problema dominante, e estaria
apontando para o lugar errado.

### 6.4 Afinidade não impede preempção, e isso é medido

A sonda sofre entre **6,7 e 7,8 trocas de contexto involuntárias por segundo**
nas oito coletas, com a thread fixada. A taxa é estável; a maior parada, na
mesma amostra, varia por um fator de 21.

`sched_setaffinity` impede que a thread **migre**. Não impede que o escalonador
a **tire da CPU** em favor de outra tarefa executável: a sonda é `SCHED_OTHER`
como qualquer processo. O contador de `/proc/self/status` mostra isso sem
ambiguidade, e custa uma leitura por execução.

> **O que este número NÃO estabelece.** A correlação de posto entre contagem de
> preempções e maior parada é **ρ = 0,42** na coleta C — positiva e fraca. A
> contagem não carrega **duração**, e uma preempção longa conta igual a uma
> curta. Afirmar que a maior parada *é* uma preempção exigiria `osnoise`, que
> atribui fonte por evento.

A estabilidade da taxa entre coletas é, por si, informação sobre o mecanismo: a
**frequência** com que a thread perde a CPU não acompanha a cauda. Se o modo
alto fosse simplesmente "uma preempção qualquer", coletas com 1/20 e com 16/20
de modo alto precisariam de taxas de preempção diferentes, e elas não têm. O
evento discreto da §6.1 é mais raro que uma preempção comum, e distingui-lo
exige instrumento por evento.

### 6.5 O que a célula P5 não decidiu

A mediana da maior parada com o irmão SMT carregado (31,6 µs) está dentro da
faixa do P0 limpo (15,7 a 752,9 µs nas vinte execuções). Com cinco repetições e
essa dispersão, a célula não separa. A
[§5.1.1 do módulo 01](../../../docs/01-fundamentos/README.md#511-smt-duas-cpus-lógicas-não-são-dois-núcleos)
mede **2,29×** de efeito do irmão sobre **vazão**; sobre **cauda**, este
experimento não mede nada — e são perguntas diferentes.

### 6.6 A busca pela fonte do modo alto

A §6.1 estabelece o que se procura: um evento discreto, de centenas de
microssegundos, que ocorre em algumas execuções e não em outras. As §6.2 a §6.4
eliminam as fontes que o tópico sabe instrumentar — IPI de TLB produz paradas
curtas, e a taxa de preempção não acompanha o modo alto.

Cada candidato abaixo foi submetido a **uma intervenção de variável única**,
com o critério de refutação fixado antes da coleta.

#### 6.6.1 Estado C profundo — eliminado

A latência de saída do C3 nesta máquina é de **350 µs**, a mesma ordem de
grandeza do modo alto. O mecanismo proposto: a preempção tira a sonda da CPU, a
CPU fica ociosa, o `cpuidle` desce ao estado profundo, e a volta cobra os
350 µs. Todos os elos são plausíveis, e juntos explicariam o modo alto sem
precisar de fonte nova.

**Intervenção:** governor `performance` e todo estado com latência ≥ 20 µs
desabilitado nas 24 CPUs, o que nesta máquina desliga o C3 e preserva o C2
(18 µs). Coleta B contra coleta C, sem nenhuma outra diferença.

**Desfecho: eliminado.** 3/20 contra 5/20, medianas de 29,0 e 25,2 µs,
Mann-Whitney **p = 0,304**. O modo alto permanece com o C3 desligado.

A cadeia falha em algum elo — ou a CPU não chega a descer ao C3 nesse
intervalo, ou desce e a volta não custa o que a tabela de latência declara. Os
dois casos são distinguíveis, e exigem `cpuidle` instrumentado por evento.

#### 6.6.2 Disputa de CPU por outras tarefas — eliminado

Uma tarefa executável concorrente explicaria paradas longas sem aparecer em
`/proc/interrupts`: a sonda perde a CPU e espera a fatia da outra.

**Evidência:** o `sysstat` registrou **fila de execução igual a 1** tanto na
coleta A quanto na C, com carga média de 1,69 e 1,10. A coleta A tem 16/20 de
modo alto e a C tem 5/20, com a mesma fila.

**Desfecho: eliminado.** A fila de execução não distingue os dois regimes.

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

### 6.7 O que permanece aberto, e o que falta para fechar

| Candidato | Desfecho | Evidência |
|---|---|---|
| IPI de invalidação de TLB | produz paradas **curtas** | §6.2, §6.3 |
| preempção comum | taxa não acompanha o modo alto | §6.4 |
| estado C profundo | **eliminado** | B × C, p = 0,304 |
| disputa de CPU | **eliminado** | fila de execução = 1 em A e C |
| pressão de memória como estado | **não sustentado** | réplica E″, p = 0,269 |
| atividade de recuperação | descritivo | §6.6.4 |
| configuração de memória, reinício | **não separados** | confundidos entre si |

A última linha é a única variável de pé entre A e C, e ela é dupla: instalar o
segundo pente exigiu reiniciar, e as duas mudanças não podem ser separadas por
software. Separá-las exige remover o pente e recoletar — intervenção física,
registrada aqui como o experimento que falta, não como pendência de redação.

**O instrumento que falta é o mesmo em todas as linhas.** Contagem agregada por
vetor e por processo não atribui **um evento** a **uma fonte**; ela só permite
eliminar candidatos por correlação ausente, que foi o que este tópico fez. O
`osnoise` do kernel rastreia por evento e diria, para cada parada individual,
quem ocupou a CPU. É o próximo passo, e a §8 o registra como limitação.

> **O que estas cinco intervenções estabelecem, mesmo sem a causa.** Três
> candidatos plausíveis foram eliminados por medição, e um quarto não
> sobreviveu à réplica. Um material que afirmasse qualquer um deles por
> compatibilidade de escala estaria hoje publicando uma explicação falsa —
> duas delas tinham a ordem de grandeza certa. **Compatibilidade de escala
> torna uma hipótese testável, não verdadeira**, e é a diferença entre as duas
> coisas que este tópico demonstra na prática.

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
- **P3 e P4 exigem reiniciar**, e ficam para uma sessão com a máquina dedicada.
- **SMI não é observável** sem `hwlat`, que precisa da máquina quieta por muito
  tempo. Se houver SMI acima da janela, nenhum perfil zera o descarte — e o
  texto dirá isso quando houver medição.
- **A sonda mede uma CPU por vez.** Ruído correlacionado entre CPUs, que
  importa num pipeline de vários lcores, não aparece.
- **O modo alto da distribuição bimodal não tem fonte atribuída, e é a
  limitação principal do tópico.** Quatro candidatos foram submetidos a
  intervenção e nenhum sobreviveu: estado C profundo, disputa de CPU, pressão
  de memória como estado e atividade de recuperação (§6.6). `/proc/interrupts`
  não o explica: na execução de 723 µs da coleta A os únicos vetores foram
  `LOC` (59 958), `NMI` (4) e `PMI` (4), e nenhum deles dura centenas de
  microssegundos.
- **O instrumento disponível não atribui evento a fonte.** Contagem agregada
  por vetor e por processo permite **eliminar** candidatos, que foi o que as
  oito coletas fizeram; não permite **identificar** a causa de uma parada
  individual. Para isso é preciso `osnoise`, que rastreia por evento.
- **A configuração de memória e o reinício não foram separados.** Instalar o
  segundo pente exigiu reiniciar, e nenhuma intervenção de software desfaz uma
  das duas mudanças sem a outra. É a única variável de pé entre as coletas A e
  C, e separá-la exige remover fisicamente o pente.
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
