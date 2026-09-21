/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Estatística mínima para microbenchmarks.
 *
 * POR QUE ISTO EXISTE
 *
 * Publicar um número solto ("8,4 ns") esconde a pergunta que importa: quão
 * confiável ele é? Uma medição de 8,4 com dispersão de 0,1 e outra de 8,4 com
 * dispersão de 6,0 sustentam conclusões muito diferentes, e o leitor não tem
 * como distinguir se só lhe damos a média.
 *
 * O QUE REPORTAMOS
 *
 *   mediana  - tendencia central robusta; estima o custo observado na pratica.
 *   minimo   - estima o custo real da operacao; o ruido e unilateral.
 *   p25-p75  - intervalo interquartil, de onde sai o selo.
 *   amplitude- min-max, a faixa completa observada.
 *   CV       - desvio padrao / media; DETECTOR de excursao, nao medida de
 *              confianca.
 *
 * A justificativa de cada escolha -- por que o minimo estima o custo real, por
 * que a media nao entra, por que a amplitude e publicada apesar de fragil, e
 * por que nao ha marcador binario de excursao -- esta no README.md secao 9.2
 * "Por que estes estimadores, e o que eles nao sao".
 *
 * QUANTAS AMOSTRAS O SELO EXIGE PARA SIGNIFICAR ALGO
 *
 * Isto foi medido, em 18/09/2026, e o resultado desqualifica leituras do selo
 * feitas com poucas amostras.
 *
 * Coletando 70 amostras de um mesmo ponto da fase 2 do `custo-paralelismo` e
 * recalculando `disp` em dez grupos DISJUNTOS de sete — com a função
 * `percentil()` abaixo, a de verdade, interpolada —, o ponto de 2 núcleos
 * produziu selo EM BRANCO cinco vezes, `~` três e `!` duas. A dispersão
 * verdadeira daquele ponto, com as 70 amostras, é 4,4%: `~`. E o ponto de 4
 * núcleos, cuja dispersão verdadeira é 10,4% e portanto MERECE `!`, não marcou
 * `!` em nenhum dos dez grupos.
 *
 * O selo erra nas duas direções com n = 7, e a razão é aritmética: o p25 sai
 * interpolado entre a 2ª e a 3ª amostra e o p75 entre a 5ª e a 6ª. Mover uma
 * única amostra desloca os dois. O IQR é robusto contra CAUDA, não contra
 * TAMANHO DE AMOSTRA.
 *
 * Consequência prática, e ela é assimétrica:
 *
 *   disp < 3% ou disp > 15%  -> o selo é confiável mesmo com n pequeno; a
 *                               medição está longe do limiar.
 *   3% <= disp <= 15%        -> o selo é uma loteria abaixo de ~20 amostras.
 *                               Aumente n antes de explicar o fenômeno.
 *
 * Por isso `custo-paralelismo` usa 21 amostras na fase 2 e 7 na fase 1: a fase 1
 * tem dispersão baixa e fica fora da faixa perigosa; a fase 2 cai dentro dela.
 *
 * MAS n É SÓ UMA DIMENSÃO DO PROBLEMA, e isto foi aprendido depois, em
 * 19/09/2026. São duas causas diferentes, e aumentar n só ataca a primeira:
 *
 *   PROBLEMA ESTATÍSTICO -- poucos pontos dão baixa resolução aos quartis. O
 *   p25 sai interpolado entre a 2ª e a 3ª amostra e o p75 entre a 5ª e a 6ª;
 *   mover uma amostra desloca os dois. Mais amostras resolvem.
 *
 *   PROBLEMA EXPERIMENTAL -- a coleta compara duas condições em MOMENTOS
 *   diferentes, e frequência, temperatura e carga da máquina se confundem com
 *   o efeito. Mais amostras NÃO resolvem: em blocos separados, elas apenas dão
 *   mais tempo para a máquina mudar de estado entre A e B. O que resolve é
 *   INTERCALAR (ver `collect_paired`) e acomodar a frequência antes de coletar.
 *
 * A prova de que são causas distintas: subir de 15 para 21 amostras piorou o
 * selo de duas linhas do `custo-comunicacao`; intercalar as mesmas medições, no
 * mesmo n, devolveu as duas a selo limpo.
 *
 * A escolha do número de amostras não é orçamento de tempo — mas o DESENHO da
 * coleta decide antes dela.
 *
 * Deliberadamente não há marcador binário para outlier. Um limiar do tipo
 * "máximo > 1,25x a mediana" produz um penhasco arbitrário: duas linhas com
 * excursão praticamente igual (1,246x e 1,264x) receberiam selos opostos por
 * uma diferença de 1,4%. Exibir os dois números e ensinar a lê-los juntos é
 * mais honesto que esconder a continuidade atrás de um limiar.
 *
 * O QUE ISTO NAO E
 *
 * Nao e analise estatistica rigorosa: nao ha intervalo de confianca formal nem
 * teste de hipotese, e a omissao e deliberada. Ver README.md secao 9.2 "Por que
 * estes estimadores, e o que eles nao sao".
 */
#ifndef DPDK_ACADEMY_STATISTICS_H
#define DPDK_ACADEMY_STATISTICS_H

/* Compartilhado entre custo-espera.c e custo-espera-cpp.cpp: a comparação entre
 * as duas linguagens só vale se a metodologia de coleta for literalmente a
 * mesma, e não apenas equivalente. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <time.h>

/* Nem todo programa usa todas as variantes de impressão. */
#if defined(__GNUC__)
#define STAT_MAYBE_UNUSED __attribute__((unused))
#else
#define STAT_MAYBE_UNUSED
#endif

/* Número de amostras. Pode ser reduzido pela variável de ambiente
 * DPDK_ACADEMY_AMOSTRAS, para que a integração contínua verifique que os
 * programas EXECUTAM sem gastar minutos coletando estatística que ninguém vai
 * ler. Medição de verdade usa o padrão. */
#define DEFAULT_SAMPLES_FIXED 25
/* Limiares sobre a dispersão ROBUSTA (IQR/mediana), não sobre o CV. */
#define DISP_ESTAVEL 3.0
#define DISP_SUSPEITA 10.0


struct statistics {
    double median;
    double minimum;
    double maximum;
    double p25, p75;
    double p99;   /* cauda: só é significativo com amostras suficientes */
    double cv;    /* coeficiente de variação, em % — sensível a outliers */
    double disp;  /* dispersão robusta: (p75-p25)/mediana, em % */
    int samples;
};

/* Devolve quantas amostras usar. Medições caras declaram um padrão menor; a
 * variável de ambiente, quando presente, é um TETO aplicado a todas. */
static STAT_MAYBE_UNUSED int samples(int padrao)
{
    const char *e = getenv("DPDK_ACADEMY_AMOSTRAS");
    if (e == NULL)
        return padrao;
    const int n = atoi(e);
    const int teto = n >= 3 ? n : 3; /* menos de 3 não permite quartis úteis */
    return padrao < teto ? padrao : teto;
}

#define DEFAULT_SAMPLES samples(DEFAULT_SAMPLES_FIXED)

/* Teto de RODADAS por amostra, análogo ao de amostras acima.
 *
 * POR QUE EXISTE: reduzir amostras não basta em máquina lenta. `custo-espera`
 * mede repasse entre threads -- condvar e semáforo passam pelo futex e por
 * troca de contexto --, e num runner de CI de 2 núcleos isso é uma ordem de
 * grandeza mais caro que na máquina de referência de 24. A primeira execução
 * da CI estourou o limite de 300 s com `DPDK_ACADEMY_AMOSTRAS=3` já aplicado:
 * o custo estava nas 200 000 rodadas POR amostra, que a variável não tocava.
 *
 * Só faz sentido como TETO, nunca como padrão: baixar rodadas piora a
 * resolução da medida, então quem quer número publicável não define a variável.
 * Na CI, onde o objetivo é apenas verificar que o programa executa, define. */
static STAT_MAYBE_UNUSED int rounds(int padrao)
{
    const char *e = getenv("DPDK_ACADEMY_RODADAS");
    if (e == NULL)
        return padrao;
    const int n = atoi(e);
    const int teto = n >= 1000 ? n : 1000; /* abaixo disso o relógio domina */
    return padrao < teto ? padrao : teto;
}

static int cmp_double(const void *a, const void *b)
{
    const double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

/* Percentil por interpolação linear sobre o vetor JÁ ORDENADO. */
static STAT_MAYBE_UNUSED double percentil(const double *v, int n, double p)
{
    if (n == 1)
        return v[0];
    const double pos = p * (n - 1);
    const int i = (int)pos;
    const double frac = pos - i;
    return i + 1 < n ? v[i] + frac * (v[i + 1] - v[i]) : v[n - 1];
}

/* Resume um vetor de amostras JÁ coletadas. ORDENA `v` no lugar.
 *
 * Existe separado de collect() porque nem toda medição cabe no formato "chame
 * esta função n vezes": travessia entre processos, por exemplo, produz uma
 * amostra por mensagem recebida, e o vetor já chega pronto. */
static STAT_MAYBE_UNUSED struct statistics summarize(double *v, int n)
{
    struct statistics e = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    if (v == NULL || n <= 0)
        return e;

    double soma = 0;
    for (int i = 0; i < n; i++)
        soma += v[i];
    const double media = soma / n;

    double var = 0;
    for (int i = 0; i < n; i++)
        var += (v[i] - media) * (v[i] - media);
    var /= (n > 1 ? n - 1 : 1); /* variância amostral */

    qsort(v, (size_t)n, sizeof(double), cmp_double);
    e.samples = n;
    e.minimum = v[0];
    e.maximum = v[n - 1];
    e.median = percentil(v, n, 0.50);
    e.p25 = percentil(v, n, 0.25);
    e.p75 = percentil(v, n, 0.75);
    e.p99 = percentil(v, n, 0.99);
    e.cv = media > 0 ? 100.0 * sqrt(var) / media : 0.0;
    e.disp = e.median > 0 ? 100.0 * (e.p75 - e.p25) / e.median : 0.0;

    return e;
}

/* Executa `medicao` n vezes e resume as amostras. */
static STAT_MAYBE_UNUSED struct statistics collect(double (*measurement)(void), int n)
{
    /* Cast explícito: este cabeçalho é compartilhado com a versão em C++, onde
     * a conversão implícita de void* não é permitida. */
    double *v = (double *)malloc((size_t)n * sizeof(double));
    struct statistics e = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    if (v == NULL)
        return e;

    for (int i = 0; i < n; i++)
        v[i] = measurement();

    e = summarize(v, n);
    free(v);
    return e;
}

/* ===================== Coleta PAREADA de duas medições =====================
 *
 * POR QUE ISTO EXISTE, e é um defeito real que ficou oito dias no ar.
 *
 * `custo-traducao.c` publicava "a diferença é 18,2 ns" subtraindo duas
 * medianas colhidas em BLOCOS SEPARADOS: 21 amostras de 4 KB, depois 21 de
 * 2 MB. Duas coisas dão errado nesse arranjo.
 *
 * A primeira é deriva. Entre o fim de um bloco e o fim do outro passam minutos,
 * e frequência, temperatura e carga da máquina mudam nesse intervalo. A
 * diferença entre as duas medianas absorve essa deriva inteira.
 *
 * A segunda é mais sutil e mais importante: **a dispersão da diferença não se
 * deduz das dispersões das duas medianas**. Duas medições com `disp` de 1% cada
 * podem produzir uma diferença com dispersão de 30%, se elas oscilarem juntas
 * ou em oposição. Publicar `disp` das duas parcelas e nenhum indicador da
 * diferença é publicar confiança que não foi medida -- e a diferença é
 * justamente a conclusão que o documento tira.
 *
 * A correção é INTERCALAR e PAREAR: na mesma volta do laço mede-se A e depois
 * B, guarda-se `delta_i = a_i - b_i` e `razao_i = a_i / b_i`, e resume-se cada
 * um dos quatro vetores. A deriva lenta cancela no par, e a diferença passa a
 * ter selo próprio.
 *
 * Vale para toda conclusão que é uma DIFERENÇA ou uma RAZÃO entre medições:
 * o custo do page walk, a penalidade de travessia entre domínios, o custo do
 * SMT. Nenhuma delas herda a estabilidade das parcelas. */
struct paired_stats {
    struct statistics a, b, delta, razao;
    int n;             /* pares coletados */
    int mesmo_sinal;   /* em quantos deles a diferença teve o sinal da mediana */
};

static STAT_MAYBE_UNUSED struct paired_stats
collect_paired(double (*ma)(void), double (*mb)(void), int n)
{
    /* O cppcheck acusa `memsetClassFloat` aqui: zerar bytes de um `double` so
     * equivale a 0.0 em IEEE-754, e a linguagem nao promete isso. A ressalva e
     * correta em geral e nao se aplica a este material, que declara a maquina
     * de medicao e nao roda em outra.
     *
     * A alternativa obvia -- `= {0}` -- foi tentada e e PIOR aqui: este
     * cabecalho tambem compila como C++, onde ela dispara dez
     * -Wmissing-field-initializers, e a barra do projeto e zero aviso. Trocar
     * uma nota de analisador por dez avisos de compilador nao e conserto. */
    struct paired_stats p;
    /* cppcheck-suppress memsetClassFloat */
    memset(&p, 0, sizeof p);

    double *va = (double *)malloc((size_t)n * sizeof(double));
    double *vb = (double *)malloc((size_t)n * sizeof(double));
    double *vd = (double *)malloc((size_t)n * sizeof(double));
    double *vr = (double *)malloc((size_t)n * sizeof(double));
    if (va == NULL || vb == NULL || vd == NULL || vr == NULL) {
        free(va); free(vb); free(vd); free(vr);
        return p;
    }

    for (int i = 0; i < n; i++) {
        va[i] = ma();
        vb[i] = mb();               /* na MESMA volta: é isto que pareia */
        vd[i] = va[i] - vb[i];
        vr[i] = vb[i] > 0.0 ? va[i] / vb[i] : 0.0;
    }

    p.a = summarize(va, n);
    p.b = summarize(vb, n);
    p.razao = summarize(vr, n);

    /* CONTA O SINAL ANTES DE RESUMIR: `summarize` ordena no lugar, e depois
     * dela a ordem original se perde -- mas o que interessa aqui é quantos
     * pares concordam, não em que ordem. */
    p.n = n;
    p.mesmo_sinal = 0;
    p.delta = summarize(vd, n);
    for (int i = 0; i < n; i++)
        if ((vd[i] > 0.0) == (p.delta.median > 0.0))
            p.mesmo_sinal++;

    free(va); free(vb); free(vd); free(vr);
    return p;
}

/* O selo avisa QUEM LÊ a tabela. Estas três funções avisam a SUÍTE, que não lê
 * tabela nenhuma -- ela lê o código de saída.
 *
 * A distinção é o ponto. As funções de medição deste projeto devolvem valor
 * negativo quando a operação medida falha -- um `rte_mempool_get()` que não
 * entrega objeto, por exemplo. `collect()` grava esse negativo no vetor como se
 * fosse tempo, `summarize()` tira mediana em cima dele, e o programa imprimia a
 * tabela e saía com 0. O selo "?" denunciava a linha para quem lesse; o código
 * de saída dizia OK para quem não lê.
 *
 * É a mesma regra que fez `l3_multiprocesso.sh` trocar `exit 0` por `exit 77`:
 * o que não foi verificado não pode ser reportado como verificado.
 *
 * BELOW_RESOLUTION existe separado de INVALID porque mediana zero não é
 * sentinela de erro: é operação mais rápida que a resolução do relógio. Não é
 * publicável como custo, e não é defeito. Os callbacks devem devolver negativo
 * ou NaN em falha, nunca zero. */
enum collection_state { COLLECTION_INVALID, COLLECTION_BELOW_RESOLUTION, COLLECTION_VALID };

static STAT_MAYBE_UNUSED enum collection_state collection_state(struct statistics e, int n)
{
    if (n <= 0 || e.samples != n || !isfinite(e.median) || !isfinite(e.minimum) ||
        !isfinite(e.maximum) || !isfinite(e.p25) || !isfinite(e.p75) ||
        !isfinite(e.p99) || !isfinite(e.cv) || !isfinite(e.disp) || e.minimum < 0)
        return COLLECTION_INVALID;
    return e.median > 0 ? COLLECTION_VALID : COLLECTION_BELOW_RESOLUTION;
}

static STAT_MAYBE_UNUSED int collection_is_valid(struct statistics e, int n)
{
    return collection_state(e, n) == COLLECTION_VALID;
}

/* Adaptador para os programas SEM EAL: falha encerra o processo antes de
 * publicar. Quem tem runtime de pé (EAL, threads, pools) não pode usar este --
 * precisa de `collect` + `collection_is_valid` e da própria limpeza, porque
 * `exit()` aqui pularia `rte_eal_cleanup()`. */
static STAT_MAYBE_UNUSED struct statistics collect_or_fail(double (*measurement)(void), int n)
{
    struct statistics e = collect(measurement, n);
    if (!collection_is_valid(e, n)) {
        fprintf(stderr, "COLETA INVALIDA OU ABAIXO DA RESOLUCAO:"
                        " sem resultado publicavel\n");
        exit(EXIT_FAILURE);
    }
    return e;
}

/* Marca visual da DISPERSÃO OBSERVADA NESTA COLETA.
 *
 *   " "  dispersão baixa nesta coleta
 *   "~"  dispersão moderada nesta coleta
 *   "!"  dispersão alta nesta coleta
 *   "?"  NÃO HOUVE MEDIÇÃO — ver abaixo
 *
 * A SEMÂNTICA MUDOU EM 19/09/2026, e a mudança é uma retratação.
 *
 * Antes estes selos eram descritos como "marca de confiança": " " significava
 * "o valor típico é confiável". Isso afirma demais. Um selo calculado sobre uma
 * coleta descreve **aquela coleta**, e três experimentos mostraram que ele não
 * é propriedade do benchmark:
 *
 *   - com n = 7 o mesmo ponto produziu os três selos em dez grupos disjuntos;
 *   - a mesma medição, colhida em blocos separados em vez de intercalada, saiu
 *     `!` num arranjo e limpa no outro -- sem que nada no fenômeno mudasse;
 *   - a linha de base do `custo-comunicacao` oscilava entre 0,45 e 0,54 ns
 *     conforme a FREQUÊNCIA da CPU no momento, com ciclos por operação
 *     constantes. Selo sujo, trabalho idêntico.
 *
 * Portanto: o selo não diz que o valor é verdadeiro, nem que a operação é
 * estável. Diz quanto as amostras DESTA coleta discordaram entre si.
 *
 * O SELO "?" EXISTE POR CAUSA DE UM DEFEITO REAL DESTE ARQUIVO.
 *
 * Quando uma medição falha por completo — por exemplo, uma função de medição
 * que devolve 0.0 porque pthread_create falhou —, todas as amostras são zero.
 * Aí `media` e `mediana` são zero, e os guards `media > 0` / `mediana > 0` de
 * summarize(), que existem para evitar divisão por zero, fazem cv e disp valerem
 * **0,0%**. Com disp = 0, este selo devolvia " ": a linha da tabela em que nada
 * foi medido aparecia como a MAIS confiável do conjunto.
 *
 * Uma medição de tempo cuja mediana é exatamente zero não é uma medição rápida:
 * é uma medição que não aconteceu. O selo agora diz isso.
 *
 * Mediana negativa recebe o mesmo tratamento: as funções de medição deste
 * projeto devolvem valores negativos como código de erro, e uma duração
 * negativa não existe. */
static STAT_MAYBE_UNUSED const char *badge(struct statistics e)
{
    if (!collection_is_valid(e, e.samples))
        return "?";
    if (e.disp <= DISP_ESTAVEL)
        return " ";
    if (e.disp <= DISP_SUSPEITA)
        return "~";
    return "!";
}

/* Casas decimais conforme a magnitude: sem isso, valores abaixo de 1 ns saem
 * todos iguais na exibição e contradizem o CV, que é calculado sobre os
 * valores reais. */
static STAT_MAYBE_UNUSED int decimals(double v)
{
    if (v < 1.0)
        return 3;
    if (v < 100.0)
        return 2;
    return 1;
}

/* Imprime uma DIFERENÇA pareada, e não usa `print_row` de propósito.
 *
 * `badge()` e `disp` foram feitos para durações, que são positivas. Uma
 * diferença não é: ela pode trocar de sinal entre pares, e foi o que aconteceu
 * na primeira coleta pareada do `custo-traducao` -- a amplitude do delta ia de
 * -12,8 a +23,8 ns. Nesse caso `minimum < 0` faz `collection_is_valid` recusar
 * a coleta e o selo sair `?`, que significa "não houve medição". Falso: houve, e
 * o resultado é justamente que a diferença oscila.
 *
 * Então a diferença é publicada com o que de fato a descreve: mediana, IQR em
 * NANOSSEGUNDOS (e não IQR/mediana, que explode quando a mediana é pequena) e
 * **em quantos pares o sinal se repete**. Esta última é a linha que diz se o
 * efeito é consistente, e nenhuma das duas medianas separadas a contém. */
static STAT_MAYBE_UNUSED void print_delta(const char *rotulo, struct paired_stats p)
{
    const int d = decimals(p.delta.median < 0 ? -p.delta.median : p.delta.median);
    printf("  %-34s %9.*f  IQR %.*f to %.*f   range %.*f to %.*f   %d/%d pairs\n",
           rotulo, d, p.delta.median, d, p.delta.p25, d, p.delta.p75,
           d, p.delta.minimum, d, p.delta.maximum, p.mesmo_sinal, p.n);
}

/* Avisa, na SAIDA DE ERRO, quando o selo desta linha nao pode decidir.
 *
 * Vai para stderr de proposito: a tabela publicada e colada da saida padrao, e
 * este aviso e para quem RODA a medicao, nao para quem le o documento. Assim o
 * autor descobre que precisa de mais amostras sem que nenhuma tabela ja
 * publicada mude de forma.
 *
 * A faixa vem da secao "QUANTAS AMOSTRAS O SELO EXIGE" no topo deste arquivo:
 * entre 3% e 15% de dispersao, com menos de 20 amostras, o selo sai diferente
 * a cada coleta -- medido em 18/09/2026, dez grupos de sete do mesmo ponto
 * produziram os tres selos. */
static STAT_MAYBE_UNUSED void avisar_selo_indeciso(const char *rotulo, struct statistics e)
{
    if (e.samples < 20 && e.disp >= DISP_ESTAVEL && e.disp <= 15.0)
        fprintf(stderr,
                "  warning: \"%s\" has disp %.1f%% with %d samples -- in that band the seal\n"
                "           does not decide. Raise it to 20+ before explaining the result.\n",
                rotulo, e.disp, e.samples);
}

static STAT_MAYBE_UNUSED void print_row(const char *rotulo, struct statistics e)
{
    avisar_selo_indeciso(rotulo, e);
    const int d = decimals(e.median);
    char iqr[40], amp[40];
    snprintf(iqr, sizeof(iqr), "%.*f-%.*f", d, e.p25, d, e.p75);
    snprintf(amp, sizeof(amp), "%.*f-%.*f", d, e.minimum, d, e.maximum);
    printf("  %-34s %9.*f  %-15s %-17s %5.1f%% %5.1f%% %s\n", rotulo, d, e.median, iqr, amp,
           e.disp, e.cv, badge(e));
}

/* --- PROVENIENCIA ---------------------------------------------------------
 *
 * POR QUE ISTO EXISTE
 *
 * Ate 20/09/2026 NENHUM dos 21 programas de medicao se identificava. A saida
 * publicada era anonima: tinha numero, dispersao e selo, e nada que dissesse
 * DE ONDE VEIO. O repositorio inteiro se apoia na regra de que todo numero tem
 * um programa que o produz -- e o bloco publicado nao dizia QUAL VERSAO desse
 * programa, em que maquina, com que compilador.
 *
 * Isso ficou caro no dia em que o hardware mudou: com o EXPO 6000 ligado, os
 * numeros antigos passaram a descrever uma maquina que nao existia mais, e nao
 * havia no proprio bloco com o que compara-los.
 *
 * O QUE ELE NAO FAZ
 *
 * Nao substitui o `scripts/ambiente.sh`, que reporta topologia, governor,
 * mitigacoes, hugepages e velocidade de memoria. Este cabecalho responde uma
 * pergunta menor e diferente: QUAL BINARIO produziu ESTE bloco. Os dois juntos
 * fecham a cadeia; separados, cada um responde metade.
 */
/* O cabecalho gerado vive no diretorio de BUILD, e so existe quando o
 * programa foi construido pelo meson. `__has_include` deixa o mesmo fonte
 * compilar a mao, com `gcc programa.c`, sem quebrar -- e nesse caso o campo
 * diz `sem-git`, que e a verdade: aquele binario nao tem procedencia. */
#if defined(__has_include)
#  if __has_include("academy_version.h")
#    include "academy_version.h"
#  endif
#endif
#ifndef ACADEMY_COMMIT
#define ACADEMY_COMMIT "sem-git"
#endif

/* A versao do DPDK entra na procedencia porque ela e VARIAVEL EXPERIMENTAL em
 * estudo que compara releases: sem ela, dois bracos de campanha ficam
 * indistinguiveis no arquivo. Programas sem DPDK devolvem string vazia, e a
 * linha de procedencia deles nao muda.
 *
 * A deteccao e por `__has_include` porque este header e compartilhado entre
 * programas que linkam DPDK e programas que nao linkam. */
#if defined(__has_include)
#  if __has_include(<rte_version.h>)
#    include <rte_version.h>
#    define ACADEMY_TEM_DPDK 1
#  endif
#endif

static STAT_MAYBE_UNUSED const char *academy_dpdk_versao(void)
{
#ifdef ACADEMY_TEM_DPDK
    static char buf[64];
    snprintf(buf, sizeof(buf), "  |  %s", rte_version());
    return buf;
#else
    return "";
#endif
}

static STAT_MAYBE_UNUSED void print_provenance(const char *programa)
{
    /* `uname` ja traz o hostname em `nodename`, e `localtime` e C89.
     *
     * `gethostname` e `localtime_r` exigem macro de teste de funcionalidade
     * (_POSIX_C_SOURCE / _GNU_SOURCE), que precisa ser definida ANTES de
     * qualquer header do sistema -- e este arquivo e incluido DEPOIS dos
     * includes de quem o usa. Depender disso faria a compilacao quebrar
     * conforme o programa, que e pior que usar a alternativa portatil. */
    struct utsname u;
    char quando[40];
    const time_t agora = time(NULL);
    const struct tm *tmv;

    if (uname(&u) != 0)
        u.nodename[0] = u.sysname[0] = u.release[0] = '\0';
    quando[0] = '\0';
    tmv = localtime(&agora);
    if (tmv)
        strftime(quando, sizeof(quando), "%Y-%m-%dT%H:%M:%S%z", tmv);

    printf("  origin: %s @ %s  |  %s %s %s  |  gcc %s  |  %s%s\n\n",
           programa, ACADEMY_COMMIT, u.nodename, u.sysname, u.release, __VERSION__, quando,
           academy_dpdk_versao());
}

static STAT_MAYBE_UNUSED void print_header(void)
{
    printf("  %-34s %9s  %-15s %-17s %5s %5s\n", "measurement", "median", "p25-p75 (IQR)",
           "range min-max", "disp", "CV");
    printf("  %-34s %9s  %-15s %-17s %5s %5s\n", "----------------------------------", "---------",
           "---------------", "-----------------", "-----", "-----");
}

/* Variante com conversão para ciclos de clock. Comparar em CICLOS neutraliza a
 * diferença de frequência entre máquinas e gerações — é assim que se separa
 * "ficou mais rápido porque o clock subiu" de "ficou mais rápido de verdade". */
static STAT_MAYBE_UNUSED void print_row_cycles(const char *rotulo, struct statistics e, double period_ns)
{
    const int d = decimals(e.median);
    char iqr[40];
    snprintf(iqr, sizeof(iqr), "%.*f-%.*f", d, e.p25, d, e.p75);
    printf("  %-34s %9.*f  %-15s %8.0f      %5.1f%% %s\n", rotulo, d, e.median, iqr,
           period_ns > 0 ? e.median / period_ns : 0.0, e.disp, badge(e));
}

static STAT_MAYBE_UNUSED void print_header_cycles(void)
{
    /* O rótulo é `disp`, e não `CV`, porque é `e.disp` que imprimir_ciclos()
     * publica nesta coluna. Enquanto dizia "CV", a tabela mais acadêmica do
     * projeto -- a que confronta a Tabela 3.1 de McKenney -- rotulava a
     * dispersão robusta com o nome do coeficiente de variação, que é outra
     * grandeza e vive na outra variante de impressão. */
    printf("  %-34s %9s  %-15s %8s      %5s\n", "measurement", "median", "p25-p75 (IQR)", "cycles",
           "disp");
    printf("  %-34s %9s  %-15s %8s      %5s\n", "----------------------------------", "---------",
           "---------------", "--------", "-----");
}

/* Variante para LATÊNCIA, que se reporta por percentis e não por valor típico.
 * Publica p99 no lugar da amplitude: em plano de dados a cauda é o requisito,
 * e o máximo isolado é uma amostra só — informa menos do que parece. */
static STAT_MAYBE_UNUSED void print_row_tail(const char *rotulo, struct statistics e)
{
    const int d = decimals(e.median);
    printf("  %-30s %9.*f %9.*f %9.*f %9.*f  %7d\n", rotulo, d, e.minimum, d, e.median, d, e.p75, d,
           e.p99, e.samples);
}

static STAT_MAYBE_UNUSED void print_header_tail(void)
{
    printf("  %-30s %9s %9s %9s %9s  %7s\n", "measurement", "minimum", "median", "p75", "p99",
           "samples");
    printf("  %-30s %9s %9s %9s %9s  %7s\n", "------------------------------", "---------",
           "---------", "---------", "---------", "-------");
}

#endif
