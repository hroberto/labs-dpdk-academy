# Metodologia e reprodutibilidade — módulo 01

*Read this in [English](metodologia.en.md).*

> Anexo de [Fundamentos](README.md). O corpo do módulo publica **o que muda o
> modelo mental**; este arquivo guarda **o que prova que a medição foi feita
> direito**.
>
> A separação não é cosmética. Uma autópsia de benchmark ensina muito — "em
> microbenchmark, desmonte antes de publicar" é das lições mais úteis daqui —
> mas ensina *sobre medição*, não sobre o custo da fronteira kernel/usuário. No
> meio da aula, ela sequestra a aula. Aqui, ela é a aula.

---

## 1. §2 — as duas correções do `custo-syscall`

A tabela de [§2](README.md#2-a-fronteira-user-space--kernel-space) publica três
números: chamada de função, `clock_gettime` pelo vDSO e syscall real. Chegar
neles exigiu duas correções, e as duas são instrutivas por razões diferentes: a
primeira é um erro de **instrumento**, a segunda é um erro de **declaração de
regime**.

### 1.1 O compilador apagou a chamada

> **Esta tabela já publicou 0,115 ns e "294×", e os dois estavam errados.** A
> função de referência não tinha argumento nem efeito colateral e devolvia
> constante, então o GCC a classificou como `const`, dobrou a chamada no
> literal e a içou para fora do laço — `__attribute__((noinline))` impede
> *inlining*, não propagação interprocedural de constante. O laço medido era
> `movq $0x2a, sumidouro` duas vezes, sem nenhuma instrução `call`, e a razão
> comparava uma syscall com dois *stores*.
>
> A correção foi tornar a função opaca ao compilador, com `asm volatile` e
> clobber de memória. Confira que a chamada existe antes de confiar no número:
>
> ```bash
> objdump -d build/docs/01-fundamentos/medicoes/custo-syscall | \
>     awk '/<m_funcao>:/,/^$/' | grep call
> ```
>
> Fica o método, que vale além deste caso: **em microbenchmark, desmonte antes
> de publicar.** Um laço rápido demais é hipótese de erro de medição antes de
> ser resultado.

### 1.2 A razão publicada era de outro regime

> **A RAZÃO 36× É DO REGIME FRIO, e isto foi medido em 16/09/2026.** A tabela
> acima é transcrição fiel de uma execução — mas de uma **primeira execução após
> ociosidade**, e nesse regime a chamada de função mede 0,92 ns. Oito execuções
> seguidas, com a máquina já em uso, dão 0,72 a 0,75 ns para a mesma chamada, e a
> razão sobe para **45× a 49×** (mediana 46×).
>
> Os dois regimes são reais e reprodutíveis, cada um com dispersão interna baixa
> — a tabela acima mostra 0,4% de amplitude. O que faltava era **declarar em qual
> deles se mediu**.
>
> O efeito é o mesmo que o [submódulo de benchmarking](../../trilha/03-performance/01-benchmarking/)
> mede e explica: a primeira execução após ociosidade sai ~30% alta na operação
> mais curta. Aqui ele não inflou um número solto — inflou o **denominador** de
> uma razão, e por isso a razão saiu para **menos**: 33,5/0,92 = 36, contra
> 33,8/0,73 = 46.
>
> **O argumento desta seção não muda**, porque ele nunca dependeu da razão: sai de
> 33,8 ns contra 67,2 ns de orçamento, e a chamada de função não entra na conta.
> Mas a razão é a frase que as pessoas repetem, e ela estava 22% baixa.
>
> Reproduza: rode `custo-syscall` uma vez depois de alguns minutos de máquina
> parada, e depois oito vezes seguidas. A diferença aparece na primeira linha.

### 1.3 O que fica das duas

| Correção | Classe do erro | Lição que sobrevive |
|---|---|---|
| 0,115 ns / 294× | o instrumento não media o que dizia medir | desmonte o binário antes de publicar |
| 36× contra 46× | a medição estava certa, o regime não estava declarado | diga se mediu a frio ou em regime |

E uma observação que vale para o documento inteiro: **nenhuma das duas mudou a
conclusão do §2**. Ela sai de 33,8 ns contra 67,2 ns de orçamento, e a chamada
de função não entra nessa conta. O que as duas atingiram foi a **razão**, que é
a frase de efeito — exatamente a parte que as pessoas repetem, e por isso a que
mais precisa estar certa.

---

## 2. §4.1 — o desenho do `custo-traducao`

A [§4.1](README.md#41-memória-virtual-o-que-significa-traduzir-um-endereço)
publica a diferença entre páginas de 4 KB e hugepages de 2 MB. Três decisões de
desenho sustentam esse número, e nenhuma delas muda o modelo mental do leitor —
elas provam que a medição isola o *page walk* de todo o resto.

### 2.1 O que fica fora do cronômetro

**O que fica fora do cronômetro, de propósito.** Medido na máquina de
referência, uma amostra de 512 MB:

| Etapa | Custo | Por que fica fora |
|---|---|---|
| `mmap` de 512 MB | ~0 ms | só cria o mapeamento; nenhuma memória existe ainda |
| `memset` da região | 88 ms (4 KB) / 46 ms (2 MB) | **força as faltas de página aqui**, não no laço |
| sorteio e montagem da cadeia | ~215 ms | escrever 8,4 M ponteiros não é o objeto do teste |
| `free` do vetor de ordem (64 MB) | — | devolvido antes do primeiro carimbo |
| **laço cronometrado** | **~3 500 ms** | ← é só isto que entra na conta |

O `memset` é o item importante dessa lista, e o número de faltas de página que
ele provoca é a própria aritmética da seção aparecendo no contador do sistema:

```
  páginas de 4 KB:  131 072 faltas de página   (512 MB ÷ 4 KB)
  hugepages de 2 MB:    256 faltas de página   (512 MB ÷ 2 MB)
```

Sem esse pré-toque, a primeira volta do ciclo pagaria uma falta de página a cada
página nova — microssegundos cada — e a medição publicaria o custo de **criar**
o mapeamento, não o de **traduzi-lo**. Repare, de passagem, que o `memset` em si
já custa quase o dobro com páginas de 4 KB: 131 072 entradas no kernel contra
256.

### 2.2 Por que a região tem exatamente 512 MB

O tamanho não é arbitrário. Ele é o único valor que satisfaz quatro restrições
ao mesmo tempo, e entender isso é entender o experimento:

| A região precisa ser… | Senão… | Nesta máquina |
|---|---|---|
| muito maior que o L3 | o percurso mede cache, não memória | L3 = 32 MB por bloco |
| muito maior que o alcance da TLB com 4 KB | o lado "ruim" não falta, e não há o que medir | exige 131 072 entradas |
| pequena o bastante para caber no alcance com 2 MB | o lado "bom" também falta, e a diferença some | exige 256 entradas |
| pequena o bastante para a reserva ser viável | o teste vira privilégio de máquina grande | 256 hugepages = 512 MB |

As duas linhas do meio são o coração do desenho. Nenhuma TLB de segundo nível de
x86 atual guarda mais que alguns milhares de entradas — ou seja, **131 072
entradas não cabem de jeito nenhum**, e quase todo acesso do lado de 4 KB paga a
caminhada. Já **256 entradas cabem com folga em qualquer uma delas**, e o lado
de 2 MB acerta quase sempre. O experimento força os dois extremos e publica a
distância entre eles.

É também a resposta do [exercício 6](README.md#exercícios): encolher a região para 4 MB
faz a vantagem sumir, porque aí os dois lados cabem — 1 024 entradas de 4 KB
ainda cabem na TLB, e 4 MB inteiros cabem no L3.

### 2.3 A área reservada: 256 hugepages, e por que a receita pede 512

**`MAP_HUGETLB` não negocia.** Diferente das *transparent hugepages*, que o
kernel promove em segundo plano quando consegue, essa flag serve-se de um
**pool reservado antecipadamente** e **não cai para 4 KB** quando ele não basta:
o `mmap` falha com `ENOMEM`, e acabou.

É essa ausência de silêncio que permite ao programa usar uma medição real como
teste de capacidade — se `amostra_2m()` devolve erro, é porque a reserva não
existe:

```c
if (amostra_2m() < 0) { /* ... */ return 77; }   /* 77 = PULADO no Meson */
```

O código de saída 77 está lá por um motivo documentado no
[`meson.build`](medicoes/meson.build): sair com 0 fazia a suíte reportar verde
**sem que nada tivesse sido medido**, e como `HugePages_Total=0` é o padrão da
maioria das máquinas e do runner de CI, o falso verde era a regra, não a
exceção.

**A conta da reserva:**

```
região medida          512 MB
tamanho da hugepage      2 MB
                      ────────
mínimo necessário       256 hugepages
```

A receita do documento pede **512** (`sudo sysctl -w vm.nr_hugepages=512`), o
dobro do mínimo. A folga não é desperdício; ela cobre três situações reais:

- **o pool é global.** Outro processo — um DPDK em execução, um teste anterior
  que não encerrou — pode estar segurando parte dele.
- **em máquina com mais de um nó NUMA o pool é dividido entre os nós.** Um
  `mmap` de 512 MB precisa de 256 páginas **no nó onde a memória será tocada**;
  com 512 páginas repartidas entre dois nós, sobra exatamente o mínimo e nenhuma
  margem.
- **a reserva pode ser parcialmente atendida** — o próximo ponto.

**`sysctl` não falha alto, e este é o erro operacional mais comum.** Se a
memória estiver fragmentada, o kernel reserva *o que conseguir* e o comando sai
com sucesso do mesmo jeito. O único jeito de saber é ler de volta:

```bash
sudo sysctl -w vm.nr_hugepages=512
grep -E "HugePages_Total|HugePages_Free|HugePages_Rsvd|Hugepagesize" /proc/meminfo
#   Total = o que o kernel CONSEGUIU reservar (pode ser menor que 512)
#   Free  = ainda não entregues a ninguém
#   Rsvd  = prometidas a um mmap que ainda não as tocou
```

Se `HugePages_Total` voltar abaixo de 256, a medição vai pular. Em máquina ligada
há muito tempo, reservar cedo resolve — ou no boot, que é a única forma confiável
em memória fragmentada:

```bash
# persistente, aplicado no boot
echo "vm.nr_hugepages = 512" | sudo tee /etc/sysctl.d/10-hugepages.conf
# ou na linha de comando do kernel: hugepagesz=2M hugepages=512
# por nó NUMA, quando houver mais de um:
echo 256 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
```

**A reserva sai da memória do sistema.** Páginas reservadas deixam de estar
disponíveis para qualquer outra coisa: não entram em `MemAvailable`, não são
recuperadas sob pressão e não vão para swap. 512 páginas de 2 MB são **1 GB
retirado da máquina** enquanto a reserva existir.

> **Esta reserva não é a mesma do
> [`preparar-hugepages.sh`](../../scripts/preparar-hugepages.sh).** Aquele
> script monta um **hugetlbfs gravável**, necessário para o modelo
> primário/secundário do módulo 02, onde dois processos precisam mapear o mesmo
> *arquivo*. `custo-traducao.c` usa memória **anônima** (`MAP_ANONYMOUS |
> MAP_HUGETLB`) e não precisa de ponto de montagem nenhum: precisa apenas que o
> **pool exista**. Reservar sem montar basta aqui; montar sem reservar, não.

---

## 3. §5.2 — por que o regime de thread única foi descartado

A [§5.2](README.md#quanto-custa-dormir--e-o-que-exatamente-é-caro) mede o mutex
sem disputa em **8,5 ns**, e declara que todas as medições rodam com outra
thread presente no processo. Havia um número menor disponível, e ele foi
descartado — a razão é metodológica, e é das mais instrutivas do módulo.

> **Aparte: o caminho rápido da glibc, e por que ele foi descartado.**
>
> A glibc mantém um atalho para processos de **thread única**, no qual o mesmo
> mutex custa ~2 ns em vez de 8,5 — não há com quem competir, então a instrução
> atômica é pulada. O número é real, e mesmo assim inválido como referência.
>
> A primeira razão é que nenhum programa concorrente o desfruta. A segunda é
> pior: o atalho é perdido **permanentemente** na primeira criação de thread, e
> não volta nem depois de a thread ser juntada.
>
> ```
>   antes de qualquer thread      :  2.40 ns
>   apos criar E JUNTAR uma thread:  8.99 ns
>   __libc_single_threaded = 0
> ```
>
> A consequência prática é fatal para a medição: o valor dependia da **ordem** em
> que as medições rodavam dentro do programa, variando de 2,4 a 9,0 ns conforme
> a posição no arquivo. **Medição que depende da ordem em que se mede não é
> medição** — por isso o regime de thread única foi abandonado, e a tabela acima
> reporta só o caso realista.

---

## 4. §10 — o estado de PTI desta máquina

A [§10](README.md#por-que-a-syscall-aqui-é-tão-barata) afirma que o PTI não
está ativo nesta máquina, e que por isso os 33,8 ns de syscall não são um custo
universal. A afirmação é **medida**, não inferida da arquitetura — ser AMD não
implica PTI desligado, porque a mitigação é configurável por parâmetro de boot.

As três conferências, com a saída literal. Nenhuma exige privilégio:

```bash
$ cat /sys/devices/system/cpu/vulnerabilities/meltdown
Not affected

$ grep -o '\bpti\b' /proc/cpuinfo
        (nenhuma saída — a flag `pti` só aparece quando PTI está ativo)

$ cat /proc/cmdline
BOOT_IMAGE=/boot/vmlinuz-7.0.0-31-generic root=UUID=<omitido: identifica a máquina> ro quiet splash amd_iommu=on iommu=pt crashkernel=2G-4G:320M,4G-32G:512M,32G-64G:1024M,64G-128G:2048M,128G-:4096M
```

As três dizem coisas diferentes, e as três são necessárias:

| Conferência | O que ela estabelece |
|---|---|
| `vulnerabilities/meltdown` | o kernel classifica esta CPU como não afetada pelo Meltdown clássico |
| flag `pti` em `/proc/cpuinfo` | **PTI não está ativo** — é esta que prova o estado, não a anterior |
| `/proc/cmdline` | nada foi forçado por parâmetro: não há `pti=on`, `pti=off` nem `nopti` |

A terceira fecha a porta para a objeção óbvia. Sem ela, um leitor poderia supor
que o estado observado veio de configuração manual, e não do padrão do kernel
para esta CPU.

> **Uma distinção que vale manter separada.** "Esta CPU não é afetada pelo
> Meltdown clássico" **não** é o mesmo que "esta CPU não tem vulnerabilidades de
> execução especulativa". São afirmações diferentes, e só a primeira está aqui.

---

## 5. O `0,397` da `atomica relaxed`, e quem o explicou

A campanha de variação entre execuções de 19/09/2026 encontrou no
`custo-espera` um valor que **nenhuma medição de dentro da máquina explicou** —
e a causa acabou vindo de fora dela. O caso fica registrado porque a forma de
achar a resposta vale mais que o número.

**O que foi observado.** Nove execuções do mesmo binário, com uma execução de
aquecimento descartada, nove amostras cada:

```
com ASLR:  0,270  0,205  0,397  0,205  0,205  0,205  0,397  0,205  0,262
sem ASLR:  0,206  0,397  0,205  0,206  0,206  0,205  0,206  0,206  0,206
```

Desligar a aleatorização de endereços com `setarch -R` elimina os valores
**intermediários** (0,262 e 0,270) — viés de leiaute, o que a
[§9.1](README.md#91-as-quatro-escalas-de-dispersão-e-o-que-cada-uma-não-alcança)
descreve. Sobrava o `0,397`, **1,94 vez** o valor modal, grande demais para a
rampa de frequência, cuja amplitude aqui é 29%.

**O que a instrumentação não achou.** Medindo frequência antes, depois e máxima
durante cada execução, mais trocas de contexto e interrupções, o fenômeno não
reapareceu em 14 execuções. Sem a sonda, outras 14 também limpas. Vinte e oito
seguidas sem uma ocorrência, contra taxa-base de 1 a 2 em 9 nas campanhas.

**A variável faltante era ambiental.** Durante as campanhas havia **vídeo sendo
decodificado** na máquina; durante a investigação, não. Isso é testável, e o
teste fecha:

```
  sem carga externa          0,205  0,206  0,206  0,208  0,206
  com carga nos irmaos SMT   0,346  0,347  0,345  0,347  0,346
```

A razão sob carga é **1,69×**; a observada na campanha, **1,94×**. As duas
ficam entre 1 e os **2,29×** que a [§5.1.1](README.md#511-smt-duas-cpus-lógicas-não-são-dois-núcleos)
mede para um irmão SMT saturando as ALUs — que é o intervalo em que cai um
decodificador de vídeo, ocupando o irmão em parte do tempo.

**O que fica de método, e é o motivo desta seção existir.** Nenhum instrumento
interno ao processo podia ver isso: frequência, contexto e interrupção são
consequências, não a causa. **A variável omitida não estava no programa nem na
máquina — estava em quem mais usava a máquina.** É o limite prático da régua da
[§9.1](README.md#91-as-quatro-escalas-de-dispersão-e-o-que-cada-uma-não-alcança):
as três primeiras escalas de dispersão pressupõem que o resto do sistema não
mudou, e essa premissa não é verificável de dentro.

**A quarta escala nasceu desta lacuna, e não a fecha.** Ela mede o efeito do
estado da máquina alternando ócio e medição — o que alcança um estado que o
próprio protocolo produz. Carga externa e imprevisível, como a deste caso,
continua fora: para vê-la é preciso olhar para fora do processo, e nenhum dos
quatro instrumentos faz isso.

---

### 5.1 O `0,397` é `1,818 / f`, e o `0,205` é `1,125 / f`

A seção acima identificou a causa certa — carga no irmão SMT — por eliminação e
por um teste de carga que reproduziu a razão. O que faltava era a grandeza
invariante: **a medição não tem um valor em nanossegundos; tem um valor em
ciclos**, e tudo o que se observou em nanossegundos é esse número dividido pela
frequência do momento.

**O instrumento.** O `custo-espera` dá a esta medição nove amostras de 2 milhões
de rodadas — cerca de 4,5 ms de trabalho. Uma CPU não sai da frequência base
nesse tempo. Investigar a distribuição pelo programa inteiro custaria 27 s por
3,6 ms de dado útil, então a pergunta pediu instrumento próprio:
[`sonda-relaxed.c`](medicoes/sonda-relaxed.c), que repete o laço original —
mesmo alinhamento, mesma ordem de memória, mesmo sumidouro volátil — e publica
**as amostras individuais com a frequência de cada uma**, em vez do resumo.

**O que 20 000 amostras mostram.** Com o núcleo sozinho, e depois que a
frequência estabiliza:

```
  bloco          ns/operacao   GHz    ciclos
  -----------   -----------  -----   -------
      1- 2000        0.2074   5.44     1.129
   2001- 4000        0.2034   5.53     1.125
   4001- 6000        0.2036   5.53     1.125
   6001- 8000        0.2036   5.53     1.125
   8001-10000        0.2037   5.53     1.125
  10001-12000        0.2037   5.53     1.126
  12001-14000        0.2036   5.53     1.125
  14001-16000        0.2036   5.53     1.125
  16001-18000        0.2036   5.53     1.125
  18001-20000        0.2038   5.53     1.126
```

Os nanossegundos se movem; os **ciclos não**. E com o irmão SMT saturado por um
laço em `taskset -c 12`, outras 20 000 amostras:

```
      1- 5000        0.3378   5.38     1.817
   5001-10000        0.3379   5.38     1.817
  10001-15000        0.3381   5.38     1.818
  15001-20000        0.3380   5.38     1.818
```

**O modelo tem dois parâmetros e explica todos os valores já publicados:**

```
  ns por operacao = ciclos / frequencia

    ciclos = 1,125   nucleo sozinho
           = 1,818   irmao SMT saturado
```

| valor publicado | ciclos implícitos | frequência implícita |
|---:|---|---:|
| 0,205 | 1,125 | 5,49 GHz |
| 0,255 | 1,125 | 4,41 GHz |
| 0,262 e 0,270 | 1,125 | 4,29 e 4,17 GHz |
| 0,397 | 1,818 | 4,58 GHz |
| 0,410 | 1,818 | 4,43 GHz |

A verificação direta fecha na quarta casa: a sonda, executada fria, mede
**0,2597 ns** com a frequência lida em **4,33 GHz**, e `1,125 / 4,33` é
**0,2598**.

> **A razão de 1,94× da seção acima era `1,818 / 1,125 = 1,616` mais a
> diferença de relógio entre as duas observações.** A explicação estava certa;
> a razão medida misturava dois efeitos, e por isso não batia exatamente com o
> `1,69×` do teste de carga.

#### A atribuição ao ASLR não se sustenta

A seção acima atribui os valores **intermediários** (0,262 e 0,270) a viés de
leiaute, porque eles desapareceram ao desligar a aleatorização com `setarch -R`.
A atribuição é plausível e está errada: os dois braços daquele teste correram
em **sequência**, e o segundo herdou uma CPU já aquecida pelo primeiro.

Intercalando os braços, de modo que ambos vejam a mesma condição térmica:

```
  par 1:  com ASLR 0,2585   sem ASLR 0,2023     <- a primeira corrida e fria
  par 2:  com ASLR 0,2028   sem ASLR 0,2029
  par 3:  com ASLR 0,2028   sem ASLR 0,2027
  par 4:  com ASLR 0,2028   sem ASLR 0,2029
  par 5:  com ASLR 0,2028   sem ASLR 0,2028
  par 6:  com ASLR 0,2028   sem ASLR 0,2029
```

Os dois braços são indistinguíveis. O que produz o valor intermediário é a
**primeira corrida**, com ou sem ASLR — e a corrida fria some do segundo braço
de um teste sequencial por construção, não por efeito do leiaute.

> **O que sobrevive e o que cai.** Sobrevive a causa do modo alto: carga no
> irmão SMT, agora com a grandeza invariante medida. Cai a atribuição dos
> intermediários ao leiaute, que era um confundimento com o estado térmico. O
> teste que a separa é intercalar os braços, e ele é barato.

> **Os dois valores continuam publicados na tabela acima, e devem.** Eles foram
> medidos corretamente; o que caiu foi a explicação deles. Retratar a medição
> seria apagar o dado por causa de um erro que estava na leitura.

#### O que isto obriga em quem mede

Qualquer medição desta ordem de grandeza publicada em nanossegundos, sem a
frequência ao lado, é um número sobre um eixo não declarado. As três condições
que o projeto usa dão três respostas para o mesmo laço:

| condição | frequência típica | `atomic relaxed` |
|---|---:|---:|
| gráfico, `powersave` | ramp de 4,33 a 5,5 | 0,205 a 0,410 |
| texto, `powersave` | 4,33 a 4,95 | 0,255 |
| texto, `performance` | 5,58 estável | 0,205 |

Nenhuma está errada. As três medem o mesmo 1,125 ciclos.

## 6. Pré-registro: o segundo pente de memória

Esta seção é escrita **antes** da medição, e é a primeira vez que este
repositório faz isso. O motivo é que a oportunidade é boa demais para
desperdiçar: em 20/09/2026 o EXPO 6000 foi ligado na placa, e em três dias um
segundo pente entra no slot B2 — mesma CPU, mesmo kernel, mesmo binário, mesma
velocidade de memória. **Muda uma variável: o número de canais.**

Isolamento assim é raro. E ele responde a uma pergunta que a §4.2 do módulo 01
responde hoje sem ter medido.

### O que a §4.2 afirma, e o que o EXPO já sugeriu

O texto publicado diz, sobre os ~21 GB/s que doze núcleos alcançam juntos:

> *"é a banda da memória, e os dois caminhos chegam nela. Um núcleo sequencial
> a satura sozinho; oito núcleos dispersos precisam se juntar para isso."*

O EXPO deu o primeiro indício contra a segunda frase. Ele elevou a taxa por
canal em 25%, e o acesso sequencial de **um** núcleo não se mexeu:

| RAM, um núcleo | antes do EXPO | depois | variação |
|---|---:|---:|---:|
| `sequencial` (amortizado) | 0,200 ns | **0,195 ns** | **−2,5%** |
| `aleatorio` (amortizado) | 7,09 ns | 6,45 ns | −9,0% |
| `dependente` (latência) | 98,73 ns | 88,00 ns | −10,9% |

Latência caiu 11%, o acesso disperso 9% — e o sequencial praticamente não se
mexeu. Um número que não responde a memória mais rápida **não está limitado
pela memória**.

### As previsões, e o que refuta cada uma

Declaradas agora, com o critério de refutação junto. Esta é a parte que a
[§9.1](README.md#91-as-quatro-escalas-de-dispersão-e-o-que-cada-uma-não-alcança)
cobra e que o documento vinha devendo: afirmar que dois números são iguais
exige dizer **antes** qual diferença contaria como relevante.

| # | Previsão com canal duplo | Refutada se |
|---|---|---|
| 1 | `sequencial` de **um** núcleo **não se move** (< 5%) | subir mais de 20% |
| 2 | a vazão agregada de doze núcleos **sobe muito** (> 40%) | subir menos de 10% |
| 3 | a latência `dependente` muda pouco (< 5%) | mudar mais de 10% |
| 4 | `custo-comunicacao` não se move (< 5%) | mudar mais de 10% |

A 4 é o controle negativo: comunicação entre núcleos não toca a DRAM, então se
ela se mover, alguma coisa mudou que não é o canal, e as outras três perdem o
valor.

### O que cada desfecho obriga

**Se 1 e 2 se confirmarem**, a §4.2 fica mais precisa e mais curta: os ~21 GB/s
agregados **são** teto de banda, e a frase *"um núcleo sequencial a satura
sozinho"* está **errada** — aquele núcleo está limitado por si mesmo, não pela
memória. O texto passa a distinguir duas coisas que hoje ele funde.

**Se 2 falhar** — se o agregado também não subir —, o teto não é da memória, e
a explicação inteira daquela subseção precisa ser refeita, não corrigida.

**Se 1 falhar**, o EXPO e o canal movem o mesmo número em direções
inconsistentes, e o primeiro suspeito passa a ser o instrumento.

### O que o EXPO já decidiu, antes do pente

O pré-registro foi escrito para o segundo pente. O EXPO respondeu **duas das
quatro previsões** antes disso, e vale registrar que foi assim — a previsão
declarada continuou servindo para um experimento que não era o previsto.

A campanha de 20/09, cinco rodadas em máquina ociosa, com o aquecimento
descartado, comparada com os valores publicados:

```
  12 nucleos (agregado)      30,92 -> 21,27 ns/acesso    -31,2%   RESPONDE
  1 nucleo, sequencial        0,200 -> 0,195 ns/acesso     -2,5%   nao responde
```

**Previsão 1 confirmada, previsão 2 confirmada.** Memória 25% mais rápida
melhorou o agregado em 45% de vazão e não fez nada pelo núcleo sozinho. As duas metades
da frase da §4.2 se separam: o agregado **é** limitado pela banda; o núcleo
sequencial sozinho **não é** — ele está limitado por si mesmo.

A frase *"um núcleo sequencial a satura sozinho"* está, portanto, **errada**, e
o segundo pente não precisa decidir isso: ele vai servir de confirmação
independente, com outra intervenção sobre a mesma grandeza.

### E uma confirmação que a §4.1 declarava não ter

A [§4.1](README.md#por-que-a-diferença-é-11-ns-e-não-três-acessos-à-ram) explica
que o custo extra de tradução é servido pelo L3, e classifica a explicação como
*"compatível, não demonstrado"* — porque demonstrar exigiria contador de
hardware.

O EXPO produziu a evidência por outro caminho. Se a penalidade é servida pelo
L3, memória mais rápida **não deve** baratea-la:

```
  L3 dependente                  9,71 ->  9,73 ns    +0,2%
  DIFERENCA de traducao         10,65 -> 10,94 ns    +2,7%
  RAM dependente                98,73 -> 88,00 ns   -10,9%
```

A DRAM melhorou 11%, o L3 ficou em 0,2%, e a tradução **acompanhou o L3** com 2,7%. Não é
o contador de hardware que a seção pede, e não prova o caminho percorrido; mas
é uma predição arriscada que se confirmou, e o experimento original não
conseguia produzi-la.

### A linha divisória, como validação do conjunto

Vale o registro geral, porque ele diz mais sobre os instrumentos que sobre o
hardware. Das **56** medições que o `comparar-hardware.py` confronta hoje:

| Faixa | Quantas | O que há nela |
|---|---:|---|
| até 1,5% | **24** | cache, atômicas, travas locais — nada que toque a DRAM |
| 1,6% a 9,0% | 16 | caminhos mistos: parte do trabalho em cache, parte fora |
| 10,9% a 31,2% | **16** | DRAM e o *fabric* entre CCDs |

> **A faixa do meio existe, e uma versão anterior desta seção a omitia.** O
> texto dizia "doze não se moveram, dez se moveram", como se a divisão fosse
> limpa. Ela era limpa no conjunto menor que a ferramenta cobria então; com
> 56 comparações há dezesseis medições entre 1,6% e 9,0%, e apagá-las tornaria
> o argumento mais bonito do que os dados permitem.

O que sustenta a validação não é a ausência de meio-termo, e sim **os extremos
caírem onde o mecanismo prevê**. `laco sozinho`, `RAZAO com/sem irmao SMT`,
`L1d dependente` e `L3 dependente` saíram em **0,0%** — nenhum deles toca a
memória principal. O agregado de doze núcleos saiu em **31,2%**, o maior de
todos, e é o que mais disputa banda.

Instrumento que responde onde deve e fica quieto onde deve é a única evidência
possível de que ele mede o que diz medir.

### O confundimento do segundo pente, e como ele fica tratado

Acrescentar o pente muda **duas** coisas ao mesmo tempo: a capacidade vai de 16
para 32 GB e o canal vai de único a duplo. Atribuir a diferença inteira à banda
seria exatamente o erro que esta seção existe para evitar.

**O que dá para afirmar hoje, com registro.** O maior conjunto de trabalho do
conjunto de programas é de **512 MB** — `REGIAO_BYTES` no `custo-traducao.c`,
constante no fonte, que não cresce com a RAM instalada. Durante a coleta de
4800 a memória disponível ficou entre 7,0 e 7,5 GiB. Fator de catorze.

O `scripts/ambiente.sh` passou a registrar o disponível junto do total, e cada
braço carrega amostras durante a coleta. Antes disso a afirmação "a capacidade
nunca foi limitante" dependia da minha palavra.

**O que isso é, e o que não é.** É um argumento de mecanismo somado a um fato
registrado: capacidade sobrando não tem por onde alterar a latência de uma
cadeia dependente de 512 MB. **Não é um controle** — um controle mudaria a
capacidade mantendo o canal fixo.

**O controle existe, e tem custo próprio.** Os dois pentes no mesmo canal
(A1+A2) dariam 32 GB em canal único, isolando a capacidade. Mas DDR5 com dois
módulos por canal costuma forçar redução de velocidade, e isso introduziria uma
terceira variável — trocar um confundimento por outro.

**O desenho que eu proponho no lugar** aproveita o que já existe: um fatorial
2×2, velocidade cruzada com canal.

| | 4800 MT/s | 6000 MT/s |
|---|---|---|
| **16 GB, canal único** | coletado | coletado |
| **32 GB, canal duplo** | a coletar | a coletar |

Ele não separa capacidade de canal — nenhum desenho viável aqui separa. O que
ele entrega é melhor do que parece: **o efeito da velocidade medido nas duas
configurações de canal**. Se a mesma troca de 4800 para 6000 produzir o mesmo
efeito com um e com dois pentes, o instrumento está consistente, e a diferença
restante entre as linhas fica atribuível ao par capacidade+canal — declarado
como par, e não como banda.

### Desfecho: as quatro previsões, medidas

O segundo pente entrou em 23/09/2026. A coleta é
`2026-09-23-expo6000-canal-duplo`, mesmo protocolo e mesmo estado de máquina da
linha de base — `powersave`, C3 ativo, seis rodadas com a de aquecimento
descartada. Uma variável: o número de canais.

| # | Previsão | Limite declarado | Medido | Desfecho |
|---|---|---|---:|---|
| 1 | `sequencial` de um núcleo não se move | < 5% | −4,1% | **NÃO TESTÁVEL** |
| 2 | vazão agregada de doze núcleos sobe muito | > 40% | **+68,0%** | **confirmada** |
| 3 | latência `dependente` muda pouco | < 5% | **−1,8%** | **confirmada** |
| 4 | `custo-comunicacao` não se move | < 5% | **maior desvio 4,2%** | **confirmada** |

```
  1 nucleo, sequencial        0,195 -> 0,187 ns/acesso    -4,1%   <- instrumento
  12 nucleos, agregado        21,27 -> 12,66 ns/acesso   -40,5%
                              564,2 -> 947,9 M acessos/s +68,0%
  RAM dependente              88,00 -> 86,38 ns           -1,8%
  1 nucleo, custo-paralelismo  6,20 ->  5,85 ns/acesso    -5,6%   <- substituta
```

> **A previsão 1 não podia falhar, e por isso não conta.** A coluna
> `sequencial` do `efeito-cache` é limitada pelo laço que a mede, não pela
> memória: o acumulador forma uma cadeia carregada pelo laço com teto de cerca
> de um elemento por ciclo, e esse teto é o mesmo com o conjunto na L1d e com
> ele em DRAM. Um número que não pode se mover não tem como refutar uma
> previsão de que ele não se move.
>
> A previsão foi registrada de boa-fé e o desfecho medido está correto como
> aritmética. O que não existe é o **valor evidencial**: o critério de
> refutação — "subir mais de 20%" — era inalcançável por construção. A §4.2 do
> módulo 01 traz a ressalva do instrumento, e um
> [teste L2](README.md#42-cache-e-localidade) trava a armadilha.
>
> **A substituta está na última linha do bloco.** O `custo-paralelismo` mede um
> núcleo sozinho com o mesmo instrumento que mede os doze, e ali o número
> **pode** se mover: ele se moveu 14,5% quando a frequência mudou. Que tenha se
> movido só 5,6% com o canal é resultado, não teto. A previsão 1 seria melhor
> servida por esse instrumento, e é assim que fica registrada para a próxima
> configuração de hardware.
>
> **O fatorial de 24/09 refez esse par com pareamento melhor** e deu −11,0 a
> −11,6 % para a frequência contra −7,7 a −8,4 % para o canal. A leitura
> sobrevive — o núcleo sozinho responde mais à frequência —, com margem bem mais
> estreita do que estes 14,5 contra 5,6 sugerem.

**A previsão 4 é a que dá valor às outras duas.** `custo-comunicacao` mede
tráfego de linha de cache entre núcleos, que não toca a DRAM: se o canal
mexesse nele, a intervenção teria efeito onde não deveria e as demais
perderiam o sentido. As cinco medições do programa ficaram entre 0,0% e 4,2%,
com a razão entre irmão SMT e núcleo distinto parada em **2,29 → 2,29**.

Um instrumento que responde onde deve e fica quieto onde deve é a única
evidência possível de que ele mede o que diz medir — e desta vez isso foi
declarado antes, não observado depois.

> **E o controle negativo não protegeu contra o defeito da previsão 1.** Ele
> confere se a **intervenção** vaza para onde não deveria. O que derrubou a
> previsão 1 foi outra coisa: o **instrumento** dela ter um teto próprio, que
> nenhuma intervenção alcança. São falhas de famílias diferentes, e um controle
> negativo bem construído passa verde sobre a segunda.
>
> A pergunta que teria pego o defeito não é "a intervenção vazou?", e sim **"o
> que este número faria se a hipótese fosse falsa?"**. Para a previsão 1 a
> resposta era "o mesmo", e isso podia ter sido respondido antes de medir — ou
> depois, com o teste de variar o nível de cache e observar que o valor não se
> move. Fica registrada como a pergunta a fazer em todo pré-registro futuro.

<!-- cita-retratado: 14,5 14.5 31,2 31.2 5,6 5.6 40,5 40.5 7,2 7.2 -->

#### O que o desfecho obrigou a mudar

A seção previa: *"se 1 e 2 se confirmarem, a §4.2 fica mais precisa e mais
curta"*. Foi o que aconteceu. A frase *"um núcleo sequencial a satura sozinho"*
saiu do módulo 01, e a subseção passou a publicar as **duas** intervenções lado
a lado, porque elas medem a mesma grandeza por caminhos independentes:

| Intervenção | 12 núcleos | 1 núcleo | razão |
|---|---:|---:|---:|
| 4800 → 6000 MT/s, com 1 pente | −28,6% | −11,6% | 2,5× |
| 4800 → 6000 MT/s, com 2 pentes | −26,3% | −11,0% | 2,4× |
| 1 → 2 pentes, a 4800 MT/s | −44,6% | −8,4% | 5,3× |
| 1 → 2 pentes, a 6000 MT/s | −42,8% | −7,7% | 5,6× |

A segunda intervenção é a mais limpa das duas, e por uma razão de mecanismo:
**dobrar os canais dobra a banda sem tocar na latência**, enquanto trocar a
frequência move as duas coisas ao mesmo tempo. Confirmar a mesma assimetria
pelos dois caminhos é mais forte do que confirmar por um só.

> **Estes valores são de 24/09 e substituem os do bloco acima, que é de 23/09.**
> O bloco fica como está: ele registra o que aquela comparação deu, e reescrevê-lo
> apagaria o pré-registro em vez de completá-lo. O que mudou não foi a medição,
> foi o **pareamento**. O contraste de canal de 23/09 comparava uma coleta com a
> CPU fria, partindo de 4,33 GHz, contra outra quente e estável a 5,58 GHz —
> regime de frequência como terceira variável dentro de um contraste que se
> propunha a isolar canais.
>
> As quatro células de 24/09 medem cada fator nos **dois níveis** do outro, em
> condição única, e concordam entre si: a frequência move o mesmo com um pente
> ou dois, o canal move o mesmo a 4800 ou a 6000. O efeito de um núcleo é o que
> mais se desloca — de −5,6 % para −8,4 % —, porque é o mais sensível ao relógio
> e era o mais contaminado.

#### O fatorial 2×2 tem três células de quatro

O desenho proposto acima cruzava velocidade com canal. Com esta coleta ele fica
assim:

| | 4800 MT/s | 6000 MT/s |
|---|---|---|
| **16 GB, canal único** | coletado | coletado |
| **32 GB, canal duplo** | **falta** | coletado |

A célula que falta exige voltar a BIOS para 4800 com os dois pentes instalados.
Ela não decide nenhuma das quatro previsões — todas já se resolveram — mas
responde a uma pergunta diferente: **se o efeito da velocidade é o mesmo nas
duas configurações de canal**, o que testaria a consistência do instrumento
através de uma mudança de hardware. Fica registrada como coleta disponível, não
como pendência de conclusão.

#### O confundimento capacidade+canal continua declarado

Acrescentar o pente mudou capacidade e canal juntos, e **isto não foi
resolvido** — nenhum desenho viável nesta máquina os separa sem remover o
pente, intervenção que o responsável pela máquina recusou. É decisão
registrada, não bloqueio técnico. O que o desfecho
acrescenta é que a previsão 3 restringe o espaço: se a capacidade fosse o que
move o agregado, ela teria de fazê-lo **sem** alterar a latência de uma cadeia
dependente de 512 MB, que é o que a previsão 3 mediu parada em −1,8%.

Capacidade sobrando não tem por onde acelerar uma cadeia que já cabia na
memória disponível — a memória livre durante a coleta de canal único ficou em
torno de 7 GiB, catorze vezes o conjunto de trabalho. É argumento de mecanismo
somado a fato registrado, e continua **não sendo um controle**.

#### Um nó NUMA, e o que isso encerra

Com os dois pentes, `numactl --hardware` continua reportando **um único nó**, e
`/sys/devices/system/node/` tem só `node0`. Canal duplo é propriedade do
controlador de memória, não da topologia NUMA: esta CPU apresenta toda a memória
como um domínio.

Qualquer experimento que dependa de **mais de um nó NUMA** — localidade de pool
por nó, custo de acesso remoto, posicionamento de lcore por nó — permanece
impossível nesta máquina, e não por falta de pentes. A
[§4.3 do módulo 01](README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só)
já declara que os números de NUMA ali vêm da literatura e que medi-los exige
hardware de dois soquetes. Este registro fecha a porta de um caminho que a troca
de hardware parecia ter aberto: **canal duplo é propriedade do controlador de
memória, não da topologia NUMA**, e as duas coisas se confundem com facilidade
justamente porque ambas falam de "quantos caminhos até a memória".

### O que já está registrado como limitação

A máquina mediu **em canal único** tudo o que foi publicado até aqui, e o
documento não dizia isso — nem o `scripts/ambiente.sh`, que existe justamente
para o ambiente não ser descrito em prosa. Os dois campos entraram junto com
esta seção; quando exigem privilégio, eles **declaram que não foram lidos** em
vez de sumir.

---

## 7. A condição de coleta: por que a sessão gráfica foi excluída

O protocolo de medição deste repositório especifica máquina dedicada, sem
carga concorrente, e os scripts de campanha o declaram no cabeçalho — *"a
máquina está exclusiva para esta finalidade"*. A condição foi tratada como
suficiente até que o rastreamento por evento a contradisse.

### O que a medição mostrou

O rastreador `osnoise` atribuiu as paradas mais longas de uma CPU ociosa à
função `amdgpu_device_delay_enable_gfx_off`, que reativa o *power gating* do
bloco gráfico da GPU integrada. A execução ocorre em *workqueue* por CPU e
consome centenas de microssegundos. Com a sessão gráfica suspensa, a mesma
CPU apresentou máximo de 25 µs contra 711 µs — e a função desapareceu do
rastro. A cadeia completa, com pré-registro e critério de refutação, está em
[§6.6.5 e §6.6.6 do módulo de isolamento de CPU][iso].

A consequência para o protocolo é direta: **fechar o navegador não suspende a
sessão gráfica**. O compositor, o servidor de display e o driver da GPU
permanecem ativos e produzem, sozinhos, eventos de até 800 µs a intervalos de
poucos segundos. A declaração de exclusividade descrevia uma condição que não
era a condição medida.

### O que isso obriga, e o que não obriga

O efeito sobre os resultados já publicados é limitado pelo desenho estatístico.
O projeto reporta **mediana com dispersão**, não média; um evento raro de
800 µs desloca pouco a mediana de uma coleta com bilhões de amostras. A
medida direta desse deslocamento, na métrica mais sensível disponível — a
mediana da maior parada, composta inteiramente por cauda — foi de 24,8 µs para
21,5 µs, ou 13 %. Métricas de corpo da distribuição deslocam menos.

Esses 13 % valem para coleta que corre com a **sessão gráfica ociosa**, e não
generalizam. Entre as nove coletas do tópico de isolamento, oito ficam entre
21,5 e 30,9 µs e uma fica em 515,5 µs — todas na mesma máquina, as duas pontas
com sessão gráfica ativa. A contribuição da sessão não é constante aditiva:
depende de quanto ela trabalhou durante a medição, porque a reativação do
*power gating* é agendada por atividade gráfica.

A especificação passa a distinguir dois regimes:

| Grandeza de interesse | Condição exigida |
|---|---|
| mediana, média, razão entre medianas | máquina dedicada, sessão gráfica permitida |
| dispersão, jitter, p99, p99,9, máximo | **modo texto**, sem gerenciador de display |

O modo texto é obtido por entrada de GRUB de boot único com
`systemd.unit=multi-user.target`. O script
[`ferramental/qualidade/campanha.sh`][cmt] recusa execução
enquanto houver processo gráfico vivo, de modo que a condição seja verificada
pelo programa e não pela lembrança do operador.

### O limite desta correção

Os 198 rótulos que o `comparar-hardware.py` confronta **não foram
reexecutadas** em modo texto. Pelo argumento da mediana espera-se deslocamento
reduzido, mas trata-se de expectativa, não de medição. O achado também é de
uma máquina, com GPU integrada AMD: plataformas com GPU discreta ou outro
driver não estão cobertas.

[iso]: ../../trilha/03-performance/03-isolamento-cpu/README.md#665-identificação-da-fonte-por-rastreamento-de-eventos
[cmt]: ../../ferramental/qualidade/campanha.sh

---

## Navegação

- Volta para: [Fundamentos](README.md)
- O programa: [`medicoes/custo-syscall.c`](medicoes/custo-syscall.c)
