# Módulo 01 — Fundamentos práticos do DPDK

> **Níveis 3 e 4** do [plano de estudo](../../docs/plano-estudo-dpdk.md) ·
> Teoria correspondente: [01 — Fundamentos](../../docs/01-fundamentos/README.md)
> e [02 — Runtime do DPDK](../../docs/02-runtime-dpdk/README.md)

Este é o único módulo da trilha com conteúdo completo. Ele cobre as duas coisas
que todo programa DPDK faz antes de tratar o primeiro pacote: **subir o runtime**
e **conseguir memória sem alocar no caminho quente**.

## Tópicos

| Tópico | Assunto | Nível | Testes |
|---|---|---|---|
| [01 — Inicialização da EAL](01-eal-hello/) | o que a EAL decide antes da sua primeira linha rodar | 3 | L2 |
| [02 — Mempool, ring e lote](02-mempool-ring/) | emprestar e devolver objetos; passar lotes entre núcleos | 4 | L1 + L2 |
| [Alternativa em C++23 puro](02-mempool-ring/alternativas/cpp23/) | o mesmo problema sem DPDK, com o mesmo contrato verificado | 4 | L1 + L2 |

## A ordem importa

Os dois tópicos podem ser lidos na ordem que quiser, mas há uma dependência real
entre eles: o tópico 02 usa memória que **a EAL do tópico 01 reservou**. Quem
pular o primeiro vai encontrar no segundo opções de linha de comando
([`--in-memory`][optmem], [`--no-huge`][optdebug], [`-l`][optlcore]) sem saber o que fazem nem o que custam.

E há uma dependência na direção contrária, menos óbvia: o tópico 02 mede que
atravessar de um núcleo para outro custa de 4,0 a 4,8 vezes mais quando os
núcleos estão em domínios de cache diferentes. **Escolher em qual CPU cada lcore
roda** é assunto do [módulo de runtime](../../docs/02-runtime-dpdk/README.md#51-lcore-não-é-cpu),
na teoria. Medir sem saber controlar deixa metade da lição de fora.

## Por que cada tópico tem os testes que tem

A divisão não é arbitrária, e explicá-la é parte do conteúdo:

- **O tópico 01 tem só L2.** Não há lógica pura para isolar — o tópico *é* a
  inicialização do runtime. Testar variações de argumento exige um processo por
  variação, porque [`rte_eal_init()`][apiealinit] não é reentrante; daí o teste
  ser um script, e não um caso de GoogleTest.
- **O tópico 02 tem L1 e L2.** A lógica de pacote vive em arquivo próprio, sem
  incluir nada do DPDK, e por isso roda em milissegundos no L1. O que só existe
  com o runtime de pé — integridade do pool depois de milhares de ciclos de
  reúso — fica no L2.

Essa separação tem um custo concreto que vale conhecer: subir a EAL leva
**123 ms** nesta máquina ([§2 do módulo de runtime](../../docs/02-runtime-dpdk/README.md#2-o-custo-de-existir-quanto-a-eal-leva-para-nascer)).
Uma suíte que exigisse o runtime para cada asserção pagaria esse preço em cada
caso de teste.

## Como rodar

```bash
./scripts/build-all.sh
./scripts/test-all.sh l1     # lógica pura, sem EAL
./scripts/test-all.sh l2     # runtime real
```

## Próximo módulo

[02 — Pipeline e processamento em lote](../02-pipeline/), onde o ring deixa de
ser exercício e vira estágio de um caminho de dados.

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3

[optdebug]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#debugging-options
[optlcore]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#lcore-related-options
[optmem]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#memory-related-options
