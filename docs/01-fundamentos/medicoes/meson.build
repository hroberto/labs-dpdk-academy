# libm: estatistica.h usa sqrt() para o desvio padrao.
libm = meson.get_compiler('c').find_library('m', required : false)

# --- L1 NEGATIVO: o aborto de collect_or_fail dispara mesmo? ---------------
#
# `collect_or_fail` e usado por OITO programas sem EAL, e existe para encerrar o
# processo quando a coleta nao e publicavel. O caminho de aborto estava SEM
# TESTE, e a ausencia foi medida: trocando a condicao por `if (0)`, a suite
# inteira continuava verde. O teste de "coleta invalida deve falhar" que ja
# existia exercita o OUTRO caminho, o dos programas com EAL.
#
# `should_fail : true` e o ponto: se este programa um dia sair com SUCESSO, o
# meson reporta UNEXPECTEDPASS e a suite fica vermelha -- porque sucesso aqui
# significa que o aborto sumiu.
coleta_zero = executable(
  'coleta-zero',
  'tests/coleta_zero.c',
  dependencies : [libm],
  include_directories : include_directories('.'),
  install : false,
)
test('fundamentos - L1 (coleta que nao aconteceu deve abortar)', coleta_zero,
     suite : ['l1', 'fundamentos'], timeout : 30, should_fail : true)

# --- L1: o modulo de estatistica, sem EAL e sem DPDK -----------------------
#
# estatistica.h calcula a mediana, o IQR, o p99, a dispersao e o CV de TODA
# tabela publicada neste repositorio, e passou muito tempo sem teste nenhum --
# o pior lugar possivel para nao ter, porque um defeito aqui nao quebra nada
# visivelmente: apenas publica numeros errados com aparencia de certos.
if gtest_dep.found()
  test_l1_statistics = executable(
    'test_l1_statistics',
    'tests/test_l1_statistics.cpp',
    dependencies : [gtest_dep, libm],
    include_directories : include_directories('.'),
    install : false,
  )
  test(
    'fundamentos - L1 (estatistica)',
    test_l1_statistics,
    protocol : 'gtest',
    suite : ['l1', 'fundamentos'],
    timeout : 30,
  )
else
  # GTest ausente: registrar um marcador que PULA (codigo 77) em vez de
  # nao registrar nada. Sem isto a suite l1 encolhia em silencio e
  # reportava verde -- ver ferramental/qualidade/pular-sem-gtest.sh.
  test('fundamentos - L1 (estatistica)', bash,
       args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-gtest.sh',
               'fundamentos - L1 (estatistica)'],
       suite : ['l1', 'fundamentos'], timeout : 30)
endif


# --- L1: a cadeia de ponteiros que TRÊS programas montam -------------------
#
# `cadeia.h` existe porque a terceira cópia da mesma construção saiu errada e a
# suíte nao percebeu: `efeito-cache` publicou 0,9 ns como latencia da RAM com um
# ciclo degenerado, e o teste do programa -- "executa" -- continuou verde,
# porque um programa que mede a coisa errada tambem sai com zero.
#
# A propriedade quebrada e combinatoria (K ciclos disjuntos cobrindo cada no uma
# vez), nao depende de hardware nem de tempo, e por isso cabe em L1.
if gtest_dep.found()
  test_l1_cadeia = executable(
    'test_l1_cadeia',
    'tests/test_l1_cadeia.cpp',
    dependencies : [gtest_dep],
    include_directories : include_directories('.'),
    install : false,
  )
  test(
    'fundamentos - L1 (cadeia de ponteiros)',
    test_l1_cadeia,
    protocol : 'gtest',
    suite : ['l1', 'fundamentos'],
    timeout : 30,
  )
else
  test('fundamentos - L1 (cadeia de ponteiros)', bash,
       args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-gtest.sh',
               'fundamentos - L1 (cadeia de ponteiros)'],
       suite : ['l1', 'fundamentos'], timeout : 30)
endif


# ===================== ALINHAMENTO DE LACO, PARA TODOS =====================
#
# Medido em 19/09/2026, depois que o custo-comunicacao mostrou o problema: o
# tempo por operacao de um laco curto depende do ENDERECO em que o compilador o
# coloca, e o endereco muda quando QUALQUER outra parte do arquivo muda.
#
# A VARREDURA, e o teste que ela exigiu. A primeira passagem comparou UMA
# execucao de cada build e produziu tres suspeitos. Isso nao basta, e o proprio
# material ensina por que: comparar uma coleta de cada lado confunde a diferenca
# entre os binarios com a variacao entre execucoes. O criterio adotado foi
# repetir cinco a vinte execucoes de CADA binario e exigir que as duas faixas
# NAO SE SOBREPONHAM.
#
#   SENSIVEIS -- faixas disjuntas, efeito determinado pelo binario
#     custo-comunicacao   laco de ALU       0,447-0,449  <->  0,535-0,544
#     efeito-cache        aleatorio L1d     0,218-0,226  <->  0,259-0,261
#                         aleatorio L2      0,254-0,263  <->  0,331-0,332
#
#   INSENSIVEIS -- as faixas coincidem
#     custo-espera        chama pthread_*: as cinco linhas concordam
#     custo-mckenney      2,05 / 20,8 / 89,9 nos tres alinhamentos
#     custo-traducao      preso a latencia da memoria (~95 ns)
#     efeito-cache        a coluna `dependente`, em todos os niveis
#
#   REPROVADO NO TESTE -- parecia sensivel e nao e
#     custo-syscall       a chamada de funcao de referencia dava 0,92 com -O2 e
#                         0,72 com -falign-loops=64. Repetindo o MESMO binario
#                         dez vezes: 0,923 0,714 0,750 0,749 0,723 0,714 0,726
#                         0,714 0,723 0,716. Nao e a flag -- e variacao entre
#                         EXECUCOES, e o modo alto depende do leiaute de
#                         enderecos do processo. Ver a retratacao no §2 do
#                         modulo 01.
#
# A regra que sobrevive: laco de poucos ciclos limitado pelo front-end sofre;
# laco dominado por chamada, travessia do kernel ou espera de memoria, nao.
#
# A flag entra em TODOS de proposito, e nao so nos sensiveis. Aplicar so onde
# hoje importa exige que alguem lembre da lista ao escrever o decimo programa --
# e a lista nao esta onde esse alguem vai olhar. Nos insensiveis ela nao muda
# numero nenhum (medido acima), entao o custo de aplicar a todos e zero e o de
# esquecer e uma medicao irreprodutivel.
#
# NAO e afinacao de desempenho. E o que faz duas compilacoes do mesmo fonte
# devolverem o mesmo numero -- e, onde nem isso basta, e o que deixa a parte
# que NAO se resolve assim visivel, como no custo-syscall.
alinhamento = ['-falign-loops=64']

# PROVENIENCIA: o commit entra no binario NA HORA DO BUILD.
#
# `vcs_tag` regenera o cabecalho quando o estado do git muda; `run_command` o
# fixaria na configuracao e o binario declararia procedencia vencida sem aviso.
# O arquivo gerado entra como FONTE de cada programa, e nao so como include,
# porque incluir nao garante ordem de build -- o executavel poderia ser
# compilado antes de o cabecalho existir.
versao_h = vcs_tag(
  input : 'academy_version.h.in',
  output : 'academy_version.h',
  command : ['git', 'describe', '--always', '--dirty', '--tags'],
  fallback : 'sem-git',
)

# Medições dos fundamentos (níveis 1 e 2).
#
# Não dependem do DPDK: o objetivo é medir as propriedades da MÁQUINA que
# justificam a existência do DPDK — o custo de atravessar a fronteira do
# kernel e o custo de perder localidade de memória.

# L1: le o CPUID e imprime a TLB real. Nao mede tempo -- le uma propriedade
# declarada do hardware. Existe porque /proc/cpuinfo reporta o valor BRUTO no
# Zen 5 (sem o multiplicador x32) ate o kernel 7.4, e o modulo 01 publica o
# alcance da TLB como numero. Em CPU nao-AMD sai com 77 (PULADO).
tlb_real = executable('tlb-real', 'tlb-real.c', versao_h, install : false)
test('fundamentos - L1 (TLB real via CPUID)', tlb_real,
     suite : ['l1', 'fundamentos'], timeout : 30)

custo_syscall = executable('custo-syscall', 'custo-syscall.c', versao_h, c_args : alinhamento,
                           dependencies : [libm], install : false)
efeito_cache = executable('efeito-cache', 'efeito-cache.c', versao_h, c_args : alinhamento,
                          dependencies : [libm], install : false)
custo_traducao = executable('custo-traducao', 'custo-traducao.c', versao_h, c_args : alinhamento,
                            dependencies : [libm], install : false)
# L3: mede CONCORRENCIA de memoria (latencia x vazao). Usa hugepages apenas
# para tirar a TLB da conta; sem elas sai com 77 (PULADO).
custo_paralelismo = executable('custo-paralelismo', 'custo-paralelismo.c', versao_h,
                               c_args : alinhamento,
                               dependencies : [dependency('threads'), libm], install : false)
test('fundamentos - custo-paralelismo (L3)', custo_paralelismo,
     suite : ['l3', 'fundamentos'], timeout : 300)

# Sensivel a alinhamento: ver o bloco no topo deste arquivo.
custo_comunicacao = executable('custo-comunicacao', 'custo-comunicacao.c', versao_h,
                               c_args : alinhamento,
                               dependencies : [dependency('threads'), libm], install : false)
# Reproduz a Tabela 3.1 de McKenney nesta maquina, para confronto direto com a
# referencia canonica da area.
custo_mckenney = executable('custo-mckenney', 'custo-mckenney.c', versao_h,
                            c_args : alinhamento,
                            dependencies : [dependency('threads'), libm], install : false)
# L3: exige DOIS dominios de cache L3 e 3+ CPUs. Sem eles, sai com 77 (PULADO).
test('fundamentos - custo-mckenney (L3)', custo_mckenney,
     suite : ['l3', 'fundamentos'], timeout : 300)

# --- Eixo de falha (ROADMAP, Etapa 7.5) -----------------------------------
#
# O que acontece do outro lado do orcamento por pacote. Nao depende do DPDK,
# como o resto deste modulo: o que se mede e o comportamento de uma fila finita
# quando o servico passa a chegada, e isso e propriedade da maquina.
orcamento_estourado = executable('orcamento-estourado', 'orcamento-estourado.c', versao_h,
                                 c_args : alinhamento,
                                 dependencies : [libm], install : false)
test('fundamentos - L2 (orcamento estourado)', orcamento_estourado,
     suite : ['l2', 'fundamentos'], timeout : 120)

# O mesmo eixo, com a chegada que o `orcamento-estourado` NAO tem: aleatoria e
# concentrada no tempo. Ele responde quantos descritores o anel de RX precisa
# para absorver rajada de market data, e mostra que a resposta nao depende da
# taxa media -- depende da distribuicao dela no tempo.
rajada_nasdaq = executable('rajada-nasdaq', 'rajada-nasdaq.c', versao_h,
                           c_args : alinhamento,
                           dependencies : [libm], install : false)
# 300 s, nao 120: a parte de socket inunda e drena o buffer 9 vezes por
# tamanho, e isso leva ~40 s nesta maquina. Timeout apertado transforma
# maquina lenta em falha de CI que nao diz nada sobre o codigo.
test('fundamentos - L2 (rajada de market data)', rajada_nasdaq,
     suite : ['l2', 'fundamentos'], timeout : 300)

custo_espera = executable('custo-espera', 'custo-espera.c', versao_h,
                          c_args : alinhamento,
                          dependencies : [dependency('threads'), libm], install : false)

# Espelho em C++23 do programa acima, para validar se a escolha de linguagem
# altera o custo da sincronizacao. Ver scripts/validar-cpp-vs-c.sh.
custo_espera_cpp = executable('custo-espera-cpp', 'custo-espera-cpp.cpp',
                              cpp_args : alinhamento,
                              dependencies : [dependency('threads'), libm], install : false)

# Estes são instrumentos de medição, não código de biblioteca: o teste apenas
# garante que continuam executando e produzindo resultado.
test('fundamentos - custo-syscall executa', custo_syscall,
     suite : ['l2', 'fundamentos'], timeout : 120)
test('fundamentos - efeito-cache executa', efeito_cache,
     suite : ['l2', 'fundamentos'], timeout : 180)

# L3: sem hugepages reservadas nao ha o que medir, e o programa sai com 77
# (PULADO). Saia com 0 antes -- e como HugePages_Total=0 e o padrao da maioria
# das maquinas e do runner do CI, o falso verde era a regra, nao a excecao.
test('fundamentos - custo-traducao (L3)', custo_traducao,
     suite : ['l3', 'fundamentos'], timeout : 300)

# L3: exige DOIS dominios de cache L3. Em CPU de dominio unico sai com 77.
test('fundamentos - custo-comunicacao (L3)', custo_comunicacao,
     suite : ['l3', 'fundamentos'], timeout : 180)

test('fundamentos - custo-espera executa', custo_espera,
     suite : ['l2', 'fundamentos'], timeout : 300)

test('fundamentos - custo-espera-cpp executa', custo_espera_cpp,
     suite : ['l2', 'fundamentos'], timeout : 300)
