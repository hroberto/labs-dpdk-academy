/* SPDX-License-Identifier: MIT
 *
 * Programa mínimo cuja medição NÃO acontece — e que por isso deve morrer.
 *
 * POR QUE ELE EXISTE
 *
 * `collect_or_fail()` é o adaptador usado por SETE programas de medição sem EAL.
 * Ele existe para uma coisa só: encerrar o processo quando a coleta não é
 * publicável, em vez de deixar o programa imprimir zero como se fosse tempo.
 *
 * Esse caminho de aborto passou a existir sem teste, e a ausência foi medida:
 * trocando `if (!collection_is_valid(e, n))` por `if (0)` -- isto é, desligando
 * o aborto --, a suíte inteira continuava VERDE. O teste de "coleta invalida
 * deve falhar" que já existia exercita o OUTRO caminho (`collect` +
 * `collection_is_valid`), usado pelos programas com EAL de pé, que não podem
 * chamar `exit()` sem pular `rte_eal_cleanup()`.
 *
 * Uma verificação que nunca falhou é indistinguível de uma que nunca dispara.
 * Este programa a faz disparar: a função de medição devolve 0.0 sempre, que é o
 * sintoma exato de medição que não aconteceu (thread que não subiu, relógio que
 * não andou). O teste correspondente é `should_fail : true` -- se este programa
 * um dia SAIR COM SUCESSO, a suíte fica vermelha, porque significa que o aborto
 * sumiu.
 */
#include "statistics.h"

/* Zero sempre: nenhuma medição ocorreu. Não é "rápido" -- é "não houve". */
static double nao_mediu(void)
{
    return 0.0;
}

int main(void)
{
    const struct statistics e = collect_or_fail(nao_mediu, DEFAULT_SAMPLES);
    /* Inalcançável se `collect_or_fail` cumprir o contrato. Publicar daqui é
     * exatamente o defeito que ele previne, então o programa o faz de propósito:
     * se esta linha executar, o `should_fail` do meson acusa. */
    printf("PUBLICOU O QUE NAO FOI MEDIDO: mediana %.3f\n", e.median);
    return 0;
}
