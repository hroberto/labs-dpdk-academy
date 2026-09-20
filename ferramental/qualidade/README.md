<!-- cita-defeito -->
# Qualidade — os verificadores e o gancho

<!-- Este documento REPRODUZ as contas erradas que os verificadores pegam, para
     explicar o que cada um faz. A marca acima o isenta do portão de aritmética
     e aparece na contagem final dele: a isenção é declarada, não silenciosa. -->

**Isto não é material de estudo, mas o material depende disto para poder afirmar
que não mente.**

## Os nove verificadores

Rodam na suíte `l1+docs`, registrados no `meson.build` da raiz. Cada um nasceu de
um defeito medido, não de teoria:

| Verificador | Regra | Defeito que o originou |
|---|---|---|
| `verificar-links.py` | link relativo aponta para arquivo e âncora que existem | âncora morta em título com travessão |
| `verificar-ancoras.py` | âncora de linha aponta para o trecho certo do código | número de linha envelhece em silêncio quando o código muda |
| `verificar-retratacoes.py` | valor declarado retratado não sobrevive fora do bloco | retratação escrita, e o número derrubado continuou publicado noutra página |
| `verificar-aritmetica.py` | percentual que o texto torna conferível fecha | "100 dos 123 ms, 83%" — e 100/123 é 81,3% |
| `verificar-autodescricao.py` | o que o material afirma sobre si corresponde ao disco | banner "conteúdo não escrito" em documento de 171 linhas medidas |
| `verificar-promessa.py` | todo programa citado existe na árvore, e toda fonte entra na compilação | `controle-anel.cpp` na árvore sem registro e sem compilar |
| `verificar-idioma.py` | documento em inglês não carrega português | quatro varreduras por lista de palavras declararam a paridade limpa, e ela não estava |
| `verificar-paridade.py` | par pt/en tem a mesma estrutura de títulos, posição a posição | tradução ganhou seção que o original não tinha, e ninguém viu |
| `verificar-tabelas.py` | toda linha de tabela tem a largura do cabeçalho dela | sete linhas de referência bibliográfica dentro da tabela comparativa da §6.2, com duas células numa tabela de três |

**Os nove têm autoteste** registrado, e eles verificam o próprio verificador
contra casos montados, incluindo iscas de falso positivo. `verificar-links.py`
foi o último a ganhar o seu, e a demora era o problema: é o de maior alcance, e
um verificador que passa a aceitar tudo continua imprimindo "N links
verificados, 0 quebrados" — verde indistinguível do legítimo.

O último da lista nasceu de uma medição, não de teoria. As promessas executáveis
deste material são todas da forma *"Rode `X` e observe `Y`"*; **nenhuma é
pergunta de compreensão**. O projeto não promete que o leitor entenda — promete
que ele consiga refazer. Clareza não tem proxy sintático (quatro instrumentos
foram testados contra este corpus e os quatro produziram ruído), mas "o programa
citado existe e é construído" é decidível, e é a promessa que de fato foi feita.

## O que NÃO é portão: `auditar-fontes.py`

Os nove acima são decidíveis: ou a linha tem a largura certa, ou não tem.
`auditar-fontes.py` não é — ele mede **distância entre a afirmação e a fonte
dela**, e erra de propósito para os dois lados.

Ele existe porque a regra de citação passou a ser cumprida no fim do documento.
As seções 10 e 13 acumularam as referências, o que dá aparência de cobertura
sem entregar nenhuma: fonte listada no rodapé não sustenta um parágrafo mil
linhas acima. Foi o caso do futex — as duas afirmações do §5.2 tinham fonte
desde sempre, a mil linhas de distância.

Rode-o à mão (`-v` lista os candidatos). Ligá-lo no portão repetiria o erro que
este repositório já documentou: **verificador ruidoso é desligado, e
verificador desligado não verifica nada.**

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
