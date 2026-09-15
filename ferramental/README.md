# Ferramental

**Isto não é material de estudo.** É a infraestrutura que sustenta o material —
o que garante que ele diz a verdade, e o que foi construído para hardware que
esta máquina não tem.

Está separado de `scripts/` por uma razão medida. Antes desta divisão, `scripts/`
tinha 39 arquivos e 7792 linhas, e **o que o estudante efetivamente executa era
7% disso**:

| Finalidade | Arquivos | Linhas | Onde ficou |
|---|---:|---:|---|
| AF_XDP | 8 | 3335 | [`ferramental/af-xdp/`](af-xdp/) |
| Verificadores e processo | 12 | 1444 | [`ferramental/qualidade/`](qualidade/) |
| NIC (segurança) | 6 | 716 | `scripts/` — protege a máquina de quem estuda |
| Uso do estudante | 6 | 544 | `scripts/` |

O AF_XDP sozinho era 43% de todo o código de script, para uma capacidade que a
NIC de referência não tem.

## Por que continua versionado, e não ignorado

A proposta inicial era mover para fora do controle de versão. Três motivos
mudaram a decisão, e o primeiro é experiência direta deste repositório:

1. **Um `reset --hard` destruiu horas de trabalho não rastreado.** Colocar 3335
   linhas nesse estado repete a condição exata do acidente.
2. **A CI depende dos verificadores.** Ignorá-los desliga a etapa de consistência
   do `.github/workflows/ci.yml`.
3. **Esconder é a classe de defeito que este projeto combate.** Teste que não
   roda, evidência fora do git, verificação que some sem avisar — o material
   inteiro persegue isso. Ignorar seria o mesmo movimento com outro nome.

O que reduz volumetria é **separar e declarar**, não ocultar. Quem abre
`scripts/` agora vê o que usa; quem abre `ferramental/` sabe, pelo nome do
diretório e por este arquivo, que está olhando para outra coisa.

## Nesta pasta

- **[af-xdp/](af-xdp/)** — diagnóstico e verificação de AF_XDP zero-copy. Não
  executável no hardware de referência; preservado para quando houver placa que
  o suporte. O contexto está em
  [af-xdp-preparacao.md](../trilha/04-projeto-final/af-xdp-preparacao.md).
- **[qualidade/](qualidade/)** — os verificadores que rodam na suíte `l1+docs` e
  o gancho de pré-commit que a CI executa. Registrados no `meson.build` da raiz:
  saem de `scripts/`, não saem da verificação.
