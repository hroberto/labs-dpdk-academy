/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — quantas entradas a TLB desta máquina tem, de verdade.
 *
 * POR QUE ISTO EXISTE
 *
 * O módulo 01 afirma que o alcance da TLB decide o custo da tradução, e que o
 * alcance é `entradas × tamanho da página`. O primeiro fator precisa vir de
 * algum lugar — e o lugar óbvio, `/proc/cpuinfo`, ESTÁ ERRADO nesta máquina.
 *
 * A partir do Zen 5 a AMD passou a codificar o tamanho do último nível de TLB
 * em MÚLTIPLOS DE 32, com um bit (`L2TlbSizeX32`, CPUID 0x80000021 EAX[14])
 * mandando o software multiplicar. O Linux não checa esse bit até o 7.4: ele
 * publica os valores brutos, e quem ler `/proc/cpuinfo` calcula o alcance 32x
 * menor que o real.
 *
 * Este programa pergunta ao processador em vez de ao kernel. Não mede tempo:
 * lê uma propriedade declarada do hardware. Por isso não usa `statistics.h` e
 * não tem dispersão — não há amostra, há um fato.
 *
 * LIMITE DECLARADO
 *
 * A decodificação das folhas 0x80000005/6/19 e do bit X32 é ESPECÍFICA DA AMD.
 * Em processador Intel estas folhas existem mas significam outra coisa, e o
 * programa recusa em vez de imprimir número errado — que é o defeito que ele
 * existe para corrigir.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* GUARDA DE ARQUITETURA, e ela existe porque a porta de entrada promete arm64.
 *
 * `<cpuid.h>` e `__get_cpuid` sao exclusivos de x86: em AArch64 este arquivo
 * nao compila, e ele era registrado no meson sem condicao nenhuma. O
 * `README.md` declara "Linux x86_64 ou arm64" como requisito, e a arvore nao
 * sustentava a segunda metade -- o mesmo desencontro que o `cpu_pause.h`
 * corrigiu para a dica de espera.
 *
 * Fora de x86 o programa COMPILA e PULA com 77. Nao compilar seria pior que
 * pular: quebraria a build inteira num alvo que o projeto diz suportar, e a
 * unica coisa que falta ali e este instrumento, nao o material. */
#if !defined(__x86_64__) && !defined(__i386__)

int main(void)
{
    printf("PULADO: a leitura da TLB por CPUID e especifica de x86.\n");
    printf("  Esta arquitetura expoe a geometria da TLB por outro caminho\n");
    printf("  (em AArch64, os registradores de ID do sistema), e este programa\n");
    printf("  nao o implementa. O modulo 01 publica o alcance da TLB medido\n");
    printf("  na maquina de referencia, que e x86-64.\n");
    return 77;   /* PULADO para o Meson, e nao sucesso */
}

#else

#include <cpuid.h>

/* Um nível de TLB, já com o multiplicador aplicado. */
struct nivel {
    unsigned itlb, dtlb;
};

static int e_amd(void)
{
    unsigned a, b, c, d;
    char v[13] = {0};
    if (!__get_cpuid(0, &a, &b, &c, &d))
        return 0;
    memcpy(v, &b, 4);
    memcpy(v + 4, &d, 4);
    memcpy(v + 8, &c, 4);
    return strcmp(v, "AuthenticAMD") == 0;
}

/* CPUID 0x80000021 EAX[14]: quando ligado, os campos do L2 valem x32. */
static unsigned multiplicador_l2(void)
{
    unsigned a, b, c, d;
    if (__get_cpuid_max(0x80000000, NULL) < 0x80000021)
        return 1;
    if (!__get_cpuid(0x80000021, &a, &b, &c, &d))
        return 1;
    return ((a >> 14) & 1) ? 32u : 1u;
}

static void imprimir(const char *rot, struct nivel l1, struct nivel l2,
                     unsigned long long pagina)
{
    const double alcance = (double)l2.dtlb * (double)pagina;
    printf("  %-18s %7u %9u   %10.0f %s\n", rot, l1.dtlb, l2.dtlb,
           alcance >= (1ull << 30) ? alcance / (1ull << 30) : alcance / (1ull << 20),
           alcance >= (1ull << 30) ? "GB" : "MB");
}

int main(void)
{
    /* Inicializados porque `__get_cpuid` deixa os registradores INTOCADOS
     * quando a folha nao existe. Ler lixo da pilha e publica-lo como tamanho de
     * TLB seria a mesma classe de defeito que este programa corrige. */
    unsigned a = 0, b = 0, c = 0, d = 0;

    printf("Real TLB of this machine, read from CPUID\n\n");
    if (!e_amd()) {
        printf("  Non-AMD processor: this program's decoding is AMD-specific\n");
        printf("  (leaves 0x80000005/6/19 and the L2TlbSizeX32 bit). Printing a\n");
        printf("  wrong number would repeat the very defect this program corrects.\n");
        /* 77 = PULADO no Meson: o requisito nao existe nesta maquina. */
        return 77;
    }

    const unsigned x = multiplicador_l2();

    if (__get_cpuid_max(0x80000000, NULL) < 0x80000019) {
        printf("  Extended TLB leaves absent on this processor.\n");
        return 77;
    }

    if (!__get_cpuid(0x80000005, &a, &b, &c, &d))      /* L1: EBX 4 KB, EAX 2 MB */
        return 77;
    const struct nivel l1_4k = {b & 0xff, (b >> 16) & 0xff};
    const struct nivel l1_2m = {a & 0xff, (a >> 16) & 0xff};

    if (!__get_cpuid(0x80000006, &a, &b, &c, &d))      /* L2: EBX 4 KB, EAX 2 MB */
        return 77;
    const unsigned bruto_4k = (b >> 16) & 0xfff, bruto_2m = (a >> 16) & 0xfff;
    const struct nivel l2_4k = {(b & 0xfff) * x, bruto_4k * x};
    const struct nivel l2_2m = {(a & 0xfff) * x, bruto_2m * x};

    /* A LINHA DE 1 GB TAMBEM LEVA O MULTIPLICADOR, e conferir isso custou uma
     * conclusao errada antes de custar a certa.
     *
     * A especificacao de CPUID (25481, de 2008) descreve o campo como
     * "L2DTlb1GSize. L2 data TLB number of entries for 1-GB pages" -- mas ela
     * antecede o Zen 5 e o bit L2TlbSizeX32, entao nao decide nada aqui.
     *
     * Quem decide e o hardware descrito pelo fabricante. O Software
     * Optimization Guide para o Zen 5 traz "an additional 4-way
     * set-associative 1G page L2 DTLB with 1024 entries". Esta maquina reporta
     * tamanho BRUTO 32 e associatividade 4:
     *
     *     32 x 32 = 1024 entradas, 4-way  -- bate nos dois campos.
     *
     * Sem o multiplicador dariam 32 entradas, e a associatividade continuaria
     * 4-way: so o par tamanho+associatividade fecha, e ele so fecha com o x32.
     *
     * O patch do Linux nao serve de referencia para esta folha: o
     * `cpu_detect_tlb_amd` nao le 0x80000019. Os numeros "64, 64 e 32" que
     * circularam sobre esse patch sao 4 KB, 2 MB e 4 MB -- o 4 MB do kernel e
     * derivado como `2m >> 1`.
     */
    if (!__get_cpuid(0x80000019, &a, &b, &c, &d))      /* 1 GB: EAX L1, EBX L2 */
        return 77;
    const struct nivel l1_1g = {a & 0xfff, (a >> 16) & 0xfff};
    const struct nivel l2_1g = {(b & 0xfff) * x, ((b >> 16) & 0xfff) * x};

    printf("  page               L1 DTLB   L2 DTLB   L2 reach\n");
    printf("  ----------------   -------   -------   --------\n");
    imprimir("4 KB", l1_4k, l2_4k, 4096ull);
    imprimir("2 MB (hugepage)", l1_2m, l2_2m, 2ull << 20);
    imprimir("1 GB (hugepage)", l1_1g, l2_1g, 1ull << 30);

    printf("\n  L2 multiplier (L2TlbSizeX32): %ux\n", x);
    if (x > 1) {
        printf("  RAW CPUID values: %u (4 KB) and %u (2 MB)\n", bruto_4k, bruto_2m);
        printf("\n  The kernel publishes the raw values up to version 7.4. Check:\n");
        printf("    grep -m1 'TLB size' /proc/cpuinfo\n");
        printf("  If the number there does not match the L2 column above, this is why.\n");
    }

    printf("\n  Note the 1 GB row: a SEPARATE structure, 4-way, 1024 entries.\n");
    printf("  The formula 'reach = entries x page' assumes the number of\n");
    printf("  entries does not change with page size -- a premise that holds\n");
    printf("  from 4 KB to 2 MB and BREAKS at 1 GB -- by a factor of 4,\n");
    printf("  not by the 512x the page size alone would suggest.\n");
    return 0;
}

#endif /* x86 */
