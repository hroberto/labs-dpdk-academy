# Primeira execução da intervenção — parcial, e por quê

Esta coleta é de **2026-09-25 00:03**, com a versão inicial de
`ferramental/qualidade/experimento-gfxoff.sh`. Fica arquivada porque a escrita
funcionou e os números são reais, mas ela responde só metade da pergunta.

## O que vale

A escrita de quatro bytes binários no `amdgpu_gfxoff` foi **aceita nos dois
sentidos** — `ok 4 bytes` ao desligar e ao religar. Isso encerra, por execução,
a questão do impedimento: a intervenção existe nesta máquina.

Os três resumos do `osnoise` são válidos como medida. `Max Single`, o maior
evento isolado em 60 s:

| célula | GFXOFF | Max Single | Max Noise |
|---|---|---:|---:|
| a1 | ligado | 574 µs | 1 034 µs |
| b | **desligado** | **104 µs** | 627 µs |
| a3 | ligado | 496 µs | 863 µs |

As duas células ligadas concordam entre si e a desligada fica abaixo das duas.
É **um par**, em sessão gráfica, sem repetição: sinal, não inferência.

## O que não vale, e o defeito que o produziu

A linha `gfx_off no rastro: 0`, impressa para as três células, **não é uma
medição**. `rtla ... -t` só grava o rastro quando a sessão é interrompida por
`-s`, `-S` ou `-a`; o script usava `-T 1`, que é limiar de **contagem**, não de
parada. Nenhum arquivo de rastro foi escrito, e o `grep` sobre arquivo ausente
devolveu zero.

Zero por ausência de arquivo é indistinguível de zero por ausência de evento —
o mesmo defeito que o `l2_run.sh` deste projeto já teve, e pela mesma razão:
um verificador que não distingue "não achei" de "não existe".

A versão corrigida separa as duas perguntas em duas fases, porque uma janela
com limiar de parada termina no primeiro evento grande e não serve de janela
quantitativa. Onde não há rastro, ela imprime `SEM RASTRO`.
