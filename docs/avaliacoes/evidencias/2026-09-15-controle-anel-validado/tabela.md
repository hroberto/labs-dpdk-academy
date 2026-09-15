# Controle do anel SPSC

Custo amortizado do ciclo de transferência, incluindo geração e conferência de sequência. Não é latência individual nem comparação com DPDK. Uma passagem de aquecimento por processo; ordem aleatória registrada, coleta serial. Os quartis descrevem repetições do custo amortizado.

| API | Lote | CPUs produtor/consumidor | Repetições | Mediana ns/objeto | p25–p75 |
|---|---:|---|---:|---:|---|
| objeto | 1 | 0/0 | 25 | 22.589 | 22.517–22.855 |
| objeto | 1 | 0/2 | 25 | 59.305 | 55.606–60.337 |
| objeto | 8 | 0/0 | 25 | 3.422 | 3.378–3.533 |
| objeto | 8 | 0/2 | 25 | 25.530 | 24.803–26.119 |
| objeto | 32 | 0/0 | 25 | 1.903 | 1.895–1.937 |
| objeto | 32 | 0/2 | 25 | 20.235 | 19.943–20.612 |
| objeto | 128 | 0/0 | 25 | 1.741 | 1.720–1.771 |
| objeto | 128 | 0/2 | 25 | 19.843 | 19.450–19.961 |
| bloco | 1 | 0/0 | 25 | 22.610 | 22.536–23.711 |
| bloco | 1 | 0/2 | 25 | 59.485 | 55.806–61.722 |
| bloco | 8 | 0/0 | 25 | 3.098 | 3.081–3.161 |
| bloco | 8 | 0/2 | 25 | 24.836 | 24.739–25.061 |
| bloco | 32 | 0/0 | 25 | 1.336 | 1.331–1.357 |
| bloco | 32 | 0/2 | 25 | 19.880 | 19.797–19.904 |
| bloco | 128 | 0/0 | 25 | 1.148 | 1.124–1.583 |
| bloco | 128 | 0/2 | 25 | 19.826 | 19.764–19.883 |

Registros: [amostras](amostras.csv), [metadados](metadados.json), [ambiente](ambiente.txt), [comandos e status](execucoes.json).

A diferença entre APIs inclui o trabalho dos laços e das cópias; não isola o custo de uma instrução atômica. A comparação entre CPUs inclui sincronização e interferência. Turbo e frequência não foram fixados; a dispersão não corrige esses fatores.
