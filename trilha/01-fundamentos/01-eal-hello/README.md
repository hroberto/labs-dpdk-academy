# Tópico 01 — Inicialização da EAL

> **Nível 3** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: DPDK instalado ([ferramental](../../../docs/00-visao-geral/ferramental.md))

> **In English.** The smallest complete DPDK program: initialize the EAL, report
> what it created, shut down. The lesson is in the failure paths — there are
> **two**, and only one reaches your code. An unknown argument makes the EAL
> terminate the process itself (exit 234, which is `-EINVAL` truncated to 8
> bits); a valid argument with an impossible value returns `-1` and lets you
> handle it. The L2 test asserts both, including the *absence* of your error
> message in the first case.

## 1. Fundamento: o que a EAL resolve

Um programa comum não precisa perguntar em qual núcleo roda, de qual nó de
memória vem sua alocação, ou se as páginas são de 4 KB ou 2 MB. O kernel decide
por ele, e as escolhas são razoáveis para carga geral.

Para plano de dados, essas escolhas deixam de ser razoáveis. Em 10 GbE com
quadros de 64 bytes chegam 14,88 milhões de pacotes por segundo — cerca de
**67 nanossegundos por pacote**. Uma única troca de contexto ou uma falha de TLB
consome boa parte desse orçamento. O programa precisa decidir ele mesmo onde
roda e de onde vem sua memória.

A **[EAL][cEAL]** (*Environment Abstraction Layer*) é a camada que toma essas decisões
antes da primeira linha da sua lógica executar. Ela é o que transforma um
processo comum em um processo de plano de dados.

## 2. Mecanismo: o que [`rte_eal_init()`][apiealinit] faz

A chamada faz muito mais do que "inicializar":

| Etapa | Efeito |
|---|---|
| Interpreta as opções da EAL | consome os argumentos antes de `--` |
| Cria as threads dos **lcores** | uma por núcleo pedido em [`-l`][optlcore], fixada nele |
| Reserva memória | [hugepages][cHuge] por nó NUMA, ou anônima com [`--no-huge`][optdebug] |
| Escolhe o modo IOVA | endereço físico ou virtual para DMA |
| Descobre dispositivos | varre os barramentos (PCI, vdev) |
| Inicializa subsistemas | logs, timers, modo primário/secundário |

> **lcore** (*logical core*) é a unidade de execução do DPDK: uma thread criada
> pela EAL e **fixada** a uma CPU lógica. O [glossário oficial][glossario] a
> chama de "unidade lógica de execução do processador, às vezes chamada thread
> de hardware ou thread da EAL". É por isso que `-l 0` resulta em um lcore, e
> não em "um núcleo disponível": você está pedindo *threads fixadas*, não
> permissão para usar núcleos.

Duas propriedades do contrato importam desde já:

**Ela devolve quantos argumentos consumiu, não zero em sucesso.** Um erro comum
é tratar o retorno como código de status. O valor serve para avançar `argv`:

```c
int consumidos = rte_eal_init(argc, argv);
if (consumidos < 0) {
    fprintf(stderr, "EAL: %s\n", rte_strerror(rte_errno));
    return EXIT_FAILURE;          /* ENCERRE AQUI. Ver o aviso abaixo. */
}
argc -= consumidos;
argv += consumidos;   /* agora argv aponta para os argumentos da APLICAÇÃO */
```

> **O `return` não é zelo: é obrigatório.** Uma versão anterior deste documento
> trazia `if (consumidos < 0) { /* rte_errno diz o motivo */ }` — com o corpo
> vazio. Em erro, `consumidos` vale `-1`, a execução cai nas duas linhas
> seguintes, e elas fazem `argc + 1` e `argv - 1`: um ponteiro **antes** do
> início do vetor. Isso é comportamento indefinido, e o programa segue rodando
> como se tudo estivesse bem. Foi apontado numa revisão externa que leu apenas o
> texto — o trecho publicado era mais perigoso que o código real, porque é o
> trecho que se copia.

**Ela é global e não reentrante.** Não pode ser chamada duas vezes no mesmo
processo — fato que determina como este projeto estrutura os testes de
integração (ver seção 5).

**E nem todo erro chega a você.** O trecho acima trata `consumidos < 0`, e esse
ramo existe — mas há uma classe de falha que nunca o alcança: **argumento
desconhecido encerra o processo dentro da própria EAL**, sem retornar:

```console
$ ./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0 --opcao-inexistente --in-memory --no-huge
ARGPARSE: unknown argument --opcao-inexistente!
$ echo $?
234
```

Repare no que **não** apareceu: a mensagem `Erro ao inicializar a EAL`, que é o
que [`hello_dpdk.c`](hello_dpdk.c) imprimiria no ramo de erro. Ela não foi
impressa porque aquele ramo não executou. O código 234 vem da EAL, não da
aplicação.

A consequência prática é que **validar argumentos da EAL antes de chamá-la não é
possível pela própria EAL**: ou o argumento está certo, ou o processo morre.
Código que precisa sobreviver a configuração inválida — um supervisor que tenta
várias configurações, por exemplo — tem de validar antes, ou aceitar que a
tentativa custa um processo.

**E ela não é barata.** Medida com **exatamente a configuração deste tópico**
(`-l 0 --in-memory --no-huge`), `rte_eal_init()` custa **123 ms** de mediana,
contra **0,30 ms** de [`rte_eal_cleanup()`][apiealclean] — mais de duas ordens de
grandeza entre nascer e morrer. O número é medido por
[`docs/02-runtime-dpdk/medicoes/custo-init.c`](../../../docs/02-runtime-dpdk/medicoes/custo-init.c),
que precisa de um processo por amostra justamente por causa da não-reentrância.
Guarde a consequência desde já: um processo DPDK é um **serviço de longa
duração**, nunca algo que se sobe por requisição.

## 3. Trade-offs: as opções usadas aqui

O comando de estudo é:

```bash
./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0 --in-memory --no-huge
```

| Opção | O que faz | Custo |
|---|---|---|
| `-l 0` | usa apenas o lcore 0 | nenhum, para este exemplo |
| [`--in-memory`][optmem] | não grava arquivos de runtime em disco | impede processos secundários |
| `--no-huge` | usa memória anônima de 4 KB | **mais falhas de TLB; impede processos secundários; nem todo [PMD][cPMD] aceita** |

> **PMD** (*Poll Mode Driver*) é o driver de NIC do DPDK, que roda em user-space
> e **consulta** a placa em laço em vez de esperar interrupção — daí o nome. É o
> que substitui o driver do kernel no caminho de dados. Nenhum PMD é usado neste
> tópico; o termo aparece porque a escolha de memória afeta quais deles
> funcionam.

`--no-huge` merece atenção. Ele existe para permitir que este tópico rode em
qualquer máquina, sem privilégios. Mas hugepages não são um detalhe de
configuração: elas reduzem falhas de TLB porque uma página de 2 MB cobre o mesmo
espaço que 512 páginas de 4 KB. Em carga real, você quer hugepages. Aqui,
optamos por portabilidade porque o objeto de estudo é o ciclo de vida da EAL.

Sem `--no-huge`, e sem hugepages reservadas, a EAL aborta com
`EAL: Cannot get hugepage information`.

**Nesta máquina o cenário é outro, e vale reproduzir.** Há 1024 hugepages
reservadas, mas `/dev/hugepages` pertence a `root` com modo `0755`. A falha,
portanto, é de **permissão**, não de ausência:

```console
$ ./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0
EAL: Detected CPU lcores: 24
EAL: Detected NUMA nodes: 1
EAL: Detected shared linkage of DPDK
EAL: Selected IOVA mode 'VA'
EAL: get_seg_fd(): open '/dev/hugepages/rtemap_0' failed: Permission denied
EAL: Couldn't get fd on hugepage file
EAL: error allocating rte services array
EAL: rte_service_init() failed
Erro ao inicializar a EAL: Cannot allocate memory
```

Duas mensagens distintas, duas causas distintas: uma diz que **não há** hugepage;
a outra, que **não se pode abri-la**. Confundir as duas leva a reservar mais
memória quando o que falta é permissão.

E há um terceiro caso, que surpreende: `--in-memory` **sozinho**, sem
`--no-huge`, funciona — e usa hugepage de verdade, obtida por `memfd` sem
precisar de acesso a `/dev/hugepages`. É o que a
[§4.5 do módulo 02](../../../docs/02-runtime-dpdk/README.md#45-o-que-desliga-o-modelo-multiprocesso-sem-avisar)
demonstra. Para hugepages com arquivo, sem rodar como `root`, o projeto traz
[`scripts/preparar-hugepages.sh`](../../../scripts/preparar-hugepages.sh).

> **As duas opções custam a mesma coisa, e só uma avisa.** `--in-memory` declara
> o efeito na própria ajuda da EAL (`disables secondary process support`).
> `--no-huge` não declara nada: o processo primário sobe normalmente e é o
> **secundário** que falha depois, com `EAL: Cannot init memory` — mensagem que
> não menciona a opção responsável. O motivo é o mesmo nos dois casos: sem
> arquivo respaldando a memória, não há o que um segundo processo mapear. A
> demonstração das duas falhas está na
> [§4.5 do módulo 02](../../../docs/02-runtime-dpdk/README.md#45-o-que-desliga-o-modelo-multiprocesso-sem-avisar).

> **Onde ficam os arquivos de runtime.** Quase todo material diz `/var/run/dpdk`,
> e para `root` é isso mesmo. Para um usuário comum, a EAL usa o diretório de
> runtime da sessão: `$XDG_RUNTIME_DIR/dpdk/<prefixo>/`. Quem procura no lugar
> errado conclui que a EAL não gravou nada. Ver
> [§3.2 do módulo 02](../../../docs/02-runtime-dpdk/README.md#32-o-que-a-eal-deixa-no-host).

## 4. Implementação

O código está em [`hello_dpdk.c`](hello_dpdk.c). Ele faz o ciclo mínimo:
inicializa, reporta o que a EAL decidiu, e encerra com [`rte_eal_cleanup()`][apiealclean].

Compile e execute:

```bash
./scripts/build-all.sh
./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0 --in-memory --no-huge
```

Saída esperada:

```
EAL: Detected CPU lcores: 24
EAL: Detected NUMA nodes: 1
EAL: Detected shared linkage of DPDK
EAL: Selected IOVA mode 'VA'
DPDK Academy: EAL inicializada com sucesso.
Versao do DPDK: DPDK 25.11.0
Lcores disponiveis: 1 (lcore principal: 0)
No NUMA do lcore principal: 0
Argumentos restantes para a aplicacao: 0
```

As linhas iniciadas por `EAL:` são da própria camada, **não são erros**. Repare
na terceira linha da saída da aplicação: a máquina tem 24 núcleos, mas
[`rte_lcore_count()`][apilcorecount] responde `1`, porque `-l 0` pediu apenas um. A EAL não usa
o que existe; usa o que foi pedido.

### Exercícios

1. Rode com `-l 0-3`. Quantos lcores a EAL reporta?
2. Rode com `-- a b c`. O que muda na última linha, e por quê?
3. Rode com uma opção inexistente. Qual o código de saída — e por que a mensagem
   de erro **da aplicação** não aparece?
4. Remova `--no-huge`, mantendo `--in-memory`. Funciona na sua máquina? Se sim,
   de onde veio a memória?
5. Remova as duas opções. Agora a EAL provavelmente falha. A mensagem fala de
   hugepage **ausente** ou de hugepage **inacessível**? As duas exigem correções
   diferentes.

## 5. Validação

Este tópico tem **apenas teste L2**, e a ausência de L1 é intencional: não há
lógica pura para isolar — o tópico *é* a inicialização do runtime.

```bash
./scripts/test-all.sh l2
```

O teste ([`tests/l2_run.sh`](tests/l2_run.sh)) verifica o contrato de linha de
comando: que `-l 0` resulta em exatamente um lcore, que argumentos após `--`
chegam à aplicação, e que uma opção inválida faz o programa sair com código
diferente de zero.

Ele é um script, e não um caso de GoogleTest, precisamente por causa da
propriedade da seção 2: como `rte_eal_init()` não pode ser chamada duas vezes no
mesmo processo, testar *variações de argumentos* exige um processo por variação.

## 6. Quando dá errado

> **A pergunta deste tópico:** o que acontece quando a EAL **não** sobe?

A [seção 2](#2-mecanismo-o-que-rte_eal_init-faz) já mostrou que existem dois
caminhos de falha e que só um deles chega ao seu código. Esta seção fecha o que
falta: **executá-los lado a lado**, ver o que cada um devolve, e saber quanto
disso é confiável.

### 6.1 Os dois caminhos, lado a lado

```console
$ ./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 999
EAL: No valid lcores in core list
EAL: invalid coremask or core-list parameter, please check specified cores are part of 0-23
EAL: Error parsing command line arguments.
Erro ao inicializar a EAL: Invalid argument
$ echo $?
1
```

A última linha é da **aplicação** — é o `fprintf` de [`hello_dpdk.c`](hello_dpdk.c)
imprimindo `rte_strerror(rte_errno)`. Compare com o caminho A da seção 2, em que
ela não aparece:

| | A — `--opcao-inexistente` | B — `-l 999` |
|---|---|---|
| `rte_eal_init()` | não retorna | devolve `-1` |
| Seu `if (consumidos < 0)` | **não executa** | executa |
| Código de saída | 234, escolhido pela EAL | `EXIT_FAILURE`, escolhido por você |
| Diagnóstico disponível | só o que a EAL imprimiu | `rte_errno` legível por você |

A consequência operacional: **um código de saída não-zero de um processo DPDK
pode não ser seu**. Um supervisor que trate "≠ 0" como "a aplicação falhou" erra
o diagnóstico no caminho A, em que a aplicação nem começou.

### 6.2 De onde vem o 234

Não é arbitrário: é `-EINVAL` truncado em 8 bits, porque o shell só enxerga o
byte baixo do que o processo devolve.

```console
$ python3 -c "print((-22) & 0xFF)"
234
```

### 6.3 Como isso é capturado — e o que o teste não garante

O [teste L2](tests/l2_run.sh) exercita **os dois caminhos**, e a separação custou
uma versão anterior: ela verificava apenas "código ≠ 0", que é verdade nos dois e
portanto não distingue nada. Hoje ele afirma o código exato e, no caminho A,
afirma também a **ausência** da mensagem da aplicação — a prova de que o ramo de
erro não rodou.

> **O que esse teste amarra a uma release.** O `234` e a mensagem
> `unknown argument` vêm de `librte_argparse`, não da EAL — conferi com
> `strings`: a string existe em `librte_argparse.so` e não em `librte_eal.so`.
> Essa biblioteca só existe a partir do **DPDK 24.03**. Numa release anterior o
> caminho A sai com outro código e outra mensagem, e o teste falha **em vermelho
> sem haver defeito no programa**. Esta máquina roda DPDK 25.11; se a sua for
> mais antiga, é esse o motivo.

## 7. Limitações

- Nenhuma NIC é envolvida. A EAL descobre dispositivos, mas nada é configurado.
- Com `--no-huge`, o comportamento de memória não representa produção.
- `rte_eal_cleanup()` libera os recursos da EAL, mas em uma aplicação real o
  encerramento correto envolve também parar e fechar as portas antes disso.

## 8. Para onde ir daqui

Dois caminhos, e a ordem entre eles é sua:

**Aprofundar o runtime** — [Módulo 02: Runtime do DPDK](../../../docs/02-runtime-dpdk/README.md).
Este tópico mostra a EAL subindo; o módulo 02 trata dela como sistema: quanto
custa inicializar e por quê, o modelo de memória por trás da reserva, processos
primário e secundário compartilhando memória sem cópia, a máquina de estados dos
lcores e o modo IOVA. É onde `--in-memory` e `--no-huge`, usados aqui como
atalho de portabilidade, aparecem com o preço que cobram.

**Seguir a prática** — [02 — mempool, ring e processamento em lote](../02-mempool-ring/),
onde a memória reservada pela EAL passa a ser usada de fato.

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
[apiealclean]: https://doc.dpdk.org/api/rte__eal_8h.html#a7a745887f62a82dc83f1524e2ff2a236
[apilcorecount]: https://doc.dpdk.org/api/rte__lcore_8h.html#a1728dc7f14571ba778d3b5b41aa09283

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cPMD]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html

[glossario]: https://doc.dpdk.org/guides/prog_guide/glossary.html

[optdebug]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#debugging-options
[optlcore]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#lcore-related-options
[optmem]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#memory-related-options
