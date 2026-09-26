/* SPDX-License-Identifier: MIT
 *
 * Converter argumento de linha de comando, ou recusar.
 *
 * POR QUE ISTO EXISTE
 *
 * `atoi("abc")` devolve 0. `strtoull("12x", NULL, 10)` devolve 12. Nenhum dos
 * dois tem como avisar, porque o valor de erro está DENTRO do domínio válido:
 * zero é uma CPU, zero é um tamanho de cache, doze é uma contagem de pacotes.
 *
 * O sintoma medido, antes desta correção:
 *
 *     stall_probe abc 1   -> mede a CPU 0, imprime "cpu 0", sai com 0
 *     pipeline_ring -n 12x -> processa 12 pacotes, sem dizer nada
 *
 * É a mesma família que atravessa esta auditoria inteira: o programa declara
 * uma condição -- a CPU medida, o tamanho da amostra -- que não é a que foi
 * pedida. E aqui é pior que nas outras, porque quem digitou o comando acredita
 * ter pedido outra coisa.
 *
 * A CONVERSÃO PARCIAL TAMBÉM É RECUSADA, e não só a total. `12x` é o caso
 * traiçoeiro: `atoi` e `strtoull` aceitam o prefixo e descartam o resto, então
 * um erro de digitação vira um número plausível em vez de um erro.
 */
#ifndef ACADEMY_ARGUMENTO_H
#define ACADEMY_ARGUMENTO_H

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

/* 0 e preenche `fora`; -1 recusa e explica em stderr. `nome` vai na mensagem
 * para que quem leu o comando saiba QUAL argumento estava errado. */
static inline int academy_arg_u64(const char *texto, const char *nome,
                                  unsigned long long minimo,
                                  unsigned long long maximo,
                                  unsigned long long *fora)
{
    /* O SINAL E RECUSADO AQUI, e nao em cada chamador.
     *
     * `strtoull("-1", ...)` nao e erro: a norma manda converter e NEGAR, e o
     * resultado e ULLONG_MAX com `fim` no final da string. Nada acusa. Quem
     * aceitasse a faixa ate UINT64_MAX -- e havia dois -- recebia o maior
     * valor possivel de um usuario que digitou "menos um".
     *
     * Medido antes: `pipeline_ring -n -1` nao reclamava e passava a processar
     * 18 quintilhoes de pacotes; o comando teve de ser morto.
     *
     * Fechar a classe aqui e melhor que confiar no teto de cada chamador, que
     * capturaria o complemento por acidente e so quando o teto fosse baixo. */
    if (texto[0] == '-') {
        fprintf(stderr, "%s: '%s' e negativo, e este argumento nao aceita sinal\n",
                nome, texto);
        return -1;
    }

    char *fim = NULL;
    errno = 0;
    const unsigned long long v = strtoull(texto, &fim, 10);

    if (fim == texto || *fim != '\0') {
        fprintf(stderr, "%s: '%s' nao e um numero inteiro\n", nome, texto);
        return -1;
    }
    if (errno == ERANGE) {
        fprintf(stderr, "%s: '%s' esta fora da faixa representavel\n", nome, texto);
        return -1;
    }
    if (v < minimo || v > maximo) {
        fprintf(stderr, "%s: %llu fora da faixa aceita [%llu, %llu]\n",
                nome, v, minimo, maximo);
        return -1;
    }
    *fora = v;
    return 0;
}

static inline int academy_arg_int(const char *texto, const char *nome,
                                  int minimo, int maximo, int *fora)
{
    unsigned long long v;
    /* A mensagem aqui nomeia a FAIXA, que e mais util para um inteiro com
     * minimo declarado; `academy_arg_u64` tambem recusa o sinal, e recusar
     * duas vezes e melhor que depender de qual das duas foi chamada. */
    if (texto[0] == '-') {
        fprintf(stderr, "%s: '%s' e negativo, e a faixa aceita comeca em %d\n",
                nome, texto, minimo);
        return -1;
    }
    if (academy_arg_u64(texto, nome, (unsigned long long)(minimo < 0 ? 0 : minimo),
                        (unsigned long long)maximo, &v) != 0)
        return -1;
    *fora = (int)v;
    return 0;
}

/* Para `segundos`, que nao e inteiro. Recusa NaN, infinito e conversao
 * parcial; a faixa fica com quem chama, porque cada programa tem a sua. */
static inline int academy_arg_double(const char *texto, const char *nome, double *fora)
{
    char *fim = NULL;
    errno = 0;
    const double v = strtod(texto, &fim);
    if (fim == texto || *fim != '\0') {
        fprintf(stderr, "%s: '%s' nao e um numero\n", nome, texto);
        return -1;
    }
    if (errno == ERANGE || !(v == v) || v > 1e300 || v < -1e300) {
        fprintf(stderr, "%s: '%s' esta fora da faixa representavel\n", nome, texto);
        return -1;
    }
    *fora = v;
    return 0;
}

#endif /* ACADEMY_ARGUMENTO_H */
