# Topologia de lcores — recoleta de procedência

**Por que esta coleta existe, e por que ela não segue o protocolo de modo texto.**

O bloco de `--lcores` da §5 do módulo 02 era sustentado **exclusivamente** por
`estado-lcore.lcores` da coleta `2026-09-24-1917`, cuja linha de procedência diz:

```
origin: estado-lcore @ v0.06.00-41-g0ae1546-dirty
```

`-dirty` significa árvore com alterações não commitadas. O commit citado não
descreve o programa que produziu aquele número, e o *diff* não existe em lugar
nenhum — a cadeia "todo número publicado tem um programa que o produz" estava
rompida para aquelas três linhas.

## Por que esta recoleta é válida fora do modo texto

O bloco em questão é **topologia**, não desempenho. As colunas saem de
`rte_lcore_cpuset()`, `rte_lcore_to_cpu_id()` e do nó NUMA — consultas ao mapa
da máquina, sem relógio no caminho. Sessão gráfica não altera o mapeamento de
lcore para CPU.

A confirmação é empírica: a saída é **idêntica byte a byte** à publicada, que
veio da máquina em modo texto com outro kernel.

## O kernel mudou, e isso fica registrado

| | coleta anterior | esta |
|---|---|---|
| kernel | 7.0.0-31-generic | **7.0.0-34-generic** |
| commit | `v0.06.00-41-g0ae1546-dirty` | `v0.07.00-16-g0275f14` |

A máquina foi atualizada em 25/09. Para esta grandeza a mudança não tem efeito —
a tabela é a mesma. Para as grandezas de **tempo**, ela é uma variável nova: as
coletas arquivadas são todas de 7.0.0-31, e a próxima campanha não será
diretamente comparável a elas sem que isso esteja dito.
