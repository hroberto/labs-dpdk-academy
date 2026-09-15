# Reavaliação geral após os ajustes — 15/09/2026

A avaliação atual é **3,8/5 (38/50)**, contra **3,7/5 (37/50)** da
[avaliação anterior](relatorio-evolucao-3-7-para-4-5.md). A melhora concedida é
em clareza e rastreabilidade dos dados. A suíte final executou 57 entradas:
53 OK, uma falha esperada, nenhuma falha inesperada e três SKIP. A meta 4,5
continua sem evidência suficiente para aprovação.

## Método e isonomia

Foram mantidos os dez critérios, pesos iguais de 10% e a escala anterior:
0 ausente; 1 incipiente; 2 com lacunas relevantes; 3 adequado com ressalvas;
4 forte; 5 consistente e exemplar no escopo declarado. As notas são julgamentos
qualitativos fundamentados; não são medições objetivas nem percentuais de
cobertura. Não se inferiram resultados de cenários ausentes, causas de
desempenho, compreensão de leitores ou funcionamento da NIC futura.

A inspeção abrangeu a política de validação, primeira execução, matriz,
inventário, roteiro de leitura, trechos dos módulos relacionados às pendências
e os controles de publicação, supervisor e proteção de interface. Os testes
abrangeram todas as entradas registradas no build, sem filtro por nível.
Isso não constitui revisão semântica exaustiva de cada afirmação da documentação.

Foram usados os mesmos limites funcionais da avaliação anterior: três amostras
e 20 mil rodadas nos programas que respeitam essas variáveis. A execução foi
serial para evitar concorrência entre entradas da suíte. Não se interpretaram
os tempos obtidos como campanha de desempenho. Não foram produzidas métricas
de cobertura de linhas/ramos nem executada uma campanha de sanitizadores.

O [manifesto](evidencias/2026-09-15-reavaliacao-geral/manifesto.json) identifica
comandos, fontes e artefatos. A árvore estava modificada; por isso o commit base
é acompanhado de hashes e de um arquivo com as fontes avaliadas. Os dados
históricos originais foram preservados. A compilação completa da atividade
imediatamente anterior foi incorporada como evidência, identificada como tal.

## Resultados observados

| Nível | Entradas | OK | Falha esperada | FAIL | SKIP |
|---|---:|---:|---:|---:|---:|
| L1 | 26 | 26 | 0 | 0 | 0 |
| L2 | 24 | 23 | 1 | 0 | 0 |
| L3 | 7 | 4 | 0 | 0 | 3 |
| Total | 57 | 53 | 1 | 0 | 3 |

Os [resultados por entrada](evidencias/2026-09-15-reavaliacao-geral/suites.json)
preservam saída, retorno e duração. Não se somam as duas execuções desta
atividade nem os casos internos dos testes para anunciar mais cobertura.

A primeira execução teve duas falhas de gravação de evidência: o avaliador
definiu `DPDK_ACADEMY_EVIDENCE_DIR` com um diretório pai ainda inexistente.
Os runners anunciaram ausência de hugetlbfs gravável, mas a preservação dos
logs terminou com erro de `mktemp`, produzindo FAIL. O resultado original está
em [suites-primeira-execucao.json](evidencias/2026-09-15-reavaliacao-geral/suites-primeira-execucao.json).
Após criar o diretório, toda a suíte foi repetida, sem mudar os fontes.
Os mesmos dois testes retornaram 77. A primeira execução não foi apagada nem
reclassificada; o resultado final corresponde à execução com o diretório criado.

Os três SKIP finais são comunicação primário/secundário, morte do primário com
invalidação e reinício em nova geração. O [ambiente observado](evidencias/2026-09-15-reavaliacao-geral/ambiente.json)
tinha 1.024 hugepages livres de 2 MiB, mas `/dev/hugepages` pertencia ao root,
com modo `drwxr-xr-x`, sem escrita para o usuário uid 1000. Não houve preparação
privilegiada do host. Esses testes dependem de memória compartilhada acessível,
não da Mellanox ConnectX-4 Lx.

A falha esperada de L2 é o controle de inicialização com argumento inválido.
Seu registro confirma retorno não zero; esse contrato é menos específico que
o controle de coleta inválida, cujo runner também confere o diagnóstico.
Não se atribui à falha esperada uma verificação de causa mais forte que a
implementada pelo teste.

Outras evidências verificadas:

- Compilação separada, com cache do compilador desabilitado: 84 etapas,
  retorno zero, sem avisos ou erros no [log de compilação](evidencias/2026-09-15-reavaliacao-geral/compilacao-nova.txt).
- Publicação: um caso íntegro e doze corrupções controladas passaram nas
  asserções; quatro mutações de contratos foram detectadas pela bateria.
- As duas campanhas de 400 amostras foram regeneradas em cópias, com status
  válido e tabelas idênticas byte a byte; ver [regeneração](evidencias/2026-09-15-reavaliacao-geral/regeneracao-campanhas.json).
  Isso verifica os dados preservados, sem realizar uma nova coleta.
- A suíte conferiu 531 links relativos sem quebra e um inventário de 81
  tabelas/blocos em oito páginas. Das 35 âncoras por linha, sete foram confirmadas
  e 28 ficaram não verificadas: 27 externas e uma sem conteúdo confirmado.
  A verificação posterior dos links deste relatório fica registrada à parte.
- Os testes de supervisor e proteção da interface passaram com fontes
  controladas. Não comprovam recuperação com EAL nem alteração segura da NIC real.

## Notas por critério

| Critério | Anterior | Atual | Fundamentação e limite |
|---|---:|---:|---|
| Consistência com a proposta | 4 | 4 | Política distingue memória, runtime e rede futura; correções numéricas e estados históricos estão explícitos. Falta revisão cruzada completa das afirmações centrais para 5. |
| Objetividade | 4 | 4 | Percurso de execução, contratos e pendências localizáveis. Não foi demonstrada aplicação integral de pergunta, resultado, limite e decisão em todos os módulos desenvolvidos. |
| Clareza | 4 | 4 | Unidades e estados têm explicação explícita. O roteiro de leitura continua sem execução independente, requisito anterior para 5. |
| Simplicidade | 4 | 4 | Há um percurso curto de primeira execução e referências para aprofundamento; não foi observado motivo para alterar a nota dentro da inspeção realizada. |
| Profundidade da análise | 4 | 4 | Hipótese, fatores não controlados e confronto de duas campanhas estão registrados. Não há demonstração causal nem confronto equivalente de todas as conclusões históricas. |
| Profundidade da solução | 3 | 3 | Pipeline e supervisor controlado passaram, incluindo falhas provocadas. Recuperação em processos DPDK reais continua sem execução, condição anterior para 4. |
| Qualidade/cobertura aplicável L1 | 4 | 4 | 26 entradas OK, mutações detectadas e contratos mapeados. A matriz se declara selecionada; não há demonstração de cobertura integral das fronteiras críticas e dos ambientes pendentes. |
| Qualidade/cobertura aplicável L2 | 4 | 4 | 23 OK e um negativo esperado; publicação incompleta, retorno parcial, consumidor parado e supervisor exercitados. A aprovação não é percentual de cobertura. |
| Qualidade/cobertura aplicável L3 | 3 | 3 | Quatro executados e três SKIP. Os requisitos de runtime continuam sem evidência; ausência da NIC futura não foi usada como reprovação adicional. |
| Clareza e rastreabilidade dos dados | 3 | 4 | Publicação recusa corrupções; duas tabelas regeneradas exatamente; inventário e restrições dos dados históricos explícitos. Falta rastreabilidade ou retirada individual das conclusões restantes para 5. |
| **Total / média** | **37 / 3,7** | **38 / 3,8** | **O aumento de um ponto em dados altera a média em 0,1.** |

O patamar 4 em dados reconhece uma cadeia operacional forte no conjunto
delimitado D09 e o bloqueio de publicações inválidas. Não concede a condição de
5 — rastreabilidade de todas as tabelas que sustentam decisões ou retirada de
suas conclusões. A quantidade de testes novos não concedeu automaticamente
pontos em L1/L2; resultados aprovados e extensão da cobertura são propriedades
diferentes. A média não compensa os requisitos de aceitação ainda pendentes.

## Avaliação adicional recebida

As notas da imagem continuam como histórico transcrito, sem reatribuição.
Não foram fornecidos rubrica, pesos e evidências que permitam reaplicar aquela
régua com isonomia. A causa das divergências permanece não determinada.

| Dimensão | Rodada 1 | Rodada 2 | Situação dos requisitos associados nesta revisão |
|---|---:|---:|---|
| Cobertura | 80 | 70 | RD01: matriz delimitada; inventário exaustivo pendente. |
| Clareza | 71 | 76 | RD02: leitura independente pendente. |
| Níveis de teste | 84 | 79 | RD03: resultados separados; três L3 não executados. |
| Testabilidade | 82 | 77 | RD04: negativos e mutações executados; recuperação EAL pendente. |
| Acadêmica | 79 | 75 | RD05: D09 confrontado; demais famílias sem nova campanha nesta revisão. |
| Segurança | 71 | 74 | RD06: proteção e limpeza verificadas com fixtures; integração física pendente. |
| Rigor de medição | 74 | 76 | RD07: publicação e regeneração verificadas; histórico com lacunas. |
| Estrutura | 73 | 75 | RD08: links conferidos; aceitação do percurso pelo leitor pendente. |
| Prática | 81 | 79 | RD09: pipeline executado; runtime compartilhado e rede pendentes. |
| Manutenibilidade | 72 | 72 | RD10: mutações executadas; exercício completo de manutenção pendente. |
| Ferramental | 73 | 73 | RD11: ambiente atual exercitado; ensaio sem dependências é evidência anterior, não repetida aqui; uid 0 e referências externas não verificados. |
| Global | 77 | 75 | Valores históricos, sem conversão para 3,8/5. |

## Pendências para uma nova candidatura a 4,5

1. Executar os três L3 de runtime em hugetlbfs acessível, preservando estados,
   consumo, falha injetada, encerramento e recuperação. Isso permite avaliar
   solução e L3 para 4, sem antecipar aprovação.
2. Aplicar o roteiro a leitor independente e registrar intervenções e repetição
   das tarefas após correções, para reconsiderar clareza 5.
3. Completar a revisão semântica por afirmação e por módulo: consistência,
   objetividade e todas as decisões quantitativas precisam de evidência própria.
4. Completar as fronteiras críticas da matriz e os ambientes ainda não
   demonstrados; mutações selecionadas não encerram toda a aceitação de L1.

Mantém-se o cenário de aceitação anterior: consistência 5, objetividade 5,
clareza 5, simplicidade 4, análise 4, solução 4, L1 5, L2 4, L3 4 e dados 5.
São 45/50 pontos, sete acima desta revisão, condicionados a evidências novas.
