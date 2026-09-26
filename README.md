![labs-dpdk-academy — guia de estudo e laboratório prático para DPDK: alto throughput, baixa latência, C/C++23, Linux, medições reproduzíveis. A ilustração mostra o caminho de um pacote: entrada pela RX, processamento no DPDK, rings e mempool, distribuição entre lcores e chegada à memória NUMA.](docs/assets/banner-BR.jpg)

# DPDK Academy — estudo experimental reprodutível de desempenho no plano de dados

**Todo número publicado aqui tem um programa que o produz.** Medido numa máquina
nomeada, e corrigido quando a medição discordou — inclusive da documentação
oficial. Guia de estudo de DPDK com base em engenharia de software, arquitetura
de sistemas e C++23, com prosa em português e código em inglês.

*Read this in [English](README.en.md).*

## Objetivo

Este repositório foi pensado para servir como base didática para profissionais iniciantes e avançados que desejam aprender DPDK de forma estruturada, profunda e aplicada.

Ele combina:

- fundamentos teóricos do DPDK e do plano de dados
- arquitetura de software e runtime de alto desempenho
- exercícios práticos em C e C++23
- comparação com implementações puras em C++23
- abordagem crítica de trade-offs e performance
- documentação como fonte de conhecimento técnico

## O que este projeto cobre

- introdução ao DPDK e ao papel do plano de dados
- princípios de alto desempenho e arquitetura de software
- fundamentos do Linux, memória, cache, NUMA e CPU affinity
- [EAL][cEAL], mbuf, mempool, ring e lifecycles de pacotes
- RX/TX, burst, batch processing e polling
- comparação entre DPDK e software puro em C++23
- benchmarking, observabilidade, qualidade e engenharia real

## Estrutura do repositório

- `docs/` — documentação didática e estrutura de estudo
- `trilha/` — módulos organizados por nível de profundidade
- `scripts/` — automação de build e testes
- `subprojects/` — dependências de teste fixadas por hash (arquivos `.wrap`)
- `ROADMAP.md` — visão geral do plano evolutivo do projeto
- `PADROES.md` — a régua que o material segue, e os portões que a aplicam
- `LICENSE` — licença do conteúdo do projeto

Cada tópico da trilha é **autocontido**: documento, código, testes e, quando
existir, a alternativa sem DPDK para o mesmo problema, em `alternativas/` dentro
do próprio tópico. Exemplo:

```
trilha/01-fundamentos/02-mempool-ring/
├── README.md              teoria, mecanismo, trade-offs, exercícios
├── packet.c / packet.h    lógica pura (testável sem DPDK)
├── pipeline_ring.c        runtime: EAL, mempool, ring
├── tests/                 L1 (GoogleTest) e L2 (integração)
└── alternativas/cpp23/    mesmo problema sem DPDK, mesmo contrato
```

## Filosofia de aprendizagem

Este projeto não trata o DPDK como uma ferramenta isolada. Ele busca ensinar:

- teoria e arquitetura antes da API
- mecanismo antes da otimização
- prática executável antes de performance fantasiosa
- design de software antes de micro-otimizações sem contexto
- documentação clara e rigorosa como parte da engenharia
- números medidos e confrontados com a literatura da área, nunca afirmados

## Trilhas de estudo

A trilha principal está em:

- `docs/plano-estudo-dpdk.md`
- `trilha/README.md`
- `ROADMAP.md`

**A ordem de estudo canônica é a dos dez níveis do
[plano de estudo](docs/plano-estudo-dpdk.md).** É a única numeração que os
módulos citam: cada documento abre declarando o seu "Nível N", e é esse número
que vale. Os outros documentos de entrada têm papéis diferentes e não numeram a
progressão:

| Documento | Para quê serve |
|---|---|
| [docs/plano-estudo-dpdk.md](docs/plano-estudo-dpdk.md) | **a ordem de estudo**, em dez níveis — é o que os módulos citam |
| [trilha/README.md](trilha/README.md) | índice do que existe em código e teste, com o estado de cada tópico |
| [ROADMAP.md](ROADMAP.md) | ordem de **construção** do material — não é ordem de leitura |
| [PADROES.md](PADROES.md) | o critério que separa aqui um número publicável de uma anedota |

Os dez níveis, e onde cada um está:

| Nível | Assunto | Estado |
|---:|---|---|
| 1-2 | Fundamentos de sistema e de rede | [docs/01-fundamentos](docs/01-fundamentos/) |
| 3 | Runtime e EAL | [docs/02-runtime-dpdk](docs/02-runtime-dpdk/) · [trilha 01-eal-hello](trilha/01-fundamentos/01-eal-hello/) |
| 4 | Mempool, mbuf, ring e ciclo de dados | [docs/03-mempool-ring-mbuf](docs/03-mempool-ring-mbuf/) · [trilha 02-mempool-ring](trilha/01-fundamentos/02-mempool-ring/) |
| 5 | Pipeline e contrapressão | [trilha/02-pipeline](trilha/02-pipeline/) — **escrito**; profundidade de fila e recusa medidas |
| 6 | RX/TX e hardware | [trilha 01-rx-tx-burst](trilha/02-pipeline/01-rx-tx-burst/) — ambiente medido, sem código; depende de NIC |
| 7 | NUMA, cache e desempenho | coberto dentro dos [fundamentos](docs/01-fundamentos/) |
| 8 | Observabilidade e qualidade | [trilha/03-performance](trilha/03-performance/) — **escrito**; método de medição e telemetria medidos |
| 9 | Virtualização e nuvem | **não iniciado** |
| 10 | Projeto final e alternativas | [trilha/04-projeto-final](trilha/04-projeto-final/) — **consolidação escrita**; a aplicação não existe |

> **Esta tabela substituiu uma lista de sete passos que competia com os dez
> níveis em vez de citá-los.** A colisão era concreta: o passo 5 da lista era
> "NUMA, cache e CPU affinity" enquanto o Nível 5 é "Pipeline", de modo que
> "nível 5" significava duas coisas conforme o documento. A lista também
> omitia, sem dizer, os níveis 6 e 9.

## O que se pressupõe de você

A trilha vai de iniciante a avançado **em DPDK** — não em programação de
sistemas. Espera-se familiaridade com C, Linux, threads, ponteiros e noções de
rede; **não** se espera conhecer NUMA, TLB, hugepages, coerência de cache, IOMMU
ou qualquer coisa do DPDK, que o material ensina do zero.

A lista completa, com o que é ensinado e o que não é, está em
[docs/00-visao-geral](docs/00-visao-geral/README.md#2-o-que-se-pressupõe-do-leitor).

## Requisitos de ferramenta

- Linux x86_64 ou arm64
- GCC 14+ ou Clang 18+ (C11 e C++23; as declarações POSIX vêm de `_GNU_SOURCE`,
  declarado por arquivo — ver [ferramental §2.2](docs/00-visao-geral/ferramental.md))
- **DPDK 23.11 ou mais novo**, com `pkg-config --modversion libdpdk` funcionando
  (Debian/Ubuntu: `dpdk-dev`; Fedora/RHEL: `dpdk-devel`)

  | Release | Estado |
  |---|---|
  | 25.11 | máquina de referência — a maior parte dos números publicados vem dela |
  | 26.07 | usada no estudo comparativo do cache do mempool ([módulo 03 §1.4](docs/03-mempool-ring-mbuf/README.md)), que publica números das **duas** |
  | 23.11 | CI (Ubuntu 24.04); suíte passa |
  | < 23.11 | não testado; o `meson setup` recusa |

  Cada bloco publicado carrega a *release* que o produziu na própria linha de
  procedência; a tabela diz onde procurar, não substitui a leitura dela.

  A faixa não é decorativa: a diferença entre 23.11 e 25.11 já produziu dois
  defeitos que só aparecem em uma das duas — `--in-memory --no-huge` juntos, e
  o código de saída de argumento desconhecido. Ambos estão documentados no
  [tópico 01](trilha/01-fundamentos/01-eal-hello/README.md).
- Meson 1.1+ e Ninja

Opcionais, e só a partir da etapa de benchmarking e qualidade: clang-format,
clang-tidy, sanitizers e perf. Nada da trilha atual depende deles — compilar,
rodar e testar os tópicos 1 a 4 exige apenas a lista acima.

O GoogleTest, usado nos testes L1, é baixado automaticamente pelo Meson e não
precisa ser instalado. Rode `./scripts/check-env.sh` para diagnosticar o
ambiente. As decisões de ferramental estão explicadas em
[docs/00-visao-geral/ferramental.md](docs/00-visao-geral/ferramental.md).

## Uso rápido

```bash
./scripts/check-env.sh      # o que está instalado e o que falta
./scripts/ambiente.sh       # registro do hardware onde os números foram medidos
./scripts/build-all.sh      # configura e compila tudo
./scripts/test-all.sh       # suíte completa
./scripts/test-all.sh l1    # só lógica pura (rápido, sem EAL)
./scripts/test-all.sh l2    # só integração com o runtime
./scripts/test-all.sh l3    # só o que exige concessão do host
```

> **Antes de estranhar os testes que pulam: hugepage reservada não é hugepage
> utilizável.** É a pegadinha mais provável desta lista, e ela não se parece com
> um erro.
>
> Para o DPDK multiprocesso são necessárias **duas** coisas ao mesmo tempo:
> páginas reservadas **e** um ponto `hugetlbfs` em que o *seu* usuário possa
> escrever. A montagem padrão do systemd é `/dev/hugepages`, `root:root 755` —
> então o caso comum é ter mil páginas livres e nenhuma delas alcançável, e os
> testes **L3 pulam** sem que nada pareça errado.
>
> `check-env.sh` tira essa conclusão para você, em uma linha. Quando faltar:
>
> ```bash
> sudo ./scripts/preparar-hugepages.sh
> ```
>
> Pede privilégio **uma vez** e monta o ponto no seu nome — depois disso nenhuma
> execução precisa de root.
>
> **E se você experimentar muito à mão, limpe o diretório de runtime.** Cada
> execução com `--file-prefix` novo deixa dezenas de MB em
> `$XDG_RUNTIME_DIR/dpdk`, que é *tmpfs*. A suíte limpa os seus; execução avulsa,
> não. Quando enche, a EAL morre com **SIGBUS** ao mapear o `fbarray` — inclusive
> com `--no-huge` —, e a mensagem fala de barramento, não de disco cheio. Aqui
> isso derrubou nove testes de uma vez e parecia regressão de código.
> `check-env.sh` avisa antes; com nenhum DPDK rodando, `rm -rf $XDG_RUNTIME_DIR/dpdk/*`
> resolve. E não há atalho sem privilégio: `hugetlbfs` não é
> montável em *user namespace* (o kernel não a marca como tal), e `--no-huge`
> não serve porque o processo secundário se anexa mapeando o arquivo de respaldo
> das hugepages — sem ele, não há anexação. Medido, não suposto.

### Os três níveis de teste, e o que separa um do outro

O nome de cada teste começa por `l1`, `l2` ou `l3`, e o critério **não é o
tamanho nem a importância** — é *o que o teste precisa da máquina para poder
rodar*. Essa é a pergunta que decide onde ele mora:

| Nível | Precisa de | Consequência prática |
|---|---|---|
| **L1** | nada além do compilador | roda em qualquer lugar, em milissegundos; é onde vive a lógica pura, sem EAL |
| **L2** | a EAL de pé, um processo, sem privilégio | roda em qualquer lugar; paga ~123 ms de inicialização por caso |
| **L3** | algo que o **host** precisa conceder: `hugetlbfs` gravável, vários núcleos | pode não rodar, e então **pula** em vez de falhar |

A fonte canônica desta definição é [`scripts/test-all.sh`](scripts/test-all.sh),
que é também quem a executa. Para contar quantos há de cada:

```bash
meson test -C build --list | grep -oE '^l[123]' | sort | uniq -c
```

**Um L3 que pula não é um teste que passou.** Quando a pré-condição não existe, o
runner sai com o código 77 — que o Meson registra como `SKIP`, e não como `OK` —
e imprime qual pré-condição faltou. Nesta máquina, como usuário comum, três L3
pulam porque `/dev/hugepages` é `drwxr-xr-x root root`: a condição é conferida,
não suposta. Confirme por conta própria com `ls -ld /dev/hugepages`, e rode
`sudo ./scripts/test-all.sh l3` para exercitá-los de fato.

A distinção existe porque a alternativa é pior: um teste que precisa de
privilégio e *finge* passar sem ele publica um verde que não corresponde a
verificação nenhuma.

## Fluxo recomendado

### 1. Estudo teórico

Comece pela documentação em `docs/` e `trilha/`.

### 2. Prática modular

Cada módulo deve ser executado, entendido e documentado.

### 3. Comparação com C++23 puro

A alternativa em C++23 puro deve ser usada para entender custos, abstrações e arquitetura.

### 4. Benchmark e análise crítica

O objetivo não é só "rodar", mas entender por que a arquitetura funciona e quando a escolha é correta.

## Objetivo final

O projeto busca formar uma base técnica sólida para quem quer:

- aprender DPDK de forma consistente
- compreender software de alto desempenho
- trabalhar com arquitetura de dados e plano de dados (*data plane*)
- comparar DPDK com C++23 puro de forma crítica e didática
- construir documentação profissional e material de estudo real

## Contribuição

Sugestões de módulos, estudos, exemplos e melhorias na didática são bem-vindas.

## Segurança

Como relatar problema, e o que conta como problema neste contexto:
[SECURITY.md](SECURITY.md). Resumo: o ativo a proteger é a **procedência do
conteúdo**, não sigilo — não há segredo aqui. Todo commit é assinado, e a
`main` exige assinatura verificada.

## Licença

Conteúdo publicado para fins educacionais e de estudo.

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
