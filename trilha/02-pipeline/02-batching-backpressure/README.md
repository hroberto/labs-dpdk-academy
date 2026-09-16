# Submódulo 02 — Batching e contrapressão

> **Nível 5** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [01 — RX/TX em lote](../01-rx-tx-burst/)

> **In English.** What to do when the queue fills — and the answer is not about
> the queue. The ring's usable capacity is `depth − 1` and the pool holds 4095
> objects, so once capacity reaches the pool the ring can hold everything that
> exists and **can no longer fill**. The measured boundary lands exactly where
> the arithmetic says: capacity 1023 → 62 529 refusals, 2047 → 104 866,
> **4095 → zero**. Backpressure is governed by the **pool-to-queue ratio**, not
> by depth alone. Burst size matters more than depth, and in the counterintuitive
> direction: at depth 256, going from burst 8 to 128 takes 8.5 ns to 2.8 ns and
> cuts refusals from 219 292 to 85 143. Of the three policies in scope, only
> **drop** was measured; blocking and pushing back are described without an
> experiment, and the gap is stated.

Responder à pergunta que o tópico de mempool deixa em aberto: **o que fazer
quando a fila enche.**

## 1. Fundamento: contrapressão é o consumidor dizendo "pare"

Um pipeline tem um produtor e um consumidor, e nada garante que andem no mesmo
passo. Quando o produtor é mais rápido, a fila entre eles cresce até o limite —
e aí o sistema precisa de uma resposta. São três, e só três:

**Descartar.** O produtor joga fora o que não coube. É a resposta do plano de
dados quando o dado velho perde valor: num *feed* de bolsa, um tick de dez
milissegundos atrás já não interessa.

**Bloquear.** O produtor espera a fila abrir. Corre o risco de travar tudo se o
consumidor nunca drenar, e é por isso que o programa deste tópico tem prazo de
progresso (`-t`).

**Empurrar para trás.** O produtor repassa a recusa a quem o alimenta. Só existe
se houver a quem repassar — numa NIC recebendo multicast, não há.

A resposta certa depende do que o dado significa, e essa é a parte que não se
resolve com código.

## 2. Mecanismo: quem decide se a fila enche

Aqui está o resultado menos intuitivo deste submódulo, e ele **não é sobre a
fila**.

O programa usa um `rte_ring` de profundidade configurável e um `rte_mempool` de
**4095 objetos**. A capacidade útil do anel é `profundidade − 1`: uma posição
fica reservada para distinguir cheio de vazio.

Então, quando a capacidade do anel alcança o tamanho do pool, **o anel passa a
caber todos os objetos que existem** — e não tem mais como encher. Não há
contrapressão possível, não porque a fila seja generosa, mas porque não sobrou
nada para ficar de fora.

**A contrapressão é decidida pela razão entre pool e fila, não pela fila
sozinha.** A seção 6 mede a fronteira, e ela cai exatamente onde a aritmética
manda.

### Fila cheia não é perda no transporte

A distinção se confunde com facilidade, e as duas aparecem neste projeto:

| | Fila cheia no ring interno | Perda no transporte |
|---|---|---|
| Quem sofre | o produtor, que recebe recusa | o consumidor, que nunca vê o dado |
| Detecção | retorno da função de enfileiramento | descontinuidade de sequência |
| Resposta | tentar de novo, descartar, ou empurrar para trás | pedir retransmissão, ou seguir com o livro incompleto |

O tópico de mempool conta "tentativas com fila cheia" e repete. Num sistema onde
o produtor é uma bolsa transmitindo por multicast, essa opção não existe: o
datagrama que não foi lido está perdido, e o que se detecta depois é um **salto
no número de sequência** — o mecanismo que o
[módulo de runtime](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário)
já implementa e testa.

## 3. Trade-offs: fila funda não é de graça

Aumentar a fila reduz recusa e aumenta a latência de ponta a ponta: um objeto
enfileirado atrás de outros dez mil espera por todos eles. É o trade-off clássico
entre vazão e latência, e ele tem um limite superior que a seção 6 mostra — a
partir do ponto em que a fila cabe o pool inteiro, aprofundar mais **não compra
nada** e paga pegada de cache.

O lote tem efeito oposto e maior do que se espera: lotes grandes amortizam o
custo por objeto dos dois lados, e com isso o consumidor drena mais rápido — o
que reduz a recusa em vez de aumentá-la.

## 4. Implementação

A profundidade da fila era **fixa em 1024** no código, o que tornava o primeiro
item do escopo deste submódulo impossível de medir. Passou a ser a opção `-q`:

```bash
B=build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring
$B --no-huge -m 512 --no-pci -l 0,2 -- -n 200000 -b 32 -q 1024 -t 8000
```

Duas recusas de uso, ambas com a explicação junto:

```
-q 1000   → deve ser potencia de dois (exigencia do rte_ring)
-q 8 -b 32 → -q 8 nao comporta um lote de 32 (capacidade util e profundidade-1)
```

A segunda existe porque, sem ela, um lote maior que a fila faz o produtor girar
sem nunca enfileirar, até o prazo de progresso estourar — cinco segundos de nada
em vez de uma linha dizendo o que está errado.

## 5. Validação

```bash
./scripts/ambiente-medicao.sh --uma-linha   # carimbe o ambiente junto
B=build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring
for q in 1024 2048 4096; do
  printf 'prof=%-6s ' "$q"
  $B --no-huge -m 512 --no-pci -l 0,2 --file-prefix=v$q -- \
     -n 200000 -b 32 -q $q -t 8000 2>/dev/null | grep 'nao couberam'
done
```

Com **um lcore** (`-l 0`), produtor e consumidor se alternam e a fila nunca
enche: a recusa é **zero em qualquer profundidade**. A contrapressão só aparece
quando os dois lados correm de verdade em paralelo.

## 6. Quando dá errado — a superfície medida

Duas CPUs (`-l 0,2`), 200 000 pacotes, pool de 4095 objetos. Cada ponto é a
mediana de três execuções, **descartando a primeira** — pelo motivo medido no
[submódulo de benchmarking](../../03-performance/01-benchmarking/), onde a
primeira execução após ociosidade sai ~30% alta.

| Profundidade | Capacidade | Lote 8 | Lote 32 | Lote 128 |
|---|---|---|---|---|
| 64 | 63 | 6,7 ns · 146 704 | 5,2 ns · 270 684 | — |
| 256 | 255 | 8,5 ns · 219 292 | 3,6 ns · 114 822 | 2,8 ns · 85 143 |
| 1 024 | 1 023 | 5,2 ns · 70 897 | 3,6 ns · 109 060 | 3,5 ns · 188 098 |
| 4 096 | **4 095** | 4,8 ns · **0** | 3,0 ns · **0** | 2,4 ns · **0** |
| 16 384 | 16 383 | 5,9 ns · **0** | 3,1 ns · **0** | 2,5 ns · **0** |

(tempo por pacote · objetos que não couberam; o mesmo objeto recusado várias
vezes conta cada vez, e é por isso que a contagem pode passar do número de
pacotes.)

### A fronteira cai onde a aritmética manda

O pool tem 4095 objetos. Capacidade `4096 − 1 = 4095` é o primeiro valor que
alcança o pool inteiro:

| Profundidade | Capacidade | vs. pool | Não couberam |
|---|---|---|---|
| 1 024 | 1 023 | menor | 62 529 |
| 2 048 | 2 047 | menor | 104 866 |
| 4 096 | **4 095** | **igual** | **0** |

A transição é abrupta e está exatamente no ponto previsto. Isso confirma o
mecanismo da seção 2: **a fila deixou de encher porque passou a caber tudo o que
existe**, não porque ficou "grande o bastante".

É também um aviso sobre leitura apressada. Olhando só a primeira tabela, a
conclusão natural seria *"profundidade ≥ 4096 elimina a contrapressão"* — uma
afirmação sobre a fila. A afirmação verdadeira é sobre a **razão**, e num sistema
com pool maior a mesma profundidade voltaria a recusar.

### O lote pesa mais que a profundidade

Do pior ponto ao melhor há **3,5×**: 8,5 ns (profundidade 256, lote 8) contra
2,4 ns (profundidade 4096, lote 128). E o lote domina: na profundidade 256, ir de
lote 8 para 128 leva de 8,5 a 2,8 ns e corta a recusa de 219 292 para 85 143.

Lotes grandes reduzem a recusa. O contrário do que a intuição sugere — e o motivo
é que o custo por objeto cai dos dois lados, então o consumidor drena mais rápido
do que o produtor enche.

### Aprofundar além da fronteira não compra nada

Comparando 16 384 com 4 096, já sem recusa em ambos:

- **lote 8**: 5,9 contra 4,8 ns — 23%, acima do ruído
- **lote 32**: 3,1 contra 3,0 ns — 3%
- **lote 128**: 2,5 contra 2,4 ns — 4%

Os dois últimos **não são diferença**: a amplitude entre execuções medida no
submódulo de benchmarking é de 4,6%, e 3% e 4% cabem dentro dela. Publicá-los
como piora seria ler ruído.

O caso do lote 8 está fora do ruído e é consistente com pegada de cache — uma
fila de 16 383 ponteiros ocupa 128 KB, e com lotes pequenos há muito mais idas e
vindas ao anel. Mas **uma medição acima do ruído não é uma causa estabelecida**,
e este documento não afirma mais do que mediu.

## 7. Limitações

**As três políticas não foram implementadas — só uma foi medida.** O programa
devolve ao pool o que não coube, que é a política de *descarte*. Bloquear e
empurrar para trás estão descritos na seção 1 e não têm experimento aqui. O
entregável do esqueleto pedia as três; entregou-se uma, e a lacuna está dita.

**Descarte com critério ficou de fora.** Qual pacote descartar quando é preciso
descartar algum é decisão de política, e exige metadado que `struct packet` não
carrega hoje.

**Contrapressão até a NIC não foi tocada.** Exige a placa fora do kernel, que é
o que o [submódulo 01](../01-rx-tx-burst/) trava esperando.

**Uma máquina, um par de núcleos.** Tudo medido com `-l 0,2`, dentro do mesmo
domínio de L3. Atravessar domínios muda o custo da travessia e provavelmente a
forma da superfície — veja [fundamentos §4.3](../../../docs/01-fundamentos/README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só).

**Comparação com C++23 puro não foi feita.** Estava nos entregáveis e não entrou.

## 8. Para onde ir daqui

| | |
|---|---|
| **Anterior** | [01 — RX/TX em lote](../01-rx-tx-burst/) |
| **Próximo** | [03 — Performance e observabilidade](../../03-performance/) |
| **Módulo** | [02 — Pipeline](../README.md) |
| **Programa** | [`pipeline_ring.c`](../../01-fundamentos/02-mempool-ring/pipeline_ring.c) |
