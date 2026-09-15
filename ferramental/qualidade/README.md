<!-- cita-defeito -->
# Qualidade — os verificadores e o gancho

<!-- Este documento REPRODUZ as contas erradas que os verificadores pegam, para
     explicar o que cada um faz. A marca acima o isenta do portão de aritmética
     e aparece na contagem final dele: a isenção é declarada, não silenciosa. -->

**Isto não é material de estudo, mas o material depende disto para poder afirmar
que não mente.**

## Os cinco verificadores

Rodam na suíte `l1+docs`, registrados no `meson.build` da raiz. Cada um nasceu de
um defeito medido, não de teoria:

| Verificador | Regra | Defeito que o originou |
|---|---|---|
| `verificar-links.py` | link relativo aponta para arquivo e âncora que existem | âncora morta em título com travessão |
| `verificar-ancoras.py` | âncora de linha aponta para o trecho certo do código | número de linha envelhece em silêncio quando o código muda |
| `verificar-retratacoes.py` | valor declarado retratado não sobrevive fora do bloco | retratação escrita, e o número derrubado continuou publicado noutra página |
| `verificar-aritmetica.py` | percentual que o texto torna conferível fecha | "100 dos 123 ms, 83%" — e 100/123 é 81,3% |
| `verificar-autodescricao.py` | o que o material afirma sobre si corresponde ao disco | banner "conteúdo não escrito" em documento de 171 linhas medidas |

Quatro deles têm **autoteste** registrado: verificam o próprio verificador contra
casos montados, incluindo iscas de falso positivo.

E todos **pulam com código 77** quando falta `python3`, em vez de sumir da
suíte — `pular-sem-python3.sh` existe porque a ausência do `else` fazia a suíte
encolher e reportar verde.

## O gancho

`pre-commit.sh` concentra as regras de consistência do projeto. Ele é executado
pela **CI** (`.github/workflows/ci.yml`), e não apenas como gancho local: antes
disso, vivia num opt-in que nunca foi instalado, e `dependabot.yml` publicava
como proteção algo que não rodava em lugar nenhum.

## Por que aqui e não em `scripts/`

Porque o estudante não executa nada disto. `scripts/` é o que ele roda;
`ferramental/` é o que garante o que ele lê. A separação é de audiência, não de
importância — ver [o README do ferramental](../README.md).
