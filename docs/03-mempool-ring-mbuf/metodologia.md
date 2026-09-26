# Metodologia — mempool, ring e mbuf

*Read this in [English](metodologia.en.md).*

Este arquivo guarda o **desenho dos experimentos** do módulo 03: o que cada
programa mede, o que ele deliberadamente **não** mede, e até onde cada resultado
autoriza concluir.

Ele segue o padrão dos módulos [01](../01-fundamentos/metodologia.md) e
[02](../02-runtime-dpdk/metodologia.md). A razão de existir é a mesma: detalhe
de desenho experimental interrompe a leitura do README sem que ninguém o procure
ali, e separado ele fica disponível para quem quer contestar um número.

---

## 1. §1 — por que o programa publica razões, e não só nanossegundos

Esta é a decisão metodológica mais consequente do módulo, e ela foi **imposta
pela máquina**.

A frequência do processador decide o valor absoluto, e o mesmo binário deu
**2,78 ns e 2,18 ns** para o `malloc` de um objeto só. Não é ruído nem sorte de
turbo: é o *governor*, e a separação nas coletas arquivadas é perfeita —
`powersave` dá 2,78 ns nas **vinte** execuções de quatro coletas, `performance`
dá 2,18 a 2,20 nas **trinta** de seis. Vinte e sete por cento, sem uma
sobreposição.

**E a razão não se move.** Na mesma medição, o lote de 128 objetos dá entre
44,0× e 45,7× nas cinquenta execuções — atravessando os dois *governors*, duas
velocidades de memória e dois números de canais.

> **Por que o lote é estável e o objeto único não.** O `malloc` de um objeto é a
> primeira grandeza que o programa mede, e ela sai **no relógio frio**: sem
> sessão gráfica nada aqueceu a CPU entre invocações. Quando o laço do lote
> chega, ele já rodou segundos de trabalho e o relógio subiu — com `powersave`
> ou sem ele. **A ordem de medição é parte da condição**, e quem comparar a
> primeira linha de um programa com a última está comparando dois estados de
> relógio, não duas operações.

<!-- cita-retratado: 2,19 2.19 2,23 2.23 2,77 2.77 -->

Daí a regra que o módulo adota: **a razão é a afirmação; o nanossegundo é
circunstância.** O texto afirma "duas vezes mais rápido", não "0,98
nanossegundos", porque a primeira sobrevive à frequência e a segunda não.

O programa publica a frequência observada ao lado do resultado, e isso não é
ornamento: é o que permite a quem reproduz saber se a coleta dele rodou no mesmo
regime.

> **O que esta escolha custa.** Uma razão não diz se o custo absoluto cabe no
> orçamento. Para isso o número em nanossegundos continua necessário — e é por
> isso que o programa publica os dois, em vez de escolher.

---

## 2. §6.2 — a regra 4, e o que significa confrontar documentação primária

A [§4 do dimensionamento](medicoes/sizing.h) enuncia, **a partir da documentação
do DPDK**, que com `n % cache_size != 0` alguns objetos *"will always stay in the
pool and will never be used"*.

Isso era **aritmética testada em L1** — verificada como cálculo, nunca observada
num pool de verdade. O `pool-esgotado.c` observou:

| n | cache | previsto preso | obtido de fato |
|---:|---:|---:|---:|
| 4095 | 256 | **255** | **4095** |
| 1023 | 32 | **31** | **1023** |

Um consumidor único drenando o pool obtém **todos** os objetos, inclusive os que
a regra dava como perdidos.

### O que o desenho exigiu, e onde ele para

Achar a discrepância foi a parte fácil. **Explicá-la exigiu ler o fonte do
DPDK**, e é lá que está: em `rte_mempool_do_generic_get()`, quando o
reabastecimento do cache falha por não haver objetos para um lote inteiro, o
código faz `goto driver_dequeue` e busca os que faltam direto do anel de trás.

A conclusão publicada é que a regra **não está errada — está mal enunciada.**
Ela não descreve uma condição de perda permanente; descreve um regime.

**E o experimento não cobre o regime em que a regra realmente atua**: vários
lcores, cada um com seu cache. Isso está declarado no README, e é a diferença
entre "a regra é falsa" e "a regra não vale no caso que eu medi" — a segunda é a
que a evidência sustenta.

---

## 3. §3 — o anel num lcore só, e por que isso é deliberado

As medições de anel rodam **num lcore só, sem disputa nenhuma**. Não é limitação
acidental: é o que isola o custo do *caminho* MP/MC do custo da *contenção*.

O resultado que esse isolamento produz é o interessante — **existe custo de
MP/MC mesmo sem contenção real**, e ele vem das operações atômicas que o caminho
executa por construção, não de alguém disputando.

**O que ele não autoriza:** dizer quanto custa o anel sob disputa de vários
produtores. Essa é outra pergunta, com outro desenho, e o módulo não a responde.

---

## 4. §6 — `pool-esgotado` não mede tempo

Vale destacá-lo porque quebra o padrão do resto do repositório: ele **não produz
mediana, IQR nem selo**.

Ele verifica **comportamento de fronteira** — quantos objetos saem, o que
acontece quando o pool esgota, se `get_bulk` entrega lote parcial. São
propriedades determinísticas, e publicar dispersão sobre elas inventaria
incerteza onde não há.

É a mesma distinção que o [`tlb-real`](../01-fundamentos/medicoes/tlb-real.c) faz
no módulo 01, e pela mesma razão: **o instrumento estatístico depende da pergunta
experimental**, não de uniformidade editorial.

---

## 5. Ameaças à validade

**Validade interna — o experimento isolou o que pretendia?**

Sim, e ao custo de estreitar o escopo. Um lcore, sem disputa, pool quente. Cada
uma dessas escolhas remove uma variável e, junto com ela, uma pergunta.

A mais relevante: **o mecanismo do degrau do `malloc` não foi investigado,
apenas observado.** O texto diz que o degrau aparece entre 16 e 32, e não diz por
quê — porque não mediu.

**Validade externa — até onde generaliza?**

Os **nanossegundos não generalizam**; as **razões** generalizam melhor, e é por
isso que são elas que o módulo afirma. Nem umas nem outras generalizam para
máquina com outra hierarquia de cache ou outro alocador.

Não há **NIC nem DMA** em nenhuma medição. Tudo o que o módulo diz sobre o
ciclo de vida de um pacote real é arquitetura derivada da documentação.

E não há **comparação entre os *mempool handlers*** do DPDK — só o padrão.

**Validade de construção — a métrica representa o fenômeno?**

Aqui está a ressalva que mais importa neste módulo. O que se publica é **custo
por operação**, e não **distribuição de latência de cauda**. Um plano de dados
falha pela cauda, não pela média — e este módulo mede a média de um caminho, não
o p99 de um sistema.

Tratar `0,98 ns por operação` como se dissesse algo sobre o pior caso de um
pipeline seria trocar uma pergunta pela outra.

---

## Navegação

- Módulo: [Mempool, ring e mbuf](README.md)
- Metodologias: [Fundamentos](../01-fundamentos/metodologia.md) · [Runtime](../02-runtime-dpdk/metodologia.md)
