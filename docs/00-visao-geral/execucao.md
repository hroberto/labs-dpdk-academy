# Primeira execução e leitura dos resultados

Este percurso exercita a versão em memória. Use Linux com compilador C/C++23,
DPDK, Meson e Ninja, conforme o [ferramental](ferramental.md). Execute os comandos
na raiz do repositório. A NIC futura não é necessária para este percurso.

## Compilar e verificar

```bash
./scripts/check-env.sh
./scripts/build-all.sh
./scripts/test-all.sh l1
./scripts/test-all.sh l2
```

L1 verifica lógica e ferramentas; L2 integra os executáveis disponíveis sem
preparar hardware. `OK` significa que aquela entrada foi exercitada; `SKIP`
identifica um requisito ausente. `EXPECTEDFAIL` só é esperado nos controles
negativos registrados. Consulte o diagnóstico de qualquer `FAIL` antes de
interpretar medições. Logs ficam em `build/meson-logs/`.

## Executar o pipeline

```bash
./build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring \
  -l 0 --no-huge --no-pci --file-prefix=academia_leitura \
  -- -n 10 -b 8 -t 2000
```

A CPU 0 precisa pertencer à máscara permitida do processo; ajuste `-l` se
necessário. O resultado funcional esperado é 10 pacotes, 695 bytes e todos os
objetos devolvidos ao pool. Dez pacotes não formam uma medição de desempenho.
O parâmetro `-t` limita a espera sem progresso; falha desse prazo encerra o
pipeline após drenar os objetos pendentes.

Para entender a metade de **posse** — quem libera o objeto, e por que liberar o
segundo segmento de uma cadeia é erro — leia
[§2.4 Posse: quem libera](../03-mempool-ring-mbuf/README.md#24-posse-quem-libera).
A metade de **progresso** (o prazo do `-t`, e o que acontece ao estourá-lo) está
descrita no parágrafo acima e **ainda não tem seção própria** no módulo: o link
anterior apontava para uma "§6.4 Política de posse e progresso" que nunca foi
escrita.
Para estudar o mecanismo completo, siga o [tópico prático](../../trilha/01-fundamentos/02-mempool-ring/README.md).

## Ler uma tabela

Comece pelo [controle rastreável do anel](../avaliacoes/evidencias/2026-09-14-controle-anel/tabela.md).
Identifique API, lote, CPUs, número de repetições e unidade. As linhas descrevem
custo amortizado; não são p99 de latência de pacote nem desempenho da NIC.
Use os links da tabela para conferir ambiente, fontes e amostras.

## Avançar no runtime

O [módulo de runtime](../02-runtime-dpdk/README.md#10-quando-dá-errado) descreve
silêncio, validade do livro e reinício de sessão. Seus testes reais L3 exigem
hugetlbfs gravável com páginas livres. Se faltar esse requisito, o SKIP é uma
pendência identificada; os testes de lógica e de supervisor não o substituem.

Continue pela [trilha](../../trilha/README.md) conforme o mecanismo que deseja
investigar. A [política de validação](validacao.md) distingue o que foi escrito,
implementado, testado e medido.

Acompanhe os contratos e pendências na
[matriz de requisitos](../avaliacoes/matriz-requisitos.md). As campanhas que
sustentam comparações quantitativas ficam no
[inventário de dados](../avaliacoes/inventario-dados.md).
