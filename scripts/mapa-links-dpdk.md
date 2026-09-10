# Mapa de links da documentação do DPDK

Registro canônico dos símbolos e conceitos do DPDK citados nos documentos deste
repositório, com o link oficial de cada um. Serve a dois propósitos:

1. **Consistência** — o mesmo símbolo aponta sempre para o mesmo lugar.
2. **Cobertura** — ao escrever documento novo, consultar esta tabela evita
   deixar API sem referência.

Convenção adotada: **a primeira ocorrência de cada símbolo em cada arquivo vira
link**; repetições no mesmo arquivo ficam em texto simples, para não poluir a
leitura.

## Funções (referência de API, com âncora Doxygen)

| Símbolo | Rótulo | URL |
|---|---|---|
| `rte_eal_init()` | `apiealinit` | <https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3> |
| `rte_eal_cleanup()` | `apiealclean` | <https://doc.dpdk.org/api/rte__eal_8h.html#a7a745887f62a82dc83f1524e2ff2a236> |
| `rte_lcore_count()` | `apilcorecount` | <https://doc.dpdk.org/api/rte__lcore_8h.html#a1728dc7f14571ba778d3b5b41aa09283> |
| `rte_socket_id()` | `apisocketid` | <https://doc.dpdk.org/api/rte__lcore_8h.html#a7c8da4664df26a64cf05dc508a4f26df> |
| `rte_eth_dev_info_get()` | `apidevinfo` | <https://doc.dpdk.org/api/rte__ethdev_8h.html#a47933dd514cda48f158117ddfa139658> |
| `rte_eth_dev_socket_id()` | `apidevsocket` | <https://doc.dpdk.org/api/rte__ethdev_8h.html#ad032e25f712e6ffeb0c19eab1ec1fd2e> |
| `rte_eth_tx_burst()` | `apitxburst` | <https://doc.dpdk.org/api/rte__ethdev_8h.html#a83e56cabbd31637efd648e3fc010392b> |
| `rte_eth_dev_rx_intr_enable()` | `apirxintr` | <https://doc.dpdk.org/api/rte__ethdev_8h.html#a88371c8cf4b2ec9e3e2e7c9adae2fe9a> |
| `rte_pktmbuf_pool_create()` | `apipoolcreate` | <https://doc.dpdk.org/api/rte__mbuf_8h.html#a8f4abb0d54753d2fde515f35c1ba402a> |
| `rte_mempool_put_bulk()` | `apiputbulk` | <https://doc.dpdk.org/api/rte__mempool_8h.html#a5e46fc827d764e516e8ff0c3f00e33fc> |
| `rte_ring_enqueue_burst()` | `apienqburst` | <https://doc.dpdk.org/api/rte__ring_8h.html#a85ad08ed07e2e485c94466e03bf252c4> |
| `rte_ring_dequeue_burst()` | `apiringdeq` | <https://doc.dpdk.org/api/rte__ring_8h.html#a9dd35643c4cdc6fa00ece3cafbcd94d2> |
| `rte_eal_process_type()` | `apiproctype` | <https://doc.dpdk.org/api/rte__eal_8h.html#a1280c4f5e0f2082163ecb1f30a968cd9> |
| `rte_eal_iova_mode()` | `apiiovamode` | <https://doc.dpdk.org/api/rte__eal_8h.html#a1e1ff16a6096013452673ea31ea16aa8> |
| `rte_memzone_reserve()` | `apimzreserve` | <https://doc.dpdk.org/api/rte__memzone_8h.html#a58c7cd707097b56e3ca29fb3c172565e> |
| `rte_memzone_lookup()` | `apimzlookup` | <https://doc.dpdk.org/api/rte__memzone_8h.html#ac7fc18c445135eb2e91a1f2ab989cdde> |
| `rte_memzone_free()` | `apimzfree` | <https://doc.dpdk.org/api/rte__memzone_8h.html#aaa4ec5a6d04c8cd4a55beae18f52aa31> |
| `rte_eal_remote_launch()` | `apiremotelaunch` | <https://doc.dpdk.org/api/rte__launch_8h.html#a2bf98eda211728b3dc69aa7694758c6d> |
| `rte_eal_wait_lcore()` | `apiwaitlcore` | <https://doc.dpdk.org/api/rte__launch_8h.html#ae9500e1d35bd4cfb95d18c0be863cb1e> |
| `rte_eal_get_lcore_state()` | `apilcorestate` | <https://doc.dpdk.org/api/rte__launch_8h.html#a66d883d90f6112489b69c996a2f6f2ab> |
| `rte_get_main_lcore()` | `apimainlcore` | <https://doc.dpdk.org/api/rte__lcore_8h.html#a5449c6ee062fe3641520374152ce6c67> |
| `rte_lcore_to_socket_id()` | `apitosocketid` | <https://doc.dpdk.org/api/rte__lcore_8h.html#a023b4909f52c3cdf0351d71d2b5032bc> |
| `rte_lcore_to_cpu_id()` | `apitocpuid` | <https://doc.dpdk.org/api/rte__lcore_8h.html#acbf23499dc0b2d223e4d311ad5f1b04e> |
| `rte_lcore_cpuset()` | `apicpuset` | <https://doc.dpdk.org/api/rte__lcore_8h.html#a830bea1c9dda2c18d04252f297e25721> |
| `rte_get_tsc_hz()` | `apitschz` | <https://doc.dpdk.org/api/rte__cycles_8h.html#ae016e608f344823e677819d8f04264c5> |
| `rte_get_tsc_cycles()` | `apitsccycles` | <https://doc.dpdk.org/api/rte__cycles_8h.html#a34aaedfb8b9fa4f83d4cb3108cda2041> |
| `rte_pause()` | `apipause` | <https://doc.dpdk.org/api/rte__pause_8h.html#ad59aa7777c93d3cfd5f10617a3acd1c5> |
| `rte_mempool_get()` | `apimpget` | <https://doc.dpdk.org/api/rte__mempool_8h.html#a6150c041e889498a08d0e0d0769292cb> |
| `rte_mempool_get_bulk()` | `apimpgetbulk` | <https://doc.dpdk.org/api/rte__mempool_8h.html#a0d326354d53ef5068d86a8b7d9ec2d61> |
| `rte_ring_create()` | `apiringcreate` | <https://doc.dpdk.org/api/rte__ring_8h.html#a155cb48ef311eddae9b2e34808338b17> |
| `rte_ring_enqueue_bulk()` | `apienqbulk` | <https://doc.dpdk.org/api/rte__ring_8h.html#ab8debfb458e927d559e7ce750048502d> |
| `rte_pktmbuf_alloc()` | `apimbufalloc` | <https://doc.dpdk.org/api/rte__mbuf_8h.html#aa45d061a7317ece01fed9185f1a3bd51> |
| `rte_pktmbuf_free()` | `apimbuffree` | <https://doc.dpdk.org/api/rte__mbuf_8h.html#a1215458932900b7cd5192326fa4a6902> |
| `rte_pktmbuf_prepend()` | `apiprepend` | <https://doc.dpdk.org/api/rte__mbuf_8h.html#a37b34f8b32723db17b2df80391bfa42d> |
| `rte_pktmbuf_chain()` | `apichain` | <https://doc.dpdk.org/api/rte__mbuf_8h.html#af52dbeb3951f5b90259d3760128ee139> |

> **`_bulk` e `_burst` são contratos diferentes, não sinônimos.** `_bulk` devolve
> "either 0 or n" — tudo ou nada; `_burst` aceita parcial e devolve quantos
> couberam. A demonstração está na
> [§3.1 do módulo 03](../docs/03-mempool-ring-mbuf/README.md#31-_bulk-e-_burst-não-são-sinônimos).

> **Cuidado com `rte_lcore_to_cpu_id()`.** Apesar do nome, ela **não** devolve o
> número da CPU: a documentação da própria função diz *"the id of the lcore on a
> socket starting from zero"* — um índice relativo ao nó NUMA. Quem quer a CPU
> real usa `rte_lcore_cpuset()`. A distinção está demonstrada na
> [§5.1 do módulo 02](../docs/02-runtime-dpdk/README.md#51-lcore-não-é-cpu).

## Estruturas e bibliotecas (guia do programador)

Estruturas apontam para o **guia**, não para a API: o leitor que encontra
`rte_mbuf` pela primeira vez precisa do capítulo que explica o conceito, não da
lista de campos.

| Símbolo | Rótulo | URL |
|---|---|---|
| `rte_mbuf` | `guiambuf` | <https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html> |
| `rte_mempool` | `guiamempool` | <https://doc.dpdk.org/guides/prog_guide/mempool_lib.html> |
| `rte_ring` | `guiaring` | <https://doc.dpdk.org/guides/prog_guide/ring_lib.html> |
| `rte_flow` | `guiaflow` | <https://doc.dpdk.org/guides/prog_guide/ethdev/flow_offload.html> |

## Conceitos

| Termo | Rótulo | URL |
|---|---|---|
| EAL | `cEAL` | <https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html> |
| PMD | `cPMD` | <https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html> |
| hugepages | `cHuge` / `hugetlb` | <https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html> |
| vfio-pci | `cDrivers` / `drivers` | <https://doc.dpdk.org/guides/linux_gsg/linux_drivers.html> |
| testpmd | `cTestpmd` | <https://doc.dpdk.org/guides/testpmd_app_ug/> |
| AF_XDP | `cAfxdp` | <https://doc.dpdk.org/guides/nics/af_xdp.html> |
| vhost-user | `cVhost` | <https://doc.dpdk.org/guides/nics/vhost.html> |
| multiprocesso | `cmultiproc` | <https://doc.dpdk.org/guides/prog_guide/multi_proc_support.html> |
| opções da EAL | `cparams` | <https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html> |
| glossário | `glossario` | <https://doc.dpdk.org/guides/prog_guide/glossary.html> |

## Opções de linha de comando da EAL

A página oficial de opções **não tem âncora por opção** — tem âncora por
categoria. Linkar as catorze opções citadas num documento à mesma URL seria
enfeite; apontar cada uma para a sua seção é navegação. Daí seis rótulos, e não
um por opção.

| Rótulo | Seção oficial | Opções que caem nela |
|---|---|---|
| `optlcore` | [Lcore-related options](https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#lcore-related-options) | `-l`, `--lcores`, `--main-lcore`, `--service-corelist` |
| `optmem` | [Memory-related options](https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#memory-related-options) | `--in-memory`, `--no-shconf`, `--huge-unlink`, `--iova-mode` |
| `optmulti` | [Multiprocessing-related options](https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#multiprocessing-related-options) | `--proc-type` |
| `optdev` | [Device-related options](https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#device-related-options) | `--allow`, `--block`, `--no-pci` |
| `optdebug` | [Debugging options](https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#debugging-options) | `--no-huge` |
| `optlinux` | [Linux-specific EAL parameters](https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#linux-specific-eal-parameters) | `--file-prefix`, `--huge-dir`, `--numa-mem`, `--socket-mem` |

Dois pontos que vale registrar, porque não são óbvios:

**`--no-huge` está sob *Debugging options*, não sob memória.** É a classificação
da própria documentação oficial, e sustenta o que o
[módulo 02](../docs/02-runtime-dpdk/README.md#45-o-que-desliga-o-modelo-multiprocesso-sem-avisar)
diz sobre ela não ser escolha de produção.

**Não use as âncoras `#id1`, `#id2`, `#id3`.** O Sphinx as gera automaticamente
para títulos repetidos — as seções da parte específica de Linux têm os mesmos
nomes da parte comum. Elas mudam em silêncio numa reestruturação da página; por
isso as opções específicas de Linux apontam para o pai estável
`#linux-specific-eal-parameters`.

## Notas de versão e APIs antigas

Citadas quando um documento precisa mostrar que algo **mudou**. Links para
versão antiga são deliberados nesses casos, e só nesses.

| Uso | Rótulo | URL |
|---|---|---|
| renomeação master/slave para main/worker (20.11) | `rel2011` | <https://doc.dpdk.org/guides/rel_notes/release_20_11.html> |
| `rte_launch.h` na API 19.11, com o estado `FINISHED` | `api1911` | <https://doc.dpdk.org/api-19.11/rte__launch_8h.html> |
| `lib/eal/linux/eal_timer.c` (v25.11), `get_tsc_freq()` | `fonteeal` | <https://github.com/DPDK/dpdk/blob/v25.11/lib/eal/linux/eal_timer.c> |

## Duas armadilhas ao adicionar links

**Não coloque link em título.** O identificador da seção é gerado a partir do
texto do título, e a sintaxe do link entra nele: `### Nível 3 — [EAL]&#91;rotulo&#93;`
produz a âncora `nível-3-ealceal-e-ambiente-do-runtime`, quebrando qualquer
referência que apontasse para a seção. Linke na primeira menção do corpo.

**Âncoras Doxygen não são verificáveis por código de status, nem por
proximidade.** Páginas Doxygen têm muitas âncoras próximas, e heurísticas de
"a âncora mais perto do nome" apontam para o símbolo vizinho com facilidade —
já produziram aqui links de `rte_eal_init` que levavam a `rte_eal_process_type`
e de `rte_ring_enqueue_burst` que levavam à variante `_sp_`. O único critério
confiável é o título do bloco de detalhe (`memtitle`), que traz o nome exato.
Use [`scripts/ancora-dpdk.py`](ancora-dpdk.py), que faz esse casamento:

```bash
./scripts/ancora-dpdk.py rte__ring_8h.html rte_ring_dequeue_burst
./scripts/ancora-dpdk.py --verificar    # confere o mapa inteiro
```

**Âncoras Doxygen não são verificáveis por código de status.** Uma URL com
fragmento errado devolve 200 do mesmo jeito, porque o fragmento é resolvido no
navegador. Para conferir de verdade, procure o identificador no HTML:

```bash
curl -sL "https://doc.dpdk.org/api/rte__ring_8h.html" | grep -c 'a9dd35643c4cdc6fa00ece3cafbcd94d2'
```
