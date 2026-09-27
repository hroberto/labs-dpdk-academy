# Caracterização não classificável: árvore suja, e a sujeira mudou o instrumento

**Esta coleta não alimenta o `sensibilidade-leiaute.tsv`.** Os arquivos brutos
estão intactos: ela documenta um mecanismo de contaminação diferente do da
coleta das 15:27, e por isso vale guardada.

## O que ela tem de bom

Modo texto com **zero processos gráficos**, governor fixado, 20 repetições por
artefato, **160 de 160 células PASS**. E a âncora **fechou**: no alinhamento de
produção a variante reproduz byte a byte o binário do `build-precommit/` daquela
árvore. O portão introduzido depois da coleta das 15:27 funcionou.

## O que a refuta

A árvore estava **suja**. Um arquivo rastreado tinha sido removido — um wrapper
acidental que um `git add -A` descuidado havia versionado —, e o `git describe`
passou a terminar em `-dirty`.

O `PADROES.md` §1 diz que binário de árvore suja não é procedência. Aqui isso
**não é formalidade**: a sujeira alterou materialmente o instrumento.

```
v0.08.00-36-gb07a8f94        (21 chars)  ->  .text eaf9abfa…   campanha 14:30
v0.08.00-42-g769f98c7-dirty  (27 chars)  ->  .text b8ab1d8a…   esta coleta
```

## O mecanismo, medido

Compilando o mesmo fonte, com as mesmas flags, trocando só a string de
procedência:

| | `.text` | `.rodata` |
|---|---|---|
| mesmo comprimento, conteúdo diferente | **idêntico** | diferente |
| comprimento diferente | **diferente** | diferente |

A causa é o endereçamento relativo ao PC: mudar o tamanho de um literal desloca
os objetos seguintes no `.rodata`, e cada referência a eles carrega o
deslocamento **dentro do `.text`**.

Ou seja: o `text_sha256`, que existe para identificar o instrumento, mudava
quando o contador de commits passasse de dois para três dígitos, quando uma tag
ficasse mais longa, ou quando a árvore ficasse suja. Por razão nenhuma ligada à
máquina ou ao código medido.

## O que mudou por causa dela

**O `statistics.h` passou a guardar a procedência em espaço fixo** — um
`const char[64]` com `_Static_assert` de limite, para que tag grande demais
quebre a compilação em vez de truncar em silêncio. O conteúdo continua inteiro
no `.rodata`; o código para de se mover.

**E a caracterização ganhou um portão de árvore limpa**, que olha também
arquivos não rastreados — `git describe --dirty` os ignora, e um `.h` solto no
diretório de fontes entra na compilação sem aparecer ali. Coletas em
`historico/` são exceção declarada: são saída de medição, nunca entram em
caminho de inclusão.

Esse portão teria impedido esta execução **antes da primeira compilação**.

## Por que ela não foi apagada

Porque é a evidência de que o `.text` respondia ao comprimento da própria
linha de procedência — um caminho de contaminação que ninguém tinha procurado,
e que só apareceu porque a âncora da coleta anterior obrigou a comparar dois
hashes que deveriam coincidir e não coincidiram.
