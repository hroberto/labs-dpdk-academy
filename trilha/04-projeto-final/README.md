# Projeto final

*Read this in [English](README.en.md).*

> **Nível 10** do [plano de estudo](../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: todos os módulos anteriores

Consolidar o material num sistema executável, documentado e medido, e usá-lo para
responder à pergunta que atravessa o projeto inteiro: **quando o DPDK compensa, e
quando não compensa.**

## Estado deste documento, sem eufemismo

**A consolidação está escrita. A aplicação não existe.**

São coisas diferentes, e o documento não deve confundi-las. O que segue é o
balanço do que os módulos anteriores demonstraram, a decisão explícita sobre a
comparação com AF_XDP, e o inventário do que falta. O que não há é o receptor de
*market data* rodando de ponta a ponta sobre uma NIC — e a seção 6 diz o que
exatamente impede.

## 1. O que o projeto demonstrou, em números

Cada linha tem programa que a produz e está medida nesta máquina. Nenhuma é
citação.

| Achado | Número | Onde |
|---|---|---|
| Uma syscall custa dezenas de chamadas de função | 33,8 ns contra 0,73 ns quente (**46×**) ou 0,92 frio (36×) | [fundamentos §2](../../docs/01-fundamentos/README.md) |
| Subir a EAL não é grátis | **118 ms** | [runtime §2](../../docs/02-runtime-dpdk/README.md#2-o-custo-de-existir-quanto-a-eal-leva-para-nascer) |
| Atravessar domínio de cache domina tudo | **4,0 a 4,8×** | [mempool-ring](../01-fundamentos/02-mempool-ring/) |
| Paralelizar pode piorar | 1 lcore vence 2 em quase toda a tabela | [mempool-ring](../01-fundamentos/02-mempool-ring/) |
| Contrapressão é a razão pool/fila, não a fila | fronteira em capacidade = 4 095 | [contrapressão §6](../02-pipeline/02-batching-backpressure/) |
| Frequência livre cobra pouco | 9× no clock → **4,6%** no resultado | [benchmarking §6](../03-performance/01-benchmarking/) |
| A primeira execução após ociosidade mente | **~30%** a mais | [benchmarking §6](../03-performance/01-benchmarking/) |
| O perfilador de CPU não vê o descarte na NIC | `imissed`, legível só por telemetria | [observabilidade §6](../03-performance/02-observabilidade/) |

**A tese que sobrevive a tudo isso é modesta e útil:** o DPDK remove a syscall e a
cópia, e entrega o pacote onde o programa quiser. O que ele **não** remove é a
física da máquina — travessia de cache, localidade NUMA, orçamento de barramento.
Três dos oito achados acima são sobre a máquina, não sobre o DPDK, e nenhum deles
melhora por trocar de framework.

## 2. O sistema, quando existir

O cenário dos fundamentos e do runtime é o candidato natural: um **receptor de
*market data***, com o feed handler como processo primário e um consumidor como
secundário. Ele já tem peças escritas e testadas — livro de ofertas, detecção de
perda por número de sequência, travessia entre processos medida — em
[`docs/02-runtime-dpdk/medicoes/`](../../docs/02-runtime-dpdk/medicoes/).

Isto é sugestão de continuidade, não obrigação. Se outro domínio ensinar melhor o
que falta ensinar, o outro domínio vence: o objeto de estudo é o DPDK.

## 3. As três comparações

| Abordagem | O que ela custa | O que ela entrega |
|---|---|---|
| **DPDK** | hugepages, núcleos dedicados, driver ligado ao processo, 118 ms para subir | menor latência e maior taxa de pacotes |
| **C++23 sobre sockets** | syscall e cópia por pacote | roda em qualquer lugar, sem privilégio |
| **AF_XDP** | requisitos de driver e de kernel | *bypass* parcial mantendo driver e modelo de segurança do kernel |

A segunda já tem medição parcial na
[alternativa em C++23](../01-fundamentos/02-mempool-ring/alternativas/cpp23/),
e a ressalva de lá continua valendo: aquele teste compara estruturas em memória,
não a pilha de rede.

## 4. AF_XDP: a decisão, tomada

O esqueleto deixava duas saídas em aberto e exigia escolher uma. **Escolhida a
segunda: AF_XDP entra como comparação conceitual, com números de terceiros
atribuídos, e a medição fica para quem tiver hardware adequado.**

A razão é medida, não preferência. Consultado com privilégio, o próprio netdev
responde:

```
NETDEV_XDP_ACT_BASIC:         no
NETDEV_XDP_ACT_REDIRECT:      no
NETDEV_XDP_ACT_XSK_ZEROCOPY:  no
```

`BASIC: no` significa que a NIC **não tem XDP nativo nenhum** — não é o caso de
"tem XDP, falta zero-copy". Aqui o AF_XDP só funciona em **modo genérico (SKB)**,
em que o eBPF roda *depois* da alocação do `sk_buff`, dentro da pilha: o mais
lento dos modos, e o que menos representa AF_XDP.

Medir isso e chamar de AF_XDP repetiria o erro que a alternativa em C++23 já
documenta: **medir um cenário que remove aquilo pelo qual a tecnologia cobra.**
Um número assim é pior que nenhum, porque parece resposta.

### A evidência, reproduzível

O módulo do driver confirma independentemente — importa porque a interface aqui
está *down*, e alguém poderia atribuir o "no" ao link caído:

```bash
for d in r8169 i40e ice ixgbe mlx5_core; do
  m=$(modinfo -n "$d") || continue
  tmp=$(mktemp)
  case "$m" in *.zst) zstdcat "$m" >"$tmp";; *.xz) xzcat "$m" >"$tmp";; *) cp "$m" "$tmp";; esac
  printf '%-10s xdp_=%-4s xsk_ chamados=%-3s xsk_ definidos=%s\n' "$d" \
    "$(nm "$tmp" | grep -c 'xdp_')" \
    "$(nm "$tmp" | awk '$1=="U" && $2 ~ /xsk_/' | wc -l)" \
    "$(nm "$tmp" | awk '$1!="U" && $NF ~ /xsk_/' | wc -l)"
  rm -f "$tmp"
done
```

| driver | `xdp_` (XDP nativo) | chamadas ao núcleo XSK | código XSK próprio | diagnóstico |
|---|---:|---:|---:|---|
| `r8169` (a NIC daqui) | **0** | 0 | 0 | **sem XDP nenhum** |
| `i40e` | 37 | 7 | 13 | XDP + zero-copy |
| `ice` | 83 | 7 | 13 | XDP + zero-copy |
| `ixgbe` | 38 | 8 | 12 | XDP + zero-copy |
| `mlx5_core` | 59 | 8 | 43 | XDP + zero-copy |

As três colunas separam situações que um único número confundiria:

- **`xdp_`** distingue "não tem XDP" de "tem XDP, falta zero-copy" — é a coluna
  que classifica a RTL8125;
- **chamadas** são símbolos *indefinidos*: funções do núcleo XSK que o driver
  invoca;
- **código próprio** são funções XSK que ele *define*.

Suporte real tem as três.

> **A descompressão não é detalhe.** Este documento já publicou
> `nm -D .../r8169.ko.zst | grep -c xsk_`, e ela **não funciona**: módulos vêm
> comprimidos com zstd, o `nm` recusa o arquivo, o `grep -c` engole o erro e
> devolve `0`. Rodando no `i40e`, que tem suporte, o resultado também era `0` —
> o comando dizia "sem zero-copy" para todo driver do sistema, e a conclusão
> sobre a RTL8125 estava certa por coincidência. Conferido de novo em 16/09/2026:
> a forma direta devolve `0` para `r8169` e `i40e`; a que descomprime antes
> reproduz a tabela acima.

> **E esta evidência prova menos do que parece — nem sequer é condição
> necessária.** Símbolo no módulo é indireto: *inlining*, renomeação e mudanças
> de implementação produzem falso negativo. Responde "vale a pena tentar?", não
> "isto funciona".
>
> A hierarquia, da mais fraca para a mais forte:
>
> 1. **símbolos no módulo** — heurística, sem privilégio;
> 2. **`NETDEV_XDP_ACT_XSK_ZEROCOPY`** anunciada pelo netdev, via
>    `xdp-loader features` — **exige root**;
> 3. **bind real com `XDP_ZEROCOPY`** — a única prova:
>    `sudo xdpsock -i <iface> -q 0 -N -z -r`. Rodar **sem** `-z` não prova nada:
>    há fallback silencioso para modo cópia.

## 5. O que este projeto ensina sobre honestidade técnica

Vale registrar, porque foi o que mais se aprendeu aqui e não estava no plano.

**Não apurado não é fato negativo.** A maior parte dos defeitos corrigidos neste
repositório é da mesma família: `ls | wc -l` devolvendo `0` para "não consegui
olhar"; `%G?` devolvendo `N` para "não consegui verificar"; `nm` falhando em
silêncio e o `grep -c` publicando `0`. Em todos, a ausência de resposta saiu como
resposta negativa — que é a mais tranquilizadora e a mais perigosa.

**Verificação que não roda é pior que nenhuma.** Um teste desregistrado, um
portão que falha por construção na CI, uma regra cujo padrão parou de casar
depois de uma reescrita: os três emitem verde e não conferem nada.

**Compressão cria falsidade.** Um índice que resume "regressão em 128" a partir
de uma tabela que separa um lcore de dois publica algo que a fonte não diz.

## 6. O que falta, e por quê

**A aplicação.** Não há receptor de *market data* de ponta a ponta. As peças
existem em `docs/02-runtime-dpdk/medicoes/` e nunca foram montadas num sistema.

**A NIC fora do kernel.** O submódulo
[01 — RX/TX](../02-pipeline/01-rx-tx-burst/) tem escopo e capacidades da placa
medidos, e está travado por uma linha: `enp8s0` tem `IFF_UP` ligado, e a trava de
captura recusa. `sudo ip link set enp8s0 down` destrava — é decisão de quem opera
a máquina, e por isso o script não a toma.

**A comparação justa com sockets.** A alternativa em C++23 compara estruturas em
memória; a comparação que interessa é contra a pilha de rede do kernel, e ela
precisa da NIC.

**`imissed` observado acontecendo.** O mecanismo está demonstrado com `net_null`,
que não tem descritor de hardware. O valor exige a placa.

**Benchmark com ambiente fixado.** O submódulo 01 de performance mediu que fixar
frequência muda pouco; falta medir o efeito de `isolcpus`, que exige reiniciar.

## 7. Navegação

| | |
|---|---|
| **Anterior** | [03 — Performance e observabilidade](../03-performance/) |
| **Índice** | [Trilha](../README.md) · [Plano de estudo](../../docs/plano-estudo-dpdk.md) · [Roadmap](../../ROADMAP.md) |
