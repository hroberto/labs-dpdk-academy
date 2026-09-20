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
#include <cpuid.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

    printf("TLB real desta maquina, lida do CPUID\n\n");
    if (!e_amd()) {
        printf("  Processador nao-AMD: a decodificacao deste programa e especifica\n");
        printf("  da AMD (folhas 0x80000005/6/19 e o bit L2TlbSizeX32). Imprimir\n");
        printf("  numero errado seria repetir o defeito que este programa corrige.\n");
        /* 77 = PULADO no Meson: o requisito nao existe nesta maquina. */
        return 77;
    }

    const unsigned x = multiplicador_l2();

    if (__get_cpuid_max(0x80000000, NULL) < 0x80000019) {
        printf("  Folhas estendidas de TLB ausentes neste processador.\n");
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

    if (!__get_cpuid(0x80000019, &a, &b, &c, &d))      /* 1 GB: EAX L1, EBX L2 */
        return 77;
    const struct nivel l1_1g = {a & 0xfff, (a >> 16) & 0xfff};
    const struct nivel l2_1g = {b & 0xfff, (b >> 16) & 0xfff};

    printf("  pagina             L1 DTLB   L2 DTLB   alcance do L2\n");
    printf("  ----------------   -------   -------   -------------\n");
    imprimir("4 KB", l1_4k, l2_4k, 4096ull);
    imprimir("2 MB (hugepage)", l1_2m, l2_2m, 2ull << 20);
    imprimir("1 GB (hugepage)", l1_1g, l2_1g, 1ull << 30);

    printf("\n  multiplicador do L2 (L2TlbSizeX32): %ux\n", x);
    if (x > 1) {
        printf("  valores BRUTOS do CPUID: %u (4 KB) e %u (2 MB)\n", bruto_4k, bruto_2m);
        printf("\n  O kernel publica os brutos ate a versao 7.4. Confira:\n");
        printf("    grep -m1 'TLB size' /proc/cpuinfo\n");
        printf("  Se o numero de la nao bater com a coluna L2 acima, e por isso.\n");
    }

    printf("\n  Repare na linha de 1 GB: o segundo nivel guarda MUITO menos\n");
    printf("  entradas. A formula 'alcance = entradas x pagina' assume que o\n");
    printf("  numero de entradas nao muda com o tamanho da pagina -- premissa\n");
    printf("  que vale de 4 KB para 2 MB e QUEBRA em 1 GB.\n");
    return 0;
}
