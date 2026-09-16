# Ferramental

**Isto não é material de estudo.** É a infraestrutura que sustenta o material —
o que garante que ele diz a verdade, e o que foi construído para hardware que
esta máquina não tem.

Está separado de `scripts/` por uma razão medida. Antes desta divisão, `scripts/`
tinha 39 arquivos e 7792 linhas, e **o que o estudante efetivamente executa era
7% disso**:

| Finalidade | Arquivos | Linhas | Onde ficou |
|---|---:|---:|---|
| Verificadores e processo | 12 | 1444 | [`ferramental/qualidade/`](qualidade/) |
| NIC (segurança) | 6 | 716 | `scripts/` — protege a máquina de quem estuda |
| Uso do estudante | 6 | 544 | `scripts/` |

O AF_XDP era 43% de todo o código de script, para uma capacidade que a NIC de
referência não tem -- ela anuncia `xdp_features = 0x00`. Em 15/09/2026 ele saiu
do repositório inteiro, com o documento de preparação junto: escopo que não
produz resultado nesta máquina não justifica o custo de leitura.

## Versionado ou descartado: o critério mudou conforme a pergunta

Quando esta pasta foi criada, a proposta era tirar tudo do controle de versão.
Foi recusada por três razões, e a primeira é experiência direta deste
repositório: um `reset --hard` destruiu horas de trabalho não rastreado, e
colocar milhares de linhas nesse estado repetiria a condição do acidente. A
segunda: a CI executa os verificadores. A terceira: esconder é a classe de
defeito que este projeto combate -- teste que não roda, evidência fora do git,
verificação que some sem avisar.

Esse raciocínio vale para o que **fica**, e é por isso que `qualidade/` continua
versionado.

Para o AF_XDP a pergunta era outra, e a resposta também. Ali não se tratava de
onde guardar código útil, mas de **manter código que não produz resultado**: a
NIC de referência não tem XDP, então nada daquilo respondia a uma pergunta do
material. O que não agrega não precisa de lugar melhor -- precisa sair. Foi para
`temp/`, fora do git, e o que se perdeu está declarado no `meson.build`: quatro
testes L1 que exercitavam a lógica de decisão com fontes controladas.

A distinção, em uma linha: **separar e declarar** quando o código serve e
atrapalha a leitura; **descartar e declarar** quando ele não serve.

## Nesta pasta

- **[qualidade/](qualidade/)** — os verificadores que rodam na suíte `l1+docs` e
  o gancho de pré-commit que a CI executa. Registrados no `meson.build` da raiz:
  saem de `scripts/`, não saem da verificação.
