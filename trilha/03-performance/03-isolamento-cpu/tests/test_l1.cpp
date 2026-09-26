// SPDX-License-Identifier: MIT
// L1 — a aritmetica da janela e o parser de /proc/interrupts, sem EAL.
//
// O que se pode testar sem maquina nem privilegio: a conversao de quadro em
// nanossegundos, a classificacao de paradas em baldes, e a leitura do formato
// de /proc/interrupts. O que NAO se testa aqui e o valor das paradas -- isso
// depende da maquina e e o objeto da medicao, nao do teste.
#include <gtest/gtest.h>

extern "C" {
#include "gap_hist.h"
#include "procstat.h"
}

// --------------------------------------------------------------------------
// A janela: aritmetica do meio fisico, conferivel com lapis
// --------------------------------------------------------------------------

TEST(Janela, QuadroMinimoEm10GbeCustaSessentaESeteNanossegundos)
{
    // 64 B de quadro + 20 B de sobrecarga = 84 B = 672 bits.
    // A 10 Gbit/s, 672 / 10 = 67,2 ns. E o orcamento por pacote do modulo 01.
    EXPECT_NEAR(janela_ns_por_quadro(64, 10.0), 67.2, 0.01);
}

TEST(Janela, EscalaComDescritoresETaxa)
{
    // 512 descritores a 10 GbE: 512 x 67,2 ns = 34,4 us.
    EXPECT_NEAR(janela_ns(512, 64, 10.0), 34406.4, 1.0);
    // Dobrar os descritores dobra a janela.
    EXPECT_NEAR(janela_ns(1024, 64, 10.0), 2.0 * janela_ns(512, 64, 10.0), 0.01);
    // Dobrar a taxa a divide pela metade: o mesmo anel aguenta menos tempo.
    EXPECT_NEAR(janela_ns(512, 64, 20.0), janela_ns(512, 64, 10.0) / 2.0, 0.01);
}

TEST(Janela, QuadroMaiorAumentaAJanela)
{
    // Um quadro de 1518 B ocupa mais tempo na linha, entao o mesmo anel
    // absorve uma parada MAIOR. Quem dimensiona pensando so em 64 B esta no
    // caso pessimista, que e o certo -- mas vale saber que e pessimista.
    EXPECT_GT(janela_ns(512, 1518, 10.0), janela_ns(512, 64, 10.0));
}

TEST(Janela, TaxaInvalidaNaoDividePorZero)
{
    EXPECT_DOUBLE_EQ(janela_ns_por_quadro(64, 0.0), 0.0);
    EXPECT_DOUBLE_EQ(janela_ns_por_quadro(64, -1.0), 0.0);
}

// --------------------------------------------------------------------------
// O histograma
// --------------------------------------------------------------------------

TEST(Histograma, BaldeEOExpoenteDeDois)
{
    EXPECT_EQ(gap_balde_de(1u), 0u);
    EXPECT_EQ(gap_balde_de(2u), 1u);
    EXPECT_EQ(gap_balde_de(3u), 1u);   // [2,4) cai no balde 1
    EXPECT_EQ(gap_balde_de(4u), 2u);
    EXPECT_EQ(gap_balde_de(1023u), 9u);
    EXPECT_EQ(gap_balde_de(1024u), 10u);
}

TEST(Histograma, ZeroNaoEIndefinido)
{
    // Duas leituras consecutivas do relogio podem devolver o mesmo valor, e
    // `__builtin_clzll(0)` e indefinido. O balde 0 recebe o caso.
    EXPECT_EQ(gap_balde_de(0u), 0u);
    gap_hist h;
    gap_hist_iniciar(&h);
    gap_hist_somar(&h, 0u);
    EXPECT_EQ(h.amostras, 1u);
    EXPECT_EQ(h.maior, 0u);
}

TEST(Histograma, MaiorEExatoEnquantoOPercentilEPiso)
{
    gap_hist h;
    gap_hist_iniciar(&h);
    for (int i = 0; i < 99; i++)
        gap_hist_somar(&h, 10u);
    gap_hist_somar(&h, 5000u);   // uma excursao

    // O maior e guardado sem quantizacao: e o numero que se publica.
    EXPECT_EQ(h.maior, 5000u);
    // O percentil devolve o PISO do balde que o contem -- 4096, nao 5000.
    // Interpolar dentro do balde afirmaria precisao que o histograma nao tem.
    EXPECT_EQ(gap_percentil_piso(&h, 1000), 4096u);
    // E o corpo da distribuicao fica no balde de 8: [8,16) contem o 10.
    EXPECT_EQ(gap_percentil_piso(&h, 500), 8u);
}

TEST(Histograma, VazioNaoInventaPercentil)
{
    gap_hist h;
    gap_hist_iniciar(&h);
    EXPECT_EQ(gap_percentil_piso(&h, 990), 0u);
    EXPECT_EQ(gap_acima_da_janela(&h, 1000.0, 1.0), 0u);
}

TEST(Histograma, AcimaDaJanelaSubestimaDeProposito)
{
    gap_hist h;
    gap_hist_iniciar(&h);
    gap_hist_somar(&h, 3000u);   // balde 11: [2048, 4096)
    gap_hist_somar(&h, 9000u);   // balde 13: [8192, 16384)

    // Janela de 4000 ciclos: o balde 11 NAO e contado, porque parte dele esta
    // abaixo da janela. So o balde cujo piso ja excede entra.
    EXPECT_EQ(gap_acima_da_janela(&h, 4000.0, 1.0), 1u);
    // Com janela de 1000, os dois baldes tem piso acima e os dois contam.
    EXPECT_EQ(gap_acima_da_janela(&h, 1000.0, 1.0), 2u);
}

// --------------------------------------------------------------------------
// O parser de /proc/interrupts
// --------------------------------------------------------------------------

// Recorte real do formato, com as tres formas que aparecem: vetor numerado com
// descricao apos as contagens, vetor simbolico, e linha sem contagem nenhuma.
static const char *kAmostra =
    "           CPU0       CPU1       CPU2       CPU3\n"
    "  0:         31          0          0          0  IO-APIC   2-edge      timer\n"
    "  9:          0          0          0          0  IO-APIC   9-fasteoi   acpi\n"
    "113:      12345      54321          7          8  PCI-MSI   1048576-edge  nvme0q0\n"
    "NMI:          0          0          0          0  Non-maskable interrupts\n"
    "LOC:    1000000    1000001    1000002    1000003  Local timer interrupts\n"
    "TLB:        400        401        402        403  TLB shootdowns\n"
    "ERR:          0\n";

TEST(Procstat, NumeroDeCpusSaiDoCabecalho)
{
    proc_tabela t;
    ASSERT_EQ(proc_analisar(kAmostra, &t), 0);
    // Supor um numero fixo quebraria ao trocar de maquina, e quebraria calado.
    EXPECT_EQ(t.n_cpus, 4u);
}

TEST(Procstat, LeVetorNumeradoESimbolico)
{
    proc_tabela t;
    ASSERT_EQ(proc_analisar(kAmostra, &t), 0);
    EXPECT_EQ(proc_valor(&t, "0", 0), 31u);
    EXPECT_EQ(proc_valor(&t, "113", 1), 54321u);
    EXPECT_EQ(proc_valor(&t, "LOC", 3), 1000003u);
    EXPECT_EQ(proc_valor(&t, "TLB", 2), 402u);
}

TEST(Procstat, DescricaoDoVetorNaoViraContagem)
{
    proc_tabela t;
    ASSERT_EQ(proc_analisar(kAmostra, &t), 0);
    // A linha do IO-APIC tem `2-edge` depois das quatro contagens. Um parser
    // que lesse ate o fim da linha transformaria o `2` numa quinta CPU.
    EXPECT_EQ(proc_valor(&t, "0", 3), 0u);
    EXPECT_EQ(proc_valor(&t, "9", 3), 0u);
}

TEST(Procstat, RotuloAusenteValeZero)
{
    proc_tabela t;
    ASSERT_EQ(proc_analisar(kAmostra, &t), 0);
    // `RES` so aparece depois do primeiro IPI de reagendamento da maquina.
    // Ausente significa que nunca disparou, e zero e a resposta certa.
    EXPECT_EQ(proc_valor(&t, "RES", 0), 0u);
}

TEST(Procstat, CabecalhoSemCpuEErro)
{
    proc_tabela t;
    EXPECT_EQ(proc_analisar("nao e o arquivo esperado\n  0: 1 2 3\n", &t), -1);
}

TEST(Procstat, DeltaOrdenaEIgnoraContadorQueNaoCresceu)
{
    proc_tabela antes, depois;
    ASSERT_EQ(proc_analisar(kAmostra, &antes), 0);

    static const char *kDepois =
        "           CPU0       CPU1       CPU2       CPU3\n"
        "113:      12355      54321          7          8  PCI-MSI   1048576-edge  nvme0q0\n"
        "LOC:    1000500    1000001    1000002    1000003  Local timer interrupts\n"
        "TLB:        402        401        402        403  TLB shootdowns\n";
    ASSERT_EQ(proc_analisar(kDepois, &depois), 0);

    proc_delta d[8];
    const size_t n = proc_delta_cpu(&antes, &depois, 0, d, 8);
    ASSERT_EQ(n, 3u);
    // Maior delta primeiro: o tick domina, como se espera de uma CPU com tick.
    EXPECT_STREQ(d[0].rotulo, "LOC");
    EXPECT_EQ(d[0].delta, 500u);
    EXPECT_STREQ(d[1].rotulo, "113");
    EXPECT_EQ(d[1].delta, 10u);
    EXPECT_STREQ(d[2].rotulo, "TLB");
    EXPECT_EQ(d[2].delta, 2u);
}

TEST(Procstat, DeltaIgnoraCpuForaDaTabela)
{
    proc_tabela t;
    ASSERT_EQ(proc_analisar(kAmostra, &t), 0);
    proc_delta d[8];
    EXPECT_EQ(proc_delta_cpu(&t, &t, 99, d, 8), 0u);
}
