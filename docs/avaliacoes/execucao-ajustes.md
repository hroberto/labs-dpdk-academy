# Execução dos ajustes de qualidade

> A avaliação posterior à entrega está em
> [reavaliacao-geral-2026-09-15.md](reavaliacao-geral-2026-09-15.md): 3,8/5,
> com nova execução geral e preservação dos resultados e limites. Os registros
> abaixo descrevem a validação original da implementação.

Este registro acompanha a implementação do
[relatório de evolução](relatorio-evolucao-3-7-para-4-5.md). A matriz de contratos
e dos requisitos RD01–RD11 fica em [matriz-requisitos.md](matriz-requisitos.md).
As metas de nota continuam condicionadas à evidência, incluindo a execução real
do runtime e a leitura independente.

| Entrega | Estado e evidência |
|---|---|
| Publicação completa | Implementada; CLI rejeita doze corrupções e regenera o conjunto íntegro. |
| Mutações da publicação | Quatro contratos removidos deliberadamente são detectados pela bateria. |
| Erro de alocação | Runner exige código e diagnóstico da coleta; erro genérico da EAL não aprova o controle. |
| Divergências numéricas | Razão corrigida e identidade entre campanhas retirada por falta de registros; interpretação histórica delimitada. |
| Coerência de saídas | Primário informa contagens e motivo de encerramento; texto estatístico limita o significado da dispersão. |
| Supervisor | Aguarda estado ativo e consumo; registra eventos e exige estado final válido. Testes controlados verificam ordem, PIDs e preservação de arquivo alheio. |
| Proteção da NIC | Alvo explícito e único; guarda recusa interfaces UP/default e consultas incompletas; fixtures sem alteração de hardware. |
| Inventário | Oito páginas, tabelas/blocos identificados por posição e hash; natureza das famílias e limites explícitos. |
| Nova coleta | 400 amostras em 16 cenários, 25 repetições por cenário; publicação validada e confronto descritivo com a campanha anterior. |
| Runtime real | Pendente de hugetlbfs gravável e execução dos L3; não depende da NIC. |
| Leitura independente | [Roteiro pronto](leitura-aceitacao.md); nenhuma resposta foi preenchida como observação de leitor. |

A [comparação das campanhas](evidencias/2026-09-15-ajustes/comparacao-campanhas.json)
registra fontes idênticas do benchmark e regeneração exata das duas tabelas.
Com duas CPUs e lote 128, a mediana da API por objeto/bloco passou de
19,689/19,858 para 19,843/19,826 ns. A ordem das medianas mudou; isso não
sustenta uma afirmação de vantagem universal da API em bloco. Frequência e
interferência não foram fixadas.

A configuração local exige autenticação interativa para `sudo`. Não foi
possível preparar hugetlbfs nesta execução. Nenhuma alteração de interface,
driver, montagem ou reserva de memória do host foi realizada para contornar
essa condição. Os testes com fixtures não substituem a validação física.

## Validação executada

A suíte final teve **57 entradas: 53 OK, uma falha esperada, nenhuma falha
inesperada e três SKIP**. O controle de amostra inválida agora aparece como OK
porque seu runner verificou a causa esperada; não se trata de aceitar a amostra.
Os registros selecionados estão em [suites.json](evidencias/2026-09-15-ajustes/suites.json).

| Nível | OK | Falha esperada | SKIP |
|---|---:|---:|---:|
| L1 | 26 | 0 | 0 |
| L2 | 23 | 1 | 0 |
| L3 | 4 | 0 | 3 |

Depois dessa execução, a separação dos prefixos de geração foi reforçada e o
teste do supervisor foi executado novamente. Ele inclui agora um arquivo de
outra geração cujo prefixo começa pelos mesmos dígitos. O resultado está em
[supervisor-prefixo.json](evidencias/2026-09-15-ajustes/supervisor-prefixo.json).

Os [controles de publicação](evidencias/2026-09-15-ajustes/controles-publicacao.json)
confirmaram retorno 0 para dados íntegros e retorno 1 após remover uma amostra,
remover um cenário ou duplicar uma amostra. Os 13 casos da CLI e as quatro
mutações selecionadas passaram na suíte. A tabela anterior permanece intacta
quando a nova tentativa é recusada, acompanhada de status FAIL explícito.

A configuração Meson sem Python/GTest e os 15 marcadores executados estão em
[dependencias-ausentes.json](evidencias/2026-09-15-ajustes/dependencias-ausentes.json).
Todos retornaram 77. Esse ensaio verifica a configuração e os marcadores;
não é uma compilação completa sem essas dependências.

O pre-commit rápido terminou sem falhas ou avisos, incluindo sintaxe, build e
L1. Os verificadores continuam declarando referências não apuradas; esse
resultado não comprova o conteúdo de cabeçalhos externos. O inventário
estrutural contém 81 tabelas/blocos em oito páginas.

O [manifesto da entrega](evidencias/2026-09-15-ajustes/manifesto.json) identifica
as fontes preservadas e os artefatos. A nota 4,5 não foi concedida: o runtime
real, a leitura independente e a cobertura completa das conclusões históricas
continuam sujeitos aos critérios do plano. As duas réguas de avaliação
permanecem separadas.
