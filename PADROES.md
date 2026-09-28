# Padrões de engenharia do DPDK Academy

Este documento descreve a régua que o material segue. Ele existe para que
qualquer pessoa que leia, revise ou contribua saiba **qual é o critério** — e
para que discordar dele seja possível, o que exige que ele esteja escrito.

Não é uma lista de estilo. É o que separa, neste repositório, um número
publicável de uma anedota.

---

## 1. A regra que manda em todas as outras

**Todo número publicado tem um programa que o produz.**

Não "veio de uma medição": veio *daquele* arquivo, daquela execução, arquivada
em `historico/`, com a linha de procedência que nomeia o binário, o commit, o
kernel e a data. Um número transcrito à mão é um número sem quem o confira, e
este repositório já pagou por cada vez que essa regra foi relaxada.

Do mesmo princípio saem três consequências operacionais:

- **A execução de aquecimento não é procedência.** A campanha rotula a primeira
  rodada como descartada; publicar a partir dela é publicar a condição que o
  desenho exclui.
- **Binário de árvore suja não é procedência.** Um `-dirty` no `git describe`
  significa que o commit citado não descreve o programa que produziu o número.
- **Um bloco, uma execução.** Misturar a tabela de uma rodada com a razão de
  outra produz um documento que contradiz a si mesmo, e a aritmética denuncia.

## 2. Ceticismo com alegação de desempenho

A postura padrão é **desconfiar de ganho fácil**. Preferir evidência, correção e
explicabilidade a otimização dogmática.

- Questionar a suposição antes de otimizar ou reestruturar.
- Separar correção, segurança e desempenho em decisões distintas.
- Identificar caminho quente, pressão de alocação, contenção e posse antes de
  mexer no código.
- Evitar otimização prematura, a menos que a carga, a restrição ou o modelo de
  custo a justifiquem.
- Avaliar latência, vazão, memória, afinidade de CPU, NUMA e complexidade
  operacional **juntos**.

**Alegação de desempenho sem contexto não entra.** Cenário, suposições,
hardware, método de medição e limitações fazem parte do número — não são
apêndice dele.

## 3. Como um resultado é apresentado

- **Mediana com dispersão**, não média. E o selo de dispersão alta é para ser
  lido: onde ele aparece, uma execução isolada não sustenta conclusão.
- **Razões não são intrinsecamente mais resistentes ao leiaute.** Elas só
  cancelam uma perturbação quando ela é comum aos dois termos. Quando
  numerador e denominador percorrem caminhos de código distintos, a razão pode
  **herdar — ou amplificar** — a sensibilidade de um deles. Esta seção afirmava
  o contrário, e a medição de 27/09/2026 desfez: a razão `with/without SMT
  sibling`, que o módulo 01 publica como 2,29×, tem **0,00% de variação entre
  execuções do mesmo binário e 19,65% entre alinhamentos** — enquanto o seu
  numerador não se move nada. Ela é menos robusta que o próprio termo de cima.
- **Pré-registro com critério de refutação** antes de medir. Previsão avaliada
  depois do resultado vira interpretação.
- **Controle negativo** sempre que a intervenção puder mover tudo. Se mexer numa
  variável move o que não depende dela, o instrumento está errado.
- **Resultado nulo é resultado**, e a diferença entre "refutado" e "sem
  instrumento para decidir" precisa estar dita.

## 4. Impedimento exige medição

Afirmar que algo **não é possível** carrega a mesma prova que afirmar um número.
"Exigiria outro kernel", "o arquivo é somente leitura", "a API não existe" — cada
uma dessas precisa do instrumento que mediu o "não dá". Onde não houver, o texto
diz "não verifiquei".

Um impedimento falso é pior que um número errado: ele encerra a investigação em
vez de enviesá-la, e ninguém volta a testar o que está documentado como
impossível.

## 5. Padrões de projeto, com parcimônia

Usar padrão só quando ele resolve problema real. Preferir a abstração mais clara
que melhore o raciocínio — não complexidade por si.

**Recomendados aqui:** RAII para posse e tempo de vida; *Strategy* para escolha
de política em tempo de execução; *Factory* para construção dependente de
ambiente; *Builder* para configuração complexa; injeção de dependência para
testabilidade; *object pool* e *memory pool* para alta vazão; *policy-based
design* para especialização em tempo de compilação no caminho quente; *Observer*
só onde o desacoplamento for realmente necessário; arquitetura em camadas quando
a separação melhorar correção e operabilidade.

**Evitar:** sobre-engenharia em caminho quente pequeno; estado global oculto;
camada de abstração sem necessidade; herança profunda em código sensível a
latência; generalização sem reuso demonstrado.

## 6. C++23 neste repositório

Alvo de toolchain moderna, com preferência por:

- RAII e semântica de posse forte; semântica de valor onde fizer sentido;
  liberação determinística.
- Layout contíguo, amigável ao cache e previsível.
- `std::span`, `std::ranges`, `std::expected` e algoritmos modernos onde couber.
- `constexpr` quando melhorar correção e clareza.
- Sem alocação dinâmica em laço sensível a desempenho.
- `std::optional`, `std::variant` e tipos seguros onde acrescentarem clareza.

O recurso moderno entra para aumentar correção e legibilidade, alinhado às
restrições reais de execução — não como demonstração.

**Uma regra específica, aprendida no código deste repositório:** `volatile` não
fecha corrida de dados. Ele impede o compilador de eliminar a releitura e não
faz mais que isso — não torna o acesso indivisível nem o ordena. Sinal entre
threads é `_Atomic`/`std::atomic`, com a ordenação escolhida e justificada.

## 7. DPDK

- Inicializar e gerenciar a EAL corretamente.
- Ser explícito sobre NUMA, afinidade e colocação de thread. **lcore não é CPU**,
  e a identidade entre os dois só vale quando a linha de comando a impõe.
- Preferir lote a trabalho por pacote.
- Manter o caminho quente livre de alocação.
- Cuidado com trava, atômica e contenção de linha de cache.
- Entender o custo real de mbuf, metadado e estado por núcleo.

**Preocupações típicas:** tempo de vida e posse do pacote; dimensionamento e
reuso de mempool; lote e contrapressão; fixação de worker; o compromisso entre
vazão, latência, simplicidade e manutenibilidade.

## 8. Documentação como artefato de engenharia

A estrutura é: **fundamento conceitual → mecanismo → restrições e
compromissos → implementação → validação → limitações**.

- Explicar a teoria antes do detalhe de implementação.
- Ensinar arquitetura antes de API; modelo de memória e de execução antes de
  dica de otimização.
- Dar a relação causa-efeito, não só o resultado.
- Dizer quando a técnica **não** se aplica, e por quê.
- Distinguir modelo conceitual, detalhe de implementação e ressalva do mundo
  real.
- Caminho de aprendizado crescente em complexidade, sem perder rigor.
- Exemplos que demonstram **julgamento de engenharia**, não micro-otimização de
  laço trivial.

**Comparações com alternativas em C++ puro explicam o compromisso
arquitetural honestamente** — inclusive quando a conclusão é desfavorável ao
DPDK.

## 9. Ao corrigir o material

1. Explicar o raciocínio por trás da recomendação.
2. Nomear o compromisso explicitamente.
3. Manter a solução ancorada na realidade de engenharia de sistemas.
4. Preferir o padrão robusto ao truque engenhoso e frágil.
5. Para alegação de desempenho, incluir cenário, suposições e limitações.
6. Preferir evidência a otimização especulativa.
7. Onde a decisão de projeto não for obviamente ótima, dar custo, benefício e
   modo de falha provável.

**Correção de fonte não narra a história da mudança.** O comentário qualifica o
trabalho final; o que mudou e por quê vai na mensagem de commit. E o raciocínio
transferível — o que alguém aprende com o defeito — vai no Markdown, não no
comentário.

## 10. Foco do material

- Arquitetura do DPDK e processamento de pacotes.
- Engenharia de desempenho para software de plano de dados.
- C++23 em ambiente de alto desempenho.
- Comparação entre DPDK e alternativas mais leves em C++ puro.
- Quando usar controle de baixo nível contra abstração de mais alto nível.
- Decisão de arquitetura sob restrição real de vazão, latência e operação.

---

## Os portões que aplicam isto

A régua acima não é honorária: parte dela é executada por
`ferramental/qualidade/pre-commit.sh`, que roda cerca de vinte verificadores.
Os que aplicam diretamente as regras deste documento:

| verificador | o que sustenta |
|---|---|
| `verificar-blocos.py` | todo bloco publicado existe literalmente numa coleta arquivada, excluídas a rodada de aquecimento e a árvore suja |
| `relatar-tabelas-medidas.py` | toda célula de tabela com unidade tem lastro, ou exceção declarada com razão |
| `comparar-publicado.py` | nenhum número publicado é contradito pela coleta atual |
| `verificar-concordancia.py` | a prosa concorda com o bloco que ela cita |
| `verificar-retratacoes.py` | valor retratado não sobrevive fora do bloco que o retrata |
| `verificar-citacao.py` | `CITATION.cff`, `meson.build` e a tag dizem a mesma versão |
| `verificar-paridade.py` | os pares pt/en têm a mesma estrutura |
| `verificar-autodescricao.py` | o que o material afirma sobre si corresponde ao disco |

O critério para um verificador entrar na barra é o mesmo de qualquer número:
ele tem autoteste, e o autoteste mata um mutante. Verificador que passa em
qualquer código não verifica nada.

E há duas formas de um autoteste passar sem verificar, aprendidas errando:

**Presença não implica validade.** Um campo usado como autoridade tem quatro
modos de ser inválido, e conferir só que a chave existe aprova os quatro:
chave ausente, chave presente e vazia, sentinela declarada, e valor dentro do
domínio que coincide por acidente. O `text_sha256` do manifesto passou pelos
quatro no mesmo dia — inclusive o último, o mais traiçoeiro: `sha256` da
entrada vazia são 64 hexadecimais legítimos, e *todo* alvo sem seção `.text`
recebia exatamente o mesmo. A asserção é sobre o **domínio do valor**, nunca
sobre a existência da linha.

**O teste carrega o mesmo código que a produção carrega.** Extrair funções do
script por `sed`/`eval` obriga o teste a reconstruir à mão o grafo de
dependências, e ele envelhece em silêncio: a produção ganha um auxiliar, a
lista do `sed` não acompanha, e a função ausente vira `comando não encontrado`
— que não interrompe nada dentro de uma substituição de comando. A suíte fica
verde exercitando uma versão mutilada do que diz exercitar. Quando o trecho é
grande o bastante para ser testado, ele é grande o bastante para ser um
arquivo que os dois carregam.

As duas regras têm a mesma raiz, e ela vale para além de teste: **o instrumento
respondeu não é o mesmo que a resposta serve.** Distinguir "medi e deu zero" de
"não consegui medir" é o que separa um portão de um enfeite.

### Fail-open semântico

A raiz acima tem nome, e ele merece ser dito porque o defeito não se parece com
defeito. O programa não falha, o parser não quebra, o teste fica verde. O erro
está na **interpretação**:

```
instrumento produz algo
      ↓
resultado existe sintaticamente
      ↓
resultado é vazio, ambíguo, inválido ou não-autoritativo
      ↓
consumidor não distingue "não sei" de "está bem"
      ↓
o portão abre
```

Em 27/09/2026 esse padrão apareceu **onze vezes num dia**, e seis delas dentro
do próprio mecanismo escrito para aplicá-lo: `%G?` respondendo `E` — *não
consegui conferir* — e o documento lendo como incidente; um leitor de texto
casando um rótulo que o programa deixou de imprimir; um campo gravado vazio e
o teste conferindo apenas a presença da chave; o `sha256` da entrada vazia
coincidindo entre alvos diferentes; um estado `SEM IDENTIDADE` caindo no ramo
que marcava desvio; uma régua medindo uma família de artefatos e julgando
outra; uma âncora degradando para aviso; duas sentinelas satisfazendo uma
igualdade; e um `head -1` escolhendo entre homônimos sem dizer.

**Todo portão que importa tem pelo menos três estados**, e a proibição é uma
só:

| | |
|---|---|
| válido / confirmado | pode afirmar |
| inválido / refutado | pode negar |
| **não apurável / sem evidência** | **não pode virar nenhum dos dois** |

E disso sai uma regra quase mecânica para quem escreve teste: **para cada
decisão binária que importa, teste também o terceiro estado.** Um mutante
responde "esta linha é executada?"; o terceiro estado responde "existe entrada
ambígua que ainda abre o portão?" — que é a pergunta que os onze casos
respondiam com sim.

Para a âncora da caracterização, por exemplo, são cinco casos e não dois:

```
1 referência, hash igual       -> passa
1 referência, hash diferente   -> falha
0 referências                  -> falha
2 referências                  -> falha, e não escolhe
hash ilegível                  -> falha, e não compara sentinelas
```

O último defeito daquele dia foi fechado **antes de produzir evidência
errada** — os dez anteriores só apareceram depois de já terem produzido. É o
sinal de que o princípio virou ferramenta de revisão, e não só explicação do
que já doeu.
