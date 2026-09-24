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
static _Alignas(64) volatile long sumidouro_clk;
static double periodo_ns(void)
{
    const int n = 20000000;
    volatile long x = 0;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n; i++)
        x = x + 1;
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
        /* OS CICLOS SAO O RESULTADO. Se o modelo estiver certo eles nao mudam
         * com o modo, com o governor nem com a maquina -- so com a carga no
         * irmao SMT. */
        printf("  CICLOS por operacao: %.3f (pelo periodo inicial)"
               "   %.3f (pelo final)\n", T0 > 0 ? med / T0 : 0.0,
               T1 > 0 ? med / T1 : 0.0);
        free(ord);
    }

    free(v);
    free(f);
    return EXIT_SUCCESS;
}
