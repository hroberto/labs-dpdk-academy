# Submódulo 02 — Batching e contrapressão

*Read this in [English](README.en.md).*

> **Nível 5** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [01 — RX/TX em lote](../01-rx-tx-burst/)

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

> **A razão física está um nível abaixo.** O trade-off dos dois parágrafos acima
> é o mesmo da [§4.2 dos fundamentos](../../../docs/01-fundamentos/README.md#42-cache-e-localidade),
> uma escala menor: lá o lote não dilui o custo de um anel, e sim o de um acesso
> à memória, e a curva medida mostra onde ele para de compensar. A mesma conta —
> vazão = concorrência ÷ latência — governa os dois.

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
mediana de **sete** execuções, descartando a primeira — pelo motivo medido no
[submódulo de benchmarking](../../03-performance/01-benchmarking/), onde a
primeira execução após ociosidade sai ~30% alta. Cada célula traz a mediana e,
entre colchetes, a **faixa observada**, porque sem ela o número engana.

| Profundidade | Capacidade | Lote 8 | Lote 32 | Lote 128 |
|---|---|---|---|---|
| 256 | 255 | 8,4 ns [7,5–9,0] | 5,2 ns [4,6–6,4] | 4,4 ns [3,4–5,0] |
| 1 024 | 1 023 | 7,7 ns [6,5–8,9] | 4,8 ns [4,3–6,3] | 3,2 ns [3,2–4,1] |
| 4 096 | **4 095** | 7,1 ns [6,1–7,4] | 4,9 ns [3,8–6,0] | 4,1 ns [3,0–4,9] |

> **RETRATAÇÃO — 16/09/2026.** Esta tabela publicou, no mesmo dia em que foi
> escrita, **quinze valores pontuais** de tempo e de recusa, obtidos com três
> execuções por ponto. Reconferida com sete execuções, **dois dos três valores de
> tempo da linha 256 ficaram FORA da faixa medida** — o publicado "2,8 ns" contra
> uma faixa de 3,4 a 5,0.
>
>
> Pior foi a contagem de recusas. Oito execuções da **mesma** configuração
> (profundidade 1024, lote 32) deram de 118 626 a 286 625: **128% de amplitude
> sobre a mediana**. Publicar "219 292" e "85 143" como se fossem medidas é dar
> três algarismos significativos a uma grandeza que varia por um fator de dois e
> meio. Os números saíram da tabela.
>
>
> **Esta retratação NÃO é conferida por máquina, e vale dizer por quê.** O
> `verificar-retratacoes.py` rastreia decimais com três algarismos significativos
> ou mais -- `0,115`, `2,18`, `65,84`. Os valores derrubados aqui ficam fora dos
> dois lados: `8,5` e `2,8` têm dois significativos, e o corte existe para que
> "5,0" não vire ruído em todo documento; `219 292` e `62 529` são inteiros com
> separador de milhar, que o padrão de número decimal nem casa.
>
> Então a garantia aqui é humana, não automática. Registrar isso é o mínimo: uma
> marca `<!-- retratado: -->` inerte seria pior que nenhuma, porque sugeriria uma
> conferência que não acontece.
>
> A recusa depende da corrida entre produtor e consumidor, que o escalonador
> arbitra a cada execução. Ela serve para responder **se houve** contrapressão --
> e essa resposta é estável, como a fronteira abaixo mostra. Não serve para dizer
> **quanta**.
>
> O defeito é meu e é exatamente o que o submódulo de benchmarking ao lado
> descreve: tratei três execuções como suficientes sem medir a dispersão. A
> metodologia estava escrita no documento vizinho e não foi aplicada aqui.

### A fronteira cai onde a aritmética manda

O pool tem 4095 objetos. Capacidade `4096 − 1 = 4095` é o primeiro valor que
alcança o pool inteiro:

| Profundidade | Capacidade | vs. pool | Houve recusa? |
|---|---|---|---|
| 1 024 | 1 023 | menor | **sim**, em todas as execuções |
| 2 048 | 2 047 | menor | **sim**, em todas as execuções |
| 4 096 | **4 095** | **igual** | **não — zero, em todas as execuções** |

**Este é o resultado estável**, e a instabilidade da contagem não o afeta: a
pergunta "houve recusa?" tem resposta binária, e ela nunca variou em 7 execuções
por ponto. Abaixo da fronteira, sempre houve; na fronteira, nunca.

A transição é abrupta e está exatamente no ponto previsto. Isso confirma o
mecanismo da seção 2: **a fila deixou de encher porque passou a caber tudo o que
existe**, não porque ficou "grande o bastante".

É também um aviso sobre leitura apressada. A conclusão natural seria
*"profundidade ≥ 4096 elimina a contrapressão"* — uma afirmação sobre a fila. A
afirmação verdadeira é sobre a **razão**, e num sistema com pool maior a mesma
profundidade voltaria a recusar.

### O lote pesa mais que a profundidade

Na profundidade 256, ir de lote 8 para 128 leva de **8,4 para 4,4 ns** — quase
metade. Em 1024, de 7,7 para 3,2. A direção é a mesma nas três profundidades, e
as faixas não se sobrepõem entre lote 8 e lote 128 em nenhuma delas: é diferença,
não ruído.

Aprofundar, no mesmo lote, move muito menos: de 256 para 4096 com lote 8 vai de
8,4 para 7,1 ns, e as faixas **se tocam**. **O lote domina a profundidade.**

O motivo é que o custo por objeto cai dos dois lados com lotes maiores, então o
consumidor drena mais rápido do que o produtor enche — o contrário do que a
intuição sugere, que é "lote maior enche a fila mais depressa".

### Aprofundar além da fronteira: não medido

A versão anterior desta seção comparava profundidade 16 384 com 4 096 e concluía
que o excesso custava pegada de cache. **A comparação saiu**, por dois motivos:

1. os valores vinham da mesma coleta de três execuções que a retratação acima
   invalidou;
2. na reconferência com `-m 512`, a configuração de 16 384 **não completou** — e
   uma medição que não roda não vira número.

O que se pode afirmar com os dados de sete execuções: de 1 024 para 4 096, no
lote 128, a mediana **piora** (3,2 para 4,1 ns) e as faixas se sobrepõem
([3,2–4,1] contra [3,0–4,9]). Ou seja: **passar da fronteira não comprou nada
mensurável aqui**, e pode ter custado. Afirmar qual dos dois exigiria mais
repetições do que foram feitas.

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
