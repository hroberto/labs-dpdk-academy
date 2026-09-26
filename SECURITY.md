# Política de segurança

*English summary at the end.*

## O que este projeto é, e por que isso define o escopo

**DPDK Academy é material de estudo.** Não há serviço em execução, não há dados
de usuário, não há credencial, e nada aqui é implantado em produção por este
repositório. O código existe para ser lido, compilado e medido por quem estuda.

Isso muda o que "vulnerabilidade" significa aqui. O ativo a proteger é a
**integridade e a procedência do conteúdo** — que ninguém publique como se fosse
o mantenedor, e que os números publicados correspondam aos programas que os
produzem. Não é confidencialidade: não há segredo neste repositório.

## O que está no escopo

Relate como problema de segurança:

- **código de exemplo que induz prática insegura sem avisar.** Este material
  ensina operações privilegiadas — `vfio-pci`, hugepages, DMA, binding de NIC.
  Um trecho que leve o leitor a expor a máquina *sem declarar o risco* é o
  defeito mais grave possível aqui, porque o dano acontece na máquina de quem
  estuda, não na nossa;
- **script que altera o host de forma não declarada ou irreversível.**
  `scripts/preparar-nic.sh`, `preparar-hugepages.sh` e `diagnostico-nic.sh`
  mexem em estado do sistema e prometem travas e reversão. Trava que não trava
  é vulnerabilidade;
- **comprometimento da cadeia de build**: dependência, ação de CI ou artefato
  que execute código não pretendido;
- **qualquer conteúdo que permita publicar em nome do mantenedor.**

## O que não está no escopo

- ausência de tratamento de erro em programa **deliberadamente** defeituoso —
  `pipeline_ring_vazado` vaza objetos de propósito, e a suíte exige que ele
  falhe;
- limitações declaradas do material: código sem NIC física, medições de uma
  máquina só, módulos marcados como esqueleto;
- relatórios automatizados de scanner sem análise de exploração no contexto
  deste projeto.

## Como relatar

**Abra uma issue pública** em
<https://github.com/hroberto/labs-dpdk-academy/issues>.

Não há divulgação coordenada aqui, e a razão é honesta: não existe sistema em
produção para proteger enquanto se prepara uma correção. Discussão aberta ajuda
mais quem estuda do que sigilo ajudaria a segurança.

A exceção é se você encontrar credencial, chave ou dado pessoal exposto no
histórico. Nesse caso use o **Private vulnerability reporting** do GitHub, na
aba *Security*, para que o material não circule enquanto é removido.

## O que esperar

Este é um projeto mantido por uma pessoa, em tempo não integral. Não há SLA.
Relatos sobre operação privilegiada — os do primeiro item do escopo — têm
prioridade sobre qualquer outra coisa, inclusive conteúdo novo.

## Procedência do conteúdo

Todo commit é **assinado**, e a branch `main` exige assinatura **verificada**.
A chave pública está no perfil do mantenedor no GitHub.

O mecanismo varia, e a propriedade que importa não: o histórico tem commits
assinados com **SSH** e commits de merge assinados com **GPG** pelo próprio
GitHub. Dizer "GPG" no lugar de "assinado" descrevia um mecanismo, e não a
garantia — e o que a `main` exige é a garantia.

### Conferindo por conta própria

`git log --format='%G?'` responde sobre **o seu chaveiro**, e não sobre esta
árvore. Ele confere cada assinatura na hora, e conferir exige ter a chave
pública de quem assinou. Num clone recém-feito, portanto:

- os commits assinados com SSH saem `G`, porque a chave do mantenedor está
  declarada no `allowed_signers`;
- **os merges do GitHub saem `E`**, porque a chave com que o GitHub assina não
  está no seu chaveiro.

`E` não quer dizer assinatura ruim. Quer dizer *não consegui conferir*. Para
que o comando responda o que se espera dele, importe a chave e declare
confiança nela:

    curl -sS https://github.com/web-flow.gpg | gpg --import
    echo "968479A1AFF927E37D1A566BB5690EEEBB952194:6:" | gpg --import-ownertrust

Depois disso todo o histórico de `main` sai `G`. Entre os dois estados há um
terceiro que vale reconhecer: com a chave importada e **sem** a confiança
declarada, os merges saem `U` — assinatura boa, dono não confiado. Ter a chave
e acreditar que ela é mesmo do GitHub são perguntas diferentes, e o gpg as
mantém separadas de propósito.

O arquivo do GitHub traz duas chaves. A que assina hoje é `B5690EEE…`, de
janeiro de 2024; a anterior, `4AEE18F8…`, expirou em 16/01/2024 e continua ali
para conferir o histórico mais antigo.

Se preferir não mexer no chaveiro, a mesma pergunta tem resposta que não depende
dele:

    gh api repos/<dono>/<repo>/commits/<sha> --jq .commit.verification

**Esta seção já esteve errada, e do pior jeito possível.** Ela afirmava que
`git log --format="%G?"` "mostra os dois" e, três linhas abaixo, que commit sem
assinatura verificada em `main` é incidente. Quem seguisse as duas instruções
encontrava um `E` para cada merge do GitHub — e a saída provável não é abrir
um relato por merge, é concluir que `E` é normal aqui. Aprender isso é o dano,
porque `E` é também o que apareceria se a chave de assinatura tivesse sido
trocada por outra. A garantia descrita estava correta; o instrumento oferecido
para verificá-la é que não entregava o que o texto prometia, e um documento de
segurança que ensina a ignorar um sinal protege menos do que um que não
mencionasse o sinal.

Feita a conferência, a regra vale sem ressalva: se você encontrar em `main` um
commit que não verifica — `B`, ou `E`/`U` depois de importar a chave —, isso é
por si só um incidente: relate.

## Configuração do repositório

O que está ligado, e o princípio por trás:

- **Dependabot alerts** e **security updates**, com **nenhuma regra de
  auto-triagem ativa**. As duas presets do GitHub que descartam alertas
  automaticamente estão desligadas, e `.github/dependabot.yml` não tem regra
  `ignore`. O critério é único: alerta de segurança chega inteiro, e o
  julgamento sobre ele é humano. Filtro que economiza pouco e que é preciso
  lembrar que existe não se paga;
- **Secret scanning** com **push protection** — a única proteção desta lista
  que age *antes* do fato. Em repositório público, chave commitada conta como
  vazada no instante do push, e reescrever histórico não desfaz o que já foi
  indexado;
- **Private vulnerability reporting**, que é o canal citado em *Como relatar*;
- `main` protegida por ruleset **ativo e sem ator de exceção**: assinatura
  verificada obrigatória, sem force push, sem deleção, e quatro verificações
  exigidas para merge — `build-and-test`, `sanitizers`, `releases-dpdk (25.11)`
  e `releases-dpdk (26.07)` —, com a branch obrigada a estar atualizada em
  relação à `main` antes de entrar.

Exigir só `build-and-test` era o estado anterior, e este documento o registrava
como decisão em aberto. Ela foi fechada. As três que faltavam são justamente as
que pegam defeito dependente da versão do DPDK e do sanitizador — o tipo que
compila, passa no teste local e aparece no leitor. Enquanto podiam estar
vermelhas sem impedir o merge, o verde do PR afirmava menos do que aparentava.
A exigência de branch atualizada fecha o caso vizinho: um PR validado contra uma
`main` que já mudou foi medido em outra árvore.

**O que o ruleset NÃO impõe**, e vale dizer porque a prática diária sugere o
contrário:

- **não exige pull request.** Quem tem permissão de escrita pode empurrar
  direto para a `main`, desde que o commit esteja assinado e as quatro
  verificações passem. Passar por PR é prática adotada, não garantia da
  configuração;
- **`build-and-test` é aceito de qualquer origem.** As outras três estão
  vinculadas ao GitHub Actions; essa não. Qualquer aplicativo com permissão de
  status pode publicar um check com esse nome e satisfazer a regra. É sobra da
  configuração antiga, não escolha — e está aqui porque uma verificação que
  qualquer um pode afirmar garante menos do que a lista sugere.

As duas estão escritas aqui para que ninguém confunda o que a ferramenta garante
com o que o hábito faz.

**O CodeQL está ativo**, com os alvos `actions`, `python` e `c-cpp`, e roda em
todo push para `main` e em todo pull request.

Este parágrafo dizia o contrário — "não há CodeQL, e não é esquecimento" — e a
razão registrada era boa na época: o *default setup* precisa compilar, compilar
aqui exige DPDK, e `pipeline_ring_vazado` vaza de propósito e seria apontado a
cada execução. O que mudou foi a configuração, não o argumento.

O texto ficou para trás da realidade, o que num documento de segurança é pior
que não dizer nada: quem o lê para saber o que protege a árvore recebia a
resposta invertida. E há duas ressalvas que continuam valendo:

- **o CodeQL não é verificação exigida para merge** — as exigidas são as
  quatro acima, e ele não está entre elas;
- **a configuração dele não está nesta árvore.** Ele roda pelo *default setup*,
  ajustado na interface do GitHub, e não por um workflow versionado. Não há
  `.github/workflows/codeql.yml`: quem clonar o repositório não consegue
  reconstruir nem auditar quais consultas rodaram. Num projeto cuja tese é que
  todo resultado tem um programa que o produz, isso é uma exceção — e está
  escrita aqui em vez de passar despercebida.

---

## Security policy (English)

This is **educational material**: no running service, no user data, no
credentials, nothing deployed to production. The asset being protected is the
**integrity and provenance of the content**, not confidentiality.

**In scope:** example code that leads readers into unsafe privileged operations
without declaring the risk (`vfio-pci`, hugepages, DMA, NIC binding); scripts
that change host state in undeclared or irreversible ways; build-chain
compromise; anything allowing publication under the maintainer's name.

**Out of scope:** deliberately broken sample programs (`pipeline_ring_vazado`
leaks on purpose and the test suite requires it to fail); documented
limitations; unanalyzed scanner output.

**Reporting:** open a public issue. There is no production system to protect
during an embargo, and open discussion serves readers better. The exception is
exposed credentials or personal data in history — use GitHub's *Private
vulnerability reporting* for those.

All commits are signed and `main` requires **verified** signatures; the
mechanism varies (SSH for authored commits, GPG for GitHub merge commits) and
the guarantee does not. Note that `git log --format='%G?'` answers about *your
keyring*, not about this tree: on a fresh clone the GitHub merge commits come
back as `E` -- "could not check" -- because GitHub's signing key is not in your
keyring, which is not the same as a bad signature. Import it and declare trust:

    curl -sS https://github.com/web-flow.gpg | gpg --import
    echo "968479A1AFF927E37D1A566BB5690EEEBB952194:6:" | gpg --import-ownertrust

and the whole history reports `G`; imported but untrusted, those commits report
`U` instead. Without touching the keyring, `gh api
repos/<owner>/<repo>/commits/<sha> --jq .commit.verification` answers the same
question. This paragraph used to promise that `%G?` showed both mechanisms,
which taught readers to dismiss `E` -- the very value a swapped signing key
would produce. Once you can verify, a commit on `main` that does not verify is
itself an incident worth reporting.

**Repository configuration:** Dependabot alerts and security updates are on,
with **no auto-triage rules** — both GitHub presets that auto-dismiss alerts are
disabled and `dependabot.yml` carries no `ignore` rule, so every security alert
arrives intact and is judged by a human. Secret scanning with push protection is
on; private vulnerability reporting is on; `main` is protected by an active
ruleset with no bypass actor, requiring verified signatures, rejecting force
pushes and deletion, and requiring four checks to pass -- `build-and-test`,
`sanitizers`, `releases-dpdk (25.11)` and `releases-dpdk (26.07)` -- on a branch
that must be up to date with `main`. The ruleset still does **not** require a
pull request, and `build-and-test` is accepted from any source while the other
three are bound to GitHub Actions. CodeQL is
**active**, covering `actions`, `python` and `c-cpp`, on every push to `main`
and every pull request. This paragraph used to state the opposite, for reasons
that were sound at the time -- the default setup must build the code, which
requires DPDK, and `pipeline_ring_vazado` leaks on purpose. The configuration
changed; the text did not. Note that CodeQL is **not a required check for
merge**: the four listed above are, and it is not among them.
