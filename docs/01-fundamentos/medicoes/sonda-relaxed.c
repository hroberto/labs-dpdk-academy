// SPDX-License-Identifier: MIT
/* Sonda dedicada ao `atomic relaxed (store+load)` do `custo-espera`.
 *
 * POR QUE UM PROGRAMA SO PARA ISTO
 *
 * O `custo-espera` leva 27 s por execucao, e 99,99% desse tempo esta nas OUTRAS
 * medicoes -- condvar, semaforo, repasse entre nucleos. O laco que interessa
 * aqui custa 0,4 ms por amostra. Investigar a distribuicao dele pelo programa
 * inteiro significaria 27 s para cada 3,6 ms de dado util.
 *
 * A PERGUNTA
 *
 * Em 24/09/2026, com o governor fixo em `performance` e sem sessao grafica, a
 * mediana desta medicao pousou em 0,255 ns nas seis repeticoes, com dispersao
 * de 0,4% a 1,5% e sem selo. Estavel -- e num valor que nao e nenhum dos dois
 * que o material ja conhece:
 *
 *   0,205 ns   o valor modal que a §5 da metodologia identifica
 *   0,397 ns   o valor que a §5 explica por carga no irmao SMT
 *   0,255 ns   este, que nenhuma das duas explicacoes cobre
 *
 * O 0,205 continua aparecendo no MINIMO da faixa das coletas de 24/09, nao na
 * mediana. Entao a pergunta nao e "o 0,205 sumiu?", e sim "por que a mediana
 * saiu de 0,205 para 0,255 quando o relogio parou de variar?".
 *
 * AS HIPOTESES, E O QUE CADA UMA PREVE
 *
 *   H1 ESTADO PROPRIO. 0,255 e um terceiro estado do laco, e a distribuicao
 *      mostra tres picos. PREVE: histograma com massa em 0,255 separada de
 *      0,205, e amostras individuais em 0,255.
 *
 *   H2 MISTURA. 0,255 nao existe como amostra; e a mediana de um vetor que
 *      alterna entre 0,205 e algo maior. PREVE: nenhuma amostra perto de
 *      0,255, e a mediana caindo ali por interpolacao entre os dois picos.
 *
 *   H3 RELOGIO. 0,255 e 0,205 sao o mesmo numero de ciclos em frequencias
 *      diferentes. PREVE: a razao 0,255/0,205 = 1,244 aparecer tambem na
 *      razao das frequencias lidas.
 *
 * As tres sao distinguiveis com amostras individuais e a frequencia de cada
 * uma, que e o que este programa publica. `custo-espera` publica so o resumo.
 *
 * O LACO E COPIA FIEL, e isso e condicao de validade: mesmo numero de rodadas,
 * mesmo alinhamento, mesma ordem de memoria, mesmo sumidouro volatil. Medir
 * um laco parecido responderia sobre o laco parecido.
 *
 *   uso:  sonda-relaxed [amostras] [cpu]
 *         padrao: 200 amostras na cpu 0
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "clock_ns.h"
#include "statistics.h"

#define RODADAS 2000000

/* Alinhamento e qualificadores identicos aos do `custo-espera`: o valor medido
 * depende de a linha de cache ser exclusiva, e mudar isso mudaria o alvo. */
static _Alignas(64) atomic_int valor;
static _Alignas(64) volatile long sumidouro;

/* Copia fiel de `m_atomica_relaxed`. O numero de rodadas e lido numa constante
 * local pelo mesmo motivo documentado no original: uma macro na condicao do
 * laco chamaria `getenv()` por iteracao e multiplicaria o custo por 150. */
static double medir_uma(void)
{
    const int n_rodadas = RODADAS;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        atomic_store_explicit(&valor, i, memory_order_relaxed);
        sumidouro = atomic_load_explicit(&valor, memory_order_relaxed);
    }
    return (double)(academy_now_ns() - t0) / n_rodadas;
}

/* PERIODO DE CLOCK MEDIDO, e nao lido do sysfs.
 *
 * `scaling_cur_freq` e o que o driver ACHA que pediu, e em amd-pstate ele nao
 * e a frequencia efetiva do nucleo. O `custo-mckenney` ja resolvia isso de
 * outro jeito: uma cadeia de somas inteiras dependentes custa um ciclo por
 * elemento em regime, entao o tempo por elemento E o periodo de clock.
 *
 * A diferenca entre as duas fontes e justamente o que esta sonda precisa
 * distinguir, porque ela publica CICLOS -- e ciclos calculados sobre uma
 * frequencia errada sao um numero errado com aparencia de invariante. */

/* A CADEIA VIVE EM REGISTRADOR, e a razao esta medida.
 *
 * A versao anterior usava `volatile long x` e somava `x = x + 1`. O `objdump`
 * mostrava o laco como `mov (%rsp); add; mov ,(%rsp)` -- load/add/store pela
 * pilha a cada iteracao --, que e EXATAMENTE o padrao que este projeto
 * retratou no `efeito-cache.c` em 0907f57.
 *
 * O QUE FOI MEDIDO, E O QUE ISSO AUTORIZA DIZER. As duas formas correndo lado
 * a lado nesta maquina deram RAZAO 1,00 em tres repeticoes -- custo por
 * iteracao indistinguivel. A razao e o que vale aqui; o absoluto saiu numa
 * maquina em uso e nao e numero publicavel.
 *
 * Isso estabelece EQUIVALENCIA DE CUSTO OBSERVADO, e nao identidade de
 * mecanismo: o assembly da versao com `volatile` continua com load e store, e
 * o que a medicao diz e que eles nao custam nada de observavel aqui. O
 * comportamento e compativel com o store-to-load forwarding dos Zen recentes,
 * que a AMD documenta e estende com Predictive Store Forwarding desde o
 * Zen 3 -- e nao com "renomeacao de memoria", termo que a documentacao nao
 * sustenta para este caso.
 *
 * E E RESULTADO DE PLATAFORMA, nao propriedade de C nem de `volatile`. Num
 * processador que nao encurte esse caminho, a mesma cadeia custaria varios
 * ciclos, o periodo "medido" sairia multiplicado por isso, e a razao
 * emissao/hardware -- que esta sonda usa para detectar NUCLEO DIVIDIDO --
 * acusaria divisao onde nao ha. Um numero certo por acidente de hardware e um
 * numero que nao viaja, e e por isso que a cadeia passou para registrador
 * mesmo sem haver defeito medido nesta maquina.
 *
 * A barreira de compilador entrega a mesma serializacao sem depender disso:
 * ela impede o compilador de eliminar ou reordenar a soma, e nao obriga a
 * ida a memoria. */
static _Alignas(64) volatile long sumidouro_clk;
static double periodo_ns(void)
{
    const int n = 20000000;
    long x = 0;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n; i++) {
        x = x + 1;
        __asm__ volatile("" : "+r"(x) :: "memory");
    }
    const double r = (double)(academy_now_ns() - t0) / n;
    sumidouro_clk = x;
    return r;
}

/* AQUECIMENTO, com a duracao que o `custo-espera` ja usa. Nao e chute: aquele
 * arquivo documenta 400 ms como o ponto onde o efeito de arranque some, medido,
 * e nao onde se cansou de esperar. */
#define AQUECIMENTO_MS 400
static void aquecer(void)
{
    const uint64_t ate = academy_now_ns() + (uint64_t)AQUECIMENTO_MS * 1000000ull;
    long a = 0;
    while (academy_now_ns() < ate)
        for (int i = 0; i < 10000; i++)
            a += i;
    sumidouro_clk = a;
}

static double freq_ghz(int cpu)
{
    char caminho[128];
    snprintf(caminho, sizeof(caminho),
             "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq", cpu);
    FILE *f = fopen(caminho, "r");
    if (f == NULL)
        return 0.0;
    long khz = 0;
    if (fscanf(f, "%ld", &khz) != 1)
        khz = 0;
    fclose(f);
    return (double)khz / 1e6;
}

static int cmp_d(const void *a, const void *b)
{
    const double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv)
{
    const int n = argc > 1 ? atoi(argv[1]) : 200;
    const int cpu = argc > 2 ? atoi(argv[2]) : 0;
    if (n < 1) {
        fprintf(stderr, "sonda-relaxed: amostras deve ser >= 1\n");
        return EXIT_FAILURE;
    }

    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    if (sched_setaffinity(0, sizeof(set), &set) != 0) {
        fprintf(stderr, "sonda-relaxed: nao consegui fixar na cpu %d\n", cpu);
        return EXIT_FAILURE;
    }

    double *v = malloc((size_t)n * sizeof(double));
    double *f = malloc((size_t)n * sizeof(double));
    if (v == NULL || f == NULL) {
        fprintf(stderr, "sonda-relaxed: sem memoria\n");
        free(v);
        free(f);
        return EXIT_FAILURE;
    }

    const char *gov_caminho = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor";
    char gov[32] = "nao lido";
    FILE *g = fopen(gov_caminho, "r");
    if (g != NULL) {
        if (fscanf(g, "%31s", gov) != 1)
            snprintf(gov, sizeof(gov), "nao lido");
        fclose(g);
    }

    printf("  sonda-relaxed: %d amostras de %d rodadas, cpu %d, governor %s\n\n",
           n, RODADAS, cpu, gov);

    aquecer();
    const double T0 = periodo_ns();
    printf("  periodo de clock MEDIDO, apos %d ms de aquecimento: %.4f ns"
           "  (%.2f GHz)\n", AQUECIMENTO_MS, T0, T0 > 0 ? 1.0 / T0 : 0.0);
    printf("  frequencia lida do sysfs no mesmo instante:         %.2f GHz\n\n",
           freq_ghz(cpu));

    /* AMOSTRA DE AQUECIMENTO DESCARTADA. Nao e cerimonia: o material ja mede
     * que a primeira execucao apos ociosidade sai ~30% alta na operacao mais
     * curta, e esta e a operacao mais curta do projeto. */
    (void)medir_uma();

    for (int i = 0; i < n; i++) {
        f[i] = freq_ghz(cpu);
        v[i] = medir_uma();
    }

    /* AS AMOSTRAS INDIVIDUAIS SAO O RESULTADO, nao o resumo. H1 e H2 dao a
     * MESMA mediana e diferem so aqui: se 0,255 e estado, ha amostras em
     * 0,255; se e mistura, nao ha nenhuma. */
    printf("  amostra  ns/operacao   GHz\n");
    printf("  -------  -----------  -----\n");
    for (int i = 0; i < n; i++)
        printf("  %7d  %11.4f  %5.2f\n", i, v[i], f[i]);

    double *ord = malloc((size_t)n * sizeof(double));
    if (ord != NULL) {
        for (int i = 0; i < n; i++)
            ord[i] = v[i];
        qsort(ord, (size_t)n, sizeof(double), cmp_d);

        /* Histograma de 10 ps: fino o bastante para separar 0,205 de 0,255 e
         * grosso o bastante para nao pulverizar um pico verdadeiro. */
        printf("\n  histograma, classes de 0,010 ns\n");
        int i = 0;
        while (i < n) {
            const double base = (double)(long)(ord[i] * 100.0) / 100.0;
            int c = 0;
            while (i < n && ord[i] < base + 0.010) {
                c++;
                i++;
            }
            printf("  %.3f a %.3f  %4d  ", base, base + 0.010, c);
            for (int k = 0; k < c * 60 / n + (c > 0); k++)
                putchar('#');
            putchar('\n');
        }
        const double med = percentil(ord, n, 0.50);
        const double T1 = periodo_ns();
        printf("\n  minimo %.4f   mediana %.4f   maximo %.4f\n",
               ord[0], med, ord[n - 1]);
        printf("  periodo de clock ao FIM: %.4f ns (%.2f GHz)\n", T1,
               T1 > 0 ? 1.0 / T1 : 0.0);
        /* OS CICLOS SAO O RESULTADO, E SAO DOIS NUMEROS DIFERENTES.
         *
         * A primeira versao publicava so o periodo empirico, e a coleta de
         * 24/09 mostrou por que isso nao basta. Com o irmao SMT saturado ela
         * deu 1,046 ciclos onde o modelo previa 1,818 -- e a previsao estava
         * certa; errado estava o denominador.
         *
         * `periodo_ns()` mede uma cadeia de somas DEPENDENTES, uma por ciclo
         * em regime. Isso e vazao de emissao DESTA thread, nao frequencia do
         * nucleo. Quando o irmao SMT disputa as unidades de execucao, as duas
         * threads emitem cada uma cerca de metade -- e o periodo empirico
         * dobra junto com a medicao. Numerador e denominador caem juntos, e a
         * divisao cancela exatamente o efeito que se quer ver.
         *
         * O sysfs nao cai: ele le a frequencia do hardware, que nao muda por
         * haver duas threads no nucleo. Medido em 24/09, com o irmao saturado:
         * sysfs 5,44 GHz contra 3,12 GHz empirico, divergencia de 1,74x. Sem
         * carga os dois concordam -- 5,59 contra 5,51.
         *
         * Por isso os dois sao publicados, com o nome do que cada um mede:
         *
         *   por HARDWARE  quantos periodos de relogio a operacao ocupa. E o
         *                 numero comparavel entre condicoes, e o que fecha o
         *                 modelo: 1,824 com irmao saturado contra 1,818
         *                 medidos em modo grafico.
         *   por EMISSAO   quantas oportunidades de emissao DESTA thread a
         *                 operacao consome. Igual ao de cima quando o nucleo
         *                 esta sozinho; menor sob disputa, e a diferenca entre
         *                 os dois E a disputa.
         */
        const double f_hw = freq_ghz(cpu);
        printf("  CICLOS por operacao\n");
        printf("    por HARDWARE (sysfs %.2f GHz):  %.3f\n", f_hw, med * f_hw);
        printf("    por EMISSAO  (medido %.2f GHz): %.3f\n",
               T1 > 0 ? 1.0 / T1 : 0.0, T1 > 0 ? med / T1 : 0.0);
        if (f_hw > 0 && T1 > 0) {
            const double razao = (1.0 / T1) / f_hw;
            printf("    razao emissao/hardware: %.2f", razao);
            /* Abaixo de ~0,8 a thread nao esta recebendo o nucleo inteiro. O
             * limiar nao e teorico: sem carga a coleta de 24/09 deu 0,99, e
             * com o irmao saturado, 0,57. */
            printf("%s\n", razao < 0.8
                   ? "   <- o nucleo esta sendo dividido"
                   : "   <- a thread tem o nucleo");
        }
        free(ord);
    }

    free(v);
    free(f);
    return EXIT_SUCCESS;
}
