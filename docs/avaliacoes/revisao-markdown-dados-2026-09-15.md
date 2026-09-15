# Revisão de Markdown e apresentação dos dados — 15/09/2026

A revisão encontrou melhorias de estrutura e ambiguidades na leitura das
tabelas. Foram ajustadas 18 páginas existentes, além deste relatório e do
inventário estrutural. O objetivo foi facilitar a interpretação sem substituir
registros históricos por números presumidos.

## Escopo e método

Foram examinados os arquivos Markdown de `docs/` e `trilha/`, os dois READMEs
da raiz e o roadmap. Artefatos em `docs/avaliacoes/evidencias/` e dependências
em `subprojects/` ficaram fora das edições. A análise combinou varredura de
títulos, blocos e tabelas com leitura dos trechos encontrados; candidatos
detectados por padrões foram conferidos antes de editar.

A validação é estrutural e documental. Não houve inspeção visual em navegador
nem ensaio de acessibilidade com leitor de tela. O comprimento de uma tabela
no arquivo, isoladamente, não demonstra um problema na sua renderização.

## Correções aplicadas

| Achado | Alteração | Benefício verificável |
|---|---|---|
| 47 blocos sem identificação | Aberturas agora usam `text` para saídas, árvores, contas e diagramas textuais. | O formato fica explícito; conteúdo interno preservado. |
| Nove tabelas de navegação sem cabeçalhos | Adicionados `Percurso` e `Destino`. | Cada coluna passa a ter um nome. |
| Oito tabelas comparativas com primeiro cabeçalho vazio | Adicionados nomes como `Aspecto`, `Plano` e `Estatística`. | A natureza das linhas fica identificada. |
| Salto de título em fundamentos | A subseção sobre média e mediana passou de nível 4 para 3. | Hierarquia contínua; texto do título e âncora preservados. |
| 27 listas sem separação do texto introdutório no plano | Inseridas linhas em branco antes das listas. | Separação explícita entre parágrafo ou título e lista. |
| Três tabelas com razão sem denominador no cabeçalho | Indicadas DPDK/C++23, C++23/DPDK e blocos diferentes/mesmo bloco. | Evita interpretar as razões invertidas como a mesma comparação. |
| Unidade e variável experimental pouco explícitas | Explicados custo por pacote, ciclo por objeto, trabalho em passos e razão adimensional. | Distingue parâmetro do experimento, custo amortizado e latência. |
| Razão do lote 8 no pipeline | Recalculada a partir dos valores exibidos: 2,3 / 1,3 ≈ 1,8. | A razão agora pode ser reproduzida pelos operandos da própria tabela. |
| Diferença entre execuções chamada de margem de erro | Retirada essa equivalência estatística. | O texto passa a informar apenas a diferença observada e o limite dos protocolos. |
| Índice apontando para avaliação histórica como referência corrente | Link direcionado à reavaliação datada, mantendo acesso ao plano anterior. | Facilita distinguir avaliação e histórico. |

Os tempos históricos de 2,3 e 1,3 ns/pacote foram mantidos. A razão anterior
de 1,7× não é o arredondamento a uma casa da divisão desses valores exibidos.
Não foi presumida a precisão das amostras originais: a nota junto da tabela
declara que a nova razão é derivada dos valores apresentados. Isso é uma
correção de apresentação aritmética, não uma nova medição do pipeline.

Os trechos principais estão em [fundamentos](../01-fundamentos/README.md),
[pipeline](../../trilha/01-fundamentos/02-mempool-ring/README.md),
[alternativa C++23](../../trilha/01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md)
e [plano de estudo](../plano-estudo-dpdk.md).

## Melhorias restantes

| Prioridade | Melhoria | Critério para encerrar |
|---|---|---|
| Alta | Associar cada conclusão quantitativa histórica à evidência ou à sua limitação específica. | O leitor encontra origem, cenário, unidade, agregação e limite junto da conclusão; um aviso geral não substitui essa associação. |
| Média | Rever tabelas extensas de requisitos e comparações em tela estreita. | Inspeção no renderizador usado pelo projeto, com cabeçalhos e conteúdo legíveis; dividir a tabela somente se houver benefício observado. |
| Média | Uniformizar notação editorial de unidades e casas decimais. | Valores em prosa/tabelas seguem convenção declarada; saídas literais continuam fiéis à origem e não ganham precisão artificial. |
| Média | Validar compreensão das comparações. | Leitor independente identifica numerador, denominador, unidade e limites sem orientação adicional. |
| Baixa | Considerar diagramas gráficos para desenhos ASCII extensos. | Substituição preserva significado, tem descrição textual e foi conferida no renderizador; não basta trocar o formato. |

Não foram alteradas as notas de qualidade nesta revisão. Formatação corrigida
não demonstra desempenho, cobertura completa dos testes ou compreensão por
outro leitor. A [reavaliação anterior](reavaliacao-geral-2026-09-15.md) permanece
como registro do estado examinado naquela execução.

## Verificação

O inventário continua com 81 tabelas/blocos em oito páginas. Seus hashes e
posições foram atualizados após revisar as alterações. A suíte documental,
as contagens estruturais e a conferência direta das razões ficam no
[registro desta revisão](evidencias/2026-09-15-markdown-dados/verificacao.json).
As 28 âncoras anteriormente não verificadas continuam com esse estado;
aprovação do verificador não certifica o conteúdo dessas referências.
