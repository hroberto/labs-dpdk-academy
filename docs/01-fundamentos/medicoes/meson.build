# libm: estatistica.h usa sqrt() para o desvio padrao.
libm = meson.get_compiler('c').find_library('m', required : false)

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
  # reportava verde -- ver scripts/pular-sem-gtest.sh.
  test('fundamentos - L1 (estatistica)', bash,
       args : [meson.project_source_root() / 'scripts/pular-sem-gtest.sh',
               'fundamentos - L1 (estatistica)'],
       suite : ['l1', 'fundamentos'], timeout : 30)
endif


# Medições dos fundamentos (níveis 1 e 2).
#
# Não dependem do DPDK: o objetivo é medir as propriedades da MÁQUINA que
# justificam a existência do DPDK — o custo de atravessar a fronteira do
# kernel e o custo de perder localidade de memória.

custo_syscall = executable('custo-syscall', 'custo-syscall.c', dependencies : [libm], install : false)
efeito_cache = executable('efeito-cache', 'efeito-cache.c', dependencies : [libm], install : false)
custo_traducao = executable('custo-traducao', 'custo-traducao.c', dependencies : [libm], install : false)
custo_comunicacao = executable('custo-comunicacao', 'custo-comunicacao.c',
                               dependencies : [dependency('threads'), libm], install : false)
# Reproduz a Tabela 3.1 de McKenney nesta maquina, para confronto direto com a
# referencia canonica da area.
custo_mckenney = executable('custo-mckenney', 'custo-mckenney.c',
                            dependencies : [dependency('threads'), libm], install : false)
# L3: exige DOIS dominios de cache L3 e 3+ CPUs. Sem eles, sai com 77 (PULADO).
test('fundamentos - custo-mckenney (L3)', custo_mckenney,
     suite : ['l3', 'fundamentos'], timeout : 300)

# --- Eixo de falha (ROADMAP, Etapa 7.5) -----------------------------------
#
# O que acontece do outro lado do orcamento por pacote. Nao depende do DPDK,
# como o resto deste modulo: o que se mede e o comportamento de uma fila finita
# quando o servico passa a chegada, e isso e propriedade da maquina.
orcamento_estourado = executable('orcamento-estourado', 'orcamento-estourado.c',
                                 dependencies : [libm], install : false)
test('fundamentos - L2 (orcamento estourado)', orcamento_estourado,
     suite : ['l2', 'fundamentos'], timeout : 120)

custo_espera = executable('custo-espera', 'custo-espera.c',
                          dependencies : [dependency('threads'), libm], install : false)

# Espelho em C++23 do programa acima, para validar se a escolha de linguagem
# altera o custo da sincronizacao. Ver scripts/validar-cpp-vs-c.sh.
custo_espera_cpp = executable('custo-espera-cpp', 'custo-espera-cpp.cpp',
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
