/* SPDX-License-Identifier: MIT
 *
 * Escolher a CPU parceira pela topologia lida, e não por aritmética.
 *
 * POR QUE ISTO EXISTE
 *
 * Três lugares deste repositório decidiam qual CPU usar como "a outra do mesmo
 * domínio de cache" somando 2 ao primeiro núcleo, ou fixando o número 2:
 *
 *   `custo-comunicacao` lia `shared_cpu_list` do L3, imprimia os domínios na
 *   tela, e então fazia `cpu_local_b = a + 2` -- ignorando o que acabara de
 *   ler. `custo-mckenney` nem lia: `cpu_remoto = 2`, constante.
 *
 * Nesta máquina as duas escolhas acertam por coincidência do enumerador: o
 * CCD0 é `0-5,12-17`, então 0 e 2 são núcleos físicos distintos do mesmo
 * domínio. Noutra topologia, o instrumento que existe para comparar DENTRO do
 * domínio compara ENTRE domínios, com o rótulo errado -- e um número certo por
 * acidente de layout é um número errado esperando outra máquina.
 *
 * AS DUAS CONDIÇÕES, e as duas importam:
 *
 *   - mesmo domínio de L3, que É a variável do experimento;
 *   - núcleo físico distinto, senão a medição troca distância de cache por
 *     disputa das unidades de execução do mesmo núcleo.
 *
 * `thread_siblings_list` SEMPRE inclui a própria CPU, então a segunda condição
 * já descarta `a`. A conferência explícita de `c != a` existe para o caso em
 * que o sysfs não responde: sem ela, a lista de irmãos volta vazia e o laço
 * escolheria a própria CPU, comparando um núcleo consigo mesmo sob o rótulo
 * "mesmo domínio".
 */
#ifndef ACADEMY_TOPOLOGIA_H
#define ACADEMY_TOPOLOGIA_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ACADEMY_MAX_CPUS_LISTA 256

/* "0-5,12-17" -> {0,1,2,3,4,5,12,13,14,15,16,17}. Devolve quantas escreveu. */
static inline int academy_expandir_lista(const char *lista, int *saida, int max)
{
    int n = 0;
    const char *p = lista;
    while (*p != '\0' && n < max) {
        char *fim;
        const long ini = strtol(p, &fim, 10);
        if (fim == p)
            break;
        long ate = ini;
        if (*fim == '-') {
            p = fim + 1;
            ate = strtol(p, &fim, 10);
        }
        for (long c = ini; c <= ate && n < max; c++)
            saida[n++] = (int)c;
        if (*fim == ',')
            fim++;
        p = fim;
    }
    return n;
}

/* Irmãos SMT de `cpu`, lidos do sysfs. Devolve 0 se não deu para ler -- e a
 * lista vazia é o caso em que a guarda `c != a` do parceiro passa a valer. */
static inline int academy_irmaos_smt(int cpu, int *saida, int max)
{
    char caminho[128], linha[256];
    snprintf(caminho, sizeof(caminho),
             "/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list", cpu);
    FILE *f = fopen(caminho, "r");
    if (f == NULL)
        return 0;
    const char *lida = fgets(linha, sizeof(linha), f);
    fclose(f);
    if (lida == NULL)
        return 0;
    return academy_expandir_lista(linha, saida, max);
}

/* Compõe pacote e núcleo numa identidade única.
 *
 * FUNÇÃO PURA DE PROPÓSITO: numa máquina de um soquete `pacote` é 0, e a
 * composição fica indistinguível de usar `core` sozinho -- o defeito que ela
 * corrige não tem como aparecer aqui. Separada assim, o teste a exercita com
 * dois pacotes sintéticos sem precisar de dois soquetes.
 *
 * SEM `physical_package_id` o resultado ainda serve: é o único caso em que o
 * sysfs costuma omiti-lo, e assumir um soquete ali é verdade. */
static inline long academy_id_nucleo(long pacote, long core)
{
    return ((pacote < 0 ? 0L : pacote) << 16) | core;
}

/* Identidade do NÚCLEO FÍSICO de uma CPU, estável entre soquetes.
 *
 * `core_id` sozinho NÃO identifica um núcleo: ele é numerado por pacote, e em
 * máquina de dois soquetes o núcleo 3 do pacote 0 e o núcleo 3 do pacote 1
 * compartilham o mesmo `core_id`. Quem deduplica só por ele conta um núcleo
 * onde há dois, e mede metade da máquina achando que mediu inteira.
 *
 * A máquina de referência tem um soquete, então aqui não há efeito -- o que
 * torna este um defeito que só aparece em quem reproduzir o estudo noutro
 * lugar, que é exatamente o público do material.
 *
 * Devolve 0 e preenche `id` com `pacote << 16 | core`, ou -1 se o sysfs não
 * expuser os dois campos. */
static inline int academy_nucleo_fisico(int cpu, long *id)
{
    char caminho[128];
    long pacote = -1, core = -1;

    snprintf(caminho, sizeof(caminho),
             "/sys/devices/system/cpu/cpu%d/topology/physical_package_id", cpu);
    FILE *f = fopen(caminho, "r");
    if (f != NULL) {
        if (fscanf(f, "%ld", &pacote) != 1)
            pacote = -1;
        fclose(f);
    }
    snprintf(caminho, sizeof(caminho),
             "/sys/devices/system/cpu/cpu%d/topology/core_id", cpu);
    f = fopen(caminho, "r");
    if (f == NULL)
        return -1;
    if (fscanf(f, "%ld", &core) != 1)
        core = -1;
    fclose(f);
    if (core < 0)
        return -1;

    *id = academy_id_nucleo(pacote, core);
    return 0;
}

/* `c` serve de parceira de `a`: está no domínio e é NÚCLEO FÍSICO DISTINTO.
 *
 * A LISTA DE IRMÃOS NÃO BASTA SOZINHA, e a primeira versão desta função
 * dependia só dela. Quando `thread_siblings_list` não pode ser lido, a lista
 * volta vazia, o laço de irmãos não rejeita nada, e qualquer `c != a` do
 * domínio era aceito -- sem prova de estar noutro núcleo físico. O programa
 * então compararia dois irmãos SMT sob o rótulo "mesmo domínio", medindo
 * disputa por unidades de execução e chamando isso de distância de cache.
 *
 * A identidade física fecha isso: `academy_nucleo_fisico` combina pacote e
 * núcleo, e dois irmãos SMT compartilham os dois. Quando ela responde, é ela
 * que decide; a lista de irmãos fica como segunda barreira, útil no caso em
 * que o `core_id` não esteja exposto e o `thread_siblings_list` esteja.
 *
 * E SE NENHUMA DAS DUAS RESPONDER, RECUSA. Não dá para demonstrar a condição
 * do experimento, e aceitar mesmo assim seria inferir por ausência. */
/* A DECISÃO, separada da LEITURA -- e a separação existe por causa do teste.
 *
 * Com o sysfs lido aqui dentro, o caso que prova a participação da identidade
 * física só roda numa máquina cuja CPU 12 seja irmã da 0. Na de referência ele
 * mata o mutante; noutro runner o bloco simplesmente não executa, e a
 * regressão deixa de existir sem que nada acuse -- que é a mesma classe de
 * "teste que parece cobrir e não cobre" que esta auditoria encontrou várias
 * vezes.
 *
 * Recebendo os identificadores prontos, todos os ramos ficam exercitáveis com
 * valores sintéticos, em qualquer máquina. */
static inline int academy_parceiro_serve_com_ids(int a, int c, const int *dom, int n,
                                                 const int *irmaos, int n_irmaos,
                                                 int tem_id, long id_a, long id_c)
{
    if (c == a)
        return 0;
    int no_dominio = 0;
    for (int i = 0; i < n; i++)
        if (dom[i] == c) {
            no_dominio = 1;
            break;
        }
    if (!no_dominio)
        return 0;

    if (tem_id)
        return id_a != id_c;

    /* Sem identidade física: a lista de irmãos é o que resta, e ela precisa
     * EXISTIR para valer como prova. Vazia, não prova nada. */
    if (n_irmaos <= 0)
        return 0;
    for (int j = 0; j < n_irmaos; j++)
        if (irmaos[j] == c)
            return 0;
    return 1;
}

static inline int academy_parceiro_serve(int a, int c, const int *dom, int n,
                                         const int *irmaos, int n_irmaos)
{
    long id_a = -1, id_c = -1;
    const int tem_id = academy_nucleo_fisico(a, &id_a) == 0 &&
                       academy_nucleo_fisico(c, &id_c) == 0;
    return academy_parceiro_serve_com_ids(a, c, dom, n, irmaos, n_irmaos,
                                          tem_id, id_a, id_c);
}

/* A CPU do MESMO domínio, em núcleo físico distinto de `a`. -1 se não houver.
 *
 * `preferida` É CONTINUIDADE, E NÃO SUPERSTIÇÃO -- e a distinção é o ponto.
 *
 * O defeito que este módulo corrige era PRESUMIR uma CPU sem conferir nada.
 * Trocar a presunção por "a primeira válida da lista" corrigiria isso e, nesta
 * máquina, mudaria o par medido de `0 <-> 2` para `0 <-> 1` -- ambos válidos,
 * ambos no CCD0, em núcleos físicos distintos. O custo seria gratuito: 11
 * coletas arquivadas e os blocos publicados carregam o rótulo com `2`, e a
 * série daquele rótulo passaria a comparar contra nada.
 *
 * Então a chamada oferece a CPU historicamente usada, e ela só é aceita se a
 * TOPOLOGIA a confirmar. Não é o número mágico de volta: antes ele era usado
 * sem conferência e em qualquer máquina; agora é uma preferência que precisa
 * passar nas mesmas três condições que qualquer outra candidata, e numa
 * topologia onde não passe, o programa escolhe outra -- ou recusa medir.
 *
 * `preferida < 0` pede simplesmente a primeira válida. */
static inline int academy_parceiro_no_dominio(int a, const char *lista_dominio, int preferida)
{
    int dom[ACADEMY_MAX_CPUS_LISTA], irmaos[64];
    const int n = academy_expandir_lista(lista_dominio, dom, ACADEMY_MAX_CPUS_LISTA);
    const int n_irmaos = academy_irmaos_smt(a, irmaos, 64);

    if (preferida >= 0 && academy_parceiro_serve(a, preferida, dom, n, irmaos, n_irmaos))
        return preferida;

    for (int i = 0; i < n; i++)
        if (academy_parceiro_serve(a, dom[i], dom, n, irmaos, n_irmaos))
            return dom[i];
    return -1;
}

#endif /* ACADEMY_TOPOLOGIA_H */
