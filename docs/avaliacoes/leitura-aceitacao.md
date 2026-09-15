# Roteiro de leitura de aceitação

Estado: **não executado por leitor independente**. Este documento prepara a
validação de clareza; não é seu resultado. O leitor não deve ter participado
da redação. Registrar revisão do projeto, pré-requisitos, intervenções e dúvidas.

| Tarefa | Resultado observável | Resultado do leitor |
|---|---|---|
| Seguir a primeira execução | Compilar e executar L1/L2; localizar logs | Pendente |
| Interpretar um SKIP | Identificar requisito ausente e comportamento não verificado | Pendente |
| Ler D09 | Explicar unidade, repetição, cenário e limite da comparação | Pendente |
| Localizar fila cheia | Explicar quem possui os objetos rejeitados e como termina | Pendente |
| Localizar recuperação | Separar lógica, supervisor e integração EAL | Pendente |
| Identificar próxima etapa | Distinguir memória, runtime e rede física | Pendente |

Usar [primeira execução](../00-visao-geral/execucao.md),
[inventário](inventario-dados.md) e [matriz](matriz-requisitos.md).
Para cada tarefa, anotar o comando ou trecho usado, o resultado e qualquer
intervenção necessária. Uma ambiguidade corrigida exige repetir a tarefa.
Não preencher respostas previstas como se fossem observações do leitor.

## Aceitação da apresentação de dados

As tarefas abaixo complementam a leitura geral e continuam **não executadas**.
O registro deve ser preenchido pelo leitor, sem gabarito antecipado.

1. Na alternativa C++23, identificar por que uma tabela divide DPDK por C++23
   e outra faz a divisão inversa; recalcular uma razão com os valores exibidos.
2. Na síntese final, localizar a origem de um tempo histórico e explicar qual
   evidência falta para tratá-lo como desempenho da versão atual.
3. Distinguir ns por objeto, ns por pacote e p99 por mensagem; explicar por
   que esses valores não podem ser somados como etapas do mesmo pipeline.
4. Ler C09 e C10 da matriz em uma tela estreita e localizar estímulo, evidência
   e limite; registrar qualquer necessidade de rolagem horizontal.

Para cada tarefa, registrar data, revisão, dispositivo/largura, trecho usado,
resposta, intervenção recebida e resultado observado. Dúvida ou erro exige
correção e nova tentativa; a existência deste roteiro não concede aprovação.
