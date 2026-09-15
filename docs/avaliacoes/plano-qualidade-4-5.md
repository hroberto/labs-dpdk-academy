# Avaliação e plano de qualidade para alcançar 4,5

> **Registro anterior à execução do plano.** A avaliação após as mudanças
> apontava para `execucao-qualidade.md`, que nunca foi escrito — a promessa
> ficou no texto e o documento não existiu, que é a mesma classe de defeito que
> este plano combate. O que existe hoje é o
> [estudo dos casos remanescentes](estudo-nunca-mentir.md), derivado da auditoria
> adversarial de 12 dimensões. Os controles e as notas deste documento foram
> preservados como referência histórica.


O DPDK Academy tem uma base didática forte e exemplos executáveis úteis. A revisão dos capítulos melhorou a consistência e a objetividade, mas a próxima evolução depende principalmente de validar os dados, tornar os resultados dos testes completos e demonstrar as políticas de falha já desenhadas. Atingir 4,5 exige evidência nessas frentes; acrescentar explicações ou testes que apenas repetem a implementação não basta.

O escopo avaliado é a versão atual de componentes em memória, runtime e ferramentas, incluindo os documentos que apresentam a futura integração. A rede física com a Mellanox ConnectX-4 Lx permanece como etapa posterior. A nota desse escopo não certifica desempenho de rede, disponibilidade operacional de um receptor de mercado ou completude de toda a trilha futura. O próprio projeto distingue esses estados. [1]

## Quadro atualizado das avaliações

A escala permanece de 0 a 5: 0 ausente; 1 incipiente; 2 com lacunas relevantes; 3 adequado com ressalvas; 4 forte; 5 consistente e exemplar no escopo declarado. As notas são julgamentos qualitativos, não percentuais de cobertura nem medidas de precisão estatística. A coluna anterior corresponde à avaliação imediatamente precedente à análise aprofundada.

| Critério | Anterior | Atual | Meta proposta | Fundamentação da nota atual |
|---|---:|---:|---:|---|
| Consistência com a proposta | 4 | 4 | 5 | Escopo e conclusões centrais corrigidos; mensagens dos programas e o esqueleto de benchmarking ainda repetem interpretações abandonadas. |
| Objetividade | 4 | 4 | 5 | Conclusões mais delimitadas e decisões explícitas; falta aplicar o mesmo padrão aos textos residuais e às saídas dos exemplos. |
| Clareza | 4 | 4 | 5 | Percursos, unidades e estados mais claros; falta comprovar que outra pessoa consegue executar e interpretar os caminhos essenciais sem orientação adicional. |
| Simplicidade | 3 | 3 | 4 | Melhor navegação, mas conceitos, procedimentos e histórico continuam concentrados em capítulos extensos. |
| Profundidade da análise | 4 | 4 | 4 | Mecanismos e hipóteses alternativas bem discutidos; controles causais ainda propostos. A meta exige consolidar esse patamar. |
| Profundidade da solução | 3 | 3 | 4 | Posse e recuperação têm desenho e critérios; espera limitada e recuperação ainda não foram demonstradas. |
| Qualidade/cobertura aplicável L1 | 4 | 4 | 5 | Boa base de lógica e fixtures; faltam separar execução parcial e fechar fronteiras da validação estatística. |
| Qualidade/cobertura aplicável L2 | 3 | 3 | 4 | A coleta negativa de alocação passou a ser rejeitada. Entretanto, o validador compartilhado ainda aceita um conjunto com NaN interior e existem subcenários pulados dentro de uma entrada aprovada. |
| Qualidade/cobertura aplicável L3 | 3 | 3 | 4 | Pré-requisitos explícitos; faltam execução real de dois cenários de runtime e asserções mais fortes sobre falha e estado. |
| Clareza e rastreabilidade dos dados | 3 | 3 | 5 | Interpretação melhorou; as tabelas históricas relevantes ainda não têm uma cadeia completa de fontes, coleta e geração. |
| **Média simples de acompanhamento** | **3,5** | **3,5** | **4,5** | **35/50 pontos observados; 45/50 como cenário de aceitação futuro.** |

A correção da coleta negativa é um avanço confirmado. A manutenção de L2 em 3 decorre de uma lacuna remanescente demonstrada por outro controle, não de desconsiderar a correção. Nenhuma nota futura foi concedida por trabalho apenas proposto. Os resultados e comandos dos controles estão preservados junto deste relatório. [2]

### Como interpretar a nota geral

A média simples é introduzida aqui como indicador de acompanhamento, com pesos iguais de 10%. As avaliações anteriores não estabeleciam uma média oficial. Como a escala é ordinal, diferenças de décimos não devem ser tratadas como medidas exatas de qualidade. O perfil dos critérios e as pendências críticas continuam sendo a evidência principal.

O alvo de 4,5 requer dez pontos adicionais em relação aos 35 atuais. Os seis primeiros critérios somam 22 pontos; os quatro últimos somam 13. Mesmo que os seis primeiros atinjam 5, a soma será 43, ou média 4,3. Portanto, manter o esforço apenas na documentação e no desenho impede alcançar o alvo pela régua proposta.

O vetor de metas da tabela é um caminho possível, não uma previsão: cinco critérios em 5 e cinco em 4. Outra combinação pode alcançar o mesmo total. Para evitar compensar uma falha de validação com apresentação melhor, recomenda-se exigir também **nenhum critério abaixo de 4 e nenhum bloqueio crítico aberto** na versão candidata.

São bloqueios críticos: uma coleta obrigatória inválida ser aceita; um teste obrigatório não exercitado aparecer como sucesso completo; uma afirmação central contradizer a implementação sem explicação; e um requisito de falha declarado como implementado não ter evidência. A ausência declarada de uma capacidade fora do escopo não é um desses bloqueios.

## Diagnóstico aprofundado

### 1. A principal fragilidade está na cadeia de evidência

Uma conclusão confiável depende de uma sequência completa: comportamento correto, execução efetivamente realizada, amostras válidas, agregação apropriada e interpretação compatível. O projeto tem boas peças nessa sequência, mas ainda permite que a apresentação final pareça mais conclusiva que as verificações anteriores.

Na árvore examinada, `custo-alocacao.c` já chama `collection_is_valid()` antes de publicar as linhas correspondentes. Um controle que substitui apenas a medição com cache por retorno `-1.0` terminou com código 1 e a mensagem de coleta inválida. Isso fecha o defeito específico anteriormente observado. [3]

O novo controle mostrou uma limitação diferente: `collection_is_valid()` verifica contagem, mínimo, máximo e mediana, mas não cada amostra antes da agregação. O conjunto `{1, 2, NaN, 4, 5, 6, 7}` resultou localmente em mínimo 1, mediana 4 e `valid=1`. A ordenação e a posição de NaN não devem ser usadas como contrato; o fato relevante é que existe uma entrada inválida aceita. Também houve selo visual vazio, interpretado como estável, para conjuntos completamente não finitos. [4]

**Solução proposta:** separar o estado da coleta do valor de duração. Cada tentativa deve produzir sucesso com valor ou falha com motivo. Antes de ordenar, validar todos os elementos, a quantidade esperada e as regras do cenário. Uma sentinela negativa misturada com valores válidos não pode desaparecer atrás da mediana. NaN e infinito devem ser rejeitados antes de qualquer estatística.

Zero precisa de um contrato específico. Pode representar quantização do relógio, enquanto alguns callbacks existentes o usam para sinalizar falha. Esses casos não são distinguíveis apenas pelo número. Recomenda-se representar explicitamente “falha”, “coleta válida abaixo da resolução útil” e “coleta utilizável”, sem transformar zero automaticamente em desempenho excepcional ou erro universal.

A publicação deve ser atômica no nível do resultado: se um cenário obrigatório falhar depois de outro ter terminado, a saída pode preservar diagnóstico e resultados parciais, mas não deve apresentar o conjunto como benchmark aprovado. Um consumidor automatizado precisa reconhecer o estado final sem interpretar adjetivos no texto.

### 2. Aprovação da suíte não significa cobertura integral dos cenários

O controle que executou `l1_xdp.sh` numa fixture sem `xdp-features.py` registrou 18 asserções não exercitadas e terminou com código 0. O texto é transparente, mas o resultado agregado do Meson não separa o bloco ausente. No L2 do pipeline, o controle de vazamento também pode imprimir “PULADO” e terminar com “todos os testes passaram” se não conseguir provocar retorno parcial ou se faltar o binário negativo. [5]

O Meson oferece um estado explícito para teste pulado pelo código 77 no protocolo padrão. Recomenda-se registrar blocos com dependências diferentes como entradas diferentes, preservando a aprovação do bloco que rodou e o SKIP do bloco ausente. Essa proposta usa recursos já disponíveis na instalação; a documentação atual também descreve opções introduzidas depois do Meson 1.10.1 local, que não devem ser adotadas sem atualizar o requisito mínimo. [6]

**Solução proposta:** inventário de requisitos e cenários, com uma linha por comportamento relevante. Para cada linha, registrar teste, pré-requisito, resultado, motivo de exclusão e evidência. O número de entradas Meson, casos GoogleTest e asserções deve permanecer separado. Um percentual de linhas executadas, se futuramente medido, será diagnóstico complementar, nunca substituto da cobertura de falhas.

Para provocar fila cheia, prefira capacidade reduzida e um consumidor controlado por sincronização explícita em uma variante de teste. Aumentar o volume e torcer para o consumidor atrasar depende do escalonamento. O controle negativo deve demonstrar que entrou no ramo desejado e depois verificar a propriedade, evitando tratar ausência do estímulo como teste concluído.

### 3. As explicações precisam convergir também nos executáveis

O módulo de runtime passou a reconhecer que a calibração média do laço não prova resolução exata nem alinhamento dos TSCs. Entretanto, `feed-secundario.c` continua imprimindo essas conclusões. O benchmark de alocação ainda afirma independência da frequência, enquanto sua documentação limita essa inferência. O esqueleto de benchmarking continua apresentando como estabelecida a interpretação de resolução que o runtime agora questiona. [7]

**Solução proposta:** tratar documentação, ajuda, stdout, comentários pedagógicos e sínteses como uma única superfície de comunicação. Para cada afirmação central, registrar a grandeza, o programa, o cenário e o limite. A revisão deve procurar equivalência de significado; não basta eliminar uma frase por expressão regular enquanto uma paráfrase mantém o problema.

Não é necessário automatizar toda a redação. Vale automatizar campos estruturados como unidade, número de amostras e status; o vínculo entre mecanismo e conclusão continua exigindo revisão técnica. Exemplos históricos podem permanecer, desde que claramente separados da descrição do comportamento vigente.

### 4. As políticas de falha precisam sair do desenho

O pipeline devolve os objetos rejeitados pelo ring e verifica conservação ao encerrar. Porém, o consumidor espera atingir uma meta e o produtor pode repetir indefinidamente se o consumidor deixar de avançar. Acrescentar um timeout somente ao produtor não resolve o encerramento: o consumidor também precisa receber uma condição de parada e os objetos ainda possuídos precisam de destino. [8]

**Entrega mínima recomendada:** estado compartilhado de execução com motivo de parada, medição local de ausência de progresso e protocolo de encerramento. Ao vencer o prazo, parar novas aquisições; sinalizar os participantes; concluir ou descartar explicitamente o trabalho pendente; esperar que o consumidor deixe de acessar os objetos; drenar o anel; conferir conservação; liberar os recursos. A ordem precisa respeitar a posse em cada transferência.

O tempo observado pode ser comparado com um limite definido antes do teste, incluindo a tolerância de escalonamento. Num Linux comum, a verificação não prova um prazo absoluto sob qualquer carga ou suspensão do processo. A documentação deve dizer em quais condições a ação foi observada e qual limite de detecção foi testado.

Para o exemplo multiprocesso, heartbeat, atualidade dos dados e validade do livro são contratos diferentes. Um heartbeat pode continuar avançando com o feed externo interrompido. Uma lacuna de sequência pode invalidar o livro com ambos os processos vivos. A solução precisa expressar esses estados separadamente e impedir que “processo vivo” seja usado como sinônimo de “dado atual”. [9]

Uma implementação inicial pode usar um contador de heartbeat e um relógio monotônico local no observador. O consumidor mede há quanto tempo não observa mudança, sem subtrair relógios de processos diferentes. A frequência de verificação e a tolerância de agendamento entram no prazo observado. O estado válido só deve ser restabelecido por uma condição explícita de reconstrução ou sincronização.

O reinício deve usar uma geração identificável e evitar que consumidores antigos acessem recursos liberados. Isso exige um supervisor ou protocolo equivalente, não apenas procurar novamente uma memzone pelo nome. A documentação oficial exige compatibilidade de versão e mapeamentos e descreve restrições de lcores no multiprocesso; ela não substitui o protocolo de recuperação da aplicação. [10]

### 5. Profundidade analítica exige controles que possam mudar a conclusão

A comparação atual de C++ e DPDK mede programas diferentes no mesmo contrato de trabalho. Ela é útil para escolher uma implementação naquele cenário, mas não distribui o custo entre alocação, fila e sincronização. A regressão no lote 128 não foi isolada como efeito de cache. Os controles propostos no próprio módulo oferecem um bom ponto de partida. [11]

Recomenda-se priorizar três investigações. A primeira compara o anel C++ com e sem publicação em bloco, mantendo capacidade, número de objetos, afinidade e estatística. A segunda repete a variação de lote com ordem alternada e observações de frequência e cache. A terceira mede os mesmos anéis em uma thread e entre duas CPUs, separando custo local da transferência.

A literatura técnica da ferramenta Google Benchmark documenta repetição, saída estruturada e interleaving aleatório; seu guia de variância também identifica turbo, afinidade, escalonamento, SMT e cache como fontes de variação. Essas práticas podem orientar os programas atuais sem exigir migração imediata de framework. [12]

O protocolo deve definir antes da coleta: hipótese, variável alterada, fatores mantidos, unidade experimental, aquecimento, repetições, exclusões e resultado que contrariaria a hipótese. Frequência observada no início e no fim não descreve necessariamente toda a janela. Contadores de cache correlacionados com tempo não provam causalidade isoladamente.

Para latência entre processos, um controle de ida e volta cronometrado no mesmo núcleo evita subtrair relógios de CPUs distintas, mas mede outra grandeza. Dividir o resultado por dois não demonstra simetria. A análise deve apresentar esse controle como verificação complementar e preservar a incerteza da medição unidirecional.

### 6. Rastreabilidade precisa permitir auditoria da conclusão

O projeto já declara que nem todas as tabelas históricas preservam amostras e metadados. Essa declaração é necessária, mas não torna os resultados regeneráveis. O alvo 5 em dados exige tratar todas as tabelas que sustentam decisões centrais da versão candidata, não apenas acrescentar um exemplo completo enquanto as principais conclusões dependem de transcrições antigas. [1]

**Solução proposta:** inventariar as tabelas e classificá-las como cálculo, medição atual rastreável, registro histórico incompleto ou resultado externo. Para cada medição central, preservar fonte exata, opções de build, ambiente, comando, status, dados disponíveis e transformação que gera a tabela. Quando a árvore estiver modificada, o hash do commit sozinho é insuficiente: preservar também as fontes ou alterações efetivamente usadas.

Há duas verificações diferentes. Regenerar a tabela a partir do mesmo conjunto de dados deve reproduzir os agregados e arredondamentos definidos. Reexecutar o programa pode produzir outros tempos; o que deve ser confrontado é o comportamento, a distribuição e a conclusão dentro do novo cenário. Não se deve exigir igualdade com os nanossegundos históricos como teste funcional.

As tabelas antigas sem registros recuperáveis podem continuar num apêndice histórico. Para sustentar recomendações atuais, devem ser substituídas por coleta rastreável ou ter sua conclusão retirada do conjunto de evidências decisórias. Amostras individuais não podem ser reconstruídas a partir de mediana e quartis.

Os registros desta avaliação documentam testes e controles de sanidade. Eles não são uma nova campanha de desempenho e não substituem o trabalho acima.

### 7. Simplicidade deve ser avaliada por tarefas de leitura

O tamanho de um capítulo não é defeito por si só. O problema aparece quando o leitor precisa atravessar teoria, incidentes antigos e instruções de execução para descobrir uma ação vigente. Os percursos recentemente adicionados ajudam, mas ainda há oportunidades de reduzir esse esforço.

O Diátaxis distingue tutorial, guia de procedimento, referência e explicação segundo a necessidade do leitor. Recomenda-se aplicar essa distinção de forma leve: preservar a sequência didática, colocar a execução mínima num caminho contínuo e mover aprofundamentos longos ou históricos para páginas ligadas. Não é necessário reorganizar todo o repositório de uma vez. [13]

Para verificar clareza, uma pessoa com os pré-requisitos declarados deve conseguir: executar o primeiro exemplo; identificar o que passou e o que foi pulado; explicar a unidade de uma tabela; localizar o tratamento de fila cheia; e distinguir uma funcionalidade presente de uma proposta. Registrar dúvidas e intervenções necessárias é mais útil que medir somente quantidade de palavras.

Para nota 5, recomenda-se uma leitura de aceitação por alguém que não participou da redação, com registro das tarefas e correções. Essa é uma proposta de evidência pedagógica, não uma certificação externa já obtida.

## Critérios de aceitação por dimensão

| Critério | Evidência necessária para 4 | Evidência adicional para 5 |
|---|---|---|
| Consistência | Afirmações centrais compatíveis com código e escopo; exceções explícitas | Revisão cruzada de documentos, CLI, saídas e sínteses sem divergências materiais; vínculos mantidos na revisão candidata |
| Objetividade | Pergunta, resultado, limite e decisão identificáveis | Todos os módulos desenvolvidos revisados com esse padrão, sem conclusões promocionais ou repetição que obscureça a ação |
| Clareza | Unidades, pré-requisitos, resultados e estados explícitos | Leitor independente conclui as tarefas essenciais; dúvidas relevantes corrigidas e reavaliadas |
| Simplicidade | Execução principal contínua; aprofundamento acessível por referência | Consulta consistente em toda a trilha desenvolvida e manutenção sem duplicação de instruções vigentes |
| Análise | Mecanismo, alternativas e limites sustentados; controles centrais executados ou conclusões reduzidas | Investigação adicional resolve as incertezas materiais e outra execução permite confrontar as conclusões |
| Solução | Políticas críticas do escopo implementadas e verificadas sob falha | Recuperação, sobrecarga e transições demonstradas em uma integração completa do escopo, com custos e limites documentados |
| L1 | Contratos e fronteiras cobertos; casos ausentes explicitamente separados | Mutações representativas dos defeitos críticos detectadas; validade estatística completa; evidência por requisito, sem aprovações parciais ocultas |
| L2 | Caminhos reais positivos e negativos; erro esperado identificado; coleção inválida rejeitada | Falhas de integração e liberação sistematicamente cobertas em configurações declaradas, sem dependência acidental de escalonamento |
| L3 | Cenários aplicáveis executados em host preparado; falhas e exclusões separadas | Campanha repetida cobre transições e degradação relevantes; diagnóstico permite distinguir indisponibilidade de recurso e defeito funcional |
| Dados | Ao menos uma cadeia completa e inventário das lacunas; decisões limitadas à evidência disponível | Todas as tabelas decisórias regeneráveis ou justificadamente substituídas; repetição confronta conclusões; registros históricos isolados |

Esses critérios especificam o que falta para a versão candidata. Não alteram retroativamente as notas históricas nem exigem implementar funcionalidades que permanecerem explicitamente fora do escopo. Para a solução alcançar 4, entretanto, as políticas de falha identificadas como entrega dessa versão precisam funcionar; apenas documentá-las como pendentes preserva a honestidade, mas não demonstra sua solução.

## Plano de trabalho e dependências

| ID | Entrega concreta | Dependência | Aceitação | Esforço relativo |
|---|---|---|---|---|
| Q01 | Validade da coleta antes da agregação; alinhamento de selo e status | Nenhuma | Sentinela isolada/mista, NaN em posições distintas, infinito, coleta incompleta e falha de recurso nunca viram benchmark aprovado | Médio |
| Q02 | Separar testes com dependências e estímulos distintos | Nenhuma | Ausência de helper ou estímulo registra SKIP específico; defeito após requisito satisfeito registra FAIL | Médio |
| Q03 | Harmonizar documentos, comentários e saídas | Q01 para os estados de coleta | Revisão das afirmações sobre frequência, relógios, perda e disponibilidade sem contradições materiais | Pequeno a médio |
| Q04 | Espera limitada e encerramento coordenado no pipeline | Q02 para os controles | Consumidor parado provoca ação definida; todas as saídas preservam posse e contagem | Médio |
| Q05 | Heartbeat, validade do livro e geração no exemplo de runtime | Contratos definidos; Q04 fornece padrão de encerramento | Pausa legítima, morte, lacuna e reinício levam aos estados corretos, sem mistura de gerações | Grande |
| Q06 | Campanha L3 em host com hugetlbfs e topologia adequada | Host preparado; Q05 para os novos cenários | Testes reais executados, sinal esperado conferido e estado observado validado; logs preservados | Médio, condicionado ao host |
| Q07 | Cadeia de coleta e geração de tabelas | Q01 e Q03 | Tabelas regeneradas dos registros; fontes e alterações locais preservadas | Médio |
| Q08 | Controles comparativos de lote, API e colocação | Q07 | Mesmo trabalho, protocolo prévio, repetições e conclusão compatível com resultados | Grande |
| Q09 | Percurso principal e leitura de aceitação | Q03; pode começar com um módulo | Tarefas de leitura concluídas e lacunas corrigidas | Médio |
| Q10 | Revisão final do quadro e versão candidata | Q01–Q09 na extensão exigida pelas metas | Média ≥ 4,5, nenhum critério < 4 e nenhum bloqueio crítico conhecido | Pequeno a médio |

Esforço relativo expressa complexidade e incerteza, não prazo contratado. Q05 e Q08 precisam de entregas intermediárias; nenhuma estimativa de dias seria confiável antes de definir a política de recuperação e os protocolos de coleta. Q01–Q03 oferecem o retorno mais direto porque corrigem evidência e comunicação usadas por várias dimensões.

A sequência recomendada começa com Q01 e Q02, fecha Q03 e produz uma primeira coleta completa em Q07. Em seguida, entrega Q04 e Q05 com seus controles e executa Q06. Q08 aprofunda os mecanismos e Q09 verifica o uso da documentação. A avaliação final deve usar uma revisão identificada e seus artefatos, evitando atribuir ao mesmo snapshot resultados obtidos antes e depois de mudanças concorrentes.

## Matriz mínima de comportamentos a verificar

| Comportamento | L1 | L2 | L3 |
|---|---|---|---|
| Coleta válida e inválida | Classificar amostras e erros antes de agregar | Callback com falha produz status inválido e saída não zero; sucesso não imprime conclusão de falha | Recurso do host ausente tem motivo separado de erro de execução |
| Transferência e conservação | Modelo de posse, capacidades e fronteiras | Retorno parcial determinístico; vazamento deliberado detectado; liberação após aborto | Concorrência real, consumidor parado e encerramento sem acesso posterior à liberação |
| Atualidade e validade | Relógio controlado; estados e limiares | Integração da política com o exemplo sem depender de tempo físico para todas as fronteiras | Pausa, morte e retomada reais com hugetlbfs |
| Geração e recuperação | Rejeitar sessão antiga e layout incompatível | Processo/fixture novo não aceita estado anterior indevidamente | Reinício coordenado; consumidores antigos encerrados antes da liberação |
| Dados e tabelas | Agregações conhecidas, casos inválidos e arredondamento | Registro completo e tabela gerada do mesmo arquivo | Reexecução em configuração documentada, com diferenças interpretadas |

O nível segue os recursos exigidos por cada caso, conforme a definição do projeto. Uma fixture de um runner de multiprocesso continua sendo L1; não substitui o multiprocesso real. Um teste com duração total limitada evita travar a suíte, mas não comprova que a política interna detectou a falha: é necessário observar motivo e estado.

Mutações devem representar defeitos concretos: omitir uma devolução, aceitar um valor inválido, ignorar uma geração ou transformar SKIP em aprovação. Nem toda alteração de ordenação de memória se manifesta num ensaio curto em x86; ausência de falha nesse ensaio não prova que o contrato concorrente esteja correto. A revisão das invariantes continua necessária.

## Limites do hardware e da próxima versão

Nenhuma entrega de correção estatística, organização documental ou geração de tabelas exige a nova NIC. Os ensaios reais de multiprocesso dependem de hugetlbfs e permissões; tratá-los como bloqueados pela placa confundiria dois pré-requisitos diferentes. A chegada da NIC também não cria um segundo nó NUMA no host. [1]

A documentação DPDK 25.11 inclui a família ConnectX-4 Lx no suporte de mlx5. O modelo bifurcado mantém o driver do kernel; a orientação genérica de desvincular a placa para VFIO não se aplica a esse caminho. Isso fundamenta a preparação, mas não demonstra offloads, AF_XDP zero-copy ou taxa sustentada da instalação futura. [14]

Depois da instalação, a campanha deve registrar identificação exata, firmware, enlace PCIe negociado, driver, filas, descritores, afinidade, offloads, conexão e gerador. RX/TX básico, RSS, perda, cauda e recuperação devem ter resultados próprios. Duas portas e uma taxa nominal não equivalem a gerador suficiente nem a resultado ponta a ponta.

Uma nota ≥ 4,5 poderá ser defendida para a versão em memória/runtime depois de cumpridos os critérios. A versão com rede deve receber uma avaliação adicional, com escopo ampliado e evidências da NIC. Reutilizar a nota anterior como aprovação da rede seria extrapolação.

## Evidências e manutenção do quadro

A avaliação considera a árvore de trabalho identificada em [manifesto.json](evidencias/2026-09-14/manifesto.json), associada ao commit base e aos hashes dos arquivos relevantes. Como existem alterações locais, o commit base não representa sozinho os fontes examinados. O manifesto identifica o recorte; não substitui um arquivo completo de fontes para reprodução de benchmarks.

O [resumo das suítes](evidencias/2026-09-14/suites.json) preserva resultados por entrada e os parâmetros de execução, sem publicar todo o ambiente da sessão. Os [controles](evidencias/2026-09-14/controles.json) têm códigos de retorno e logs separados. O [programa de reprodução](evidencias/2026-09-14/reproduzir-controles.py) compila cópias temporárias e não modifica as fontes do projeto.

| Suíte | Resultado da execução atualizada |
|---|---|
| L1 | 14 OK |
| L2 | 15 OK e 2 EXPECTEDFAIL, ambos com saída 1 |
| L3 | 4 OK e 2 SKIP por hugetlbfs gravável com páginas livres indisponível |
| Total | 37 entradas: 33 OK, 2 EXPECTEDFAIL, 2 SKIP e 0 falhas inesperadas |

O novo EXPECTEDFAIL de alocação foi incluído na execução atualizada. O controle independente de retorno negativo também confirmou a rejeição; já o controle de NaN interior demonstra por que esse resultado não fecha toda a validade da coleta.

Os testes foram executados com amostragem reduzida para verificação funcional. Não há, nesses resultados, fundamento para substituir os números históricos de desempenho. A avaliação de clareza e simplicidade continua sendo julgamento técnico; a leitura por uma pessoa independente está proposta, não realizada.

O quadro deve mudar quando houver nova evidência suficiente para cruzar o critério de aceitação. Uma correção pode fortalecer a nota existente sem elevar o inteiro. Na revisão candidata, preservar o quadro anterior, indicar a evidência nova e justificar cada alteração; metas continuam separadas das notas observadas.

## Fontes

1. DPDK Academy. [Validação, dados e evolução com hardware][1], árvore local examinada em 14/09/2026.
2. DPDK Academy. [Registros dos controles desta avaliação][2], 14/09/2026; comandos, códigos e saídas associadas.
3. DPDK Academy. [Controle de alocação inválida][3], 14/09/2026; fonte real com alteração mínima apenas na cópia temporária.
4. DPDK Academy. [Controle de estatística inválida][4], 14/09/2026; usa o header real `statistics.h`.
5. DPDK Academy. [Controle de helper ausente][5] e [runner L2 do pipeline](../../trilha/01-fundamentos/02-mempool-ring/tests/l2_run.sh), árvore local.
6. Meson. [Unit tests][6], documentação consultada em 14/09/2026; protocolo exitcode, SKIP e compatibilidade de versão.
7. DPDK Academy. [Runtime][7], [feed-secundario.c](../02-runtime-dpdk/medicoes/feed-secundario.c), [custo-alocacao.c](../03-mempool-ring-mbuf/medicoes/custo-alocacao.c) e [escopo de benchmarking](../../trilha/03-performance/01-benchmarking/README.md), árvore local.
8. DPDK Academy. [Pipeline em memória][8] e [posse: quem libera](../03-mempool-ring-mbuf/README.md#24-posse-quem-libera) (a metade de *progresso* não tem seção própria), árvore local.
9. DPDK Academy. [Proposta de detecção e recuperação][9] e [contrato compartilhado](../02-runtime-dpdk/medicoes/feed.h), árvore local.
10. DPDK Project. [Multi-process Support][10], documentação da série 25.11 servida como 25.11.3; consultada em 14/09/2026. Instalação local 25.11.0; comportamentos específicos precisam ser confrontados com essa instalação.
11. DPDK Academy. [Alternativa C++23 e controles propostos][11], árvore local.
12. Google Benchmark. [User Guide][12] e [Reducing Variance](https://google.github.io/benchmark/reducing_variance.html), documentação consultada em 14/09/2026; princípios de coleta, não evidência de adoção no projeto.
13. Daniele Procida. [Diátaxis][13], documentação consultada em 14/09/2026; distinção entre necessidades de documentação.
14. DPDK Project. [NVIDIA MLX5 Ethernet Driver][14] e [Linux Drivers](https://doc.dpdk.org/guides-25.11/linux_gsg/linux_drivers.html#bifurcated-driver), série 25.11; consultados em 14/09/2026.

[1]: ../00-visao-geral/validacao.md
[2]: evidencias/2026-09-14/controles.json
[3]: evidencias/2026-09-14/alocacao-invalida.txt
[4]: evidencias/2026-09-14/estatistica-invalida.txt
[5]: evidencias/2026-09-14/l1-helper-ausente.txt
[6]: https://mesonbuild.com/Unit-tests.html
[7]: ../02-runtime-dpdk/README.md#46-quanto-custa-atravessar-a-fronteira
[8]: ../../trilha/01-fundamentos/02-mempool-ring/pipeline_ring.c
[9]: ../02-runtime-dpdk/README.md#104-detecção-de-ausência-e-reconstrução-de-estado
[10]: https://doc.dpdk.org/guides-25.11/prog_guide/multi_proc_support.html
[11]: ../../trilha/01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md#4-outros-eixos-de-comparação
[12]: https://google.github.io/benchmark/user_guide.html
[13]: https://diataxis.fr/
[14]: https://doc.dpdk.org/guides-25.11/nics/mlx5.html
