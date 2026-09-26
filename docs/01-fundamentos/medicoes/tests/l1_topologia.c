/* SPDX-License-Identifier: MIT
 *
 * A CPU parceira sai da topologia, e o núcleo físico tem identidade estável.
 *
 * POR QUE ESTE TESTE EXISTE
 *
 * Três lugares escolhiam a "outra CPU do mesmo domínio" por aritmética --
 * `a + 2`, ou o literal `2`. Nesta máquina acertam por coincidência do
 * enumerador; noutra topologia o instrumento que existe para comparar DENTRO
 * do domínio compara ENTRE domínios, com o rótulo errado.
 *
 * E `custo-paralelismo` deduplicava núcleos por `core_id` sozinho, que é
 * numerado POR PACOTE: em dois soquetes, o núcleo 3 de cada um tem o mesmo
 * número, e a fase que mede o caminho de memória com N núcleos usaria metade
 * da máquina.
 *
 * AS ASSERÇÕES DE `parceiro_no_dominio` SÃO SOBRE PROPRIEDADES, e não sobre um
 * número. A função consulta o sysfs real para os irmãos SMT, então exigir "a
 * resposta é 1" amarraria o teste a esta máquina -- e a máquina de CI não é a
 * de referência. O que ela PROMETE é verificável em qualquer lugar: a CPU
 * devolvida está na lista, não é `a`, e não é irmã SMT de `a`.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>

#include "topologia.h"

static int falhas;

static void caso(int n, const char *descricao, long obtido, long esperado)
{
    if (obtido != esperado) {
        printf("  AUTOTESTE %d FALHOU: %s\n    esperado %ld\n    obtido   %ld\n",
               n, descricao, esperado, obtido);
        falhas++;
    }
}

static int contem(const int *v, int n, int alvo)
{
    for (int i = 0; i < n; i++)
        if (v[i] == alvo)
            return 1;
    return 0;
}

int main(void)
{
    int v[ACADEMY_MAX_CPUS_LISTA];

    /* 1-4. As tres formas que o sysfs emite, e a mistura. */
    caso(1, "faixa simples", academy_expandir_lista("0-3", v, 64), 4);
    caso(2, "primeiro da faixa", v[0], 0);
    caso(3, "ultimo da faixa", v[3], 3);
    caso(4, "lista de faixas", academy_expandir_lista("0-2,8-10", v, 64), 6);
    caso(5, "a segunda faixa entrou", v[3], 8);
    caso(6, "cpu isolada", academy_expandir_lista("5", v, 64), 1);
    caso(7, "mistura de isolada e faixa", academy_expandir_lista("0,4-6", v, 64), 4);

    /* 8. O TETO E RESPEITADO. Uma lista maior que o vetor nao pode escrever
     *    alem dele -- e o sysfs de uma maquina grande emite listas longas. */
    caso(8, "respeita o teto do vetor", academy_expandir_lista("0-999", v, 16), 16);

    /* 9. Entrada vazia nao e faixa de tamanho um. */
    caso(9, "lista vazia devolve zero", academy_expandir_lista("", v, 64), 0);

    /* 10-12. A PREFERIDA SO E ACEITA SE SERVIR. E a diferenca entre
     *    continuidade e o numero magico de volta: numa lista que nao a contem,
     *    ela e ignorada. */
    const int dom[8] = {0, 1, 2, 3};
    const int irmaos[2] = {0, 12};
    caso(10, "a preferida serve quando esta no dominio",
         academy_parceiro_serve(0, 2, dom, 4, irmaos, 2), 1);
    caso(11, "nao serve se for a propria CPU",
         academy_parceiro_serve(0, 0, dom, 4, irmaos, 2), 0);
    caso(12, "nao serve se for irma SMT",
         academy_parceiro_serve(0, 12, dom, 4, irmaos, 2), 0);
    caso(13, "nao serve se estiver fora do dominio",
         academy_parceiro_serve(0, 7, dom, 4, irmaos, 2), 0);

    /* 13a-13c. AS GUARDAS MASCARAVAM UMAS AS OUTRAS, e tres mutantes
     *    sobreviveram por isso. Cada caso abaixo isola UMA delas:
     *
     *    - `thread_siblings_list` SEMPRE inclui a propria CPU, entao a
     *      conferencia de irmao ja descartava `a`. So com a lista de irmaos
     *      VAZIA -- sysfs mudo -- a guarda `c == a` tem trabalho;
     *    - o irmao SMT estava FORA do dominio sintetico, entao a conferencia
     *      de dominio o descartava antes. Aqui ele esta dentro. */
    caso(14, "com sysfs mudo, ainda recusa a propria CPU",
         academy_parceiro_serve(0, 0, dom, 4, irmaos, 0), 0);
    const int dom_com_irmao[4] = {0, 1, 2, 12};
    caso(15, "recusa o irmao SMT mesmo quando ele esta no dominio",
         academy_parceiro_serve(0, 12, dom_com_irmao, 4, irmaos, 2), 0);

    /* 13d. A PREFERIDA INVALIDA E IGNORADA. Sem este caso, um mutante que
     *    devolvesse a preferida sem conferir nada sobrevivia -- porque o unico
     *    caso anterior passava uma preferida que JA era valida. */
    char so_dois[8];
    snprintf(so_dois, sizeof(so_dois), "0-3");
    const int ignorada = academy_parceiro_no_dominio(0, so_dois, 999);
    caso(16, "preferida fora do dominio e ignorada", ignorada != 999, 1);
    caso(17, "e a resposta ainda e valida", ignorada >= 0 && ignorada <= 3, 1);

    /* 13e. O PACOTE ENTRA NA IDENTIDADE. Numa maquina de um soquete o efeito
     *    e invisivel, e por isso a composicao e funcao pura: aqui ela recebe
     *    dois pacotes sinteticos. Sem este caso, ignorar o pacote sobrevivia. */
    /* `volatile` PARA QUE A FUNCAO SEJA EXECUTADA, e nao dobrada.
     *
     * `academy_id_nucleo` e `static inline` com argumentos literais: o
     * compilador calcula tudo em tempo de compilacao, e a assercao vira uma
     * constante. O cppcheck acusou exatamente isso -- "Condition is always
     * false" --, e tinha razao: o teste afirmava a propriedade sem executar
     * nada. Com os argumentos vindo de memoria volatil, a chamada acontece. */
    volatile long pacote_a = 0, pacote_b = 1, core = 3, sem_pacote = -1;
    caso(18, "mesmo core em pacotes diferentes tem identidades diferentes",
         academy_id_nucleo(pacote_a, core) == academy_id_nucleo(pacote_b, core), 0);
    caso(19, "pacote ausente equivale ao soquete zero",
         academy_id_nucleo(sem_pacote, core) == academy_id_nucleo(pacote_a, core), 1);

    /* 14-17. AS PROPRIEDADES, na maquina que roda o teste. */
    char lista[64];
    snprintf(lista, sizeof(lista), "0-3");
    const int p = academy_parceiro_no_dominio(0, lista, -1);
    if (p < 0) {
        printf("  (sem parceiro valido em 0-3 nesta maquina: casos 20-23 pulados)\n");
    } else {
        const int n = academy_expandir_lista(lista, v, ACADEMY_MAX_CPUS_LISTA);
        caso(20, "o parceiro esta na lista do dominio", contem(v, n, p), 1);
        caso(21, "o parceiro nao e a propria CPU", p != 0, 1);
        int ir[64];
        const int ni = academy_irmaos_smt(0, ir, 64);
        caso(22, "o parceiro nao e irmao SMT", contem(ir, ni, p), 0);
        /* A PREFERIDA VALIDA E HONRADA: e o que preserva a serie historica. */
        caso(23, "uma preferida valida e devolvida",
             academy_parceiro_no_dominio(0, lista, p), p);
    }

    /* 18. NUCLEO FISICO: a propria CPU e sempre o mesmo nucleo que ela mesma,
     *     e o irmao SMT tambem -- e e por isso que a identidade serve para
     *     deduplicar. */
    long id_a = -1, id_b = -1;
    if (academy_nucleo_fisico(0, &id_a) == 0) {
        int ir[64];
        const int ni = academy_irmaos_smt(0, ir, 64);
        if (ni >= 2) {
            const int irmao = ir[0] == 0 ? ir[1] : ir[0];
            if (academy_nucleo_fisico(irmao, &id_b) == 0)
                caso(24, "irmaos SMT tem a mesma identidade de nucleo fisico",
                     id_a == id_b, 1);
        }
    }

    printf("  %d assercao(oes) falharam\n", falhas);
    return falhas ? 1 : 0;
}
