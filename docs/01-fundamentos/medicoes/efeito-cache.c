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

/* O QUE A COLUNA `sequencial` MEDE, E O QUE ELA NAO MEDE.
 *
 * O laco acumula em `soma`, e essa soma e uma CADEIA CARREGADA PELO LACO: o
 * `add` da iteracao seguinte espera o da anterior. Latencia de 1 ciclo,
 * portanto teto de ~1 elemento por ciclo -- a 4,4 GHz, 4 bytes por ciclo dao
 * cerca de 21 GB/s.
 *
 * ESSA DESCRICAO SO PASSOU A SER VERDADE COM O ACUMULADOR EM REGISTRADOR. Ver a
 * nota em `medir()`: enquanto `soma` era `volatile`, a cadeia real era a de
 * store-to-load forwarding pela pilha, e nao a do `add`.
 *
 * Esse teto NAO DEPENDE DE ONDE O DADO ESTA. Com o conjunto na L1d o valor e o
 * mesmo que com ele em DRAM, porque nos dois casos a memoria entrega mais do
 * que o laco consome. Daqui sai a leitura correta da coluna:
 *
 *   MEDE     a taxa de emissao que o prefetcher consegue sustentar -- e o
 *            resultado e que ele a sustenta CHEIA ate 256 MB em DRAM.
 *   NAO MEDE banda de memoria. Converter 0,187 ns/elemento em "21 GB/s de
 *            banda" atribui ao subsistema de memoria um numero do laco.
 *
 * POR QUE NAO SE CONSERTA COM UM LACO MELHOR, aqui.
 *
 * Quebrar a cadeia com varios acumuladores sobe o teto para ~32-36 GB/s, e a
 * DRAM desta maquina entrega mais que isso -- os niveis continuam
 * indistinguiveis. Para ver o gradiente e preciso vetorizar, o que exige
 * `-march=native` ou equivalente. O projeto compila com `-O2` portavel de
 * proposito, para que a mesma fonte produza numero comparavel em outra
 * maquina. A escolha e essa, e o custo dela e esta coluna nao servir de
 * bandimetro.
 *
 * As colunas `aleatorio` e `dependente` nao tem esse problema: as duas ficam
 * ordens de grandeza abaixo do teto do laco, e por isso medem a memoria.
 */
static double medir(const uint32_t *a, const uint32_t *ordem, size_t n, size_t repeticoes)
{
    /* ACUMULADOR EM REGISTRADOR, COM UM UNICO ESCAPE DEPOIS DO LACO.
     *
     * `volatile` aqui punha um store e um load na pilha POR ELEMENTO, e a
     * cadeia medida passava a ser a de store-to-load forwarding -- 4 a 6 ciclos
     * nesta microarquitetura -- em vez da soma. O laco emitido era:
     *
     *     mov 0x18(%rsp),%rsi ; mov (%rdx),%ecx ; add %rsi,%rcx
     *     mov %rcx,0x18(%rsp) ; jne
     *
     * O objdump e o criterio, nao a intencao: o `volatile` estava ali para
     * impedir que o laco fosse apagado, e a forma mais barata de fazer isso
     * sem entrar no caminho quente e o escape vazio de asm depois do laco. */
    uint64_t soma = 0;
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
    /* UMA vez, fora da janela do laco: o compilador nao pode provar que `soma`
     * nao e usada, e portanto nao pode apagar as leituras. */
    __asm__ __volatile__("" : : "r"(soma) : "memory");
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

    printf("Mean latency per access, growing working set\n");
    printf("(cache line = 64 B; each uint32_t = 4 B, so 16 per line)\n\n");
    printf("(%d samples per measurement; times in ns)\n\n", AMOSTRAS_CACHE);

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

        printf("  -> penalty for losing locality: %.1fx"
               "   |  accesses in flight: ~%.0f\n\n",
               ale.median / seq.median, dep.median / ale.median);
        fflush(stdout);
    }

    printf("\n  The first two columns are AMORTISED time; the third is\n");
    printf("  LATENCY. Sequential costs nearly the same at any size,\n");
    printf("  because the prefetcher hides the latency. Random degrades, but\n");
    printf("  still amortises: the addresses come from a vector read in order,\n");
    printf("  so several accesses happen at once. Only the dependent\n");
    printf("  chain exposes the full price of ONE access.\n\n");
    printf("  The ratio between the second and third columns is how many accesses\n");
    printf("  the machine keeps in flight. See custo-paralelismo.c.\n");
    return 0;
}
