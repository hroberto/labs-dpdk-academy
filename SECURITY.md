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

Todo commit é **assinado com GPG**, e a branch `main` exige assinatura
verificada. A chave pública está no perfil do mantenedor no GitHub.

Se você encontrar um commit sem assinatura verificada em `main`, isso é por si
só um incidente: relate.

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
- `main` protegida por ruleset: assinatura verificada obrigatória, sem force
  push e sem deleção.

**Não há CodeQL**, e não é esquecimento. O *default setup* precisa compilar o
código, e compilar aqui exige DPDK instalado — ele falharia. Além disso,
`pipeline_ring_vazado` vaza de propósito e seria apontado como defeito a cada
execução; supressão mal feita em ferramenta de segurança é o começo de
ignorá-la inteira. É item de ROADMAP, não configuração às pressas.

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

All commits are GPG-signed and `main` requires verified signatures. An unsigned
commit on `main` is itself an incident worth reporting.

**Repository configuration:** Dependabot alerts and security updates are on,
with **no auto-triage rules** — both GitHub presets that auto-dismiss alerts are
disabled and `dependabot.yml` carries no `ignore` rule, so every security alert
arrives intact and is judged by a human. Secret scanning with push protection is
on; private vulnerability reporting is on; `main` is protected by a ruleset
requiring verified signatures and rejecting force pushes and deletion. CodeQL is
deliberately absent: its default setup must build the code, which requires DPDK,
and `pipeline_ring_vazado` leaks on purpose and would be flagged every run.
