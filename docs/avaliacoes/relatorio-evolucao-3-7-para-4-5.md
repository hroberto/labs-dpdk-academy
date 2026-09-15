# Relatório de evolução da qualidade do DPDK Academy

> **Plano e diagnóstico anteriores aos ajustes.** A execução está registrada
> em [execucao-ajustes.md](execucao-ajustes.md); os contratos e as pendências
> atuais estão em [matriz-requisitos.md](matriz-requisitos.md). As notas abaixo
> preservam a avaliação que originou o plano e não são atualizadas por projeção.

O projeto tem evidência suficiente para manter uma avaliação geral de **3,7/5**, mas ainda não para declarar 4,5. O avanço depende de completar a rastreabilidade das decisões, demonstrar a recuperação multiprocesso e fazer os controles de qualidade rejeitarem resultados incompletos. O caminho proposto preserva o escopo atual: fundamentos, runtime, estruturas, pipeline em memória e ferramentas de preparação. A chegada da Mellanox ConnectX-4 Lx não é pré-requisito para essas entregas.

O cenário de aceitação soma **45/50 pontos**, oito acima da avaliação vigente. Ele exige evidência nova em sete dimensões, incluindo dois pontos adicionais em dados. As notas projetadas são metas condicionais; escrever este relatório, implementar uma função ou obter uma suíte sem falhas não concede esses pontos automaticamente.

## Base, escopo e limites

A referência é a reavaliação de 15/09/2026, após os ajustes manuais. Ela substituiu a média histórica de 3,5 por 3,7. O plano anterior continua válido como registro histórico; seu diagnóstico de implementações então ausentes não deve ser apresentado como descrição do código atual. O presente relatório registra o trabalho remanescente, reconhecendo o que já foi entregue. [1]

A escala é a mesma: 0 ausente; 1 incipiente; 2 com lacunas relevantes; 3 adequado com ressalvas; 4 forte; 5 consistente e exemplar no escopo declarado. Cada dimensão tem peso de 10%. A média serve para acompanhar o projeto, não é percentual de cobertura ou medida estatística de qualidade. Um ponto em uma dimensão altera a média em 0,1; isso é aritmética da régua, não precisão empírica.

As evidências têm três estados distintos. **Executado** significa que existe resultado observado e identificado. **Inspecionado** significa que a propriedade foi localizada no código ou no documento, sem demonstração de todas as condições de execução. **Proposto** identifica uma entrega futura e sua aceitação. A ausência de evidência não prova que uma implementação falha; impede apenas certificar o comportamento ainda não demonstrado.

O pacote de evidências preserva um extrato dos resultados da suíte da reavaliação, controles adicionais de publicação e hashes de arquivos examinados. O extrato não é uma segunda execução da suíte. O commit identifica a base de uma árvore modificada; o manifesto não pretende ser uma cópia completa dessa árvore. [2]

RX/TX físico, RSS, vazão, perda e latência do receptor de rede permanecem fora da certificação atual. Os três testes de runtime pulados exigem memória compartilhada por hugetlbfs, não a NIC futura. A política do projeto já faz essa separação. [3]

## Quadro de notas e evidências necessárias

| Critério | Vigente | Meta mínima | Evidência que autoriza a mudança ou manutenção |
|---|---:|---:|---|
| Consistência com a proposta | 4 | 5 | Revisão cruzada das afirmações centrais em documentação, código, comentários e saídas; divergências corrigidas e versão identificada. |
| Objetividade | 4 | 5 | Todos os módulos desenvolvidos apresentam pergunta, resultado, limite e decisão; histórico não substitui orientação vigente. |
| Clareza | 4 | 5 | Leitor independente conclui tarefas de execução e interpretação; dúvidas materiais corrigidas e tarefas reavaliadas. |
| Simplicidade | 4 | 4 | Manter percurso principal contínuo, referências úteis e uma fonte vigente por procedimento. |
| Profundidade da análise | 4 | 4 | Manter hipóteses, controles e limites; retirar conclusões que excedam a medição e confrontar as conclusões centrais em outra campanha. |
| Profundidade da solução | 3 | 4 | Demonstrar políticas de falha e recuperação do escopo em processos DPDK reais, incluindo encerramento e validade do estado. |
| Qualidade/cobertura aplicável L1 | 4 | 5 | Matriz de contratos e fronteiras, mutações críticas detectadas e dependências ausentes separadas de aprovação. |
| Qualidade/cobertura aplicável L2 | 4 | 4 | Preservar positivos e negativos reais; identificar a causa esperada nos controles negativos e fechar a integração da publicação. |
| Qualidade/cobertura aplicável L3 | 3 | 4 | Executar os cenários aplicáveis no host preparado, preservando falhas, exclusões, transições e condições do ambiente. |
| Clareza e rastreabilidade dos dados | 3 | 5 | Todas as tabelas que sustentam decisões têm cadeia verificável, ou sua conclusão foi substituída/retirada; regeneração rejeita conjuntos incompletos. |
| **Total / média** | **37 / 3,7** | **45 / 4,5** | **Aceitação condicionada às evidências, sem compensar bloqueios críticos com apresentação melhor.** |

Os seis primeiros critérios somam 23 pontos; os quatro últimos, 14. Mesmo levando os seis primeiros a 5, o total seria 44, média 4,4. Portanto, concentrar toda a melhoria na apresentação e na solução, sem avançar em testes e dados, não alcança a meta.

O primeiro marco é alcançar 4 em solução, L3 e dados, preservando os outros critérios: total 40, média 4,0. O segundo acrescenta consistência, objetividade, clareza, L1 e dados em 5: total 45, média 4,5. Esses marcos expressam estados de aceitação, não uma previsão de aprovação.

## Avaliação adicional e requisitos de reconciliação

A imagem fornecida apresenta duas rodadas de outra avaliação, com nota global de 77 e 75. Os valores abaixo são uma transcrição do quadro, não uma nova avaliação deste relatório. A imagem não apresenta pesos, critérios de pontuação, justificativas individuais nem a revisão do projeto examinada em cada rodada. Portanto, permite registrar as diferenças numéricas, mas não atribuir sua causa a alterações do projeto ou recalcular a nota global. A transcrição estruturada preserva essa origem e esses limites. [16]

| Dimensão na imagem | Rodada 1 | Rodada 2 | Δ informado | Relação com a avaliação deste relatório |
|---|---:|---:|---:|---|
| Cobertura | 80 | 70 | −10 | Sem nota global de cobertura equivalente; a régua atual separa qualidade/cobertura aplicável L1 4, L2 4 e L3 3. |
| Clareza | 71 | 76 | +5 | Clareza 4/5; o nome coincide, mas a regra de atribuição da outra nota não foi fornecida. |
| Níveis de teste | 84 | 79 | −5 | Relação com L1 4, L2 4 e L3 3, sem correspondência numérica direta. |
| Testabilidade | 82 | 77 | −5 | Distribuída entre testes e solução; não possui nota autônoma na régua atual. |
| Acadêmica | 79 | 75 | −4 | Relação parcial com profundidade da análise 4 e dados 3; contribuição acadêmica não foi pontuada separadamente. |
| Segurança | 71 | 74 | +3 | Sem dimensão própria; acrescenta requisitos explícitos de segurança ao plano. |
| Rigor de medição | 74 | 76 | +2 | Relação com análise 4 e dados 3; não equivale somente à presença de estatística. |
| Estrutura | 73 | 75 | +2 | Relação com simplicidade 4, clareza 4 e consistência 4. |
| Prática | 81 | 79 | −2 | Relação parcial com solução 3 e execução dos exemplos; não equivale a desempenho de rede. |
| Manutenibilidade | 72 | 72 | 0 | Sem nota própria; acrescenta aceitação explícita para manutenção dos procedimentos e controles. |
| Ferramental | 73 | 73 | 0 | Sem nota própria; acrescenta aceitação explícita para disponibilidade e limites dos verificadores. |
| **Global** | **77** | **75** | **−2** | **A média deste relatório permanece 3,7/5; não há conversão validada entre as duas avaliações.** |

A última linha de dimensões da imagem agrupa “Manutenibilidade, Ferramental” e os valores “72, 73”. Aqui ela foi separada em duas linhas, preservando a ordem e o delta zero. Os deltas das demais linhas conferem com a subtração Rodada 2 menos Rodada 1. A conferência dessa aritmética não valida o método de pontuação.

O quadro recebido contém onze dimensões, sem uma linha de boas práticas C/C++23. O estudo histórico em doze dimensões contém essa linha e registra outros valores iniciais para clareza e ferramental. Não se completam as lacunas da imagem com números daquele estudo, nem se importam seus pesos automaticamente. A referência de cada avaliação deve continuar identificada. [10][16]

### Requisitos adicionais por dimensão

Os requisitos seguintes são propostas de aceitação para investigar e resolver as divergências. Não são justificativas atribuídas aos autores da outra avaliação: a imagem não contém essas justificativas. Também não pressupõem que as quedas sejam regressões do código. Eles complementam as seis frentes existentes, sem criar notas novas ou alterar os pesos dos dez critérios.

| ID | Dimensão e diferença observada | Requisito acrescentado | Evidência de aceitação | Frente responsável |
|---|---|---|---|---|
| RD01 | Cobertura: 80 → 70 | Inventariar requisitos de conteúdo e comportamento do escopo atual, separados da trilha futura. Distinguir escrito, implementado, testado e medido por requisito. | Matriz com todos os requisitos declarados, evidência e lacuna por linha; totais separados por estado. Eventual percentual informa denominador e exclusões, sem misturar cobertura de conteúdo e de código. | 1 e 4 |
| RD02 | Clareza: 71 → 76 | Confrontar a melhoria informada com tarefas de leitura, sem presumir que ela já atende à aceitação de 5/5. | Registro independente de execução, interpretação de unidades, estados de teste e limites; ambiguidades corrigidas e tarefas reavaliadas. | 5 |
| RD03 | Níveis de teste: 84 → 79 | Justificar a classificação L1/L2/L3 de cada requisito e mostrar o que efetivamente executou. Impedir que um teste de lógica seja apresentado como integração real. | Matriz requisito → nível → estímulo → asserção → resultado → ambiente; cenários ausentes aparecem separadamente. Os L3 obrigatórios têm resultado no host preparado. | 3 e 4 |
| RD04 | Testabilidade: 82 → 77 | Tornar falhas críticas provocáveis e observáveis, com relógio controlado onde aplicável, estímulo confirmado, prazo externo e estado final identificável. | Ensaios repetíveis de fila cheia, consumidor parado, geração incompatível e publicação incompleta; mutações selecionadas detectadas e nenhuma preparação malsucedida aceita como falha funcional esperada. | 2, 3 e 4 |
| RD05 | Acadêmica: 79 → 75 | Identificar a contribuição de cada experimento: reprodução de resultado conhecido, comparação controlada ou investigação própria. Explicitar pergunta, hipótese, método, referências e limites. | Ficha por conclusão central com evidência, condições de refutação e ameaças à validade; outra campanha confronta a conclusão. Não declarar novidade ou causalidade apenas pela existência de um benchmark. | 1 e 2 |
| RD06 | Segurança: 71 → 74 | Explicitar os limites das ferramentas que alteram host, processos e arquivos: seleção do recurso, privilégios, pré-condições e recuperação após falha. Revisar a proteção da interface de gerenciamento quando aplicável. | Casos controlados demonstram recusa de alvo indevido ou ambíguo, proteção de recursos alheios e limpeza restrita aos recursos da sessão. Validação que exigir hardware permanece pendente, identificada. | 3, 4 e 6 |
| RD07 | Rigor de medição: 74 → 76 | Vincular unidade experimental, protocolo, fonte, amostra e resultado publicado; separar dispersão interna de confronto entre campanhas. | Dados íntegros regeneram a tabela; remoção, duplicação e divergências de manifesto impedem publicação normal; conclusões têm limites compatíveis com o experimento. | 1 e 2 |
| RD08 | Estrutura: 73 → 75 | Manter uma fonte vigente por procedimento e estados coerentes entre índices, módulos, roadmap e avaliações históricas. | Percursos documentais conferidos; links válidos; cada divergência de estado resolvida. O leitor localiza execução, explicação e trabalho futuro sem instruções conflitantes. | 1 e 5 |
| RD09 | Prática: 81 → 79 | Demonstrar tarefas completas do escopo atual, incluindo entrada, saída esperada, diagnóstico de falha e encerramento. | Execução registrada do pipeline e do runtime aplicável, com contagens e conservação verificadas; preparação de NIC não é apresentada como recepção de tráfego validada. | 3 e 5 |
| RD10 | Manutenibilidade: 72 → 72 | Fazer uma mudança representativa de requisito atravessar código, teste e documentação sem deixar cópias vigentes conflitantes. | Exercício controlado altera um contrato ou unidade; os controles detectam os artefatos que ficaram desatualizados. Histórico permanece identificado e o ponto de atualização está documentado. | 1, 4 e 6 |
| RD11 | Ferramental: 73 → 73 | Validar presença, ausência e falha das dependências; declarar o alcance real dos verificadores e preservar diagnóstico reproduzível. | Configurações com e sem dependências mantêm inventário explícito; ausência gera SKIP aplicável, defeito gera FAIL, referência não apurada permanece não verificada. Instalação e comandos correspondem às versões declaradas. | 4 e 6 |

Segurança e manutenibilidade passam a ter requisitos próprios de aceitação, apesar de não possuírem notas individuais no quadro de dez critérios. Isso evita que desapareçam na média. A inclusão de RD06 não afirma que uma vulnerabilidade foi demonstrada; exige a revisão e os testes correspondentes. Resultados aplicáveis dessas duas dimensões devem acompanhar a aceitação da versão candidata, mesmo quando não alterarem a soma.

### Prioridade e encerramento das divergências

As maiores quedas numéricas informadas são cobertura (−10), níveis de teste e testabilidade (−5 cada), contribuição acadêmica (−4) e prática (−2). Essa ordenação justifica começar a reconciliação por RD01, RD03 e RD04, aproveitando a matriz de testes já prevista. Ela não estabelece severidade técnica: um defeito de segurança confirmado deve receber prioridade pela consequência, mesmo que a nota de segurança tenha subido.

Para encerrar cada divergência, registrar dimensão, requisitos envolvidos, revisão do projeto, escopo, evidência original, evidência atual e decisão. Quando a justificativa original não estiver disponível, marcar “causa da diferença não determinada” e avaliar os requisitos verificáveis; não inventar uma explicação para a queda. Uma nova aplicação da outra régua depende da obtenção de suas definições, pesos e critérios de aceitação.

RD01–RD11 entram no pacote de aceitação da frente 6. Cada requisito fica como atendido, pendente ou não aplicável com justificativa. Pendências críticas impedem a aceitação, independentemente da média. Permanecem dois resultados separados: **3,7/5 nesta régua**, com meta condicional de pelo menos 4,5; e **75 globais na Rodada 2 fornecida**, sem reatribuição de nota por este relatório.

## Evidência disponível e avanços já realizados

A suíte registrada na reavaliação terminou com 47 entradas Meson: 42 OK, duas falhas esperadas, nenhuma falha inesperada e três SKIP. L1 teve 17 OK; L2, 21 OK e duas falhas esperadas; L3, quatro OK e três SKIP. Não se somam esses números a casos GoogleTest ou asserções para produzir uma medida de cobertura. A execução usou limites de três amostras e 20 mil rodadas onde os programas os respeitam; é validação funcional, não campanha de desempenho. [2]

Os avanços são concretos. A estatística valida amostras antes da ordenação e tem testes para sentinela negativa, NaN, infinitos, posição da amostra inválida e coleção abaixo da resolução útil. O pipeline tem espera limitada, sinalização de parada, drenagem e conferência dos objetos. Seus testes exercitam consumidor parado no mesmo lcore e em outro lcore, além de vazamento deliberado e retorno parcial. [4]

O runtime passou a representar geração, heartbeat, atualidade dos dados e falha do consumidor. Existe supervisor de sessões e seu teste com subprocessos controlados foi aprovado. A documentação distingue essa evidência da integração real com EAL, que continua pendente. Isso melhora a solução sem autorizar atribuir a ela um resultado L3 que não ocorreu. [5]

Há também uma cadeia de medição utilizável como referência: o controle SPSC preserva 400 amostras em 16 cenários, com 25 repetições por cenário, fontes e metadados. Na reavaliação, as amostras eram finitas e positivas, os 400 registros de execução tinham retorno zero, os hashes das três fontes coincidiam e a regeneração produziu a mesma tabela. A conferência adicional deste relatório repetiu a igualdade da tabela e dos hashes. [6]

Os verificadores da reavaliação encontraram 465 links relativos sem quebra. Das 35 âncoras por linha examinadas, sete foram confirmadas e 28 ficaram não verificadas; 27 destas apontavam para alvos externos à árvore e uma não teve conteúdo confirmado. A aprovação do processo verificador não transforma essas 28 referências em conteúdo validado.

## Diagnóstico dos impedimentos

### Publicação incompleta ainda pode terminar com sucesso

O caminho normal do coletor verifica retornos dos processos e recusa valores não publicáveis. Entretanto, a função de regeneração lê o CSV disponível, agrupa as linhas e produz uma tabela sem conferir sua completude contra o protocolo preservado. Essa distinção foi exercitada em cópias temporárias dos dados, mantendo o conjunto original intacto. [7]

| Controle executado | Linhas no CSV | Retorno da regeneração | Resultado observado |
|---|---:|---:|---|
| Conjunto íntegro | 400 | 0 | Tabela idêntica à original. |
| Remoção de uma amostra | 399 | 0 | Tabela gerada com menos observações. |
| Remoção de um cenário inteiro | 375 | 0 | Tabela gerada sem aquele cenário. |
| Duplicação de uma amostra | 401 | 0 | Tabela gerada com uma observação repetida. |

A função expõe as contagens que recebeu; não há evidência de que tenha escondido uma linha. O defeito de contrato é aceitar como regeneração concluída um conjunto diferente do protocolo de 16 cenários e 25 repetições. Isso não invalida os 400 dados originais conferidos. Demonstra que o mecanismo atual não impede uma publicação futura incompleta ou duplicada.

A solução deve separar visualização exploratória de publicação validada. Uma exportação parcial pode ser útil, mas precisa de opção explícita, estado PARCIAL e impedimento de substituir a tabela de referência. Na publicação normal, validar conjunto de cenários, identificadores de repetição, unicidade, contagens, unidade, retornos e correspondência com o registro de execução antes de calcular os agregados.

### As correções numéricas ainda deixam contradições locais

O capítulo de mempool/ring apresenta 1,539 ns como resultado da execução mais favorável entre dez e informa mínimo de 1,543 ns para essas execuções. As duas afirmações não descrevem o mesmo conjunto tal como estão redigidas. No mesmo trecho, a amplitude 1,543–1,674 ns acompanha uma variação de 1,3×; a divisão dos extremos produz aproximadamente 1,0849×. A alternativa C++23 repete a alegação de 1,3× para a coluna DPDK. [8]

Não é possível decidir, pelos agregados, qual número deveria substituir o outro. A correção adequada começa nos registros das dez execuções. Se forem recuperáveis, recalcular e gerar os dois trechos a partir deles. Se não forem, retirar a afirmação de pertencimento ao conjunto e a razão sem sustentação, mantendo o registro histórico com sua limitação ou substituindo-o por nova coleta.

Há uma fragilidade adicional de interpretação: uma medição antiga ficar fora da amplitude de dez novas execuções não demonstra, por si só, que a antiga era impossível ou incorreta. O dado observado é que ela não foi reproduzida naquela campanha. Revisões de fonte, configuração e ambiente precisam ser confrontadas antes de uma conclusão mais forte. O relatório não estabelece a causa dessa diferença.

### A coerência inclui mensagens e comentários

Em `feed-primario.c`, o bloco `stopped` é alcançado tanto no encerramento normal quanto em caminhos que marcam falha. Depois dele, a mensagem “assinante consumiu tudo” é impressa sem condicionar o texto ao estado. Essa observação vem da inspeção do fluxo; a emissão no cenário de falha não foi demonstrada por execução L3 neste host. A mensagem deve depender da contagem efetiva e do motivo de parada. [9]

O cabeçalho estatístico ainda descreve o mínimo como melhor estimativa do custo real sob ruído unilateral e apresenta a dispersão interna como indicação de reprodutibilidade do valor típico. O contrato implementado calcula estatísticas do conjunto recebido; não realiza outra campanha nem verifica as premissas dessas interpretações. A redação deve limitar-se ao que o conjunto mostra e explicitar as condições necessárias para uma interpretação adicional. [4]

O estudo de casos remanescentes também precisa de marcação histórica mais precisa. Seu inventário descreve, por exemplo, ausência do `else` para Python, enquanto o `meson.build` atual já contém esse ramo. Não se deve apagar o incidente; é necessário distinguir “observado na auditoria” de “ainda presente”. Sua nota em 12 dimensões não deve ser convertida diretamente para esta avaliação em dez critérios. [10]

### O contrato dos testes ainda é mais estreito que algumas conclusões

O teste negativo de alocação está registrado com `should_fail: true`. Isso identifica uma saída malsucedida esperada, mas o registro sozinho não exige que a falha venha da amostra inválida. Um problema anterior à medição também pode produzir saída não zero. Recomenda-se um runner que confira código esperado, diagnóstico da coleta e ausência de tabela final válida. A entrada deve falhar se a EAL impedir chegar ao estímulo. [11]

A documentação do Meson distingue SKIP por retorno 77 e erro de preparação por 99. A instalação observada usa Meson 1.10.1; opções documentadas como introduzidas em 1.11 não devem ser copiadas para o projeto sem atualização explícita do requisito. Um runner com asserções resolve o contrato sem depender dessa atualização. [12]

Em `l1_apuracao.sh`, há mutações não exercitadas sob uid 0. O arquivo as informa, mas permanece necessário representar execução parcial no resultado agregado dessa configuração. A execução aprovada desta reavaliação ocorreu sem root; não é evidência de que todos os subcenários rodaram sob root. Essa fronteira deve entrar na matriz de ambientes, sem exigir privilégios para testes que podem ser simulados.

### Reiniciar processos não comprova toda a recuperação

O teste de morte do primário já espera confirmação de consumo antes de enviar SIGKILL. O caminho de falha do supervisor, por sua vez, injeta a morte após confirmar mapeamento, sem esperar o primeiro lote consumido. Seu teste de recuperação verifica nova geração, término dos processos antigos e sucesso posterior; não registra uma linha temporal completa de estado válido, falha, invalidação e reconstrução. [5]

O campo `old_processes_terminated` é produzido pelo próprio supervisor após chamar suas rotinas de parada. Ele é útil como diagnóstico, mas a asserção desse campo não substitui observação independente da ordem dos eventos. Para demonstrar recuperação de uma sessão que já processava dados, exigir consumo e estado inicial válido, confirmar a falha injetada e verificar que a nova sessão só publica estado válido após sua própria reconstrução.

O DPDK 25.11 documenta requisitos próprios de compartilhamento, incluindo versão compatível, configuração de memória e listas de cores distintas entre processos cooperantes. Isso justifica preservar essa configuração na evidência L3; sucesso do teste de subprocessos sem EAL não verifica esses requisitos. [13]

## Seis frentes de trabalho

### 1. Consolidar as afirmações e a origem dos números

Criar um inventário das tabelas e afirmações que sustentam decisões nos módulos desenvolvidos. Começar por custo de inicialização, travessia entre CPUs, alocação, modos de ring, comparação C/C++ e latência entre processos. Essa lista é um ponto de partida; a aceitação exige percorrer os módulos e registrar também as tabelas encontradas fora dela.

Cada entrada deve identificar grandeza, unidade, cenário, versão, fonte, tipo de evidência e decisão que depende dela. Os tipos recomendados são cálculo, medição rastreável, registro histórico incompleto e fonte externa. Duas medições do mesmo programa podem ter valores diferentes: não devem ser forçadas a coincidir apenas porque compartilham o executável. A identidade precisa incluir configuração, população, revisão e campanha.

Corrigir primeiro as duas contradições aritméticas identificadas. Em seguida, alinhar mensagens de falha, comentários estatísticos e documentos de auditoria. Manter o histórico em bloco ou página explicitamente histórica, com vínculo para a conclusão vigente. O inventário deve mostrar quantas tabelas decisórias têm e não têm evidência suficiente.

**Aceitação:** nenhuma afirmação decisória conhecida contradiz seus operandos ou a implementação; cada decisão tem evidência identificada ou foi retirada do conjunto de recomendações atuais. A nota de consistência 5 depende também de percorrer saídas e sínteses, não somente de corrigir os exemplos encontrados.

**Esforço relativo:** médio. A principal incerteza é a disponibilidade dos registros das campanhas antigas. A entrega beneficia consistência, objetividade, análise e dados, mas não soma pontos separadamente por arquivo corrigido.

### 2. Tornar a cadeia de dados verificável até a publicação

Fortalecer o protocolo do coletor existente antes de criar novos frameworks. O manifesto deve definir cenários esperados, repetições, unidade experimental, aquecimento, exclusões permitidas e revisão das fontes. A validação cruza esse contrato com CSV e registros de execução. Contagem total correta é insuficiente: um cenário duplicado pode compensar outro ausente.

Associar cada observação a uma chave única de campanha, cenário e repetição. Verificar se o valor exportado corresponde à saída da execução registrada, se o retorno foi aceitável e se as fontes correspondem ao manifesto. Registrar também falhas da captura de ambiente; a coleta atual salva stdout/stderr de `ambiente.sh`, mas não preserva seu código de retorno nos metadados. Metadados incompletos precisam de estado explícito. [7]

Adicionar controles negativos para amostra removida, duplicada, cenário ausente, execução malsucedida, unidade incompatível e fonte divergente. Exercitar a publicação completa, pois validar apenas uma função de agregação não verifica os vínculos entre arquivos. Gravar a nova tabela somente após todas as validações, evitando deixar uma tabela antiga apresentada como resultado da tentativa atual.

Depois, realizar nova campanha serial dos controles centrais, com fontes e ambiente preservados. Comparar distribuições e conclusões com a campanha anterior, sem exigir igualdade de nanossegundos. Aquecimento, repetições e intercalamento aleatório são práticas disponíveis também no Google Benchmark; o projeto pode manter seu coletor próprio e aplicar esses princípios sem migrar de biblioteca. [14]

**Aceitação:** dados íntegros regeneram a tabela; todos os controles deliberadamente inconsistentes recusam publicação normal; todas as tabelas decisórias do inventário têm cadeia suficiente ou foram substituídas. A segunda campanha registra concordâncias e divergências, inclusive quando contrariar a recomendação anterior.

**Esforço relativo:** alto. Automatizar o coletor é limitado; recuperar ou substituir várias campanhas históricas pode dominar o trabalho. Essa frente leva dados de 3 para 4 quando houver inventário e cadeia confiável, e para 5 quando abranger todas as decisões atuais.

### 3. Demonstrar falha e recuperação no runtime real

Preparar um host de ensaio com hugetlbfs gravável, páginas livres suficientes e CPUs permitidas distintas. Registrar usuário, afinidade, tamanho e quantidade de páginas, versões e argumentos. A verificação preliminar atual de páginas livres maiores que zero não é dimensionamento suficiente para qualquer execução; a capacidade precisa comportar o cenário selecionado. Essa preparação deve ser uma entrega própria, com registro da configuração, sem depender da NIC.

Executar primeiro comunicação normal e morte do primário. Preservar logs antes da limpeza dos diretórios temporários: os runners atuais removem artefatos ao sair, e o teste de recuperação não exporta todo o conteúdo das sessões. Depois, fortalecer e executar recuperação, coletando eventos com instante monotônico, processo, geração, contagem e estado do livro.

| Cenário | Estímulo e observação necessários | Invariante de aceitação |
|---|---|---|
| Sessão normal | Consumo real e conclusão dos dois processos | Contagens e lacunas correspondem ao cenário; encerramento sem erro. |
| Morte do primário ativo | Confirmar consumo antes de SIGKILL | Consumidor invalida o estado e termina pelo motivo esperado dentro do prazo declarado. |
| Consumidor sem progresso | Pausa ou término deliberado após conexão | Produtor limita espera; não declara consumo completo sem contagem correspondente. |
| Nova geração | Encerrar sessão defeituosa e reiniciar | Nenhum processo antigo permanece antes da reutilização de recursos; geração e prefixo mudam. |
| Reconstrução | Observar nova sessão desde o estado inicial | Livro só se torna válido após os lados exigidos serem observados nessa geração. |
| Dados parados com heartbeat ativo | Manter atividade sem publicação | Atualidade dos dados é tratada separadamente da atividade do processo. |

Os três primeiros testes L3 já registrados são a base; os estímulos adicionais fecham políticas que a documentação apresenta como comportamento da aplicação. Onde for necessário criar uma variante de teste, ela deve confirmar que o estímulo ocorreu. Não se aceita um ensaio que depende de “talvez o consumidor tenha atrasado”.

Definir antes da execução o prazo de detecção e o prazo externo de encerramento. Reportar ambos: o timeout interno não inclui necessariamente toda a desmontagem da EAL. Uma campanha repetida de dez ciclos por cenário é uma proposta inicial para observar reincidências, não uma certificação estatística de disponibilidade. Preservar toda tentativa malsucedida e ajustar o protocolo quando aparecer um problema, sem descartá-la silenciosamente.

**Aceitação:** políticas críticas do escopo demonstradas em processos reais, com evidência de ordem, estado e liberação. Nenhum SKIP dos cenários obrigatórios na execução de aceitação do host preparado. Isso sustenta solução 4 e L3 4; não certifica recuperação de mensagens de uma bolsa ou continuidade entre feeds externos.

**Esforço relativo:** alto e condicionado ao ambiente. Tempo de correção depende das falhas que os testes reais revelarem; não há estimativa factual em dias disponível.

### 4. Fechar a matriz de testes por requisito

Criar uma matriz pequena e mantida com requisito, nível, estímulo, resultado esperado, teste, pré-requisito e evidência. A matriz deve explicar o comportamento que o teste verifica. Um inventário de nomes de executáveis não demonstra cobertura dos contratos.

| Família de requisito | Evidência presente | Complemento necessário |
|---|---|---|
| Estatística inválida e resolução | L1 com amostras negativas, NaN, infinitos e zero | Mutações representativas; rejeição da publicação integrada e das coleções inconsistentes. |
| Posse e progresso do pipeline | L2 de vazamento, retorno parcial e consumidor parado | Manter asserções de contagem e liberação ao alterar o código. |
| Dependências e SKIP | Entradas separadas e fixtures existentes | Configurações sem Python/GTest e execução parcial por privilégio com resultado explícito. |
| Contrato do runtime | L1 de saúde e teste do supervisor sem EAL | Integração real e estados de reconstrução observados. |
| Documentação e números | Links e âncoras, com limites declarados | Aritmética e identidade das medições; autotestes que detectem regressões relevantes. |

Priorizar mutações dos defeitos que justificaram esta revisão: permitir NaN interior, ignorar o motivo de falha da coleta, omitir uma repetição, aceitar geração incompatível, marcar livro válido cedo ou trocar SKIP por OK. Cada mutação deve modificar efetivamente o programa e manter código executável; erro de compilação não é evidência de detecção funcional. Registrar mutações sobreviventes e equivalentes separadamente.

Medir cobertura de linhas ou ramos pode orientar a busca de áreas não exercitadas, mas não deve substituir essa matriz. Não é necessário impor um percentual universal. A meta L1 5 exige que os contratos críticos e suas fronteiras estejam demonstrados e que ausências não desapareçam no agregado. L2 4 exige preservar os testes atuais e tornar a causa dos negativos inequívoca.

**Aceitação:** cada requisito crítico declarado tem teste aplicável e evidência; cada exclusão tem motivo observável; mutações críticas selecionadas são detectadas. Casos que dependem de configuração diferente possuem resultado próprio ou declaração agregada de incompletude.

**Esforço relativo:** médio. Esta frente pode começar antes da preparação do host e fornece os critérios que a campanha L3 usará.

### 5. Validar clareza e objetividade por tarefas de leitura

O percurso de primeira execução já permite manter simplicidade em 4. Preservar essa estrutura e revisar os módulos desenvolvidos para que cada tema apresente pergunta, resultado, interpretação limitada e decisão prática. Detalhes de mecanismo e incidentes continuam disponíveis por referência. A solução não é reduzir capítulos por uma contagem arbitrária de linhas. [15]

Submeter o percurso a pelo menos uma pessoa que não tenha participado da redação. Essa pessoa deve compilar o exemplo, executar L1/L2, explicar um SKIP, identificar o denominador de uma tabela e localizar o comportamento de fila cheia e recuperação. Deve também distinguir o que existe hoje do que depende da próxima etapa de rede.

Registrar tarefa, resultado, dúvida, intervenção necessária e correção realizada. A aceitação é completar as tarefas essenciais sem intervenção necessária para corrigir uma ambiguidade do material, após revisão das dificuldades encontradas. Uma leitura independente é o mínimo desta régua, não evidência de usabilidade para toda população de estudantes.

**Aceitação:** todos os módulos desenvolvidos seguem o contrato de comunicação e as tarefas essenciais têm registro de execução e interpretação. Isso sustenta objetividade 5 e clareza 5. Sem essa leitura, preservar clareza 4, mesmo que os autores considerem o texto melhor.

**Esforço relativo:** médio, com dependência de um leitor disponível. O tempo de espera por essa pessoa não deve impedir dados, testes ou preparação de host.

### 6. Consolidar a versão candidata e reaplicar a régua

Reunir resultados em um pacote de aceitação identificado pela revisão efetivamente testada. A árvore pode conter alterações locais durante desenvolvimento, mas a evidência final precisa preservá-las ou apontar para uma revisão que as contenha. Um hash de commit anterior às mudanças não basta para reproduzir a versão avaliada.

O pacote deve incluir matriz de requisitos, inventário de tabelas, registros de campanha, logs selecionados, resultados de mutação, relatório de leitura independente e limitações abertas. Separar execução funcional reduzida, medição de desempenho e campanha de falhas. Uma execução rápida de CI não substitui os outros dois tipos de evidência.

Incluir também a situação de RD01–RD11 e o registro de reconciliação da avaliação adicional. Segurança, manutenibilidade e ferramental devem ter evidências próprias quando aplicáveis, mesmo sem nota autônoma na régua de dez critérios. A ausência das justificativas da outra avaliação não dispensa validar esses requisitos nem autoriza atribuir causas às diferenças de nota.

Executar os verificadores documentais e as suítes aplicáveis após consolidar as mudanças. Uma ocorrência de SKIP pode ser correta na CI comum; a mesma ocorrência em cenário obrigatório no host de aceitação significa validação pendente. A versão só recebe a nota após confrontar cada critério com seu artefato, sem usar a quantidade total de testes como atalho.

**Aceitação:** total de pelo menos 45 pontos, nenhum critério abaixo de 4 e nenhum bloqueio crítico conhecido aberto. O resultado deve registrar notas, razões, evidências e exclusões. Se um critério não alcançar a meta, manter a nota suportada e atualizar o trabalho restante.

**Esforço relativo:** médio. Esta frente integra as cinco anteriores; não substitui entregas ausentes por uma revisão editorial final.

## Ordem de execução e decisões de prioridade

| Ordem | Entrega | Dependência | Resultado revisável |
|---:|---|---|---|
| 1 | Inventário e correções de afirmações | Leitura dos módulos e acesso aos registros existentes | Lista de decisões, origem dos números e divergências resolvidas ou explicitamente retiradas. |
| 2 | Contrato da publicação e matriz de testes | Identidade das medições e requisitos | Controles negativos rejeitados; cobertura por requisito visível. |
| 3 | Host preparado e campanha de runtime | Recursos locais e critérios de falha definidos | Logs reais de comunicação, falha, encerramento e reconstrução. |
| 4 | Campanhas decisórias rastreáveis | Publicação validada | Tabelas regeneráveis e confronto entre campanhas. |
| 5 | Leitura independente dos percursos | Orientação vigente estabilizada | Registro de tarefas e correções de ambiguidades. |
| 6 | Reavaliação da versão candidata | Evidências anteriores completas | Quadro de notas sustentado, com pendências residuais identificadas. |

A preparação do host e o convite ao leitor podem começar enquanto se consolidam os dados. Não há benefício em esperar a placa para executar o runtime em memória. Também não há benefício em coletar centenas de novos números antes de corrigir o contrato que permite publicar um CSV incompleto.

Quando faltar registro antigo, a decisão é recuperar, recoletar ou retirar a conclusão atual; não reconstruir amostras por interpolação dos agregados publicados. Quando a recuperação real revelar defeito, corrigir e preservar o resultado anterior como incidente, seguido de nova evidência. Quando houver conflito entre fontes, identificar versão e cenário antes de escolher a explicação mais conveniente.

## Condições para 4,5 e para ultrapassar a meta

Os bloqueios críticos são: resultado inválido ou incompleto publicado como válido; requisito obrigatório não exercitado apresentado como aprovado; contradição material em afirmação central; ou política de falha apresentada como demonstrada sem evidência. Nenhum ganho de apresentação compensa esses bloqueios.

Atingir o vetor proposto leva a 4,5. Para 4,6, uma opção é elevar simplicidade de 4 para 5, demonstrando consulta consistente em toda a trilha desenvolvida e manutenção de procedimentos sem duplicação. Outra opção é elevar análise de 4 para 5 mediante investigação adicional que resolva incertezas materiais e confronto independente das conclusões. Nenhuma opção requer aumentar artificialmente o número de testes ou implementar a rede apenas para pontuar.

Elevar solução ou L3 para 5 exigiria uma campanha mais abrangente de integração, transições e degradação, com custos e limites demonstrados. Essa entrega não está pressuposta no esforço mínimo para 4,5. A escolha de ultrapassar a meta deve ocorrer depois de fechar os critérios mínimos, para não ampliar o escopo enquanto a base permanece incompleta.

Na futura versão com Mellanox, o escopo deve ser reaberto explicitamente. Resultados de memória não se tornam resultados de rede por transferência da aplicação para outra máquina. A avaliação dessa etapa incluirá configuração efetiva, tráfego, perdas, filas e latência medidos. O presente plano conclui primeiro a evidência do que o projeto já apresenta como sua versão atual. [3]

## Fontes e registros

As fontes locais foram examinadas em 15/09/2026. Os resultados históricos mantêm sua data e contexto. As três referências externas abaixo são fontes primárias de método ou contrato técnico; não atribuem notas ao projeto.

1. DPDK Academy. [Avaliação e plano anterior](plano-qualidade-4-5.md), especialmente régua e critérios de aceitação. Registro histórico anterior às implementações atuais.
2. DPDK Academy. [Extrato da suíte de reavaliação](evidencias/2026-09-15-plano/suites.json) e [manifesto dos arquivos examinados](evidencias/2026-09-15-plano/manifesto.json). O extrato omite o ambiente completo dos processos.
3. DPDK Academy. [Validação, dados e evolução com hardware](../00-visao-geral/validacao.md).
4. DPDK Academy. [Estatística compartilhada](../01-fundamentos/medicoes/statistics.h), [testes estatísticos](../01-fundamentos/medicoes/tests/test_l1_statistics.cpp), [pipeline](../../trilha/01-fundamentos/02-mempool-ring/pipeline_ring.c) e [controles de falha do pipeline](../../trilha/01-fundamentos/02-mempool-ring/tests/l2_failure.sh).
5. DPDK Academy. [Runtime, políticas e limites](../02-runtime-dpdk/README.md#10-quando-dá-errado), [supervisor](../../scripts/feed-supervisor.py), [teste do supervisor](../../scripts/tests/l2_feed_supervisor.py), [teste de morte](../02-runtime-dpdk/medicoes/tests/l3_primario_morre.sh) e [teste de recuperação](../02-runtime-dpdk/medicoes/tests/l3_recuperacao.sh).
6. DPDK Academy. [Tabela do controle SPSC](evidencias/2026-09-14-controle-anel/tabela.md), [amostras](evidencias/2026-09-14-controle-anel/amostras.csv), [metadados](evidencias/2026-09-14-controle-anel/metadados.json) e [execuções](evidencias/2026-09-14-controle-anel/execucoes.json). Campanha com data UTC 15/09/2026 e diretório identificado pela data local 14/09/2026.
7. DPDK Academy. [Coletor e regenerador](../../scripts/coletar-controle-anel.py), [reprodução dos controles de publicação](evidencias/2026-09-15-plano/reproduzir-publicacao.py) e [resultados observados](evidencias/2026-09-15-plano/controles-publicacao.json). Os dados adulterados existiram apenas em cópias temporárias de diagnóstico.
8. DPDK Academy. [O anel: preço da generalidade](../03-mempool-ring-mbuf/README.md#3-o-anel-o-preço-da-generalidade) e [comparação com C++23](../../trilha/01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md).
9. DPDK Academy. [Primário do feed](../02-runtime-dpdk/medicoes/feed-primario.c), bloco `stopped` e encerramento.
10. DPDK Academy. [Estudo de casos remanescentes](estudo-nunca-mentir.md) e [registro Meson](../../meson.build). O estudo utiliza outra matriz de avaliação.
11. DPDK Academy. [Registro dos testes de alocação](../03-mempool-ring-mbuf/medicoes/meson.build) e [teste de apuração e mutações](../../scripts/tests/l1_apuracao.sh).
12. Meson. [Unit tests](https://mesonbuild.com/Unit-tests.html), seções de testes pulados, erros e logs. Documentação contínua consultada em 15/09/2026; o projeto foi executado com Meson 1.10.1.
13. DPDK Project. [Multi-process Support, fonte da versão v25.11](https://raw.githubusercontent.com/DPDK/dpdk/v25.11/doc/guides/prog_guide/multi_proc_support.rst). Consultada em 15/09/2026; mesma versão principal da instalação 25.11.0 observada.
14. Google Benchmark. [User Guide](https://google.github.io/benchmark/user_guide.html), aquecimento, repetições e intercalamento aleatório. Documentação contínua consultada em 15/09/2026; usada como referência de método, sem adoção presumida da biblioteca.
15. DPDK Academy. [Primeira execução e leitura dos resultados](../00-visao-geral/execucao.md) e [índice da trilha](../../trilha/README.md).
16. Quadro de avaliação em imagem fornecido na conversa, com colunas Dimensão, Rodada 1, Rodada 2 e Δ. [Transcrição estruturada e limites de interpretação](evidencias/2026-09-15-plano/avaliacao-adicional.json). A imagem original permanece na conversa; não foram fornecidos o relatório completo, os pesos ou a revisão de cada rodada.

[1]: plano-qualidade-4-5.md
[2]: evidencias/2026-09-15-plano/suites.json
[3]: ../00-visao-geral/validacao.md
[4]: ../01-fundamentos/medicoes/statistics.h
[5]: ../02-runtime-dpdk/README.md#10-quando-dá-errado
[6]: evidencias/2026-09-14-controle-anel/tabela.md
[7]: evidencias/2026-09-15-plano/controles-publicacao.json
[8]: ../03-mempool-ring-mbuf/README.md#3-o-anel-o-preço-da-generalidade
[9]: ../02-runtime-dpdk/medicoes/feed-primario.c
[10]: estudo-nunca-mentir.md
[11]: ../03-mempool-ring-mbuf/medicoes/meson.build
[12]: https://mesonbuild.com/Unit-tests.html
[13]: https://raw.githubusercontent.com/DPDK/dpdk/v25.11/doc/guides/prog_guide/multi_proc_support.rst
[14]: https://google.github.io/benchmark/user_guide.html
[15]: ../00-visao-geral/execucao.md
[16]: evidencias/2026-09-15-plano/avaliacao-adicional.json
