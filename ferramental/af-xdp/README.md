# AF_XDP — diagnóstico preservado

**Nada aqui roda com resultado útil nesta máquina**, e isso é declarado em vez
de descoberto: a NIC de referência (RTL8125, driver `r8169`) anuncia
`xdp_features = 0x00` — zero símbolos `xdp_` no módulo, nenhum modo XDP nativo,
nenhum zero-copy.

São 3335 linhas, 43% de todo o código de script do projeto, para uma capacidade
que o hardware não tem. Foi por isso que saíram de `scripts/`.

## O que continua valendo

Os testes **rodam e passam** na suíte `l1+scripts`, porque exercitam a lógica de
decisão com **fontes controladas** — stubs no PATH, ELFs sintéticos, sysfs
redirecionado — e não dependem de placa. O que eles verificam é o raciocínio:
qual veredito sai de cada resposta do kernel, e que uma coleta que falhou não
vira número.

Essa parte é transferível: a disciplina de distinguir "apurei e a resposta é
não" de "não consegui apurar" nasceu aqui e hoje sustenta os scripts de NIC.

## O que falta para isto ter finalidade prática

Uma placa com XDP nativo — a ConnectX-4 Lx de 25 GbE prevista. Com ela, o
material ganha a terceira comparação do projeto final (DPDK × C++23 × AF_XDP),
hoje declarada fora de escopo em
[af-xdp-preparacao.md](../../trilha/04-projeto-final/af-xdp-preparacao.md).

Até lá, isto é preparação verificada, não resultado.
