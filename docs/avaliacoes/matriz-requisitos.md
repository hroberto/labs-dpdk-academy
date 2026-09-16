# Matriz de requisitos e evidências

Esta matriz cobre os contratos críticos selecionados da versão em memória e
as onze exigências adicionais do relatório. Não é percentual de cobertura do
projeto. A evidência de execução fica no [registro dos ajustes](execucao-ajustes.md).
Escrever um teste ou uma linha nesta matriz não altera seu estado para aprovado.

## Contratos críticos

### C01 — Amostra inválida não produz estatística utilizável

**Nível e estímulo:** L1: negativo, NaN e infinito em cada posição

**Teste / evidência:** `test_l1_statistics.cpp`

**Limite:** Não valida desempenho histórico.

### C02 — Publicação exige protocolo completo e registros correspondentes

**Nível e estímulo:** L2: CLI com dados íntegros e 12 corrupções deliberadas

**Teste / evidência:** [l2_publicacao.py](../../scripts/tests/l2_publicacao.py)

**Limite:** Fixtures de campanha; nova coleta exercita o caminho produtor.

### C03 — Controles de publicação detectam contratos removidos

**Nível e estímulo:** L1: quatro mutações executáveis

**Teste / evidência:** [l1_mutacoes_publicacao.py](../../scripts/tests/l1_mutacoes_publicacao.py)

**Limite:** Conjunto de mutações selecionado, não exaustivo.

### C04 — Falha esperada vem da coleta

**Nível e estímulo:** L2: binário com sentinela injetada

**Teste / evidência:** `medicoes/tests/l2_coleta_invalida.sh` do módulo 03

**Limite:** EAL malsucedida não é aprovação do controle.

### C05 — Retorno parcial devolve objetos rejeitados

**Nível e estímulo:** L2: anel reduzido e vazamento deliberado

**Teste / evidência:** [l2_run.sh](../../trilha/01-fundamentos/02-mempool-ring/tests/l2_run.sh),
que verifica a pré-condição antes de afirmar — repete com `-n` crescente até a
fila encher de fato, e só então exige que a variante vazada seja detectada.

**Limite:** Conferir retorno, estímulo e invariante. O modo `leak` de
`l2_failure.sh` NÃO cobre este contrato e não está registrado: invoca `-n 64`,
e com 64 pacotes o anel de 4096 nunca enche — o retorno parcial, que é o
caminho onde o vazamento vive, não chega a executar.

### C06 — Consumidor parado termina e devolve objetos

**Nível e estímulo:** L2: mesmo lcore e outro lcore

**Teste / evidência:** [l2_failure.sh](../../trilha/01-fundamentos/02-mempool-ring/tests/l2_failure.sh),
modos `paused` (um lcore) e `pausedtwo` (dois lcores), ambos registrados

**Limite:** Limite de progresso, não garantia de tempo real rígido.

### C07 — Heartbeat, atualidade e geração são distintos

**Nível e estímulo:** L1: relógio controlado e fronteira do prazo

**Teste / evidência:** `test_l1_feed_health.cpp`

**Limite:** Não substitui integração EAL.

### C08 — Nova sessão começa após terminar processos antigos

**Nível e estímulo:** L2: subprocessos reais controlados

**Teste / evidência:** [l2_feed_supervisor.py](../../scripts/tests/l2_feed_supervisor.py)

**Limite:** Confere eventos, PIDs e preservação de recurso alheio; sem EAL.

### C09 — Falha só é injetada após consumo e estado ativo

**Nível e estímulo:** L2/L3: logs de geração e consumo; cenários sem estado ativo/final

**Teste / evidência:** Teste do supervisor e `l3_recuperacao.sh`

**Limite:** L3 depende de hugetlbfs; L2 não o certifica.

### C10 — Comunicação, invalidação e recuperação reais

**Nível e estímulo:** L3: primário/secundário e SIGKILL

**Teste / evidência:** `l3_multiprocesso.sh`, `l3_primario_morre.sh`, `l3_recuperacao.sh`

**Limite:** Pendente de host preparado e execução real.

### C11 — Dependência ausente não desaparece da suíte

**Nível e estímulo:** L1: fixtures e marcadores Meson

**Teste / evidência:** `l1_xdp_dependencias.sh`, `l1_multiprocesso.sh`, ramos sem Python/GTest

**Limite:** Configuração Meson sem Python/GTest e execução dos 15 marcadores registradas; não é compilação completa nessa configuração.

### C12 — Apuração parcial não termina como aprovação integral

**Nível e estímulo:** L1: lacunas por privilégio/ferramenta

**Teste / evidência:** `l1_apuracao.sh`, retorno 77 no modo completo com lacunas

**Limite:** Execução sob uid 0 não demonstrada neste host.

### C13 — Captura total preserva interface ativa/default

**Nível e estímulo:** L1: flags, rotas IPv4/IPv6 e falhas de consulta

**Teste / evidência:** [l1_bind_guard.sh](../../scripts/tests/l1_bind_guard.sh)

**Limite:** Hardware não alterado; integração física pendente.

### C14 — Documentação e inventário detectam mudanças

**Nível e estímulo:** L1/docs: links, âncoras, contas, retratações, inventário

**Teste / evidência:** Os cinco verificadores em
[`ferramental/qualidade/`](../../ferramental/qualidade/) — links, âncoras de
linha, aritmética publicada, retratações e autodescrição — mais
`inventariar-dados.py`, todos registrados na suíte `l1+docs`

**Limite:** Escopos e exclusões explícitos; não prova revisão semântica completa.

### C15 — Percurso é compreendido sem orientação dos autores

**Nível e estímulo:** Leitura independente das tarefas de aceitação

**Teste / evidência:** [Roteiro de leitura](leitura-aceitacao.md)

**Limite:** Aguardando execução por leitor independente.


## Requisitos adicionais

### RD01 Cobertura

**Entrega associada:** C01–C15 e inventário de tabelas

**Estado de cobertura:** Matriz delimitada criada; não é inventário exaustivo de todos os requisitos futuros.

### RD02 Clareza

**Entrega associada:** C15

**Estado de cobertura:** Roteiro pronto; leitura independente pendente.

### RD03 Níveis de teste

**Entrega associada:** C01–C14

**Estado de cobertura:** Níveis e limites explícitos; C10 ainda depende do host.

### RD04 Testabilidade

**Entrega associada:** C02–C10

**Estado de cobertura:** Novos estímulos e asserções; integração EAL pendente.

### RD05 Acadêmica

**Entrega associada:** Inventário D01–D09 e confronto de D09

**Estado de cobertura:** Hipótese e limites de D09 registrados; outras famílias exigem nova coleta para decisão quantitativa.

### RD06 Segurança

**Entrega associada:** C08, C13 e revisão da limpeza do supervisor

**Estado de cobertura:** Fixtures implementadas; integração física e falhas reais de runtime não demonstradas.

### RD07 Rigor

**Entrega associada:** C01–C04, D09

**Estado de cobertura:** Contrato de publicação e nova campanha; não cobre todas as campanhas históricas.

### RD08 Estrutura

**Entrega associada:** C14, C15

**Estado de cobertura:** Índices e estados atualizados; aceitação pelo leitor pendente.

### RD09 Prática

**Entrega associada:** C05–C10

**Estado de cobertura:** Pipeline e supervisor controlado; runtime real e rede permanecem separados.

### RD10 Manutenibilidade

**Entrega associada:** C03, C14

**Estado de cobertura:** Mutações e inventário detectam mudanças selecionadas; exercício completo de manutenção ainda pendente.

### RD11 Ferramental

**Entrega associada:** C11, C12, C14

**Estado de cobertura:** Configuração sem Python/GTest exercitada; referências externas e execução sob uid 0 permanecem não verificadas.


O escopo de rede física, RSS, perda e latência do receptor permanece futuro,
conforme a [política de validação](../00-visao-geral/validacao.md). Não se atribui
sucesso nem falha funcional a esse escopo por ausência da Mellanox atual.
