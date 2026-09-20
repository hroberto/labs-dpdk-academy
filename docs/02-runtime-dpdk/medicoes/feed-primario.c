/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Feed handler de market data — o processo PRIMÁRIO.
 *
 * Papel no exemplo: é quem teria a NIC. Recebe o feed da bolsa, normaliza cada
 * atualização em `struct tick` e publica num anel em memória compartilhada da
 * EAL. Aqui não há NIC: os ticks são gerados por um PRNG determinístico, para
 * que o experimento seja reproduzível. O objeto de estudo é o RUNTIME —
 * a memzone, a fronteira de processo e o custo de atravessá-la —, não a NIC.
 *
 * Por que este desenho, e não um processo só com duas threads: separar o
 * recebimento (primário) do consumo (secundário) é o padrão real em mesa de
 * operações. O feed handler não pode cair porque uma estratégia estourou um
 * ponteiro; e a estratégia costuma ser recompilada muitas vezes ao dia,
 * enquanto o feed handler sobe uma vez (ver custo-init.c: subir a EAL não é
 * barato). Processos separados dão isolamento de falha e ciclos de vida
 * independentes; o preço é que a comunicação passa a exigir memória
 * compartilhada explícita, que é justamente o que a EAL oferece.
 *
 * USO:
 *   ./feed-primario -l 0 --file-prefix=academia -- [total] [cadencia|rajada]
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <rte_cycles.h>
#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_lcore.h>
#include <rte_memzone.h>
#include <rte_pause.h>

#include "feed.h"

#define TOTAL_PADRAO 200000u
#define PRECO_INICIAL 3250 /* R$ 32,50, em centavos */

/* Metade do spread, em centavos. O gerador publica compra em (meio - SPREAD) e
 * venda em (meio + SPREAD), de modo que a melhor compra fique SEMPRE abaixo da
 * melhor venda.
 *
 * Isto não é detalhe cosmético. A primeira versão sorteava um preço e sorteava o
 * lado de forma independente, e o resultado foi um livro CRUZADO, com spread de
 * -441 centavos — estado que não existe em mercado, porque a negociação teria
 * ocorrido. Gerador de dado de exemplo que produz estado impossível ensina o
 * leitor a desconfiar do material, não do mercado. */
#define MEIO_SPREAD 2

/* Uma lacuna a cada N ticks, para o assinante exercitar a detecção de perda.
 * É perda SIMULADA e está anunciada na saída: nada aqui perde pacote de fato. */
#define LACUNA_A_CADA 5000u

/* Espera do aperto de mão com o assinante. Generoso de propósito: o secundário
 * também precisa subir a EAL, o que custa dezenas de milissegundos. */
#define ESPERA_ASSINANTE_S 15

/* xorshift64*: determinístico e sem estado global escondido, ao contrário de
 * rand(). Reprodutibilidade vale mais aqui do que qualidade estatística. */
static uint64_t semente = 0x9E3779B97F4A7C15ULL;

static uint64_t proximo_aleatorio(void)
{
    semente ^= semente >> 12;
    semente ^= semente << 25;
    semente ^= semente >> 27;
    return semente * 0x2545F4914F6CDD1DULL;
}

/* Quantos processos SECUNDÁRIOS ainda estão vivos.
 *
 * A EAL mantém um socket de controle por processo no diretório de runtime
 * (rte_eal_get_runtime_dir(), que para usuário comum fica sob
 * $XDG_RUNTIME_DIR/dpdk/<prefixo>/). O primário é dono de "mp_socket"; cada
 * secundário cria "mp_socket_<pid>_<hash>" e o remove no próprio cleanup.
 * Enquanto sobrar algum, há secundário se desconectando.
 *
 * Isto observa um detalhe de implementação da EAL, e por isso a espera é
 * LIMITADA e a falha é não-fatal: se a convenção de nome mudar, o programa
 * segue em frente em vez de travar. A alternativa seria dormir um tempo
 * arbitrário, que não observa nada. */
static int secundarios_vivos(void)
{
    const char *dir = rte_eal_get_runtime_dir();
    if (dir == NULL)
        return -1;

    DIR *d = opendir(dir);
    if (d == NULL)
        return -1;

    int n = 0;
    const struct dirent *e;
    while ((e = readdir(d)) != NULL)
        if (strncmp(e->d_name, "mp_socket_", 10) == 0)
            n++;
    closedir(d);
    return n;
}

static void spin_cycles(uint64_t ciclos)
{
    const uint64_t fim = rte_rdtsc() + ciclos;
    while (rte_rdtsc() < fim)
        rte_pause(); /* dica ao processador: laço de espera, não trabalho útil */
}

int main(int argc, char **argv)
{
    const int consumidos_pela_eal = rte_eal_init(argc, argv);
    if (consumidos_pela_eal < 0) {
        fprintf(stderr, "feed-primario: EAL nao inicializou: %s\n", rte_strerror(rte_errno));
        fprintf(stderr, "  Este programa exige memoria compartilhada real entre processos.\n");
        fprintf(stderr, "  Nao funciona com --in-memory nem com --no-huge: veja o README.\n");
        return 2;
    }
    argc -= consumidos_pela_eal;
    argv += consumidos_pela_eal;

    if (rte_eal_process_type() != RTE_PROC_PRIMARY) {
        fprintf(stderr, "feed-primario: precisa ser o processo primario.\n");
        rte_eal_cleanup();
        return 2;
    }

    const uint64_t total = argc > 1 ? strtoull(argv[1], NULL, 10) : TOTAL_PADRAO;
    const int rajada = argc > 2 && strcmp(argv[2], "rajada") == 0;

    /* A memzone é reservada no nó NUMA DESTE lcore. Num servidor de market data
     * de verdade seria o nó da NIC — memória, núcleo e placa no mesmo nó, como
     * exige a tabela de configuração da §6.2 dos fundamentos. */
    const struct rte_memzone *mz =
        rte_memzone_reserve(FEED_MEMZONE, sizeof(struct shared_feed), (int)rte_socket_id(), 0);
    if (mz == NULL) {
        fprintf(stderr, "feed-primario: rte_memzone_reserve falhou: %s\n", rte_strerror(rte_errno));
        rte_eal_cleanup();
        return 1;
    }

    struct shared_feed *f = (struct shared_feed *)mz->addr;
    memset(f, 0, sizeof(*f));
    f->total_previsto = total;
    f->tsc_hz = rte_get_tsc_hz();
    /* Quantas lacunas serão injetadas: uma a cada LACUNA_A_CADA ticks, a partir
     * do índice LACUNA_A_CADA. Publicado ANTES do aperto de mão, para que o
     * consumidor sempre o leia com valor definitivo. */
    f->lacunas_injetadas = (LACUNA_A_CADA > 0 && total > 0) ? (total - 1) / LACUNA_A_CADA : 0;

    printf("\n== Feed handler (processo primario) ==\n\n");
    printf("  memzone .............. \"%s\"\n", mz->name);
    printf("  endereco virtual ..... %p        <- compare com o do secundario\n", mz->addr);
    printf("  endereco IOVA ........ 0x%" PRIx64 "\n", (uint64_t)mz->iova);
    printf("  tamanho .............. %zu bytes (%zu KiB)\n", (size_t)mz->len, (size_t)mz->len / 1024);
    printf("  no NUMA .............. %d\n", mz->socket_id);
    printf("  pagina ............... %zu KiB\n", (size_t)mz->hugepage_sz / 1024);
    printf("  lcore do produtor .... %u (indice no no %d, no NUMA %u)\n", rte_lcore_id(),
           rte_lcore_to_cpu_id((int)rte_lcore_id()), rte_socket_id());
    printf("  relogio (TSC) ........ %.3f GHz\n", (double)f->tsc_hz / 1e9);
    printf("  sizeof(struct tick) .. %zu bytes (%zu por linha de cache)\n", sizeof(struct tick),
           (size_t)FEED_LINHA / sizeof(struct tick));
    printf("  modo ................. %s\n", rajada ? "rajada (sem pausa)" : "cadencia (pausa entre ticks)");
    printf("  ticks a publicar ..... %" PRIu64 "\n\n", total);

    printf("  aguardando o assinante conectar (ate %d s)...\n", ESPERA_ASSINANTE_S);
    fflush(stdout);

    const uint64_t limite = rte_rdtsc() + (uint64_t)ESPERA_ASSINANTE_S * f->tsc_hz;
    while (atomic_load_explicit(&f->assinante_pronto, memory_order_acquire) == 0) {
        if (rte_rdtsc() > limite) {
            fprintf(stderr, "  nenhum assinante conectou. Encerrando.\n");
            rte_memzone_free(mz);
            rte_eal_cleanup();
            return 3;
        }
        rte_pause();
    }
    printf("  assinante conectado.\n\n");

    /* Pausa entre ticks no modo cadência: ~2 µs. O objetivo é que o consumidor
     * esteja SEMPRE ocioso quando o tick chega, para que a latência medida do
     * outro lado seja a da travessia, e não fila acumulada. */
    const uint64_t pausa = f->tsc_hz / 500000ULL;

    /* Preço MÉDIO de cada papel. O que se publica é sempre um dos dois lados,
     * derivado dele — nunca o meio, que é abstração de quem observa. */
    int32_t meio[FEED_INSTRUMENTOS];
    for (unsigned i = 0; i < FEED_INSTRUMENTOS; i++)
        meio[i] = PRECO_INICIAL + (int32_t)i * 100;

    uint64_t sequence = 0;
    uint64_t gaps = 0;
    const uint64_t t_inicio = rte_rdtsc();

    for (uint64_t i = 0; i < total; i++) {
        /* Controle de fluxo: nunca sobrescrever o que o assinante ainda não
         * leu. Sem isto o consumidor mediria latência de dado corrompido. */
        while (i - atomic_load_explicit(&f->consumidos, memory_order_acquire) >= FEED_CAPACIDADE)
            rte_pause();

        const uint64_t r = proximo_aleatorio();
        const unsigned inst = (unsigned)(r % FEED_INSTRUMENTOS);
        const int passo = (int)((r >> 8) % 3) - 1; /* -1, 0 ou +1 centavo */
        meio[inst] += passo;
        const uint8_t lado = (uint8_t)((r >> 32) & 1u);

        sequence++;
        /* Perda simulada: pula um número de sequência. */
        if (LACUNA_A_CADA > 0 && i > 0 && i % LACUNA_A_CADA == 0) {
            sequence++;
            gaps++;
        }

        struct tick *t = &f->ring[i & FEED_MASCARA];
        t->sequence = sequence;
        t->instrument = inst;
        /* Compra abaixo do meio, venda acima: é o que mantém o livro aberto. */
        t->price = meio[inst] + (lado == LIVRO_COMPRA ? -MEIO_SPREAD : MEIO_SPREAD);
        t->quantity = (uint32_t)((r >> 16) % 900) + 100;
        t->lado = lado;
        /* O carimbo é a ÚLTIMA coisa escrita antes de publicar: assim ele mede
         * a travessia, e não o tempo de montar o registro. */
        t->tsc = rte_rdtsc();

        /* release: garante que o conteúdo do tick fique visível ANTES do índice
         * que o anuncia. Sem esta ordem, o consumidor poderia ver o índice novo
         * e o tick antigo — a corrida clássica de anel produtor/consumidor. */
        atomic_store_explicit(&f->published, i + 1, memory_order_release);

        if (!rajada)
            spin_cycles(pausa);
    }

    printf("  publicados %" PRIu64 " ticks em %.1f ms\n", total,
           (double)(rte_rdtsc() - t_inicio) * 1e3 / (double)f->tsc_hz);
    printf("  lacunas de sequencia injetadas: %" PRIu64 " (perda SIMULADA)\n", gaps);
    if (gaps != f->lacunas_injetadas)
        fprintf(stderr, "  AVISO: previstas %" PRIu64 ", injetadas %" PRIu64 "\n",
                f->lacunas_injetadas, gaps);
    printf("  aguardando o assinante drenar...\n");
    fflush(stdout);

    while (atomic_load_explicit(&f->consumidos, memory_order_acquire) < total)
        rte_pause();

    printf("  assinante consumiu tudo. Aguardando ele encerrar...\n");
    fflush(stdout);

    /* O primário é dono da memória compartilhada e do socket de controle, então
     * sai POR ÚLTIMO. São DUAS esperas, e a distinção importa:
     *
     *   1. o assinante terminou de LER  -> sinalizado na memória compartilhada;
     *   2. o processo dele SUMIU        -> observado no diretório de runtime.
     *
     * Só a segunda evita o ruído de encerramento. Entre uma e outra o
     * secundário ainda está desmontando seus mapeamentos, e é justamente aí que
     * rte_eal_cleanup() do primário tentaria sincronizar com um processo que já
     * não responde ("Fail to recv reply ... mp_malloc_sync"). */
    const uint64_t limite_saida = rte_rdtsc() + (uint64_t)ESPERA_ASSINANTE_S * f->tsc_hz;
    while (atomic_load_explicit(&f->assinante_terminou, memory_order_acquire) == 0) {
        if (rte_rdtsc() > limite_saida) {
            fprintf(stderr, "  assinante nao sinalizou saida; encerrando assim mesmo.\n");
            break;
        }
        rte_pause();
    }

    int vivos = secundarios_vivos();
    while (vivos > 0) {
        if (rte_rdtsc() > limite_saida) {
            fprintf(stderr, "  ainda ha %d secundario(s) conectado(s); encerrando assim mesmo.\n",
                    vivos);
            break;
        }
        rte_delay_us_sleep(1000);
        vivos = secundarios_vivos();
    }

    printf("  todos os secundarios sairam. Encerrando o primario.\n\n");

    /* Repare no que NÃO está aqui: rte_memzone_free(mz).
     *
     * Em processo único, a ordem correta é liberar os objetos e só então chamar
     * rte_eal_cleanup(). No modelo MULTIPROCESSO entra uma restrição a mais:
     * liberar uma memzone compartilhada dispara uma sincronização com os
     * secundários (mp_malloc_sync). Se algum deles já estiver encerrando, a
     * requisição não é respondida e a EAL registra
     * "Fail to recv reply ... mp_malloc_sync". Foi o que aconteceu aqui na
     * primeira tentativa de encerramento ordenado.
     *
     * rte_eal_cleanup() libera a memzone junto com o resto, sem essa
     * negociação. A regra que fica: em multiprocesso, o primário espera os
     * secundários saírem e deixa a liberação para o cleanup. */
    rte_eal_cleanup();
    return 0;
}
