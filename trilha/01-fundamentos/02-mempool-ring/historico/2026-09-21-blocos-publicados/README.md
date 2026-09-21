# Coletas que sustentam os blocos publicados deste tópico

Os blocos de saída do `README.md` vinham de execuções avulsas: o
`verificar-blocos.py` os contava como "sem procedência", porque compara contra
o que está arquivado e a trilha não arquivava nada.

Cada arquivo aqui é a saída completa de uma invocação publicada no documento,
incluindo as linhas `EAL:` e a linha `origin:` que os blocos omitem.

| arquivo | invocação |
|---|---|
| `pipeline_ring.n10.txt` | `-l 0 --no-huge --file-prefix=topico02 -- -n 10` |
| `pipeline_ring_vazado.2m-b256.txt` | `-l 0,2 --no-huge --file-prefix=topico02 -- -n 2000000 -b 256` |
| `pipeline_ring.2m-b256.txt` | idem, no binário correto |

Não é campanha: são execuções únicas, e por isso não servem de linha de base
nem carregam dispersão. Servem para que o bloco publicado tenha um arquivo por
trás, que é o mínimo que o projeto exige de qualquer número.
