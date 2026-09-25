# Intervenção sobre o GFXOFF — 2026-09-25 00:15

Sessão gráfica **viva** (condição do experimento), CPU 2, três pares
ligado/desligado de 30 s, mais duas caças ao rastro com limiar de 300 µs.

## Fase 1 — o resultado quantitativo

`Max Single`, o maior evento isolado de ruído na janela:

| ciclo | GFXOFF ligado | GFXOFF desligado |
|---:|---:|---:|
| 1 | 762 µs | **26 µs** |
| 2 | 849 µs | **25 µs** |
| 3 | 586 µs | **24 µs** |

Medianas: 762 µs contra 25 µs. Três pares de três favorecem o desligado, e a
separação é de aproximadamente trinta vezes — não há sobreposição entre os dois
conjuntos.

O desenho é A-B-A repetido: cada janela desligada tem uma ligada imediatamente
antes e outra depois, de modo que deriva térmica ou de carga atingiria os dois
braços no mesmo intervalo. As três janelas ligadas concordam entre si
(586–849 µs) e as três desligadas também (24–26 µs).

## Fase 2 — a atribuição, que ficou pela metade

| estado | desfecho |
|---|---|
| ligado | rastro gravado; **`kworker/2:3`, 696 606 ns**, função não nomeada |
| desligado | **sem rastro**: nenhum evento ≥ 300 µs em 120 s |

O lado desligado é informativo por si: em dois minutos de sessão gráfica ativa,
nenhuma parada atingiu o limiar. Isso é consistente com a fase 1 e com a
hipótese.

O lado ligado capturou o evento — um `kworker` ocupando a CPU por 697 µs, que é
a assinatura descrita na §6.6.5 — mas **não nomeou a função**. O `rtla` habilita
apenas os próprios eventos (`irq_noise`, `softirq_noise`, `thread_noise`,
`sample_threshold`); o nome vive em `workqueue:workqueue_execute_start`, que
precisa ser pedido com `-e`. Em 31 127 linhas de rastro há zero ocorrências de
`gfx`, e isso mede a ausência do evento, não a ausência da função.

O script corrigido pede o evento. Esta coleta fica como está: a fase 1 é válida
e a fase 2 é parcial.

## Um erro de relatório, nesta execução

O resumo impresso anunciou `n=4` por braço. São **três**. O `glob` de
`osnoise-c*-ligado.txt` casou também `osnoise-caca-ligado.txt`, que é uma janela
interrompida no primeiro evento grande e não é comparável com uma janela de
30 s. Os valores extras — 209 µs no ligado e 100 µs no desligado — vêm das
caças. As três colunas da tabela acima são as janelas legítimas.

## O que isto sustenta, e o que não

Sustenta que **desligar o GFXOFF elimina o modo alto com a sessão gráfica
mantida**. Isso separa a atribuição "GPU" da atribuição "sessão gráfica", que
era a pergunta em aberto da §6.7, e o faz por intervenção e não por associação.

Não sustenta ainda que a função seja `amdgpu_device_delay_enable_gfx_off`. A
associação foi medida antes; a intervenção mostra o efeito; a costura entre as
duas depende da captura com o evento de workqueue.
