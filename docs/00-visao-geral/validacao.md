# Validação, dados e evolução com hardware

*Read this in [English](validacao.en.md).*

Esta página define os critérios comuns aos módulos. O estado de implementação
fica no [índice da trilha](../../trilha/README.md); o trabalho futuro, no
[roadmap](../../ROADMAP.md). Não confunda conteúdo escrito, teste executado e
resultado de desempenho publicado.

## Versão atual e próxima etapa

A máquina local ainda não dispõe da NIC-alvo para os testes avançados de rede.
A próxima etapa usará uma **Mellanox ConnectX-4 Lx 25GbE dual-port SFP28**, após
instalação e confirmação das capacidades na configuração efetiva.

| Escopo | Estado e critério |
|---|---|
| Lógica, EAL, estruturas e pipeline em memória | Executáveis agora; devem cumprir os invariantes dos respectivos testes. |
| Multiprocesso, hugepages e contenção | L3 executável quando seus pré-requisitos locais estiverem disponíveis; não depende da NIC-alvo. |
| RX/TX físico, RSS e escala por filas | Pendente para a próxima etapa com hardware e aplicação adequados. Sondagem de porta não valida tráfego. |
| Vazão, perda e latência do sistema de rede | Não medidas; requerem fonte de tráfego e metodologia declaradas. |
| NUMA remoto | Depende de pelo menos dois nós NUMA com memória; a chegada da NIC não assegura essa topologia. |
| AF_XDP zero-copy e offloads | Condicionados ao suporte e funcionamento na combinação real de NIC, firmware, driver e software. |

Pendência por hardware não reprova o escopo da versão atual. Também não equivale
a resultado zero ou aprovação. As medições em memória continuam sendo evidência
dos componentes, sem antecipar o desempenho da rede física.

## L1, L2 e L3

| Nível | O que verifica | Exemplos atuais |
|---|---|---|
| L1 | Lógica e ferramentas sem iniciar a EAL ou acessar NIC | Estatística, livro de ofertas, dimensionamento, pacote e fixtures dos scripts. |
| L2 | Execução e integração sem preparação especial de hardware | CLI da EAL com `--no-huge`, conservação de objetos, cadeia de mbufs e pipeline C/C++. Inclui programas sem EAL. |
| L3 | Cenários que exigem recursos específicos do host | Hugetlbfs compartilhado, morte do primário, topologia e contenção. Futuramente, rede física. |

Aplique cada nível ao comportamento que o justifica. Um programa mínimo que
apenas chama a EAL não exige um L1 artificial. Testes que imprimem tempos
verificam execução e, quando implementadas, condições de sanidade da coleta;
não validam os valores históricos publicados.

```bash
./scripts/build-all.sh
./scripts/test-all.sh l1
./scripts/test-all.sh l2
./scripts/test-all.sh l3
meson test -C build --list       # inventário atual, sem contagem duplicada na prosa
```

O runner deve distinguir:

- **PASS:** comportamento esperado efetivamente verificado.
- **FAIL:** propriedade violada, erro inesperado ou cenário incompleto depois
  de satisfeitos os pré-requisitos.
- **SKIP (77):** pré-requisito ausente identificado explicitamente; informe qual
  cenário deixou de rodar. Falha genérica da EAL não prova ausência de hardware.

Não some entradas Meson, casos GoogleTest e asserções como se fossem uma mesma
medida. O projeto não publica percentual de cobertura de código. Ao divulgar
qualidade, informe requisitos exercitados, falhas e exclusões, além das contagens.

## Como publicar dados

### Convenções editoriais de números e unidades

- Em texto português e tabelas editoriais, usar vírgula decimal: `1,8 ns`.
  Separar milhares com espaço quando necessário: `200 000 objetos`.
- Separar número e unidade: `25 GbE`, `64 B`, `40,08 ns`, `1,5 %`.
  `GbE` nomeia a tecnologia; uma taxa medida precisa de unidade como `Gbit/s`.
- Usar `B` para bytes e `bit` para bits. `MB` e `MiB` não são intercambiáveis;
  converter somente quando a base decimal ou binária estiver comprovada.
- Preservar ponto decimal, espaçamento e precisão de saídas literais, CSV,
  comandos e referências históricas. Identificar o bloco como saída; não
  editar um log para fazê-lo parecer uma nova tabela editorial.
- Informar a unidade no cabeçalho ou junto dos valores e explicar a operação:
  `ns/objeto` em um ciclo obter/devolver não é latência individual de pacote.
- Nomear numerador e denominador das razões. Declarar se a divisão usa valores
  brutos ou valores exibidos e como foi arredondada. Não acrescentar casas
  decimais que não existiam na origem.
- Distinguir `não medido`, `não aplicável` e zero. Ausência de medição não
  fornece um valor para médias, gráficos ou razões.

### Contexto mínimo de cada resultado

Uma tabela deve declarar **cenário, grandeza, unidade experimental e agregação**.
Por exemplo, `ns por objeto em um ciclo get/put` difere de `p99 em ns da
publicação até a observação`. Custos amortizados, latências individuais e tempos
do pipeline completo não são parcelas automaticamente somáveis.

Os números já transcritos nos módulos são registros históricos da máquina de
referência. Nem todas as tabelas têm amostras brutas e metadados por execução
preservados; nesses casos, sua regeneração exata não está assegurada. Razões
entre implementações também podem mudar com frequência, carga e afinidade.

Para cada nova coleta publicável, preserve em um diretório identificado:

| Artefato | Conteúdo mínimo |
|---|---|
| `metadados.md` | Data, revisão do código, alterações locais, comando exato, variáveis, compilador, opções de build, DPDK, kernel e configuração do cenário. |
| `ambiente.txt` | Saída de `scripts/ambiente.sh` naquela execução; não a do dia em que a tabela for revisada. |
| `saida.txt` e `status.txt` | Saída completa e código de retorno, inclusive quando houver falha ou SKIP. |
| `amostras.csv`, quando a medição produzir amostras | Valores individuais e unidades. Se o programa só exportar agregados, declare essa limitação; não reconstrua amostras a partir da mediana. |
| Tabela e método | Comando ou cálculo para derivá-la, aquecimento, número de amostras, descarte e dispersão. Link da tabela para o registro. |

Use uma revisão limpa ou preserve também as alterações e fontes não versionadas
usadas na execução. Registre o ambiente antes da medição e mantenha a coleta de
diagnóstico fora da janela cronometrada. Os limites `DPDK_ACADEMY_AMOSTRAS` e
`DPDK_ACADEMY_RODADAS` usados em CI verificam execução; não substituem uma coleta
destinada a comparar desempenho.

## Aceitação da próxima versão com rede

Antes de medir, registre modelo e firmware, PCIe negociado, topologia, versões,
driver/PMD, filas, descritores, afinidade, tamanho de lote e offloads ativos.
Descreva a conexão entre portas e a fonte de tráfego. Um gerador no mesmo host
consome recursos da máquina medida; duas portas não asseguram carga suficiente.

| Cenário a implementar | Critério de aceitação |
|---|---|
| RX/TX básico | Conteúdo e sequência recebidos correspondem ao tráfego enviado; diferenças são contabilizadas em perdas ou descartes identificados. |
| TX parcial e pressão sobre pools | Somente objetos não aceitos continuam sob posse da aplicação; ao encerrar, todos os objetos são liberados após parar/drenar a porta. |
| RSS e escala | Fluxos e filas observados correspondem à configuração; comparar o mesmo trabalho com número de filas/núcleos declarado. |
| Sobrecarga e recuperação | Registrar onde ocorre descarte e demonstrar retorno ao processamento após remover a sobrecarga, dentro de um limite definido antes do ensaio. |
| Desempenho | Carga oferecida, vazão recebida, perda e distribuição de latência têm unidade, duração, população e dispersão declaradas. Identificar medição unidirecional ou ida e volta e o método de relógio. |
| Comparação DPDK, sockets e AF_XDP | Mesmos dados e processamento, recursos e modos explicitados; capacidades indisponíveis são pendências, sem presumir um vencedor. |

Os limites numéricos de perda, latência e recuperação devem ser definidos a
partir do requisito do sistema antes da coleta. Ainda não há SLO de rede
validado neste projeto. A taxa nominal de 25GbE da placa é um alvo de cenário,
não uma medição do receptor nem uma promessa de taxa de linha.
