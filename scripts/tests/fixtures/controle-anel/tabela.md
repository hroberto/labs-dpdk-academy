# Controle do anel SPSC

Custo amortizado do ciclo de transferência, incluindo geração e conferência de sequência. Não é latência individual nem comparação com DPDK. Uma passagem de aquecimento por processo; ordem aleatória registrada, coleta serial. Os quartis descrevem repetições do custo amortizado.

| API | Lote | CPUs produtor/consumidor | Repetições | Mediana ns/objeto | p25–p75 |
|---|---:|---|---:|---:|---|
| objeto | 1 | 0/0 | 25 | 22.514 | 22.494–22.568 |
| objeto | 1 | 0/2 | 25 | 59.555 | 55.796–60.185 |
| objeto | 8 | 0/0 | 25 | 3.392 | 3.367–3.476 |
| objeto | 8 | 0/2 | 25 | 25.868 | 24.815–29.634 |
| objeto | 32 | 0/0 | 25 | 1.912 | 1.894–1.924 |
| objeto | 32 | 0/2 | 25 | 20.063 | 19.745–20.284 |
| objeto | 128 | 0/0 | 25 | 1.721 | 1.713–1.739 |
| objeto | 128 | 0/2 | 25 | 19.689 | 19.604–19.858 |
| bloco | 1 | 0/0 | 25 | 22.524 | 22.490–22.581 |
| bloco | 1 | 0/2 | 25 | 58.311 | 54.963–59.917 |
| bloco | 8 | 0/0 | 25 | 3.088 | 3.074–3.135 |
| bloco | 8 | 0/2 | 25 | 24.924 | 24.811–25.026 |
| bloco | 32 | 0/0 | 25 | 1.332 | 1.328–1.350 |
| bloco | 32 | 0/2 | 25 | 19.884 | 19.827–19.921 |
| bloco | 128 | 0/0 | 25 | 1.123 | 1.120–1.135 |
| bloco | 128 | 0/2 | 25 | 19.858 | 19.769–19.914 |

Registros: [amostras](amostras.csv), [metadados](metadados.json), [ambiente](ambiente.txt), [comandos e status](execucoes.json).

A diferença entre APIs inclui o trabalho dos laços e das cópias; não isola o custo de uma instrução atômica. A comparação entre CPUs inclui sincronização e interferência. Turbo e frequência não foram fixados; a dispersão não corrige esses fatores.
