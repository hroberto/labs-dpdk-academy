# Submódulo 02 — Observabilidade

*Read this in [English](README.en.md).*

> **Nível 8** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [01 — Benchmarking](../01-benchmarking/)

Enxergar o que um programa DPDK está fazendo **enquanto ele roda**, sem parar e
sem instrumentar o caminho quente.

## 1. Fundamento: o perfilador de CPU não vê o que importa

Listar `perf`, *sanitizers* e `clang-tidy` é fácil e insuficiente: são
ferramentas genéricas de C e C++, e o projeto já as trata no
[ferramental](../../../docs/00-visao-geral/ferramental.md). O que este submódulo
cobre, e nenhum outro cobre, é a observabilidade **do runtime**.

A razão é concreta. Quando a NIC descarta um pacote por falta de descritor
livre, **nenhuma instrução é executada** no seu processo. Não há pilha para
amostrar, não há função para atribuir custo, não há linha de código para culpar.
Um perfilador de CPU mostra o programa saudável e rápido, processando tudo o que
recebeu — e o que ele não recebeu é invisível.

O contador existe. Chama-se `imissed`, vive na NIC, e a seção 6 o lê com o
programa rodando.

## 2. Mecanismo: um soquete e uma linha de JSON

A EAL abre um soquete de domínio UNIX no diretório de runtime:

```
/run/user/1000/dpdk/<file-prefix>/dpdk_telemetry.v2
```

Quem se conecta manda um caminho em texto e recebe um objeto JSON. É só isso —
não há biblioteca a linkar, não há processo secundário a subir, e o cliente não
precisa ser DPDK.

**A telemetria está LIGADA POR PADRÃO, e isto foi medido.** A ajuda da EAL
mostra as duas opções lado a lado, o que sugere que uma liga e outra desliga:

```
--no-telemetry             Disable telemetry
--telemetry                Enable telemetry
```

Rodando o mesmo programa com e sem `--telemetry`, **o soquete apareceu nos dois
casos**. A flag que muda alguma coisa é `--no-telemetry`; `--telemetry` só
reafirma o padrão. Em DPDK 25.11, nesta máquina.

### Telemetria não é processo secundário

As duas coisas se confundem, e a diferença decide qual usar:

| | Telemetria | Processo secundário |
|---|---|---|
| Acesso | contadores que a biblioteca exporta | a memória compartilhada inteira |
| Cliente | qualquer coisa que fale soquete UNIX | processo DPDK com `--proc-type=secondary` |
| Acoplamento | nenhum | mesma versão de DPDK, mesmo `--file-prefix` |
| Custo de subir | conectar | uma EAL inteira — 123 ms, medidos no [runtime §2](../../../docs/02-runtime-dpdk/README.md#2-o-custo-de-existir-quanto-a-eal-leva-para-nascer) |
| Risco | leitura | pode escrever na memória do primário |

Para "quantos pacotes se perderam", telemetria. Para "quero ler a estrutura da
aplicação", secundário — que é o caminho que o
[runtime §4](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário)
já implementa e testa.

## 3. Trade-offs: contador próprio sai caro no lugar errado

O contador que a aplicação mantém é o único que sabe o que ela quis dizer — e é
também o que pode destruir o desempenho que se queria medir.

Um `uint64_t` incrementado a cada pacote, colocado na mesma linha de cache que
os dados do caminho quente, transforma cada incremento numa invalidação para os
outros núcleos. É o
[falso compartilhamento](../../../docs/01-fundamentos/README.md#421-falso-compartilhamento-o-erro-mais-comum-de-quem-escreve-plano-de-dados)
já medido nos fundamentos, agora causado pela própria instrumentação.

A defesa é a mesma de lá: contador por lcore, alinhado à linha de cache,
agregado só na hora de reportar. `pipeline_ring.c` já faz isso — o
`struct consumer_context` é `__rte_cache_aligned` exatamente por esse motivo.

## 4. Implementação

Nada a compilar: o cliente vem com o DPDK.

```bash
# um terminal: o programa, rodando
dpdk-testpmd --no-huge -m 1024 --no-pci --vdev=net_null0 -l 0-1 \
  --file-prefix=obs -- --total-num-mbufs=4096 --forward-mode=rxonly -i

# outro terminal: as perguntas
dpdk-telemetry.py -f obs
```

O cliente é interativo; `/` lista os caminhos disponíveis — **cerca de cem**
nesta instalação, entre `/eal/...`, `/ethdev/...`, `/mempool/...`, `/ring/...`,
`/cryptodev/...` e `/eventdev/...`.

Para roteirizar, mande os caminhos pela entrada padrão:

```bash
printf '/ethdev/stats,0\n/mempool/info,mb_pool_0\n' | dpdk-telemetry.py -f obs
```

## 5. Validação

```bash
./scripts/ambiente-medicao.sh --uma-linha    # carimbe o ambiente
printf '/eal/params\n' | dpdk-telemetry.py -f obs
```

`/eal/params` devolve a linha de comando **exata** com que o processo subiu:

```json
{"/eal/params": ["...feed-primario", "--no-huge", "-m", "512",
                 "--no-pci", "-l", "0", "--file-prefix=telx", "--telemetry"]}
```

É o primeiro comando a rodar num diagnóstico. Metade dos problemas de DPDK é o
processo ter subido com argumentos diferentes dos que se acredita.

## 6. Quando dá errado — o que os contadores mostram

### O descarte que o perfilador não vê

`dpdk-testpmd` com `net_null0` em `rxonly`, quatro segundos de tráfego:

```json
{"/ethdev/stats": {"ipackets": 409697376, "opackets": 0,
                   "ibytes": 26220632064, "obytes": 0,
                   "imissed": 0, "ierrors": 0, "oerrors": 0, "rx_nombuf": 0}}
```

Quatrocentos e nove milhões de pacotes, e o que interessa num diagnóstico são os
três zeros do fim:

- **`imissed`** — a NIC recebeu e não teve descritor livre para entregar. Nenhuma
  instrução do seu processo executou por causa disso.
- **`rx_nombuf`** — não havia mbuf no pool. Sintoma clássico de pool
  subdimensionado, e o [tópico de mempool](../../../docs/03-mempool-ring-mbuf/README.md)
  tem as regras de dimensionamento.
- **`ierrors`** — CRC, tamanho inválido, o que a placa rejeitou.

Os três acima de zero com `ipackets` saudável é exatamente o caso em que o
programa parece bem e está perdendo dados.

`/ethdev/xstats,0` abre por fila (`rx_q0_packets`, `rx_q0_errors`), que é onde se
descobre que o problema está numa fila só — distribuição de RSS torta, por
exemplo.

### Onde estão os objetos, agora

```json
{"/mempool/info": {"name": "mb_pool_0", "size": 4096, "cache_size": 250,
                   "populated_size": 4096,
                   "total_cache_count": 378, "common_pool_count": 3686, ...}}
```

A conta fecha e diz uma coisa útil: **378** objetos nos caches por lcore, **3686**
no pool comum, e `4096 − 378 − 3686 = 32` em voo — exatamente o lote de 32 que o
testpmd estava processando naquele instante.

Um pool que esvazia em produção aparece aqui antes de virar `rx_nombuf`.

### Duas armadilhas medidas

**Caminho desconhecido devolve `null`, não erro.**

```json
{"/memzone/list": null}          ← caminho que não existe
{"/mempool/list": []}            ← caminho válido, nada a listar
```

O correto é `/eal/memzone_list`. O protocolo *distingue* os dois casos — `null`
contra `[]` —, mas quem lê rápido vê "vazio" nos dois e conclui que não há
memzone. Conclusão errada a partir de um erro de digitação.

**Consultas no mesmo lote não são atômicas.** No mesmo `printf`, sequenciais:

```
/ethdev/stats  → ipackets      = 409 697 376
/ethdev/xstats → rx_good_packets = 409 704 896
```

Sete mil e quinhentos pacotes de diferença, porque o tráfego continuou entre uma
resposta e outra. Comparar contadores de consultas diferentes como se fossem do
mesmo instante é erro de leitura, não do DPDK.

### O contador que vem vazio

```json
{"/eal/lcore/usage": {"lcore_ids": [], "total_cycles": [],
                      "busy_cycles": [], "usage_ratio": []}}
```

Não é defeito: a EAL só preenche isso se a aplicação registrar a função de uso de
lcore (`rte_lcore_register_usage_cb`). Sem registro, o endpoint existe e responde
vazio — mais um caso em que "vazio" não quer dizer "zero".

## 7. Limitações

**Nenhuma NIC física foi medida.** Todos os números de `ethdev` vêm de
`net_null`, que não tem descritor nem fila de hardware de verdade. Por isso
`imissed` é estruturalmente zero aqui: **o mecanismo foi demonstrado, o valor não
foi observado acontecendo**. Observar exige a placa fora do kernel, que é o que
o [submódulo 01 do pipeline](../../02-pipeline/01-rx-tx-burst/) espera.

**O contador próprio não foi medido.** A seção 3 explica o risco do falso
compartilhamento e aponta a medição que já existe nos fundamentos; não há aqui um
experimento novo comparando contador alinhado contra desalinhado.

**Processo secundário como diagnóstico não ganhou experimento.** A comparação da
seção 2 é sobre mecanismo; os três testes L3 do runtime exercitam o caminho, e
**pulam nesta máquina** por `/dev/hugepages` não ser gravável pelo uid 1000.

**Uma instalação só.** "Cerca de cem endpoints" é o que este DPDK 25.11 expõe;
outra versão ou outro conjunto de drivers muda a lista. `/` é a fonte da verdade
da sua máquina.

**Nada aqui foi automatizado.** Não há teste na suíte que exercite telemetria —
seria L3, porque depende de soquete em diretório de runtime e de um processo
vivo. Fica declarado como não coberto em vez de suposto.

## 8. Para onde ir daqui

| | |
|---|---|
| **Anterior** | [01 — Benchmarking](../01-benchmarking/) |
| **Módulo** | [03 — Performance e observabilidade](../README.md) |
| **Relacionado** | [Runtime §4 — processos primário e secundário](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário) |
| **Relacionado** | [Fundamentos §4.2.1 — falso compartilhamento](../../../docs/01-fundamentos/README.md#421-falso-compartilhamento-o-erro-mais-comum-de-quem-escreve-plano-de-dados) |
