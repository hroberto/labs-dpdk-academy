# Caracterização refutada por divergência do instrumento

**Esta coleta não alimenta o `sensibilidade-leiaute.tsv`.** Os arquivos brutos
estão intactos e não devem ser alterados: eles são a evidência do defeito.

## O que ela tem de bom

A execução foi correta pelo protocolo. Modo texto com **zero processos
gráficos**, governor fixado em `performance`, 20 repetições por artefato,
**160 de 160 células PASS**, e os oito artefatos reproduzem byte a byte quando
recompilados pela receita que os produziu.

Ela é reprodutível. O problema é que reproduz, perfeitamente, **o instrumento
errado**.

## O que a refuta

No alinhamento de produção — `-falign-loops=64`, o que o projeto usa — o
artefato desta caracterização **não é** o binário que a campanha mede:

```
campanha 2026-09-27-1430 (build-precommit)   eaf9abfa3d4eefde…
caracterização, artefato al64                394f847c6eb99e0e…
```

Dois instrumentos. Pela regra do próprio mecanismo — `text_sha256` diferente —
uma classificação medida aqui não autoriza inferência nenhuma sobre os rótulos
que a campanha coleta.

## A causa

O `caracterizar-leiaute.sh` **remontava** a invocação do compilador a partir de
uma seleção de flags, em vez de reproduzir a receita arquivada pelo meson. Com
isso perdia os demais `-I` — entre eles o do diretório de build, onde o
`academy_version.h` é gerado. O `statistics.h` o inclui sob `__has_include`:

- **com** o cabeçalho, o programa compila a linha de procedência;
- **sem** ele, compila outro código, e o `.text` fica diferente.

Recompilando com o cabeçalho no caminho de inclusão, o `.text` volta a ser
`eaf9abfa…` — o da campanha. A causa está isolada e provada.

## O que mudou por causa dela

O caracterizador passou a **reproduzir o comando do meson**, substituindo
apenas `-falign-loops` e a saída, e ganhou um portão que roda **antes de medir
uma única repetição**:

> no alinhamento de produção, a variante tem de reproduzir o `.text` do binário
> de referência. Se não reproduzir, aborta — há variável não declarada.

Esse portão teria detectado o defeito em segundos, em vez de 40 minutos depois.
Ele é o controle negativo que faltava, e está coberto pelo
`scripts/tests/l1_ancora_producao.sh`, que prova os dois lados: que o controle
reconhece identidade (al64 reproduz) e que reconhece diferença (al32 não).

## Por que os binários não estão aqui

O diretório `artefatos/` ficou **fora do versionamento**. O projeto nunca
versionou binário em `historico/`, e a refutação não precisa deles: ela se
sustenta em três coisas que estão aqui — os oito `text_sha256` no
`manifesto.txt`, as 160 saídas, e a causa isolada acima.

Qualquer um reproduz o argumento em dois comandos, com o `-I` do diretório de
build e sem ele, e vê o `.text` mudar de `394f847c…` para `eaf9abfa…`.

Os binários em si **não** são recriáveis a partir da árvore atual: o script que
os produziu foi corrigido. Essa perda é aceita de propósito — o que se preserva
é a evidência do defeito, não o defeito empacotado.

## Por que ela não foi apagada

Porque é a única evidência de que o portão novo era necessário. Um erro que
some não ensina nada; um erro arquivado com a causa isolada é o que justifica o
teste que impede a repetição.
