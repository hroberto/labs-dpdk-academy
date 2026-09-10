# Submódulo 01 — Benchmarking

> **Nível 8** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [02 — Batching e contrapressão](../../02-pipeline/02-batching-backpressure/)

> **Esqueleto.** Registra escopo e compromissos; o conteúdo ainda não foi
> escrito.

## Objetivo

Medir de um jeito que sobreviva a quem duvida do resultado.

## O ponto de partida não é zero

O projeto já tem uma metodologia em uso, em `statistics.h`, e ela é o material
bruto deste submódulo. O que falta é o rigor de ambiente, que os próprios
documentos declaram estar faltando:

> *"Execução única por ponto, sem fixar frequência de CPU, sem isolar núcleos e
> sem aquecimento controlado de cache. Serve para ordem de grandeza."*
> — [Alternativa em C++23](../../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md)

Essa ressalva aparece em mais de um documento. Removê-la é o entregável central
deste submódulo.

## Escopo

- o que precisa ser fixado antes de medir: frequência, estados C, afinidade,
  isolamento de núcleo
- aquecimento: por que as primeiras iterações mentem, e quantas descartar
- repetição e agregação — e por que a mediana de repetições não é a mesma coisa
  que a mediana de amostras
- **declarar a resolução do instrumento**, prática que o
  [módulo de runtime](../../../docs/02-runtime-dpdk/README.md#46-quanto-custa-atravessar-a-fronteira)
  já adota: um consumidor que sonda não resolve diferenças menores que o próprio
  período de sondagem
- adoção de `google-benchmark`, prometida no
  [ferramental](../../../docs/00-visao-geral/ferramental.md)
- comparar em **ciclos**, não só em nanossegundos, para separar "ficou mais
  rápido" de "o clock subiu"

## Qual métrica importa

Depende do problema, e dizer isso é parte do conteúdo. Num sistema que recebe
*feed* de bolsa, o requisito não é vazão média — é a **cauda**: o tick da
abertura que chegou tarde é o que custa dinheiro. Por isso p99 e p99,9 aparecem
antes da média em todo este projeto. Num roteador de borda a conta é outra, e o
módulo deve mostrar as duas.

## Entregáveis

- suíte de benchmark reprodutível, com ambiente declarado
- documentação da metodologia, incluindo o que ela **não** garante
- revisão das ressalvas metodológicas espalhadas pelos documentos anteriores
- análise crítica: quais conclusões do projeto sobrevivem à medição rigorosa

## Navegação

| | |
|---|---|
| **Próximo** | [02 — Observabilidade](../02-observabilidade/) |
| **Módulo** | [03 — Performance e observabilidade](../README.md) |
