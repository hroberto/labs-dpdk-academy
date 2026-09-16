# Submódulo 01 — Benchmarking

> **Nível 8** do [plano de estudo](../../../docs/plano-estudo-dpdk.md) ·
> Pré-requisito: [02 — Batching e contrapressão](../../02-pipeline/02-batching-backpressure/)

> **In English.** What the "no fixed CPU frequency, no isolated cores" caveat
> actually costs, measured instead of assumed. Twelve runs starting anywhere
> between **0.61 and 5.62 GHz** — a 9× spread — produced 0.714 to 0.747 ns per
> function call: **4.6% amplitude**. The measurement loop drives the core to its
> ceiling in microseconds and the median absorbs the rest. What *does* cost is
> the **first run after a long idle**: 0.926, 0.927 and 0.930 ns in three
> independent observations, about **30% high** on the shortest operation. So
> pinning the governor helps little; **discarding the first run helps a lot** —
> the opposite of what the caveat suggests. `scripts/ambiente-medicao.sh` records
> the environment and changes nothing. The mechanism behind the 30% was not
> isolated; the effect was.

Medir é fácil. Medir de um jeito que outra pessoa consiga repetir, e chegar ao
mesmo número, é o que este submódulo trata.

## 1. Fundamento: o que uma ressalva metodológica confessa

Cinco documentos deste projeto publicam tempos carregando alguma forma da mesma
frase:

> *"melhor de três por ponto, com aquecimento nos dois lados, mas **sem fixar a
> frequência da CPU** e sem isolar núcleos — por isso os programas imprimem a
> frequência junto do tempo. Serve para ordem de grandeza e para a razão entre
> as abordagens, que é o que esta seção afirma."*
> — [Alternativa em C++23](../../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md)

A ressalva é honesta e é **vaga**. Ela diz que algo não foi controlado, e não
diz o que estava valendo na hora. Um número publicado sem o ambiente em que saiu
não é reprodutível, porque quem for repetir não sabe contra o quê comparar.

O entregável central deste submódulo é trocar essa frase por um **registro**: o
que estava fixo, o que estava variando, e quanto isso custa em dispersão.

## 2. Mecanismo: de onde vem a variação

Quatro fontes, em ordem decrescente de fama e crescente de importância real
nesta máquina:

**Escalonamento de frequência.** O núcleo muda de clock conforme a carga. Esta
máquina usa `amd-pstate-epp` com governor `powersave` e boost ligado, e vai de
**0,61 GHz a 5,66 GHz — faixa de 9,2×**. É a fonte que todo mundo cita primeiro.

**Estados de baixo consumo (C-states).** Um núcleo ocioso desce para um estado
profundo, e sair dele custa. Diferente da frequência, esse custo é pago **uma
vez**, no início, e não se repete.

**Concorrência por núcleo.** Sem `isolcpus`, o escalonador do kernel pode pôr
outra tarefa no mesmo núcleo no meio da medição. Esta máquina não isola nada:
`/sys/devices/system/cpu/isolated` está vazio.

**SMT.** Duas CPUs lógicas dividem as unidades de execução de um núcleo físico.
Com SMT ligado — como aqui —, a vizinha influencia o resultado.

## 3. Trade-offs: fixar custa, e nem sempre paga

Fixar o governor em `performance` deixa a máquina mais quente e mais gulosa o
tempo todo, para uma medição que dura segundos. Isolar núcleos exige reiniciar
com parâmetros na linha de comando do kernel, e tira esses núcleos do uso normal
da máquina. Desligar SMT reduz pela metade as CPUs lógicas disponíveis.

São custos reais, e a pergunta certa não é *"o ambiente está rigoroso?"* — é
**"quanto a falta de rigor está cobrando neste número?"**. Essa é uma pergunta
empírica, e a seção 6 a responde com medição.

## 4. Implementação

[`scripts/ambiente-medicao.sh`](../../../scripts/ambiente-medicao.sh) apura o
ambiente e **não altera nada**:

```bash
./scripts/ambiente-medicao.sh              # relatório legível
./scripts/ambiente-medicao.sh --uma-linha  # carimbo, ao lado da medição
```

O modo `--uma-linha` existe para ser gravado junto do número:

```
driver=amd-pstate-epp governor=powersave governors=performance,powersave
freq_min=613954 freq_max=5662016 boost=1 faixa=9,2x_0,61-5,66GHz
isolados=vazio nohz_full=vazio smt=on aslr=2 nmi_watchdog=1 carga=0.62
```

Três decisões de projeto valem ser ditas:

**Ele apura, não corrige.** Alterar a máquina de quem estuda a partir de um
script de diagnóstico é a mesma classe de erro que fazia `preparar-nic.sh`
derrubar uma interface no meio da verificação. Os comandos de correção são
impressos; quem opera a máquina decide.

**Tri-estado, como o resto do projeto.** Cada item sai apurado com valor, ou
**não apurado com o motivo**. "Não consegui ler o governor" nunca vira "governor
ausente", que viraria "sem escalonamento de frequência" — falso e
tranquilizador, a pior combinação. Se algum item não for apurado, o script sai
com código 1: registro de ambiente incompleto é número sem procedência.

**As chaves do carimbo não têm espaço.** `governors=performance,powersave`, e
não `governors=performance powersave`. A linha existe para ser lida por programa
depois, e um valor com espaço quebra qualquer leitor que separe por branco — em
silêncio.

## 5. Validação

```bash
./scripts/ambiente-medicao.sh                      # o seu ambiente
./scripts/ambiente-medicao.sh --uma-linha; echo $?  # 0 = apurou tudo
```

Para reproduzir o experimento da seção 6 na sua máquina:

```bash
B=build/docs/01-fundamentos/medicoes/custo-syscall
for i in $(seq 12); do
  printf '%s ' "$(awk '{printf "%.2f", $1/1e6}' \
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
  $B | awk '/chamada de funcao/{print $5}'
done
```

A primeira coluna é o clock no instante em que o processo começou; a segunda, o
resultado. Compare a dispersão de uma com a da outra.

## 6. Quando dá errado — e a intuição erra primeiro

O experimento tem uma pergunta só: **quanto a frequência livre cobra?**

Doze execuções de `custo-syscall`, com a frequência no instante de partida
variando entre **0,61 e 5,62 GHz**:

| Frequência ao iniciar | ns por chamada de função |
|---|---|
| 4,58 GHz | 0,725 |
| 5,60 GHz | 0,714 |
| 4,75 GHz | 0,745 |
| 4,38 GHz | 0,745 |
| 4,63 GHz | 0,747 |
| **0,61 GHz** | 0,724 |
| 5,61 GHz | 0,746 |
| 5,61 GHz | 0,714 |
| 3,18 GHz | 0,746 |
| 5,62 GHz | 0,720 |
| 5,60 GHz | 0,716 |
| 2,95 GHz | 0,746 |

**Variação de 9× no clock de partida produziu 4,6% de amplitude no resultado**
(0,714 a 0,747 ns). A execução que começou a 0,61 GHz — o fundo da escala —
mediu 0,724, dentro da faixa das que começaram acima de 5 GHz.

A razão é mecânica: o laço de medição são 2 000 000 de iterações por amostra,
25 amostras. O núcleo chega ao teto em microssegundos, e a mediana absorve o
resto. **A frequência de partida quase não sobrevive ao próprio experimento.**

### O que cobra caro é outra coisa

A **primeira execução depois de ociosidade prolongada** mediu, em três
observações independentes:

| Observação | 1ª execução | execuções seguintes | excesso |
|---|---|---|---|
| série de 12 | 0,926 ns | 0,713 – 0,750 | **29,9%** |
| série de 6 | 0,927 ns | 0,716 – 0,748 | **29,5%** |
| execução isolada | 0,930 ns | 0,715 | **30,1%** |

Trinta por cento, na operação mais curta do conjunto — e **reprodutível**.

A consequência inverte a intuição da ressalva: para estes programas, **fixar o
governor ajuda pouco; descartar a primeira execução após ociosidade ajuda
muito**. Quem gastasse a tarde configurando `isolcpus` e `performance` sem
descartar a primeira execução continuaria publicando um número 30% alto.

### O erro de método que quase entrou aqui

O primeiro teste de controle desta seção foi inválido, e vale registrar porque é
a armadilha natural do experimento. Rodei uma série, analisei, e rodei outra
"logo em seguida" para comparar — mas entre as duas houve dezenas de segundos de
análise, tempo suficiente para o núcleo voltar a ociar. As duas séries eram
"primeira execução após ociosidade", e a conclusão de que o efeito era por
processo estava errada.

O controle válido roda os lotes **dentro da mesma invocação**, sem intervalo. Foi
o que produziu a tabela de doze linhas acima, e foi ele que refutou a hipótese da
frequência.

## 7. Limitações

**O mecanismo do excesso de 30% não foi isolado.** Saída de C-state profundo e
páginas fora do cache são os candidatos; distinguir os dois exige `perf` com
contadores de C-state, que este submódulo ainda não faz. O que está estabelecido
é o **efeito**, medido três vezes, não a causa.

**Uma máquina só.** Todos os números são de um Ryzen 9 9900X com
`amd-pstate-epp`. Um Intel com `intel_pstate`, ou uma máquina virtual sem
controle de frequência, pode ter proporções diferentes — inclusive inverter a
conclusão. O script existe justamente para você medir a sua.

**Um programa só.** `custo-syscall` mede operações de 0,7 a 33 ns. O efeito de
30% aparece na mais curta e some nas mais longas; para trabalho da ordem de
milissegundos, provavelmente é irrelevante. A conclusão vale para a faixa medida.

**Isolamento de núcleo não foi testado.** Esta máquina não tem `isolcpus`, e
conferir o ganho exigiria reiniciar. A afirmação "isolar ajuda" continua sendo
teoria neste documento — e por isso não aparece como número.

**`google-benchmark` ainda não entrou.** A [Etapa 5 do ROADMAP](../../../ROADMAP.md)
prevê a suíte formal; o que existe hoje é `statistics.h`, com mediana, IQR,
amplitude e coeficiente de variação por ponto.

## 8. Para onde ir daqui

| | |
|---|---|
| **Anterior** | [03 — Performance e observabilidade](../) |
| **Próximo** | [02 — Observabilidade](../02-observabilidade/) |
| **Ferramenta** | [`scripts/ambiente-medicao.sh`](../../../scripts/ambiente-medicao.sh) |
| **Base** | [`docs/01-fundamentos/medicoes/statistics.h`](../../../docs/01-fundamentos/medicoes/statistics.h) |
