# Metodologia — Runtime do DPDK

*Read this in [English](metodologia.en.md).*

Este arquivo guarda o **desenho dos experimentos** do módulo 02: o que entra no
cronômetro, o que fica fora, quantas amostras e por quê, e até onde cada
resultado autoriza concluir.

Ele existe pela mesma razão que o [do módulo 01](../01-fundamentos/metodologia.md):
o README precisa ser lido de ponta a ponta, e detalhe de desenho experimental
interrompe a leitura sem que ninguém o procure ali. Separado, ele pode ser
consultado por quem quer contestar um número — que é o leitor que mais importa.

---

## 1. §2 — por que o `custo-init` exige um processo por amostra

O desenho não foi escolhido: **foi imposto pelo objeto de estudo.**

[`rte_eal_init()`][apiealinit] não é reentrante. A segunda chamada no mesmo
processo devolve `EALREADY` sem reinicializar nada. Medir N amostras dentro de
um laço, como o resto do projeto faz, mediria uma inicialização e N−1 retornos
de erro.

Daí a estrutura:

```
  pai      fork() ──► filho: rte_eal_init(), cronometra, rte_eal_cleanup()
                             escreve o resultado num pipe e termina
  pai      lê o pipe, agrega, repete
```

**Cada amostra custa um processo inteiro**, e é isso que limita o número delas a
**11**. Não é escolha estatística: é o que cabe num tempo que alguém aceite
esperar para reproduzir.

### O que fica dentro do cronômetro

Só `rte_eal_init()`. O `fork()`, a criação do pipe, a escrita do resultado e o
`rte_eal_cleanup()` ficam fora — o primeiro porque é custo do instrumento, os
demais porque respondem a outra pergunta, e o módulo publica o encerramento em
linha própria.

### A consequência que o desenho cobra

Onze amostras sustentam mediana e intervalo interquartil. **Não sustentam
percentil alto**, e o módulo não publica nenhum. É a mesma régua da
[§7 dos fundamentos](../01-fundamentos/README.md#7-métricas-o-vocabulário-para-não-se-enganar):
para p99 significar algo, 1% do conjunto precisa ser ao menos uma amostra.

---

## 2. §2.1 — medir e diagnosticar são etapas distintas

Esta é a parte do módulo que mais se perde quando alguém resume o resultado, e
a ordem importa mais que as ferramentas.

| Etapa | Instrumento | O que produziu |
|---|---|---|
| **medir** | [`custo-init.c`](medicoes/custo-init.c) | os 118 ms, com dispersão |
| **localizar** | `strace -T` | *onde* estão 100 desses milissegundos |
| **explicar** | o código-fonte do DPDK | *por que* a espera existe |

**O `strace` não produziu o número publicado.** Ele entrou depois, para
responder uma pergunta que a medição levantou e não podia resolver: um total não
diz onde o tempo foi gasto.

E a escolha do instrumento de localização também foi imposta. Um *profiler* por
amostragem **amostra a CPU**, e processo dormindo não consome CPU — os 100 ms de
espera seriam invisíveis para ele. O `strace` intercepta a **fronteira**, que é
exatamente onde a espera acontece.

> **Por que isso é metodologia e não curiosidade.** Publicar "118 ms, dos quais
> 100 são espera" como se fosse uma medição só esconde que são dois
> experimentos com instrumentos diferentes e graus de confiança diferentes. O
> primeiro tem dispersão publicada; o segundo é uma observação única.

---

## 3. §2.2 — por que 118 ms aqui, e por que isso não é propriedade do DPDK

A calibração de ~100 ms roda porque esta máquina **não expõe `tsc_known_freq`**:

```bash
grep -o 'constant_tsc\|nonstop_tsc\|tsc_known_freq' /proc/cpuinfo | sort -u
```

Sem o sinalizador, a EAL não confia na frequência declarada e a mede — e medir
frequência leva tempo de relógio, não de CPU.

**Numa máquina que exponha o sinalizador, o mesmo `rte_eal_init()` custaria algo
perto de 18 ms.** Os 118 ms são propriedade desta combinação de CPU e kernel, e
o módulo diz isso na própria seção.

É por isso que o programa aceita as opções da EAL diretamente: medir na sua
máquina é parte do exercício, não uma sugestão de cortesia.

---

## 4. §4.6 — a resolução do instrumento, e por que ela é publicada

A travessia entre processos é medida com o produtor carimbando cada tick com
`rte_rdtsc()` e o consumidor lendo. O instrumento tem um piso:

```
  instrument resolution: 11.9 ns (one consumer poll)
```

**Nenhum valor abaixo disso significa alguma coisa.** O consumidor só observa o
tick quando sonda; o intervalo entre sondagens é a granularidade do que ele
consegue distinguir.

Publicar a resolução ao lado do resultado é o que impede a leitura errada mais
provável: tratar uma diferença de 5 ns entre duas configurações como efeito,
quando ela está abaixo do que o instrumento resolve.

---

## 5. Ameaças à validade

Três perguntas diferentes, e confundi-las é o que transforma medição em
folclore.

**Validade interna — o experimento isolou o que pretendia?**

O `custo-init` isola bem: um processo por amostra elimina interferência de
estado acumulado, e o intervalo cronometrado contém só a chamada medida. O
experimento multiprocesso é mais frágil — produtor e consumidor rodam no **mesmo
domínio de cache L3**, e a
[§4.3 dos fundamentos](../01-fundamentos/README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só)
mede que atravessar domínios custa quatro vezes mais. O número publicado é o
caso favorável.

**Validade externa — até onde generaliza?**

Os 118 ms **não generalizam**, e a §2.2 explica o mecanismo. O que generaliza é
a forma do argumento: a EAL paga calibração quando o kernel não declara a
frequência do TSC, e isso é verificável em qualquer máquina com um `grep`.

A máquina tem **um único nó NUMA** e **nenhuma NIC entregue ao VFIO**. Tudo o
que o módulo diz sobre `socket_id` e sobre o caminho de dados é arquitetura
derivada da documentação, não medição.

**Validade de construção — a métrica representa o fenômeno?**

Aqui está a ressalva mais fácil de perder. "Custo de inicializar a EAL" é tempo
de **relógio**, não de CPU — e a maior parte dele é espera, não trabalho. Num
sistema que inicialize várias instâncias em paralelo, esse tempo **se
sobrepõe**; tratá-lo como custo de CPU levaria a dimensionar errado.

---

## Navegação

- Módulo: [Runtime do DPDK](README.md)
- Metodologia do módulo anterior: [Fundamentos](../01-fundamentos/metodologia.md)

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
