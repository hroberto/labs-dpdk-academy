# Intervenção sobre o GFXOFF — 2026-09-25 00:27

Sessão gráfica **viva**, CPU 2, cinco pares ligado/desligado de 30 s, mais duas
caças ao rastro com limiar de 300 µs e o evento
`workqueue:workqueue_execute_start` habilitado.

## A atribuição, que esta coleta fechou

```
kworker/2:3-446 [002] .....  8044.528193: workqueue_execute_start:
    work struct 000000009d8049fd: function amdgpu_device_delay_enable_gfx_off [amdgpu]
kworker/2:3-446 [002] d..2.  8044.528640: thread_noise: kworker/2:3:446
    start 8044.528192820 duration 446878 ns
```

O ruído de thread **começa no instante em que a função inicia**, no mesmo
`kworker`. Com o GFXOFF desligado, nenhum evento ≥ 300 µs em 120 s.

## Fase 1, e por que ela é mais fraca que a de 00:15

| ciclo | ligado | desligado |
|---:|---:|---:|
| 1 | 310 µs | 22 µs |
| 2 | 482 µs | 25 µs |
| 3 | **38 µs** | 102 µs |
| 4 | **25 µs** | 20 µs |
| 5 | 117 µs | 98 µs |

Três das cinco células ligadas não viram o modo alto. **A célula não falhou; o
evento não aconteceu nela.** A reativação do *power gating* é um evento raro e
grande — o driver só a agenda depois de um período de uso da GPU —, e uma
janela de 30 s sem transição mede outro ruído qualquer.

Daí a consequência de método: **`Max Single` numa janela curta não é uma
grandeza estável**, e comparar medianas entre os braços dilui o efeito com as
janelas em que não havia o que suprimir. O desfecho que corresponde ao
mecanismo é dicotômico — a janela teve, ou não teve, evento da ordem das
centenas de microssegundos.

Note também que o braço desligado desta coleta deu 98 e 102 µs, acima de duas
células ligadas. Publicar só a coleta das 00:15, que deu 3 de 3 com separação
de trinta vezes, seria escolher a coleta que confirma.

## A apuração das duas coletas

```
./ferramental/qualidade/analisar-gfxoff.py \
    trilha/03-performance/03-isolamento-cpu/historico/2026-09-25-0015-gfxoff-intervencao \
    trilha/03-performance/03-isolamento-cpu/historico/2026-09-25-0027-gfxoff-intervencao
```

Oito pares, janela de 30 s:

| medida | valor |
|---|---|
| teste do sinal | 7 de 8 a favor, p = 0,0703 |
| evento ≥ 300 µs, ligado | 5 de 8 |
| evento ≥ 300 µs, desligado | **0 de 8** |
| Fisher exato bilateral | **p = 0,0256** |
| maior observado, ligado | 849 µs |
| maior observado, desligado | 102 µs |
