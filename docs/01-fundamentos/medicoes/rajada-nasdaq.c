/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Nível 1 — quantos descritores o anel de RX precisa ter para absorver rajada.
 *
 * O QUE ESTE PROGRAMA RESPONDE
 *
 * O módulo publica o orçamento por pacote e mede o que acontece quando ele
 * estoura (`orcamento-estourado.c`). Ficou faltando a pergunta que um projeto
 * de verdade faz antes disso: **quantos buffers reservar**. Este programa
 * responde comparando um anel convencional com um expandido, sob chegada em
 * RAJADA.
 *
 * POR QUE A CHEGADA AQUI É ALEATÓRIA, E O `orcamento-estourado.c` NÃO É
 *
 * Aquele programa faz a chegada vencer por PRAZO FIXO: um pacote a cada
 * `orçamento` nanossegundos. Chegada determinística tem variabilidade ~0, e a
 * consequência está publicada na §11: a perda fica em 0,0 % até ρ = 0,78 e só
 * aparece perto de ρ = 1. É correto — e é o caso mais otimista que existe.
 *
 * Tráfego real não é assim. Aqui a chegada é um processo ALEATÓRIO e
 * TEMPORALMENTE CONCENTRADO: dois estados, um de silêncio relativo e um de
 * rajada na velocidade do enlace, com permanência em cada estado sorteada de
 * uma exponencial. Entre os dois estados a taxa instantânea muda por duas
 * ordens de grandeza, embora a MÉDIA DE LONGO PRAZO seja a mesma.
 *
 * O MECANISMO DA PERDA AQUI NAO E O DE KINGMAN. Durante a rajada rho passa de
 * 1, e o que governa e o acumulo: dQ/dt = lambda_rajada - mu, cujo integral e
 * (lambda_rajada - mu) x T_rajada. Kingman e aproximacao de trafego pesado
 * para fila ESTAVEL e INFINITA, e supoe chegada de RENOVACAO -- um processo de
 * dois estados tem intervalos correlacionados, entao `ca2` sozinho nao captura
 * a dependencia temporal que o estado modulador introduz.
 *
 * `ca2` continua sendo medido, e vale como EVIDENCIA da diferenca de
 * variabilidade entre os dois cenarios. Nao como fundamento da perda.
 *
 * DE ONDE VÊM AS TAXAS, E O QUE A FONTE NÃO DIZ
 *
 * Duas publicações da Nasdaq, com a coluna exata para quem quiser conferir:
 *
 *   - `bandwidthreport.pdf`, linha "NASDAQ TotalView-ITCH 4.1": coluna
 *     "Standard Bandwidth Recommendation - Current" traz 61 Mb e a coluna
 *     "- New" traz 67 Mb, com data de vigência 10/1/2010. O programa usa 67.
 *   - especificação do TotalView-ITCH FPGA: "Given the unshaped network
 *     traffic, NASDAQ OMX is requiring firms to have 10 Gb or 40 Gb network
 *     connection into the Carteret, NJ data center".
 *
 * TRES RESSALVAS, porque o que a fonte NAO diz importa tanto quanto o que diz:
 *
 * 1. 67 Mb e RECOMENDACAO DE BANDA, nao media medida. O documento nao declara
 *    a janela sobre a qual a recomendacao foi calculada. Usa-la como media de
 *    longo prazo e ESCOLHA DE MODELAGEM, declarada aqui. Se a recomendacao for
 *    baseada em pico -- e recomendacao de banda costuma ser --, a media real e
 *    MENOR, a razao de ciclo cai, e as rajadas ficam ainda mais concentradas
 *    do que neste modelo. O viés aponta para o lado confortavel.
 *
 * 2. O enlace de 10 Gb e EXIGENCIA DE CONEXAO, nao taxa observada. Que o feed
 *    seja `unshaped` nao prova que ele satura 10 Gb/s. Aqui, 10 Gb/s e o
 *    CENARIO-LIMITE DO ENLACE: o pior caso que a infraestrutura permite, nao
 *    uma medicao do feed. A especificacao so diz que o padrao "reflects true
 *    market volumes at all points during the trading day".
 *
 * 3. A FAQ do produto FPGA diz, textualmente: "Nasdaq does not have a
 *    specific bandwidth recommendation for the TotalView-ITCH FPGA product."
 *    Ou seja: os 67 Mb sao do produto de SOFTWARE, e para o FPGA -- que e o
 *    feed nao moldado -- a bolsa nao publica recomendacao nenhuma. Usar os
 *    67 Mb como media do FPGA e, mais uma vez, escolha de modelagem.
 *
 *    A mesma FAQ da a orientacao que o cenario B usa: "Nasdaq would simply
 *    advise TotalView-ITCH FPGA firms to be prepared to handle milli-second
 *    data bursts of up to 2,000 messages."
 *
 *    E ainda: "Nasdaq advises all TotalView-ITCH FPGA clients to be prepared
 *    to handle packets up to 1,500 bytes in length", porque "the packet sizes
 *    may be significantly larger during peak market periods".
 *
 *    ATENCAO A CAMADA: a frase nao diz se os 1500 B sao contados no quadro
 *    Ethernet, no pacote IP ou na carga UDP. O programa usa a leitura mais
 *    conservadora (carga + UDP + IP + Ethernet), e o que se pode afirmar com
 *    seguranca e so o obvio: 32 x 40 = 1280 B fica abaixo do limite sob
 *    qualquer leitura, e 64 x 40 = 2560 B passa sob qualquer uma. Calcular o
 *    maximo EXATO de mensagens por pacote exigiria saber a convencao.
 *
 * O QUE ESTE PROGRAMA NÃO É
 *
 * **Não é medição de NIC.** Não há rede, não há DPDK e não há driver: é
 * simulação de eventos discretos, com relógio virtual. O que vem desta máquina
 * é UM número — o custo real de processar um pacote, medido no início da
 * execução — e é ele que define a taxa de drenagem. O resto é o processo de
 * chegada, que é sorteado.
 *
 * Simulação foi escolhida por necessidade, não por conveniência: reproduzir
 * 4,5 milhões de pacotes por segundo exigiria a NIC e o gerador de tráfego que
 * o nível 6 prevê. O que se pode fazer com honestidade hoje é separar o que é
 * medido (o custo por pacote) do que é modelado (a chegada), e dizer qual é
 * qual.
 *
 * USO: ./rajada-nasdaq
 */
#define _GNU_SOURCE
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

#include "clock_ns.h"
#include "statistics.h"

/* ============================ Parâmetros ============================ */

/* Nasdaq exige 10 Gb ou 40 Gb para o feed não moldado; usamos o menor. */
#define ENLACE_GBPS 10.0
/* Recomendacao de banda do TotalView-ITCH 4.1 (produto de SOFTWARE), coluna
 * "- New" do relatorio. NAO e media medida, e NAO e do produto FPGA -- para
 * esse a Nasdaq declara nao ter recomendacao. Ver ressalvas 1 e 3. */
#define BANDA_RECOMENDADA_MB 67.0

/* CENARIO B: a orientacao que a Nasdaq de fato publica para o FPGA.
 *
 * "Be prepared to handle milli-second data bursts of up to 2,000 messages."
 *
 * A frase fala em MENSAGENS, em escala de MILISSEGUNDOS. Ela nao diz "2000
 * mensagens em exatamente 1 ms", e converter direto para 2 Mpps acrescentaria
 * uma precisao temporal que a fonte nao da. O que o programa faz e menos e
 * mais util: fixa a rajada em 2000 mensagens, adota 1 ms como a escala citada,
 * e mostra o que a CONVERSAO muda.
 *
 * Porque o anel nao conta mensagens -- conta DESCRITORES. Um datagrama
 * MoldUDP64 carrega varias mensagens ITCH, entao:
 *
 *     2000 mensagens  !=  2000 datagramas  !=  2000 descritores
 *
 * E a densidade de empacotamento e a premissa que decide. O teto vem da
 * propria FAQ: pacotes de ate 1500 B. */
#define RAJADA_MENSAGENS 2000
#define BYTES_MENSAGEM_ITCH 40   /* premissa: mensagem ITCH tipica, 20 a 50 B */
#define BYTES_PACOTE_MAX 1500    /* FAQ do FPGA */

/* PREMISSA DECLARADA: o tamanho médio do datagrama. MoldUDP64 agrupa várias
 * mensagens ITCH num datagrama, e o tamanho varia com o momento do pregão.
 * 256 B de CARGA UDP é uma escolha conservadora no meio da faixa.
 *
 * A CONTA DO FIO ESTAVA ERRADA, e o erro valia 15% na taxa de pico. Era
 * `CARGA + 24`, com o comentário dizendo "cabeçalho Ethernet mais o intervalo
 * entre quadros" -- que já seriam 26, e que de todo modo ignoravam UDP, IP,
 * FCS e preâmbulo. Um datagrama de 256 B de carga ocupa no fio:
 *
 *     carga  256
 *     UDP      8
 *     IPv4    20
 *     Ethernet 14   (sem VLAN)
 *     FCS      4
 *     preâmbulo + SFD  8
 *     intervalo entre quadros (IFG)  12
 *     -----------------------------
 *              322 B
 *
 * Com 280 B o programa publicava 4 464 286 pacotes/s de pico; com 322 são
 * 3 881 988. A razão pico/média não muda -- ela cancela --, mas `rho`, o
 * excedente da rajada e a tabela de perda inteira mudam. */
#define BYTES_CARGA 256
#define BYTES_UDP 8
#define BYTES_IPV4 20
#define BYTES_ETH 14
#define BYTES_FCS 4
#define BYTES_PREAMBULO 8
#define BYTES_IFG 12
#define BYTES_FIO (BYTES_CARGA + BYTES_UDP + BYTES_IPV4 + BYTES_ETH + \
                   BYTES_FCS + BYTES_PREAMBULO + BYTES_IFG)

/* Permanência média em cada estado. A rajada de abertura de pregão dura ordem
 * de milissegundos; o silêncio entre rajadas sai da razão de ciclo, calculada
 * para que a MÉDIA DE LONGO PRAZO bata com a banda publicada. */
#define RAJADA_MEDIA_US 1000.0

/* 600 s de tempo virtual, nao 60. Com rajada media de 1 ms e silencio de ~300
 * ms, 60 s contem so ~200 ciclos, e a razao de ciclo REALIZADA erra 11% da
 * pretendida -- o bastante para a coluna de ofertados nao bater entre os dois
 * cenarios e o leitor desconfiar, com razao. Tempo virtual nao custa relogio de
 * parede; custa CPU, e pouca. */
#define SEGUNDOS_SIMULADOS 600.0
#define SEMENTE 0x5EED1234ABCDEF01ull

/* Profundidades de anel conferidas. 512 e 1024 são os padrões que se encontram
 * em exemplo de driver; 4096 é o teto comum por fila em NIC de 10/25 GbE. */
/* 16384 e 32768 passam do teto de qualquer NIC comum, e estão aqui de
 * propósito: é onde a perda finalmente desaba, e é onde fica visível o preço
 * que se paga por ela em latência. Um anel que nenhuma NIC oferece é um
 * argumento, não uma recomendação. */
static const unsigned PROFUNDIDADES[] = {256,   512,   1024,  2048,
                                         4096,  8192,  16384, 32768};
#define N_PROFUNDIDADES (sizeof(PROFUNDIDADES) / sizeof(PROFUNDIDADES[0]))


/* ======================= Aleatório reprodutível ======================= */

/* xorshift64*: uma linha, período suficiente e SEMENTE FIXA. Reprodutibilidade
 * aqui não é capricho -- sem ela, duas profundidades de anel veriam tráfegos
 * diferentes e a comparação não significaria nada. */
static uint64_t estado_rng;

static void semear(void) { estado_rng = SEMENTE; }

static double uniforme(void)
{
    estado_rng ^= estado_rng >> 12;
    estado_rng ^= estado_rng << 25;
    estado_rng ^= estado_rng >> 27;
    const uint64_t x = estado_rng * 2685821657736338717ull;
    /* (0,1]: o zero precisa ficar de fora por causa do log() abaixo. */
    return (double)((x >> 11) + 1) / 9007199254740993.0;
}

/* Intervalo exponencial de média `media`. É o que torna a chegada um processo
 * de Poisson DENTRO de cada estado -- aleatória, não cadenciada. */
static double exponencial(double media) { return -media * log(uniforme()); }

/* Próximo instante de chegada num processo de DOIS ESTADOS, respeitando as
 * trocas que caiam antes dele.
 *
 * A PRIMEIRA VERSÃO ERRAVA AQUI, e o erro tinha direção. Ela sorteava o
 * intervalo com a taxa do estado corrente e só então, na chegada seguinte,
 * verificava se o estado havia mudado. Consequência: quando uma rajada começa
 * entre duas chegadas, o intervalo longo já sorteado com a taxa de silêncio
 * continua valendo, e a rajada só passa a produzir pacotes dezenas de
 * microssegundos depois de ter começado.
 *
 * Medido, com 600 s simulados: o esquema antigo produzia 8 339 069 chegadas
 * contra 8 878 652 do correto -- **6,1% a menos** -- e punha 46,2% delas na
 * rajada contra 49,5%. O viés é sistemático e aponta para o lado confortável:
 * rajada mais fraca do que a pretendida, logo PERDA MENOR do que a real.
 *
 * O conserto é competir as duas exponenciais. Como a exponencial não tem
 * memória, redesenhar o intervalo a partir do instante da troca, já com a taxa
 * nova, é exato -- não é aproximação. */
static double proxima_chegada_mmpp(double agora, int *em_rajada,
                                   double *restante_estado, double pico_pps,
                                   double silencio_pps, double rajada_media_ns,
                                   double silencio_media_ns)
{
    double t = agora;
    for (;;) {
        const double taxa = *em_rajada ? pico_pps : silencio_pps;
        const double ate_chegada = exponencial(1e9 / taxa);
        if (ate_chegada < *restante_estado) {
            *restante_estado -= ate_chegada;
            return t + ate_chegada;
        }
        t += *restante_estado;
        *em_rajada = !*em_rajada;
        *restante_estado =
            exponencial(*em_rajada ? rajada_media_ns : silencio_media_ns);
    }
}


/* ==================== O custo por pacote, medido aqui ==================== */

/* Trabalho sintético por pacote: decodificar cabeçalho e decidir. `volatile`
 * impede que -O2 apague o laço inteiro. */
static void processar_pacote(unsigned passos)
{
    static volatile uint64_t sumidouro;
    uint64_t x = sumidouro;
    for (unsigned i = 0; i < passos; i++)
        x = x * 6364136223846793005ull + 1442695040888963407ull;
    sumidouro = x;
}

/* Mede em SATURAÇÃO, pelo mesmo motivo que `orcamento-estourado.c`: o que
 * interessa é a capacidade de fato, que é contra o que a chegada se compara.
 *
 * E mede com a estatística da casa, não com uma leitura solta. A primeira
 * versão tirava UMA amostra, e a calibragem oscilou de 733 para 950 ns entre
 * duas execuções -- 30%, por escalonamento de frequência. Com ρ derivado dela,
 * a tabela inteira se movia sem que nada no experimento tivesse mudado.
 * Mediana de DEFAULT_SAMPLES amostras, com selo, como todo o resto do módulo. */
static unsigned passos_calibrados = 16;

static double medir_servico(void)
{
    const int repeticoes = 100000;
    const double t0 = academy_now_ns_d();
    for (int i = 0; i < repeticoes; i++)
        processar_pacote(passos_calibrados);
    return (academy_now_ns_d() - t0) / repeticoes;
}


/* ===================== O caminho convencional: socket ===================== */

/* O anel de descritores não é a única fila do caminho de recepção, e no caminho
 * CONVENCIONAL ele nem é a que decide. Um recebedor UDP comum tem, depois do
 * anel, o buffer de recepção do socket (`SO_RCVBUF`), e é lá que o descarte
 * aparece -- como `UdpRcvbufErrors` em `netstat -su`, não como `imissed`.
 *
 * Esta parte do programa MEDE esse caminho nesta máquina, em vez de estimá-lo:
 * quantos datagramas cabem de fato no buffer pedido, e quanto custa drenar um.
 *
 * ATENÇÃO A UMA ARMADILHA: `send()` em UDP NÃO falha quando o buffer do
 * RECEBEDOR está cheio -- o datagrama é descartado em silêncio e a chamada
 * devolve sucesso. Contar envios aceitos dá a capacidade errada por ordens de
 * grandeza. A capacidade verdadeira é quantos datagramas o recebedor CONSEGUE
 * LER depois de a fila ter sido inundada. */

struct socket_medido {
    int rcvbuf_concedido;
    int capacidade;      /* datagramas que couberam de fato */
    int capacidade_ingenua; /* rcvbuf / carga, que é o que se costuma supor */
    double recv_ns;      /* custo de drenar um datagrama com recv() */
    double recvmmsg_ns;  /* o mesmo, em lote */
    double disp_recv, disp_lote; /* dispersao robusta das duas, em % */
    int valido;
};

#define LOTE_RECVMMSG 32
#define INUNDAR 400000

static int abrir_par(int *rx, int *tx, int rcvbuf)
{
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    *rx = socket(AF_INET, SOCK_DGRAM, 0);
    if (*rx < 0)
        return -1;
    setsockopt(*rx, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof rcvbuf);
    if (bind(*rx, (struct sockaddr *)&a, sizeof a) != 0)
        return -1;
    socklen_t l = sizeof a;
    if (getsockname(*rx, (struct sockaddr *)&a, &l) != 0)
        return -1;

    *tx = socket(AF_INET, SOCK_DGRAM, 0);
    if (*tx < 0)
        return -1;
    const int snd = 8 << 20;
    setsockopt(*tx, SOL_SOCKET, SO_SNDBUF, &snd, sizeof snd);
    return connect(*tx, (struct sockaddr *)&a, sizeof a);
}

static void inundar(int tx)
{
    char carga[BYTES_CARGA];
    memset(carga, 0x5a, sizeof carga);
    for (int i = 0; i < INUNDAR; i++)
        if (send(tx, carga, sizeof carga, MSG_DONTWAIT) != (ssize_t)sizeof carga)
            break;
}

/* UMA leitura de cada custo. Nao publique isto: ver `medir_socket()` abaixo. */
static struct socket_medido medir_socket_uma_vez(int rcvbuf_pedido)
{
    struct socket_medido s = {0};
    int rx, tx;

    if (abrir_par(&rx, &tx, rcvbuf_pedido) != 0)
        return s;
    socklen_t l = sizeof s.rcvbuf_concedido;
    getsockopt(rx, SOL_SOCKET, SO_RCVBUF, &s.rcvbuf_concedido, &l);
    /* A conta "ingenua" de proposito: o que alguem faria na planilha, usando
     * o valor que `getsockopt` devolve. Esse valor ja carrega a semantica de
     * contabilidade do Linux -- `setsockopt` DOBRA o pedido para reserva
     * interna --, entao parte do fator que sai daqui e contabilidade e parte e
     * estrutura de recepcao. Este programa mede o EFEITO AGREGADO; nao separa
     * as componentes. */
    s.capacidade_ingenua = s.rcvbuf_concedido / BYTES_CARGA;

    /* 1. capacidade e custo de drenar um a um */
    inundar(tx);
    char destino[2048];
    int n = 0;
    const double t0 = academy_now_ns_d();
    while (recv(rx, destino, sizeof destino, MSG_DONTWAIT) > 0)
        n++;
    const double gasto = academy_now_ns_d() - t0;
    s.capacidade = n;
    s.recv_ns = n > 0 ? gasto / n : 0.0;
    close(rx);
    close(tx);

    /* 2. o mesmo, em lote */
    if (abrir_par(&rx, &tx, rcvbuf_pedido) != 0)
        return s;
    inundar(tx);
    struct mmsghdr m[LOTE_RECVMMSG];
    struct iovec iv[LOTE_RECVMMSG];
    static char lotes[LOTE_RECVMMSG][2048];
    for (int i = 0; i < LOTE_RECVMMSG; i++) {
        iv[i].iov_base = lotes[i];
        iv[i].iov_len = sizeof lotes[i];
        memset(&m[i], 0, sizeof m[i]);
        m[i].msg_hdr.msg_iov = &iv[i];
        m[i].msg_hdr.msg_iovlen = 1;
    }
    int total = 0, r;
    const double t1 = academy_now_ns_d();
    while ((r = recvmmsg(rx, m, LOTE_RECVMMSG, MSG_DONTWAIT, NULL)) > 0)
        total += r;
    const double gasto2 = academy_now_ns_d() - t1;
    s.recvmmsg_ns = total > 0 ? gasto2 / total : 0.0;
    close(rx);
    close(tx);

    s.valido = s.capacidade > 0;
    return s;
}

/* Mediana de AMOSTRAS_SOCKET leituras.
 *
 * A primeira versao tirava uma amostra de cada custo, e duas execucoes
 * seguidas discordaram sobre o que o experimento afirma: numa, `recvmmsg` em
 * lote custou 255 ns contra 364 do `recv` um a um; na seguinte, 361 contra
 * 341 -- ou seja, o lote apareceu PIOR. Publicar a primeira seria escolher a
 * execucao que confirma a tese.
 *
 * O resto do modulo ja tinha aprendido isso: medicao sem repeticao nao
 * sustenta comparacao. */
/* NOVE, e a escolha esta documentada porque o caminho obvio nao funcionou.
 *
 * Com 9 amostras a dispersao do custo de `recv` ficou entre 12% e 48%. Subir
 * para 25 -- o padrao do resto do modulo -- NAO estabilizou: ficou entre 12% e
 * 36%, e o programa passou de ~35 s para 1m34s.
 *
 * E a explicacao que eu dei para isso estava errada: atribui a instabilidade
 * ao proprio caminho de socket. Repetindo com a maquina OCIOSA, a mesma coleta
 * de 9 amostras deu dispersao de 1,5% a 4,8%. Nao era o softirq; era a carga
 * da maquina -- inclusive a minha, rodando o programa em sequencia. Por isso a
 * coluna `disp` fica publicada: ela diz em que condicao aquela coleta saiu.
 *
 * Consequencia para quem le: a coluna `disp` esta publicada ao lado de cada
 * custo justamente porque ela e alta. A comparacao entre `recv` e `recvmmsg`
 * vale pela DIRECAO, que se repete, nao pelo valor exato. */
#define AMOSTRAS_SOCKET 9

static struct socket_medido medir_socket(int rcvbuf_pedido)
{
    struct socket_medido melhor = {0};
    double recv[AMOSTRAS_SOCKET], lote[AMOSTRAS_SOCKET], cap[AMOSTRAS_SOCKET];
    int n = 0;

    for (int i = 0; i < AMOSTRAS_SOCKET; i++) {
        const struct socket_medido s = medir_socket_uma_vez(rcvbuf_pedido);
        if (!s.valido)
            return melhor;
        melhor = s;
        recv[n] = s.recv_ns;
        lote[n] = s.recvmmsg_ns;
        cap[n] = s.capacidade;
        n++;
    }
    qsort(recv, (size_t)n, sizeof(double), cmp_double);
    qsort(lote, (size_t)n, sizeof(double), cmp_double);
    qsort(cap, (size_t)n, sizeof(double), cmp_double);
    melhor.recv_ns = percentil(recv, n, 0.50);
    melhor.recvmmsg_ns = percentil(lote, n, 0.50);
    melhor.capacidade = (int)percentil(cap, n, 0.50);
    /* Dispersao das duas medidas, para que a comparacao entre elas possa ser
     * lida com a mesma desconfianca do resto do modulo. */
    melhor.disp_recv = percentil(recv, n, 0.50) > 0.0
        ? 100.0 * (percentil(recv, n, 0.75) - percentil(recv, n, 0.25))
              / percentil(recv, n, 0.50) : 0.0;
    melhor.disp_lote = percentil(lote, n, 0.50) > 0.0
        ? 100.0 * (percentil(lote, n, 0.75) - percentil(lote, n, 0.25))
              / percentil(lote, n, 0.50) : 0.0;
    return melhor;
}


/* ========================== Eventos discretos ========================== */

/* Amostragem de latencia com DECIMACAO UNIFORME.
 *
 * A primeira versao fazia `if (n_lat < max) latencias[n_lat++] = x;`, o que
 * descarta em SILENCIO tudo que passa do teto. Com 11,9 milhoes de pacotes
 * servidos e teto de 8 milhoes, um terco final da simulacao simplesmente nao
 * entrava nos percentis -- e nada na saida dizia isso.
 *
 * Aqui, quando o vetor enche, ele e compactado mantendo uma amostra de cada
 * duas e o passo dobra. O resultado cobre a execucao INTEIRA, em vez do
 * comeco dela. Custa uma passada sobre o vetor a cada duplicacao. */
struct amostrador {
    double *v;
    size_t n, teto, passo, vistos;
};

static void amostrar(struct amostrador *a, double x)
{
    a->vistos++;
    if (a->vistos % a->passo != 0)
        return;
    if (a->n == a->teto) {
        size_t k = 0;
        for (size_t i = 0; i < a->n; i += 2)
            a->v[k++] = a->v[i];
        a->n = k;
        a->passo *= 2;
    }
    a->v[a->n++] = x;
}

struct resultado {
    unsigned profundidade;
    uint64_t ofertados, servidos, descartados;
    unsigned ocupacao_maxima;
    double perda_pct, lat_mediana, lat_p99, ca2;
};

/* Uma corrida completa. `rajada` liga o processo de dois estados; desligado, a
 * chegada é CADENCIADA na mesma taxa média -- é a comparação com a §11. */
static struct resultado correr(unsigned profundidade, double servico_ns,
                               double taxa_pico_pps, double taxa_silencio_pps,
                               double razao_ciclo, int rajada,
                               double taxa_cadenciada_pps,
                               double *latencias, size_t max_latencias)
{
    struct resultado r = {0};
    r.profundidade = profundidade;

    double *chegada = malloc(sizeof(double) * profundidade);
    if (chegada == NULL) {
        fprintf(stderr, "sem memoria para o anel de %u descritores\n", profundidade);
        exit(EXIT_FAILURE);
    }
    unsigned cabeca = 0, cauda = 0, ocupacao = 0;

    semear(); /* MESMO tráfego para toda profundidade */

    const double fim_ns = SEGUNDOS_SIMULADOS * 1e9;
    /* No cenário cadenciado a taxa vem de FORA: é a taxa que a rajada
     * REALIZOU, não a pretendida. Sem isso os dois cenários ofereciam números
     * de pacotes diferentes -- 4% -- e a comparação perdia o pé. A pergunta é
     * o que muda quando a MESMA quantidade de tráfego chega concentrada. */
    const double media_pps = taxa_cadenciada_pps > 0.0
                                 ? taxa_cadenciada_pps
                                 : razao_ciclo * taxa_pico_pps +
                                       (1.0 - razao_ciclo) * taxa_silencio_pps;
    const double intervalo_medio_ns = 1e9 / media_pps;

    /* Estado do processo de chegada. Começa em silêncio, de propósito: assim a
     * primeira rajada encontra o anel vazio, que é o caso favorável. */
    int em_rajada = 0;
    const double rajada_media_ns = RAJADA_MEDIA_US * 1000.0;
    const double silencio_media_ns =
        rajada_media_ns * (1.0 - razao_ciclo) / razao_ciclo;
    double restante_estado = exponencial(silencio_media_ns);

    double agora = 0.0;
    double proxima_chegada;
    if (rajada)
        proxima_chegada = proxima_chegada_mmpp(0.0, &em_rajada, &restante_estado,
                                               taxa_pico_pps, taxa_silencio_pps,
                                               rajada_media_ns, silencio_media_ns);
    else
        proxima_chegada = intervalo_medio_ns;

    double livre_em = 0.0; /* quando o servidor volta a aceitar trabalho */
    struct amostrador am = {latencias, 0, max_latencias, 1, 0};
    double soma_gap = 0.0, soma_gap2 = 0.0;
    uint64_t n_gap = 0;
    double ultima_chegada = 0.0;

    while (proxima_chegada < fim_ns) {
        agora = proxima_chegada;

        /* --- escoa tudo que o servidor conseguiu terminar até `agora` --- */
        while (ocupacao > 0 && livre_em <= agora) {
            const double entrou = chegada[cabeca];
            cabeca = (cabeca + 1) % profundidade;
            ocupacao--;
            const double comeca = livre_em > entrou ? livre_em : entrou;
            const double sai = comeca + servico_ns;
            livre_em = sai;
            r.servidos++;
            amostrar(&am, sai - entrou);
        }

        /* --- a chegada de `agora` --- */
        r.ofertados++;
        if (n_gap > 0 || ultima_chegada > 0.0) {
            const double gap = agora - ultima_chegada;
            soma_gap += gap;
            soma_gap2 += gap * gap;
            n_gap++;
        }
        ultima_chegada = agora;

        if (ocupacao < profundidade) {
            chegada[cauda] = agora;
            cauda = (cauda + 1) % profundidade;
            ocupacao++;
            if (ocupacao > r.ocupacao_maxima)
                r.ocupacao_maxima = ocupacao;
        } else {
            r.descartados++; /* fila RX simulada sem capacidade */
        }

        /* --- sorteia o instante da próxima chegada --- */
        if (!rajada) {
            proxima_chegada = agora + intervalo_medio_ns;
            continue;
        }
        proxima_chegada = proxima_chegada_mmpp(agora, &em_rajada, &restante_estado,
                                               taxa_pico_pps, taxa_silencio_pps,
                                               rajada_media_ns, silencio_media_ns);
    }

    /* Drena o que sobrou, para não creditar como perda o que era só fim de
     * simulação. */
    while (ocupacao > 0) {
        const double entrou = chegada[cabeca];
        cabeca = (cabeca + 1) % profundidade;
        ocupacao--;
        const double comeca = livre_em > entrou ? livre_em : entrou;
        livre_em = comeca + servico_ns;
        r.servidos++;
        amostrar(&am, livre_em - entrou);
    }
    free(chegada);

    r.perda_pct = r.ofertados ? 100.0 * (double)r.descartados / (double)r.ofertados : 0.0;

    /* ca²: variância do intervalo entre chegadas dividida pelo quadrado da
     * média. É EXATAMENTE o termo que a fórmula de Kingman pede, e por isso ele
     * é calculado aqui em vez de suposto. */
    if (n_gap > 1) {
        const double media = soma_gap / (double)n_gap;
        const double var = soma_gap2 / (double)n_gap - media * media;
        /* Cancelamento catastrófico na forma E[x²]-E[x]²: com chegada
         * cadenciada a variância verdadeira é zero, e o arredondamento a
         * devolvia como -0,0000. Zero negativo impresso numa tabela é defeito
         * de apresentação, e esconder o sinal seria pior -- então o valor é
         * fixado em zero só quando o ruído é menor que a resolução. */
        double ca2 = media > 0.0 ? var / (media * media) : 0.0;
        r.ca2 = ca2 > 1e-12 ? ca2 : 0.0;
    }

    const size_t n_lat = am.n;
    if (n_lat > 0) {
        /* `percentil()` recebe FRACAO (0,50), nao percentual (50,0). Com 50.0
         * a posicao calculada estoura o vetor e a funcao devolve o ULTIMO
         * elemento -- o maximo. A primeira versao deste programa publicou o
         * maximo em tres colunas, e o sintoma era mediana igual a p99 em toda
         * linha, que eu expliquei como saturacao do anel em vez de conferir. */
        qsort(latencias, n_lat, sizeof(double), cmp_double);
        r.lat_mediana = percentil(latencias, (int)n_lat, 0.50);
        r.lat_p99 = percentil(latencias, (int)n_lat, 0.99);
    }
    return r;
}


static void cabecalho(void)
{
    printf("  anel(n)     ofertados  descartados     perda  ocup.max"
           "  mediana(us)   p99(us)\n");
    printf("  -------  ------------  -----------  --------  --------"
           "  -----------  --------\n");
}

static void imprimir(struct resultado r)
{
    printf("  %7u  %11" PRIu64 "  %10" PRIu64 "  %7.3f%%  %8u  %10.1f  %9.1f\n",
           r.profundidade, r.ofertados, r.descartados, r.perda_pct,
           r.ocupacao_maxima, r.lat_mediana / 1000.0, r.lat_p99 / 1000.0);
}


int main(void)
{
    /* Calibra o consumidor para um custo por pacote da ordem de grandeza de um
     * decodificador de feed: algumas centenas de nanossegundos. O laço procura
     * os passos que chegam perto de ALVO_NS nesta máquina, para que o resultado
     * não dependa de quão rápido o processador é. */
    const double ALVO_NS = 500.0;
    for (int i = 0; i < 2000; i++)
        processar_pacote(passos_calibrados);
    for (int i = 0; i < 24 && medir_servico() < ALVO_NS; i++)
        passos_calibrados *= 2;

    const struct statistics srv = collect_or_fail(medir_servico, DEFAULT_SAMPLES);
    const double servico_ns = srv.median;

    const double taxa_pico = ENLACE_GBPS * 1e9 / (BYTES_FIO * 8.0);
    const double taxa_media = BANDA_RECOMENDADA_MB * 1e6 / (BYTES_FIO * 8.0);
    /* O silêncio não é ausência de tráfego: é o feed fora da rajada. Metade da
     * média é uma escolha conservadora -- quanto MAIOR o silêncio, MENOR a
     * rajada precisa ser para fechar a média, e mais fácil fica o problema. */
    const double taxa_silencio = taxa_media * 0.5;
    const double razao_ciclo = (taxa_media - taxa_silencio) / (taxa_pico - taxa_silencio);
    const double drenagem_pps = 1e9 / servico_ns;

    printf("\n  RAJADA DE MARKET DATA CONTRA A PROFUNDIDADE DO ANEL DE RX\n");
    printf("  (simulacao de eventos discretos; %g s de tempo virtual)\n\n",
           SEGUNDOS_SIMULADOS);
    printf("  enlace (cenario-limite)   : %.0f Gb/s   -> pico   %9.0f pacotes/s\n",
           ENLACE_GBPS, taxa_pico);
    printf("  banda recomendada (fonte) : %.0f Mb/s   -> media  %9.0f pacotes/s\n",
           BANDA_RECOMENDADA_MB, taxa_media);
    printf("  razao pico/media          : %.0fx\n", taxa_pico / taxa_media);
    printf("  datagrama (premissa)      : %d B de carga UDP, %d B no fio\n",
           BYTES_CARGA, BYTES_FIO);
    printf("  rajada media              : %.0f us     razao de ciclo %.4f%%\n",
           RAJADA_MEDIA_US, razao_ciclo * 100.0);
    printf("\n  custo por pacote MEDIDO nesta maquina: %.0f ns  (%d amostras,"
           " disp %.1f%% %s)\n", servico_ns, srv.samples, srv.disp, badge(srv));
    printf("  drenagem sustentada                 : %.0f pacotes/s\n", drenagem_pps);

    /* TODA tabela abaixo deriva deste unico numero medido: ele define a
     * drenagem, logo rho, logo perda e latencia. Se a calibragem saiu instavel,
     * as tabelas herdam a instabilidade -- e isso precisa ser dito na saida,
     * nao descoberto por quem le. */
    if (srv.disp > DISP_SUSPEITA)
        fprintf(stderr,
                "  AVISO: a calibragem saiu com disp %.1f%% (selo !). Toda tabela\n"
                "         deste programa deriva dela, entao os valores abaixo valem\n"
                "         pela FORMA, nao pelo numero. Repita com a maquina ociosa.\n",
                srv.disp);
    printf("  rho medio  %.3f     rho durante a rajada  %.2f\n",
           taxa_media / drenagem_pps, taxa_pico / drenagem_pps);

    /* A conta que o capitulo 6 publica, feita aqui para nao depender de quem
     * le multiplicar: o excedente de UMA rajada media. Vale so para a rajada
     * MEDIA. Com permanencia exponencial, P(T > media) = 1/e = 36,8% das
     * rajadas excedem a duracao media, e a distribuicao nao tem limite
     * superior -- nenhuma profundidade fixa cobre a cauda. (A mediana e
     * ln2 = 0,693 da media, nao a media.) */
    const double excedente = (taxa_pico - drenagem_pps) * (RAJADA_MEDIA_US / 1e6);
    printf("  descritores que UMA rajada media exige: (%.0f - %.0f) x %.0f us"
           " = %.0f\n", taxa_pico, drenagem_pps, RAJADA_MEDIA_US, excedente);

    const size_t max_lat = 8000000;
    double *lat = malloc(sizeof(double) * max_lat);
    if (lat == NULL) {
        fprintf(stderr, "sem memoria para as latencias\n");
        return EXIT_FAILURE;
    }

    /* A rajada roda PRIMEIRO, para que o cenario cadenciado possa usar a taxa
     * que ela realizou de fato. */
    struct resultado raj[N_PROFUNDIDADES];
    for (size_t i = 0; i < N_PROFUNDIDADES; i++)
        raj[i] = correr(PROFUNDIDADES[i], servico_ns, taxa_pico, taxa_silencio,
                        razao_ciclo, 1, 0.0, lat, max_lat);

    const double taxa_realizada = (double)raj[0].ofertados / SEGUNDOS_SIMULADOS;
    const struct resultado cad = correr(PROFUNDIDADES[1], servico_ns, taxa_pico,
                                        taxa_silencio, razao_ciclo, 0,
                                        taxa_realizada, lat, max_lat);

    printf("\n  1. CHEGADA CADENCIADA -- um pacote a cada intervalo fixo,"
           " como na secao 11\n\n");
    cabecalho();
    imprimir(cad);
    printf("\n     ca2 = %.4f. Sem variabilidade, o anel nunca passa de um"
           " descritor ocupado.\n", cad.ca2);

    printf("\n  2. CHEGADA EM RAJADA -- a MESMA quantidade de pacotes,"
           " concentrada no tempo\n\n");
    cabecalho();
    for (size_t i = 0; i < N_PROFUNDIDADES; i++)
        imprimir(raj[i]);
    printf("\n     ca2 = %.2f, contra 0 da cadenciada: e a EVIDENCIA da"
           " diferenca de variabilidade.\n     O que governa a perda acima e"
           " o acumulo durante a rajada, (lambda - mu) x T.\n", raj[0].ca2);

    /* ---- 3. o caminho convencional: socket UDP, medido nesta maquina ---- */
    printf("\n  3. O CAMINHO CONVENCIONAL DE SOCKET, MEDIDO NESTA MAQUINA\n\n");

    const int PEDIDOS[] = {212992, 1 << 20, 8 << 20, 32 << 20};
    const size_t n_pedidos = sizeof(PEDIDOS) / sizeof(PEDIDOS[0]);
    struct socket_medido s0 = {0};

    printf("  SO_RCVBUF   concedido  datagramas  suposto  fator    recv()"
           "  disp     recvmmsg(%d)  disp\n", LOTE_RECVMMSG);
    printf("  ---------  ----------  ----------  -------  -----  --------"
           "  ----  --------------  ----\n");
    for (size_t i = 0; i < n_pedidos; i++) {
        const struct socket_medido s = medir_socket(PEDIDOS[i]);
        if (!s.valido) {
            printf("  socket indisponivel neste ambiente; cenario 3 pulado\n");
            break;
        }
        printf("  %9d  %10d  %10d  %7d  %4.1fx  %5.0f ns  %3.1f%%  %10.0f ns  %3.1f%%\n",
               PEDIDOS[i], s.rcvbuf_concedido, s.capacidade, s.capacidade_ingenua,
               (double)s.capacidade_ingenua / (double)s.capacidade,
               s.recv_ns, s.disp_recv, s.recvmmsg_ns, s.disp_lote);
        if (i == 2)
            s0 = s; /* 8 MB: o valor usado na simulacao abaixo */
    }

    if (s0.valido) {
        printf("\n  A MESMA rajada, drenada pelo socket em vez do anel"
               " (fila = %d datagramas):\n\n", s0.capacidade);
        cabecalho();
        const struct resultado um_a_um =
            correr((unsigned)s0.capacidade, servico_ns + s0.recv_ns, taxa_pico,
                   taxa_silencio, razao_ciclo, 1, 0.0, lat, max_lat);
        imprimir(um_a_um);
        const struct resultado em_lote =
            correr((unsigned)s0.capacidade, servico_ns + s0.recvmmsg_ns, taxa_pico,
                   taxa_silencio, razao_ciclo, 1, 0.0, lat, max_lat);
        imprimir(em_lote);
        printf("\n     linha 1: recv() um a um     -> %.0f ns por pacote"
               " (%.0f de trabalho + %.0f de socket)\n",
               servico_ns + s0.recv_ns, servico_ns, s0.recv_ns);
        printf("     linha 2: recvmmsg em lote   -> %.0f ns por pacote"
               " (%.0f de trabalho + %.0f de socket)\n",
               servico_ns + s0.recvmmsg_ns, servico_ns, s0.recvmmsg_ns);
        printf("     drenagem: %.0f e %.0f pacotes/s, contra %.0f do anel puro\n",
               1e9 / (servico_ns + s0.recv_ns), 1e9 / (servico_ns + s0.recvmmsg_ns),
               drenagem_pps);
    }

    /* ---- 4. o divisor nao e o numero de filas; e o numero de CANAIS ---- */
    /*
     * A versao anterior deste cenario variava o numero de filas de RSS e
     * dividia a taxa de pico por ele. Estava errado, e a fonte que este
     * programa ja cita diz por que.
     *
     * RSS distribui por HASH DO CABECALHO. Um feed multicast e um fluxo: mesmo
     * IP de origem, mesmo grupo de destino, mesmas portas. Todos os pacotes
     * caem no mesmo balde, e N filas recebem o trafego de UMA. O que divide um
     * feed nao e a NIC do assinante -- e a bolsa, quando publica o feed em
     * varios canais.
     *
     * E a FAQ do FPGA responde isso sem deixar margem. Pergunta: "Is Nasdaq
     * planning to offer the FPGA feed in a multi-channel (multi-thread)
     * option?" Resposta: "No. For the initial implementation, Nasdaq will
     * offer only a single channel version." O qualificador "for the initial
     * implementation" e da fonte e fica: ela NAO sustenta "o FPGA e sempre de
     * canal unico". O relatorio de banda concorda para
     * o produto de software: coluna "Number of Channels", TotalView-ITCH 4.1
     * tem 1. O Level 2 aparece com 3 e o TotalView-Aggregated com 8 -- citados
     * so para mostrar que existe feed publicado em varios canais.
     *
     * DUAS RESSALVAS SOBRE O QUE ESTA TABELA NAO E:
     *
     * 1. `min(canais, filas)` e o divisor IDEAL do modelo, nao o efetivo. RSS
     *    mapeia por hash, e tres fluxos em tres filas podem colidir em duas.
     *    O divisor real precisa ser MEDIDO no RSS da placa; aqui ele e o teto.
     *
     * 2. As linhas de 3 e 8 canais NAO simulam o Level 2 nem o
     *    TotalView-Aggregated. Sao O MESMO trafego deste cenario, particionado
     *    idealmente em 3 e em 8. Aqueles produtos tem taxa propria, e dividir
     *    a taxa daqui por 3 nao reproduz nenhum dos dois.
     */
    const unsigned ANEL_FIXO = 1024;
    const struct { int canais, filas; const char *nota; } ARRANJOS[] = {
        {1,  1,  "TotalView-ITCH 4.1, uma fila"},
        {1,  4,  "o MESMO feed com 4 filas de RSS"},
        {1, 16,  "e com 16 filas"},
        {3,  3,  "o MESMO trafego particionado em 3 canais (ideal)"},
        {8,  8,  "o MESMO trafego particionado em 8 canais (ideal)"},
    };
    const size_t n_arranjos = sizeof(ARRANJOS) / sizeof(ARRANJOS[0]);

    printf("\n  4. O DIVISOR E O NUMERO DE CANAIS, NAO O DE FILAS"
           " (anel fixo em %u)\n\n", ANEL_FIXO);
    printf("  canais  filas  div.ideal  rho rajada     perda  p99(us)   nota\n");
    printf("  ------  -----  ---------  ----------  --------  -------"
           "  ----------------------------------------\n");
    for (size_t i = 0; i < n_arranjos; i++) {
        const int divisor = ARRANJOS[i].canais < ARRANJOS[i].filas
                                ? ARRANJOS[i].canais : ARRANJOS[i].filas;
        const double pico_fila = taxa_pico / divisor;
        const double silencio_fila = taxa_silencio / divisor;
        const struct resultado r = correr(ANEL_FIXO, servico_ns, pico_fila,
                                          silencio_fila, razao_ciclo, 1, 0.0,
                                          lat, max_lat);
        printf("  %6d  %5d  %9d  %10.2f  %7.3f%%  %7.1f  %s\n",
               ARRANJOS[i].canais, ARRANJOS[i].filas, divisor,
               pico_fila / drenagem_pps, r.perda_pct, r.lat_p99 / 1000.0,
               ARRANJOS[i].nota);
    }
    printf("\n     As tres primeiras linhas sao IDENTICAS: 16 filas nao ajudam\n"
           "     um feed de um canal so. `div.ideal` e o TETO do que o\n"
           "     particionamento pode render; o divisor efetivo depende do hash\n"
           "     do RSS e precisa ser medido na placa.\n");

    /* ---- 5. o cenario B: a orientacao publicada, em mensagens ---- */
    /*
     * O cenario A (tabelas 1 a 4) e o LIMITE DO ENLACE: quanto cabe em 10 Gb/s.
     * Este e a ORIENTACAO PUBLICADA, e as duas nao medem a mesma coisa. Vale
     * te-las lado a lado justamente porque discordam por ordens de grandeza --
     * e a distancia entre elas e a licao.
     */
    printf("\n  5. CENARIO B -- a orientacao publicada: rajada de ate %d"
           " MENSAGENS\n     em escala de milissegundos (FAQ do TotalView-ITCH"
           " FPGA)\n\n", RAJADA_MENSAGENS);
    printf("     A FAQ fala em MENSAGENS; o anel conta DESCRITORES. TRES coisas\n"
           "     aqui sao PREMISSA, nao fonte: a janela de 1 ms (a FAQ diz so\n"
           "     \"escala de milissegundos\"), os %d B por mensagem ITCH (o\n"
           "     tamanho varia com o tipo) e o empacotamento, que e o eixo da\n"
           "     tabela justamente por ser o que mais muda o resultado.\n\n",
           BYTES_MENSAGEM_ITCH);

    const int EMPACOTAMENTO[] = {1, 2, 4, 8, 16, 32, 64};
    const size_t n_emp = sizeof(EMPACOTAMENTO) / sizeof(EMPACOTAMENTO[0]);
    const double drenados_por_ms = drenagem_pps / 1000.0;

    double excedente_max_b = 0.0;
    printf("  msgs/datagrama  carga(B)  no fio(B)  datagramas  Gb/s implicados"
           "  drenados/ms  excedente\n");
    printf("  --------------  --------  ---------  ----------  ---------------"
           "  -----------  ---------\n");
    for (size_t i = 0; i < n_emp; i++) {
        const int m = EMPACOTAMENTO[i];
        const int carga = m * BYTES_MENSAGEM_ITCH;
        /* O teto de 1500 B vem da FAQ; acima dele o empacotamento nao existe. */
        const int cabe = carga + BYTES_UDP + BYTES_IPV4 + BYTES_ETH <= BYTES_PACOTE_MAX;
        const int fio = carga + BYTES_UDP + BYTES_IPV4 + BYTES_ETH +
                        BYTES_FCS + BYTES_PREAMBULO + BYTES_IFG;
        const int datagramas = (RAJADA_MENSAGENS + m - 1) / m;
        const double gbps = (double)datagramas * fio * 8.0 / 1e6; /* em 1 ms */
        const double excedente_b = datagramas - drenados_por_ms;
        if (excedente_b > excedente_max_b)
            excedente_max_b = excedente_b;
        printf("  %14d  %8d  %9d  %10d  %15.2f  %11.0f  %9.0f%s\n",
               m, carga, fio, datagramas, gbps, drenados_por_ms,
               excedente_b > 0 ? excedente_b : 0.0,
               cabe ? "" : "   <- passa de 1500 B sob qualquer leitura");
    }
    printf("\n     Tres taxas diferentes na mesma linha: MENSAGENS (a fonte),\n"
           "     DATAGRAMAS (o que o anel conta) e BITS (o que o enlace carrega).\n"
           "     Confundi-las e o erro classico de dimensionamento de RX.\n");
    /* A COMPARACAO PRECISA SER DA MESMA GRANDEZA, e a primeira versao disto
     * comparava coisas diferentes: dizia que "o cenario B pede no maximo 2000
     * descritores". Nao pede. 2000 e o numero de MENSAGENS oferecidas, e no
     * caso extremo de uma mensagem por datagrama tambem o de DATAGRAMAS
     * oferecidos -- nao a profundidade que a rajada exige, porque o consumidor
     * drena o tempo todo. O que o anel precisa absorver e o EXCEDENTE, que a
     * propria coluna ao lado ja imprimia. */
    printf("\n     Os dois cenarios, na MESMA grandeza -- excedente de fila:\n"
           "       A (limite do enlace, rajada media de 1 ms) : %.0f descritores\n"
           "       B (2000 msgs em 1 ms, 1 msg/datagrama)     : %.0f descritores\n"
           "       B com 2 mensagens por datagrama            : 0\n",
           excedente, excedente_max_b);
    printf("\n     Nao ha contradicao entre as fontes: os dois respondem a\n"
           "     perguntas diferentes. A pergunta \"e se o enlace for ocupado\n"
           "     ate o limite?\"; B, \"o que resulta da orientacao publicada?\".\n"
           "     A e deliberadamente conservador; B e ancorado na quantidade de\n"
           "     mensagens que a bolsa publica, mas AINDA exige premissas para\n"
           "     converter mensagens em datagramas e duracao em taxa.\n");

    free(lat);
    return EXIT_SUCCESS;
}
