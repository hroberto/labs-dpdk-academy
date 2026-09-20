/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — por que "estrutura de dados contígua" não é preferência de
 * estilo, e sim decisão de desempenho.
 *
 * Percorre o mesmo vetor de duas formas, para conjuntos de trabalho de tamanhos
 * crescentes (que cabem em L1, L2, L3 e só na RAM):
 *
 *   sequencial — a[0], a[1], a[2]...  o prefetcher da CPU acerta a previsão e
 *                busca a linha de cache seguinte antes de ela ser pedida.
 *   aleatorio  — ordem embaralhada, LIDA DE UM VETOR. Os endereços são todos
 *                conhecidos de antemão, então o prefetcher erra mas o
 *                processador ainda dispara vários acessos ao mesmo tempo.
 *   dependente — cadeia de ponteiros: o endereço do próximo acesso só existe
 *                depois que este chega. Nada se sobrepõe.
 *
 * POR QUE A TERCEIRA COLUNA EXISTE
 *
 * Por muito tempo este programa publicou duas colunas, e o módulo 01 leu a
 * segunda como "a latência real da RAM". Ela não é: com os endereços conhecidos
 * de antemão, o que se mede é o custo AMORTIZADO de acessos que acontecem em
 * paralelo. A latência de um acesso isolado é cerca de doze vezes maior, e só
 * aparece quando cada acesso depende do anterior.
 *
 * Duas colunas não permitiam distinguir as duas grandezas, e por isso a
 * afirmação errada sobreviveu à revisão: o instrumento não media aquilo que o
 * texto afirmava. A terceira coluna existe para que a distinção seja visível na
 * própria tabela, e não apenas no parágrafo que a explica.
 *
 * `custo-paralelismo.c` fecha a conta: mostra a transição entre a terceira
 * coluna e a segunda, acesso a acesso.
 *
 * METODOLOGIA: igual à dos demais programas desta pasta. Ver statistics.h.
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "cadeia.h"
#include "clock_ns.h"
#include "statistics.h"

/* Total de acessos por medição, constante entre os tamanhos para comparar. */
#define ACESSOS_TOTAIS (64u * 1024u * 1024u)
/* A cadeia dependente é ~12x mais lenta por acesso: com o mesmo total o
 * programa levaria minutos. Menos acessos bastam, porque não há nada a
 * amortizar — cada um paga o preço cheio. */
#define ACESSOS_DEPENDENTES (2u * 1024u * 1024u)
/* Um passo a cada 16 uint32_t = uma linha de cache por acesso. Sem isso,
 * dezesseis passos da cadeia cairiam na MESMA linha e a medição devolveria a
 * latência da L1, qualquer que fosse o tamanho da região. */
#define U32_POR_LINHA 16
#define AMOSTRAS_CACHE_FIXO 9
#define AMOSTRAS_CACHE samples(AMOSTRAS_CACHE_FIXO)

/* collect_or_fail() recebe ponteiro sem argumentos; o caso vai por variáveis. */
enum modo { SEQUENCIAL, ALEATORIO, DEPENDENTE };
static size_t caso_tam;
static enum modo caso_modo;


static volatile uint32_t sumidouro;

static double medir(const uint32_t *a, const uint32_t *ordem, size_t n, size_t repeticoes)
{
    volatile uint64_t soma = 0;
    const uint64_t t0 = academy_now_ns();
    if (ordem == NULL) {
        for (size_t r = 0; r < repeticoes; r++)
            for (size_t i = 0; i < n; i++)
                soma += a[i];
    } else {
        for (size_t r = 0; r < repeticoes; r++)
            for (size_t i = 0; i < n; i++)
                soma += a[ordem[i]];
    }
    (void)soma;
    return (double)(academy_now_ns() - t0) / (double)(n * repeticoes);
}

/* Percorre uma cadeia de ponteiros: cada posição guarda o índice da próxima.
 * O laço é o experimento inteiro — `idx = a[idx]` não deixa o processador
 * adiantar nada, porque o endereço seguinte ainda não existe. */
static double medir_dependente(const uint32_t *a, size_t acessos)
{
    uint32_t idx = 0;
    const uint64_t t0 = academy_now_ns();
    for (size_t i = 0; i < acessos; i++)
        idx = a[idx];
    const uint64_t dt = academy_now_ns() - t0;
    sumidouro = idx;
    return (double)dt / (double)acessos;
}

/* Uma amostra do caso corrente: aloca, embaralha se preciso, percorre. */
static double amostra_caso(void)
{
    const size_t n = caso_tam / sizeof(uint32_t);
    uint32_t *a = aligned_alloc(64, n * sizeof(uint32_t));
    uint32_t *ordem = malloc(n * sizeof(uint32_t));
    if (a == NULL || ordem == NULL) {
        free(a);
        free(ordem);
        return -1.0;
    }
    for (size_t i = 0; i < n; i++) {
        a[i] = (uint32_t)i;
        ordem[i] = (uint32_t)i;
    }
    double r;
    if (caso_modo == DEPENDENTE) {
        /* A cadeia é montada sobre as LINHAS da região, não sobre os elementos.
         *
         * Confundir os dois foi um defeito real desta função: a primeira versão
         * embaralhava as `n` posições e reduzia cada valor com `% nos`, o que
         * não é permutação — vários nós recebiam o mesmo sucessor, a cadeia
         * degenerava em ciclos de dois ou três nós que cabem na L1, e a coluna
         * publicava 0,9 ns para a RAM. A construção mora agora em `cadeia.h`,
         * com a propriedade verificada em `tests/test_l1_cadeia.cpp`. */
        static uint64_t semente = 0x853C49E6748FEA9Bull;
        const size_t nos = n / U32_POR_LINHA;
        size_t *cad = malloc(nos * sizeof(size_t));
        if (cad == NULL) {
            free(a);
            free(ordem);
            return -1.0;
        }
        academy_permutar(cad, nos, &semente);
        for (size_t i = 0; i < academy_cadeia_nos(nos, 1); i++)
            a[cad[i] * U32_POR_LINHA] =
                (uint32_t)(academy_sucessor(cad, nos, 1, i) * U32_POR_LINHA);
        free(cad);
        r = medir_dependente(a, ACESSOS_DEPENDENTES);
    } else {
        /* O modo ALEATORIO embaralha ÍNDICES de elementos, não linhas, e por
         * isso continua com o vetor de `uint32_t`: convertê-lo para `size_t` só
         * para reusar `cadeia.h` dobraria uma alocação de 256 MB sem ganho de
         * correção — aqui não há ciclo a fechar, só uma ordem a sortear. */
        if (caso_modo == ALEATORIO) {
            for (size_t i = n - 1; i > 0; i--) {
                const size_t j = (size_t)rand() % (i + 1);
                const uint32_t t = ordem[i];
                ordem[i] = ordem[j];
                ordem[j] = t;
            }
        }
        const size_t repeticoes = ACESSOS_TOTAIS / n + 1;
        r = medir(a, caso_modo == ALEATORIO ? ordem : NULL, n, repeticoes);
    }
    free(a);
    free(ordem);
    return r;
}

int main(void)
{
    print_provenance("efeito-cache");
    const size_t tamanhos[] = {16u * 1024, 256u * 1024, 8u * 1024 * 1024, 256u * 1024 * 1024};
    const char *nivel[] = {"L1d", "L2", "L3", "RAM"};

    printf("Latencia media por acesso, conjunto de trabalho crescente\n");
    printf("(linha de cache = 64 B; cada uint32_t = 4 B, logo 16 por linha)\n\n");
    printf("(%d amostras por medicao; tempos em ns)\n\n", AMOSTRAS_CACHE);

    for (size_t k = 0; k < sizeof(tamanhos) / sizeof(tamanhos[0]); k++) {
        caso_tam = tamanhos[k];
        char rot[64];

        printf("  %s (%zu KB)\n", nivel[k], tamanhos[k] / 1024);
        print_header();

        caso_modo = SEQUENCIAL;
        const struct statistics seq = collect_or_fail(amostra_caso, AMOSTRAS_CACHE);
        snprintf(rot, sizeof(rot), "  sequential   (amortised)");
        print_row(rot, seq);

        caso_modo = ALEATORIO;
        const struct statistics ale = collect_or_fail(amostra_caso, AMOSTRAS_CACHE);
        snprintf(rot, sizeof(rot), "  random       (amortised)");
        print_row(rot, ale);

        caso_modo = DEPENDENTE;
        const struct statistics dep = collect_or_fail(amostra_caso, AMOSTRAS_CACHE);
        snprintf(rot, sizeof(rot), "  dependent    (LATENCY)");
        print_row(rot, dep);

        printf("  -> penalidade por perder a localidade: %.1fx"
               "   |  acessos em voo: ~%.0f\n\n",
               ale.median / seq.median, dep.median / ale.median);
        fflush(stdout);
    }

    printf("\n  As duas primeiras colunas sao tempo AMORTIZADO; a terceira e\n");
    printf("  LATENCIA. Sequencial custa quase o mesmo em qualquer tamanho,\n");
    printf("  porque o prefetcher esconde a latencia. Aleatorio degrada, mas\n");
    printf("  ainda amortiza: os enderecos vem de um vetor lido em sequencia,\n");
    printf("  entao varios acessos acontecem ao mesmo tempo. So a cadeia\n");
    printf("  dependente expoe o preco cheio de UM acesso.\n\n");
    printf("  A razao entre a segunda e a terceira coluna e quantos acessos a\n");
    printf("  maquina mantem em voo. Ver custo-paralelismo.c.\n");
    return 0;
}
