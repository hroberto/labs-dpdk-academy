# Submódulo 02 — Observabilidade

> **Nível 8** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [01 — Benchmarking](../01-benchmarking/)

> **Esqueleto.** Registra escopo e compromissos; o conteúdo ainda não foi
> escrito.

## Objetivo

Enxergar um programa de plano de dados **em produção**, onde não se pode anexar
depurador nem parar para medir.

## O que falta hoje, e é específico do DPDK

Listar `perf`, sanitizers e `clang-tidy` é fácil e insuficiente: são ferramentas
genéricas de C e C++, e o projeto já as trata no
[ferramental](../../../docs/00-visao-geral/ferramental.md). O que este submódulo
precisa cobrir, e nenhum outro cobre, é a observabilidade **do runtime**:

- **`rte_telemetry`** — o soquete de telemetria da própria EAL, com contadores de
  mempool, ring e porta, consultáveis com o programa rodando. A opção
  `--telemetry` / `--no-telemetry` aparece na ajuda da EAL e não é explicada em
  lugar nenhum do projeto.
- **Estatísticas de porta e de fila** — pacotes perdidos por falta de mbuf, por
  fila cheia, por erro de CRC. Um descarte silencioso na NIC é invisível para
  qualquer perfilador de CPU.
- **Contadores da própria aplicação**, e o cuidado de não os colocar na mesma
  linha de cache do caminho quente — o
  [falso compartilhamento](../../../docs/01-fundamentos/README.md#421-falso-compartilhamento-o-erro-mais-comum-de-quem-escreve-plano-de-dados)
  já medido nos fundamentos.
- **Processo secundário como ferramenta de diagnóstico.** É o uso mais comum do
  modelo multiprocesso na prática: um processo que se anexa à memória do
  primário, lê contadores e sai, sem tocar no caminho de dados. O mecanismo está
  em [runtime §4](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário).

## Restrição de ambiente a considerar

Duas coisas precisam ser resolvidas antes de prometer receitas:

- **VTune é da Intel** e a máquina de referência é AMD (Ryzen 9 9900X). Listá-lo
  como ferramenta central seria receita que o leitor não consegue seguir aqui.
  O equivalente da AMD é o µProf; `perf` funciona nos dois e deve ser o caminho
  principal.
- **Diagnóstico por processo secundário exige hugetlbfs gravável**, requisito que
  `--in-memory` e `--no-huge` não satisfazem
  ([runtime §4.5](../../../docs/02-runtime-dpdk/README.md#45-o-que-desliga-o-modelo-multiprocesso-sem-avisar)).
  O projeto traz [`scripts/preparar-hugepages.sh`](../../../scripts/preparar-hugepages.sh)
  para isso.

## Entregáveis

- programa instrumentado com contadores próprios, fora do caminho quente
- consulta de telemetria da EAL com o programa rodando
- diagnóstico via processo secundário, sem interromper o primário
- checklist do que observar quando o desempenho cai sem causa aparente

## Navegação

| | |
|---|---|
| **Anterior** | [01 — Benchmarking](../01-benchmarking/) |
| **Próximo** | [04 — Projeto final](../../04-projeto-final/) |
| **Módulo** | [03 — Performance e observabilidade](../README.md) |
