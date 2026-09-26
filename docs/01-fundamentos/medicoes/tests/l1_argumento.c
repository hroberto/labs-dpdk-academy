/* SPDX-License-Identifier: MIT
 *
 * Argumento de linha de comando: converte inteiro, ou recusa.
 *
 * POR QUE ESTE TESTE EXISTE
 *
 * `atoi("abc")` devolve 0 e `strtoull("12x", NULL, 10)` devolve 12. Nenhum dos
 * dois avisa, porque o valor de erro está DENTRO do domínio válido: zero é uma
 * CPU, doze é uma contagem de pacotes. Medido antes da correção:
 *
 *     stall_probe abc 1     -> media a CPU 0 e imprimia "cpu 0"
 *     pipeline_ring -n 12x  -> processava 12 pacotes, em silêncio
 *
 * E há o caso que passou pela PRIMEIRA versão deste módulo: `strtoull("-1")`
 * não é erro. A norma manda converter e negar, devolvendo o maior unsigned com
 * a string inteira consumida. `pipeline_ring -n -1` passou a processar 18
 * quintilhões de pacotes e o comando teve de ser morto.
 *
 * Um valor de erro que cai dentro do domínio válido só se detecta olhando a
 * CONVERSÃO, e não o resultado. É isso que estes casos fixam.
 */
#define _GNU_SOURCE
#include <stdio.h>

#include "argumento.h"

static int falhas;

static void caso(int n, const char *descricao, long obtido, long esperado)
{
    if (obtido != esperado) {
        printf("  AUTOTESTE %d FALHOU: %s\n    esperado %ld\n    obtido   %ld\n",
               n, descricao, esperado, obtido);
        falhas++;
    }
}

int main(void)
{
    unsigned long long u = 0;
    int i = 0;
    double d = 0.0;

    /* As mensagens vao para stderr; aqui so o veredito interessa. */
    if (freopen("/dev/null", "w", stderr) == NULL)
        return 2;   /* sem silenciar o stderr o veredito se perde no ruido */

    /* 1-3. O caminho feliz continua valendo: um teste que so recusa aprovaria
     *      uma funcao que recusa TUDO. */
    caso(1, "inteiro valido e aceito", academy_arg_u64("12", "t", 0, 100, &u), 0);
    caso(2, "e o valor chega inteiro", (long)u, 12);
    caso(3, "o limite superior e inclusivo", academy_arg_u64("100", "t", 0, 100, &u), 0);

    /* 4-6. Lixo textual: total e PARCIAL. O parcial e o traicoeiro, porque
     *      produz um numero plausivel em vez de um erro. */
    caso(4, "texto puro e recusado", academy_arg_u64("abc", "t", 0, 100, &u), -1);
    caso(5, "conversao PARCIAL e recusada", academy_arg_u64("12x", "t", 0, 100, &u), -1);
    caso(6, "string vazia e recusada", academy_arg_u64("", "t", 0, 100, &u), -1);

    /* 7-9. O SINAL NEGATIVO, que passou pela primeira versao.
     *      `strtoull("-1")` converte, nega, e devolve ULLONG_MAX sem erro. */
    caso(7, "menos um e recusado", academy_arg_u64("-1", "t", 0, 18446744073709551615ULL, &u), -1);
    caso(8, "negativo qualquer e recusado", academy_arg_u64("-42", "t", 0, 100, &u), -1);
    caso(9, "negativo e recusado mesmo com teto maximo",
         academy_arg_u64("-1", "t", 0, 18446744073709551615ULL, &u), -1);

    /* 10-11. Faixa e transbordo. */
    caso(10, "acima do teto e recusado", academy_arg_u64("101", "t", 0, 100, &u), -1);
    caso(11, "abaixo do piso e recusado", academy_arg_u64("0", "t", 1, 100, &u), -1);
    caso(12, "transbordo de unsigned long long e recusado",
         academy_arg_u64("99999999999999999999999", "t", 0, 18446744073709551615ULL, &u), -1);

    /* 13-16. O contrato de `int`, que e o do `stall_probe`: zero e uma CPU
     *        legitima, entao `atoi("abc") == 0` passava pela guarda `cpu < 0`. */
    caso(13, "inteiro valido e aceito", academy_arg_int("3", "cpu", 0, 63, &i), 0);
    caso(14, "e o valor chega", (long)i, 3);
    caso(15, "'abc' NAO vira a CPU 0", academy_arg_int("abc", "cpu", 0, 63, &i), -1);
    caso(16, "acima da faixa de CPU e recusado", academy_arg_int("9999", "cpu", 0, 63, &i), -1);

    /* 17-19. O `double` dos segundos: conversao parcial e nao-numero. */
    caso(17, "double valido e aceito", academy_arg_double("1.5", "s", &d), 0);
    caso(18, "'1.5s' e recusado (parcial)", academy_arg_double("1.5s", "s", &d), -1);
    caso(19, "'nan' e recusado", academy_arg_double("nan", "s", &d), -1);

    printf("  %d assercao(oes) falharam\n", falhas);
    return falhas ? 1 : 0;
}
