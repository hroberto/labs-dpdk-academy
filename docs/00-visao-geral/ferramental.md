# Ferramental do projeto: build, compilação e testes

Este documento explica **quais ferramentas o projeto usa, por que cada uma foi
escolhida e o que foi descartado**. Ele é parte do conteúdo de estudo, não um
apêndice administrativo: as decisões abaixo são as mesmas que aparecem em
qualquer projeto real de plano de dados, e os erros que elas evitam são erros
que custam horas a quem está começando.

---

## 1. Fundamento: por que a escolha da ferramenta importa aqui

Em muitos projetos, o sistema de build é detalhe de infraestrutura. Em um
projeto DPDK, não é — por uma razão específica:

> **DPDK não é uma dependência de biblioteca. É uma dependência de ambiente.**

Compilar contra o DPDK exige as bibliotecas e os headers. *Executar* um programa
DPDK exige, além disso, [hugepages][hugepages] reservadas, o driver correto
([`vfio-pci` ou `uio_pci_generic`][drivers]), a NIC desvinculada do kernel e permissões adequadas. Nenhum
gerenciador de pacotes entrega esse segundo conjunto.

Essa distinção governa todas as decisões deste documento.

---

## 2. Mecanismo: as ferramentas em uso

| Camada | Ferramenta | Papel |
|---|---|---|
| Configuração do build | **[Meson][meson]** | descreve alvos, dependências e testes |
| Execução do build | **[Ninja][ninja]** | executa a compilação em paralelo |
| Descoberta do DPDK | **[pkg-config][pkgconfig]** | localiza `libdpdk.pc` do sistema |
| Dependências de teste | **[Meson wrap][wrap]** | baixa e fixa o GTest por hash |
| Testes L1 | **[GoogleTest][gtest]** | asserções sobre lógica pura |
| Testes L2 | **[Meson test][mesontest]** + shell | exercita o binário como o usuário o executa |
| Estilo e análise | **[clang-format][clangformat]**, **[clang-tidy][clangtidy]** | consistência e detecção estática |
| Diagnóstico dinâmico | **sanitizers** do compilador | [ASan][asan], [UBSan][ubsan], [TSan][tsan] |

### 2.1 Meson + Ninja

A justificativa não é preferência de estilo: **o próprio DPDK é construído com
Meson e Ninja**, e distribui um arquivo `libdpdk.pc`. Isso produz um ganho
concreto e verificável — a dependência inteira se resolve em uma linha, com [`dependency()`][mesondep]:

```meson
dpdk_dep = dependency('libdpdk', method : 'pkg-config', required : true)
```

Quando você abrir o código-fonte do DPDK para estudar um [PMD][pmd], vai encontrar
`meson.build` lá também. A ferramenta ensina junto com o conteúdo.

O Ninja é apenas o executor: ele não é escolhido separadamente, é o backend
padrão do Meson. Velocidade de build não foi o critério da decisão.

### 2.2 O padrão da linguagem C: `c11` com `_GNU_SOURCE`

Uma armadilha que aparece na primeira compilação contra o DPDK. Configurar
`c_std=c11` (ISO estrito) faz a compilação **falhar** nos headers do DPDK:

```
/usr/include/dpdk/rte_ring.h:59: error: unknown type name 'ssize_t'
/usr/include/dpdk/rte_string_fns.h:74: error: implicit declaration of 'strnlen'
```

Motivo: `ssize_t` e `strnlen` são POSIX, não ISO C. Em modo ISO estrito o
compilador define `__STRICT_ANSI__`, e as [macros de teste de recurso][ftm] da
glibc deixam de expor essas declarações.

Existem **duas correções possíveis**, e a diferença entre elas é o conteúdo desta
seção:

| Correção | O que faz | Custo |
|---|---|---|
| `c_std=gnu11` | troca o padrão da linguagem por C11 + extensões GNU | resolve o sintoma e **esconde o mecanismo**; passa a aceitar extensões que não se pretendia usar |
| `c_std=c11` + `#define _GNU_SOURCE` por arquivo | mantém o padrão e pede explicitamente as declarações POSIX | uma linha no topo de cada fonte que use os headers |

**O projeto usa a segunda**, que é o que o próprio DPDK faz upstream. As duas
compilam; medido nesta máquina, com um programa que inclui `rte_eal.h`,
`rte_mempool.h` e `rte_mbuf.h`:

```console
$ cc -std=c11 $(pkg-config --cflags libdpdk) -c t.c            # 3 erros
$ cc -std=c11 -D_GNU_SOURCE $(pkg-config --cflags libdpdk) -c t.c   # 0 erros
$ cc -std=gnu11 $(pkg-config --cflags libdpdk) -c t.c               # 0 erros
```

A distinção importa porque são coisas de naturezas diferentes: `-std=` escolhe o
**dialeto da linguagem**; `_GNU_SOURCE` escolhe **quais declarações a biblioteca
expõe**. Trocar o dialeto para consertar um problema de biblioteca funciona pelo
motivo errado.

> **Esta seção foi corrigida.** A versão anterior prescrevia `gnu11` e concluía
> que "o padrão correto é `gnu11`". Uma revisão externa apontou que o DPDK
> upstream usa C11 com `_GNU_SOURCE`, e a verificação acima confirmou. O
> diagnóstico original estava certo — o remédio, não.

> **Lição transferível:** ao ver "tipo desconhecido" em header de terceiros,
> suspeite das macros de teste de recurso antes de mexer no padrão da linguagem.
> Baixar o rigor do compilador é a correção que sempre funciona e quase nunca é
> a certa.

### 2.3 Gerenciamento de dependências: pkg-config e Meson wrap

O projeto tem exatamente três dependências:

| Dependência | Natureza | Origem |
|---|---|---|
| DPDK | ambiente (kernel, [hugepages][cHuge], drivers) | sistema, via `pkg-config` |
| GoogleTest | teste, apenas desenvolvimento | `subprojects/gtest.wrap` |
| [google-benchmark][benchmark] *(previsto)* | medição, apenas desenvolvimento | wrap, quando a Etapa 5 chegar |

O [arquivo wrap][wrap] `subprojects/gtest.wrap` é **versionado no repositório** e fixa a
versão e os hashes criptográficos do código baixado. O código em si não é
versionado. O resultado é um build reprodutível sem inchar o repositório.

---

## 3. Trade-offs: o que foi descartado, e por quê

Descartar ferramentas é uma decisão de engenharia tão real quanto adotá-las.
Estas foram avaliadas e recusadas para **este** projeto.

### 3.1 [CMake][cmake]

Funcionaria. Mas exigiria `FindPkgConfig` mais a construção manual de um alvo
importado, para produzir o que o Meson resolve em uma linha — e afastaria o
estudante da ferramenta que o próprio DPDK usa.

### 3.2 [Conan 2][conan]

Foi avaliado seriamente e **removido**. Duas razões, uma factual e uma
conceitual.

A factual: **não existe receita de DPDK no [Conan Center][conancenter]**. A busca
por `dpdk` na API do ConanCenter retorna lista vazia (contra seis versões para
`zlib`, usado como controle), o diretório `recipes/dpdk` não existe no
[conan-center-index][cci], e as duas propostas de adicioná-lo
([PR #7518][pr7518] e [PR #24817][pr24817]) foram fechadas sem merge.
Uma declaração `requires = "dpdk/22.11"` simplesmente não resolve.

A conceitual, mais importante: mesmo que a receita existisse, ela entregaria
bibliotecas — e o estudante continuaria tendo que configurar hugepages, carregar
`vfio-pci` e fazer o binding da NIC. **Empacotar o DPDK esconderia exatamente
aquilo que esta trilha existe para ensinar.**

### 3.3 [vcpkg][vcpkg]

Este merece nuance, porque a resposta fácil está errada: **o vcpkg tem, sim, uma
[porta de DPDK][vcpkgdpdk]** (versão 26.3), mantida e funcional. Ela compila o DPDK da fonte
— usando Meson internamente — e gera `libdpdk.pc`, de modo que integraria com
este projeto sem alterar uma linha do `meson.build`.

Ainda assim, não foi adotado, por três custos concretos:

1. **Primeiro contato caro.** `apt install dpdk-dev` entrega cerca de sessenta
   bibliotecas `librte_*` em segundos; o vcpkg compila tudo da fonte. Numa
   trilha cujo objetivo é chegar rápido ao [`rte_eal_init()`][apiealinit], é imposto cobrado
   antes da primeira aula.
2. **Não resolve o problema real.** Entrega bibliotecas e um `.pc`; hugepages,
   `vfio-pci` e binding continuam por conta do estudante.
3. **Drivers reduzidos por padrão.** A porta desabilita `net/pcap`, mlx4/mlx5,
   QAT e outros salvo se a *feature* for pedida — um muro que não é do DPDK, é
   de empacotamento.

**Quando reconsiderar:** se o projeto passar a exigir benchmark reprodutível
cruzando máquinas ("medido contra DPDK 26.3, exatamente"), fixar a versão passa
a valer o custo do build. Isso está previsto para a Etapa 5 e será reavaliado lá.

---

## 4. Prática: os dois níveis de teste

A separação entre L1 e L2 não é burocracia de testes; ela reflete uma separação
arquitetural do código.

### 4.1 L1 — lógica pura, sem runtime

**O que é:** testes sobre a lógica que não depende do DPDK. No tópico 02, isso é
`packet.c`, deliberadamente separado de `pipeline_ring.c`.

**Por que existe:** roda em qualquer máquina, em milissegundos, sem hugepages,
sem privilégios e sem NIC. Se um teste precisa de [EAL][cEAL] para verificar uma regra de
negócio, a regra está acoplada ao runtime sem necessidade — o teste L1 vira um
detector de acoplamento.

**Ferramenta:** [GoogleTest][gtest], obtido pelo wrap do Meson. Testa código C
através de `extern "C"`.

O ganho mais relevante do GTest aqui são os [testes parametrizados][gtestparam],
que permitem expressar um invariante do próprio tópico:

```cpp
INSTANTIATE_TEST_SUITE_P(TamanhosDeLote, ResultadoIndependeDoLote,
                         ::testing::Values(1u, 2u, 3u, 4u, 8u, 10u, 32u));
```

Esse teste afirma que **o tamanho do lote é um botão de desempenho, nunca de
semântica**. Se processar em lotes de 1 e em lotes de 32 produzisse resultados
diferentes, haveria um bug de lógica disfarçado de otimização. Sete tamanhos de
lote, um corpo de teste.

### 4.2 L2 — integração com o runtime real

**O que é:** execução do binário como o estudante o executa, incluindo os
argumentos da EAL.

**Por que NÃO usa GTest:** [`rte_eal_init()`][rteeal] é global e não pode ser chamada duas
vezes no mesmo processo. O GTest roda todos os casos em um único processo, o que
obrigaria a compartilhar uma EAL entre todos os testes — impedindo justamente o
que o L2 precisa verificar: *variações* de argumentos (`-l 0`, `--no-huge`,
opção inválida, argumentos após `--`).

Esse contrato de linha de comando é conteúdo do tópico. Por isso o L2 é um
script que trata o binário como caixa-preta.

**O que o L2 verifica que o L1 não consegue:** no tópico 02, a asserção central
é `Objetos livres no pool ao final: 4095 de 4095`. Vazamento de objeto de
[mempool][mempool] é a falha clássica deste tema — o pool esvazia, a recepção passa a
devolver zero e o pipeline para em silêncio. Só o runtime revela isso.

### 4.3 Executando

```bash
./scripts/build-all.sh          # configura e compila
./scripts/test-all.sh           # tudo
./scripts/test-all.sh l1        # só lógica pura (rápido, sem DPDK)
./scripts/test-all.sh l2        # só integração
```

Ou diretamente pelo Meson:

```bash
meson setup build && meson compile -C build
meson test -C build --suite l1 --print-errorlogs
meson test -C build --suite l2 --print-errorlogs
```

> **Nota sobre CTest:** [`ctest`][ctest] é o runner do CMake e não se aplica
> aqui. O equivalente no Meson é [`meson test`][mesontest], usado acima.

---

## 5. Validação: sanitizers e análise estática

O Meson expõe os sanitizers do compilador nativamente pela opção interna
[`b_sanitize`][mesonopts] — não é preciso opção própria do projeto:

```bash
meson setup build-asan -Db_sanitize=address,undefined
meson test -C build-asan
```

Cuidado ao aplicar sanitizers a código DPDK: o [ASan][asan] intercepta o alocador
do sistema, mas os objetos do [`rte_mempool`][mempool] vêm de hugepages geridas
pela [EAL][eal] e
ficam fora do alcance dele. O ASan pega erros na sua lógica; **não** substitui a
verificação de integridade do pool feita no L2.

Estilo e análise estática são governados por [`.clang-format`][clangformat] e
[`.clang-tidy`][clangtidy] na raiz do repositório.

---

## 5.1 Medição: como este projeto produz números

Medir é ferramenta tanto quanto compilar, e aqui obedece a três regras.

**Amostragem, não medição única.** Os programas em
[`docs/01-fundamentos/medicoes/`](../01-fundamentos/medicoes/) compartilham
[`statistics.h`](../01-fundamentos/medicoes/statistics.h), que coleta várias
amostras e publica mediana, intervalo interquartil, amplitude e coeficiente de
variação. Os selos `~` e `!` saem da dispersão do miolo — robusta, por ignorar
as caudas — e o coeficiente de variação é lido em relação a ela: muito maior
denuncia amostras isoladas destoantes. Assim **o próprio resultado avisa quando
não merece confiança**, e distingue oscilação real de interferência pontual. Medição única esconde dispersão e já produziu, neste
repositório, números que variavam 40% entre execuções sem que isso aparecesse.

**Aquecimento antes de medir.** Sem ele, a primeira medição capta o arranque da
CPU — frequência baixa e caches frias — e não o regime permanente.

**Fontes têm hierarquia.** Requisito técnico vem de organismo de normalização,
e o documento nomeia qual: **IEEE 802.3** para o formato do quadro Ethernet,
**ITU-T G.114** para atraso em telefonia, **RFC 2544** da IETF para metodologia
de medição de vazão. Abaixo disso vêm a documentação oficial de cada projeto e a
literatura acadêmica revisada. Imprensa técnica entra apenas quando é a única
fonte de uma medição específica de hardware, e vem rotulada como tal.
Enciclopédia colaborativa não é usada como fonte.

**Confronto com a literatura.** Números de uma máquina só carregam os vícios
dela. Por isso as medições são comparadas com as referências aceitas na área:
o livro de **Paul McKenney**, mantenedor do RCU no kernel
([*Is Parallel Programming Hard*][perfbook]), o artigo de **David, Guerraoui e
Trigonakis** no [SOSP 2013][sosp], e o artigo original do futex de **Franke,
Russell e Kirkwood** ([OLS 2002][futex]). O confronto completo, incluindo as
discrepâncias que ele explicou, está na
[§10 dos Fundamentos](../01-fundamentos/README.md#10-confronto-com-a-literatura).

> Para o CI, `DPDK_ACADEMY_AMOSTRAS=3` reduz a coleta: lá o objetivo é verificar
> que os programas executam, não produzir estatística que ninguém vai ler.

**Âncoras de linha para o código.** Quando um documento cita um número, o link
leva **direto à linha** da função que o produziu — leitura mais fluida que
"procure a função no arquivo". O custo é manutenção: números de linha mudam
quando o código muda, e um link desatualizado não quebra, aponta em silêncio
para o trecho errado. Por isso a convenção exige que o **texto do link seja o
nome do símbolo**, e [`scripts/verificar-ancoras.py`](../../scripts/verificar-ancoras.py)
confere se cada âncora ainda cai sobre ele. Roda como teste da suíte
(`meson test --suite docs`), então uma âncora desatualizada quebra o CI em vez
de enganar o leitor.

**Referências para a documentação oficial.** Os símbolos e conceitos do DPDK
citados nos documentos apontam para a documentação oficial, seguindo um mapa
canônico em [`scripts/mapa-links-dpdk.md`](../../scripts/mapa-links-dpdk.md):
mesmo símbolo, mesmo destino, uma referência por arquivo na primeira ocorrência.
O mapa também registra duas armadilhas — link em título quebra a âncora da
seção, e âncora Doxygen errada devolve HTTP 200 do mesmo jeito.

---

## 6. Limitações conhecidas

- **Hugepages não são exercitadas nos testes.** Todos os testes usam `--no-huge`
  para rodar em qualquer máquina e em CI. Isso é uma escolha de portabilidade,
  não uma afirmação de que [hugepages][hugepages] sejam dispensáveis — em carga real elas
  reduzem *TLB miss* de forma significativa. Um tópico dedicado tratará disso.
- **Nenhum teste toca hardware de rede.** Não há NIC nem [PMD][cPMD] físico envolvido
  até os tópicos de RX/TX, que usarão PMDs virtuais ([`net_null`][netnull],
  [`net_ring`][netring], [`net_tap`][nettap], [`net_af_packet`][netafpacket]).
- **Os números de tempo impressos pelos exemplos não são benchmark.** São uma
  ordem de grandeza de execução única, sem controle de frequência, de afinidade
  ou de aquecimento de cache. Medição séria entra na Etapa 5, com
  [google-benchmark][benchmark] e metodologia documentada.
- **O ambiente de referência é Linux.** O DPDK suporta FreeBSD e Windows, mas
  nada aqui foi verificado nessas plataformas.

---

## 7. Referências externas

Documentação oficial de cada ferramenta e conceito citado acima.

### DPDK

| Assunto | Referência |
|---|---|
| Instalação em Linux | [Getting Started Guide][gsg] |
| Requisitos e hugepages | [System Requirements][hugepages] |
| Drivers `vfio-pci` / `uio_pci_generic` | [Linux Drivers][drivers] |
| EAL (camada de abstração) | [Environment Abstraction Layer][eal] |
| Mempool | [Mempool Library][mempool] |
| Ring | [Ring Library][ring] |
| mbuf | [Mbuf Library][mbuf] |
| Poll Mode Drivers | [Ethdev / PMD][pmd] |
| PMDs virtuais | [null][netnull] · [ring][netring] · [tap][nettap] · [af_packet][netafpacket] · [af_xdp][netafxdp] |
| Referência de API | [API do DPDK][dpdkapi] · [`rte_eal.h`][rteeal] |
| Ferramenta de diagnóstico | [testpmd][testpmd] |

### Build e dependências

| Assunto | Referência |
|---|---|
| Meson | [Manual][meson] · [Referência de funções][mesondep] · [Opções internas][mesonopts] |
| Sistema de wrap | [Wrap dependency system][wrap] |
| Ninja | [ninja-build.org][ninja] |
| pkg-config | [freedesktop.org][pkgconfig] |
| CMake (não usado) | [cmake.org][cmake] · [ctest][ctest] |
| Conan (avaliado, descartado) | [Documentação][conan] · [Conan Center][conancenter] · [conan-center-index][cci] |
| vcpkg (avaliado, descartado) | [vcpkg.io][vcpkg] · [porta de DPDK][vcpkgdpdk] |

### Testes e qualidade

| Assunto | Referência |
|---|---|
| GoogleTest | [Documentação][gtest] · [Testes parametrizados][gtestparam] · [Referência de asserções][gtestref] |
| Testes no Meson | [Unit tests][mesontest] |
| google-benchmark | [Repositório][benchmark] |
| clang-format | [Documentação][clangformat] |
| clang-tidy | [Documentação][clangtidy] |
| Sanitizers | [AddressSanitizer][asan] · [UndefinedBehaviorSanitizer][ubsan] · [ThreadSanitizer][tsan] |

### Linguagem

| Assunto | Referência |
|---|---|
| Padrões da linguagem C no GCC | [Standards][gccstd] |
| Macros de teste de recurso da glibc | [Feature Test Macros][ftm] |
| Recursos do C++23 | [cppreference][cpp23] |

## 8. Navegação interna

- [Visão geral do projeto](README.md)
- [Plano de estudo](../plano-estudo-dpdk.md)
- [Tópico 01 — EAL](../../trilha/01-fundamentos/01-eal-hello/)
- [Tópico 02 — mempool e ring](../../trilha/01-fundamentos/02-mempool-ring/)

<!-- ------------------------------------------------------------------- -->
<!-- Definições dos links de referência usados ao longo deste documento.  -->
<!-- ------------------------------------------------------------------- -->

[gsg]: https://doc.dpdk.org/guides/linux_gsg/
[hugepages]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[drivers]: https://doc.dpdk.org/guides/linux_gsg/linux_drivers.html
[eal]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[mempool]: https://doc.dpdk.org/guides/prog_guide/mempool_lib.html
[ring]: https://doc.dpdk.org/guides/prog_guide/ring_lib.html
[mbuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html
[pmd]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html
[netnull]: https://doc.dpdk.org/guides/nics/null.html
[netring]: https://doc.dpdk.org/guides/nics/ring.html
[nettap]: https://doc.dpdk.org/guides/nics/tap.html
[netafpacket]: https://doc.dpdk.org/guides/nics/af_packet.html
[netafxdp]: https://doc.dpdk.org/guides/nics/af_xdp.html
[dpdkapi]: https://doc.dpdk.org/api/
[rteeal]: https://doc.dpdk.org/api/rte__eal_8h.html
[testpmd]: https://doc.dpdk.org/guides/testpmd_app_ug/

[meson]: https://mesonbuild.com/
[mesondep]: https://mesonbuild.com/Reference-manual_functions.html
[mesonopts]: https://mesonbuild.com/Builtin-options.html
[mesontest]: https://mesonbuild.com/Unit-tests.html
[wrap]: https://mesonbuild.com/Wrap-dependency-system-manual.html
[ninja]: https://ninja-build.org/
[pkgconfig]: https://www.freedesktop.org/wiki/Software/pkg-config/
[cmake]: https://cmake.org/
[ctest]: https://cmake.org/cmake/help/latest/manual/ctest.1.html
[conan]: https://docs.conan.io/2/
[conancenter]: https://conan.io/center
[cci]: https://github.com/conan-io/conan-center-index
[pr7518]: https://github.com/conan-io/conan-center-index/pull/7518
[pr24817]: https://github.com/conan-io/conan-center-index/pull/24817
[vcpkg]: https://vcpkg.io/
[vcpkgdpdk]: https://github.com/microsoft/vcpkg/tree/master/ports/dpdk

[gtest]: https://google.github.io/googletest/
[gtestparam]: https://google.github.io/googletest/advanced.html
[gtestref]: https://google.github.io/googletest/reference/testing.html
[benchmark]: https://github.com/google/benchmark
[clangformat]: https://clang.llvm.org/docs/ClangFormat.html
[clangtidy]: https://clang.llvm.org/extra/clang-tidy/
[asan]: https://clang.llvm.org/docs/AddressSanitizer.html
[ubsan]: https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
[tsan]: https://clang.llvm.org/docs/ThreadSanitizer.html

[gccstd]: https://gcc.gnu.org/onlinedocs/gcc/Standards.html
[ftm]: https://www.gnu.org/software/libc/manual/html_node/Feature-Test-Macros.html
[cpp23]: https://en.cppreference.com/w/cpp/23
[perfbook]: https://arxiv.org/abs/1701.00854
[sosp]: https://dblp.org/rec/conf/sosp/DavidGT13.html
[futex]: https://www.kernel.org/doc/ols/2002/ols2002-pages-479-495.pdf

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3

[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cPMD]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html
