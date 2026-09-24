# Scripts — qual usar, e quando

Este diretório tem dezoito scripts, e a maior parte de quem clona o projeto
precisa de **quatro**. Esta página existe porque a lista alfabética não
distingue o que se usa no primeiro dia do que se usa ao reproduzir uma campanha
inteira — e porque descobrir isso lendo dezoito cabeçalhos é um custo que
nenhum deles justifica.

## Primeiro dia: a máquina serve?

```bash
./scripts/check-env.sh      # o que falta, e como instalar
./scripts/build-all.sh      # compila tudo
./scripts/test-all.sh l1    # testes que não pedem privilégio
./scripts/test-all.sh l2    # testes que rodam os programas de verdade
```

`check-env.sh` não altera nada: ele diz o que falta. Se apontar hugepages,
`preparar-hugepages.sh` monta um `hugetlbfs` próprio do seu usuário e **desfaz
com `--desfazer`** — nada permanente é alterado no sistema.

## Medir o seu ambiente

A campanha é uma só, e ela pede que você declare **em que condição** mediu:

```bash
# máquina de trabalho, com sessão gráfica
sudo ./ferramental/qualidade/campanha.sh --grafico  <nome-da-configuracao>

# servidor ou console, sem sessão gráfica
sudo ./ferramental/qualidade/campanha.sh --texto    <nome-da-configuracao>
```

O modo não tem padrão de propósito. Os dois medem bem coisas diferentes:

| | relógio | jitter | use para |
|---|---|---|---|
| `--grafico` | estável, alto | maior | medianas, médias, razões |
| `--texto` | parte frio e sobe | menor | dispersão, p99, cauda, máximo |

O nome da configuração vira o nome da coleta nos quatro históricos, com hora e
minuto acrescentados. A §7 da
[metodologia dos fundamentos](../docs/01-fundamentos/metodologia.md) explica
por que a condição precisa ser declarada em vez de herdada.

Para comparar duas coletas:

```bash
./ferramental/qualidade/comparar-hardware.py \
   docs/01-fundamentos/medicoes/historico/<uma> \
   docs/01-fundamentos/medicoes/historico/<outra>
```

## O resto, por função

**Ambiente** — três scripts, três perguntas diferentes:

| script | responde |
|---|---|
| `check-env.sh` | o que falta para rodar? |
| `ambiente.sh` | em que máquina isto rodou? (grava a procedência da coleta) |
| `ambiente-medicao.sh` | esta medição é reprodutível? (governor, C-states, turbo) |

**Preparação** — `preparar-hugepages.sh` (hugetlbfs do usuário),
`preparar-dpdk.sh` (constrói um DPDK num prefixo próprio, com ou sem
estatísticas de mempool), `preparar-nic.sh` e `diagnostico-nic.sh` (placa de
rede fora do kernel).

**Campanhas específicas** — `campanha.sh` chama estas; você só as invoca
diretamente ao reproduzir um tópico isolado:
`campanha-hardware.sh`, `campanha-isolamento.sh`, `campanha-mempool-cache.sh`,
`campanha-mempool-tempo.sh`. O `roteiro-fatorial-memoria.sh` encadeia quatro
configurações de memória e serve de exemplo de protocolo versionado.

**Bibliotecas** — `lib-*.sh` não são executáveis por conta própria; outros
scripts as carregam.

**Ferramentas de análise** — `variacao-entre-execucoes.py` mede quanto um
número muda entre execuções do mesmo binário; `bench-ccd.sh` e
`validar-cpp-vs-c.sh` atendem tópicos específicos da trilha.

## O portão de qualidade

`ferramental/qualidade/pre-commit.sh` roda os dezoito verificadores e é
para quem **edita** o material, não para quem o executa. O
[README do ferramental](../ferramental/qualidade/README.md) descreve cada um.
