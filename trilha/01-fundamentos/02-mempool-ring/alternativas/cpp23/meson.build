# Alternativa em C++23 puro ao tópico 02.
#
# Resolve o mesmo problema (produzir, enfileirar e processar pacotes em lote)
# sem DPDK: std::vector pré-reservado no lugar do mempool, std::views::chunk no
# lugar de rte_ring_dequeue_burst. Os testes asseguram o MESMO contrato da
# versão DPDK (10 pacotes -> 695 bytes), que é o que torna a comparação válida.
#
# Note que não há cpp_args aqui: o padrão vem de default_options no meson.build
# raiz, e o Meson emite a flag correta para cada compilador.

alt_cpp23_inc = include_directories('.')

cpp_threads = dependency('threads')

packet_pipeline = executable(
  'packet_pipeline',
  'packet_pipeline.cpp',
  include_directories : alt_cpp23_inc,
  install : false,
  dependencies : [cpp_threads],
)

if gtest_dep.found()
  test_l1_alt_cpp23 = executable(
    'test_l1_alt_cpp23',
    'tests/test_l1.cpp',
    dependencies : [gtest_dep],
    include_directories : alt_cpp23_inc,
    install : false,
  )
  test(
    '02-mempool-ring/alt-cpp23 - L1 (logica pura)',
    test_l1_alt_cpp23,
    protocol : 'gtest',
    suite : ['l1', 'alternativa'],
    timeout : 30,
  )
else
  # GTest ausente: registrar um marcador que PULA (codigo 77) em vez de
  # nao registrar nada. Sem isto a suite l1 encolhia em silencio e
  # reportava verde -- ver scripts/pular-sem-gtest.sh.
  test('02-mempool-ring/alt-cpp23 - L1 (logica pura)', bash,
       args : [meson.project_source_root() / 'scripts/pular-sem-gtest.sh',
               '02-mempool-ring/alt-cpp23 - L1 (logica pura)'],
       suite : ['l1', 'alternativa'], timeout : 30)
endif

test(
  '02-mempool-ring/alt-cpp23 - L2 (binario)',
  bash,
  args : [files('tests/l2_run.sh'), packet_pipeline],
  suite : ['l2', 'alternativa'],
  timeout : 120,
)

# Espelho em C++23 de custo-anel.c: mede o AnelSPSC com o MESMO protocolo, para
# que o nivel 2 da comparacao tenha os dois lados medidos. Precisa de
# estatistica.h, que vive no modulo de fundamentos.
alt_estat_inc = include_directories('../../../../../docs/01-fundamentos/medicoes')
custo_anel_cpp = executable(
  'custo-anel-cpp',
  'custo-anel-cpp.cpp',
  include_directories : [alt_cpp23_inc, alt_estat_inc],
  dependencies : [meson.get_compiler('cpp').find_library('m', required : false)],
  install : false,
)
test('02-mempool-ring/alt-cpp23 - L2 (anel SPSC em C++23)', custo_anel_cpp,
     suite : ['l2', 'alternativa'], timeout : 120)
