# Tópico 02 — mempool, ring e processamento em lote.
#
# A lógica de pacote vive em pacote.c, separada de pipeline_ring.c, justamente
# para poder ser testada sem EAL (L1). O runtime é exercitado no L2.

pacote_inc = include_directories('.')

pipeline_ring = executable(
  'pipeline_ring',
  ['pipeline_ring.c', 'packet.c'],
  dependencies : [dpdk_dep],
  include_directories : pacote_inc,
  install : false,
)

# --- L1: lógica pura, sem DPDK, sem EAL ---
if gtest_dep.found()
  test_l1_mempool_ring = executable(
    'test_l1_mempool_ring',
    ['tests/test_l1.cpp', 'packet.c'],
    dependencies : [gtest_dep],
    include_directories : pacote_inc,
    install : false,
  )
  test(
    '02-mempool-ring - L1 (logica pura)',
    test_l1_mempool_ring,
    protocol : 'gtest',
    suite : ['l1', 'dpdk'],
    timeout : 30,
  )
else
  # GTest ausente: registrar um marcador que PULA (codigo 77) em vez de
  # nao registrar nada. Sem isto a suite l1 encolhia em silencio e
  # reportava verde -- ver scripts/pular-sem-gtest.sh.
  test('02-mempool-ring - L1 (logica pura)', bash,
       args : [meson.project_source_root() / 'scripts/pular-sem-gtest.sh',
               '02-mempool-ring - L1 (logica pura)'],
       suite : ['l1', 'dpdk'], timeout : 30)
endif

# --- Variante com VAZAMENTO DELIBERADO, para o teste negativo -------------
#
# Mesmo fonte, com a devolução ao pool do retorno parcial removida por macro.
# Sem isto, o invariante verificado por pipeline_ring.c nunca seria exercitado
# no caminho de falha, e não haveria evidência de que ele dispara.
pipeline_ring_vazado = executable(
  'pipeline_ring_vazado',
  ['pipeline_ring.c', 'packet.c'],
  dependencies : [dpdk_dep],
  include_directories : pacote_inc,
  c_args : ['-DDPDK_ACADEMY_INJECT_LEAK'],
  install : false,
)

# --- L2: mempool e ring reais sob a EAL ---
test(
  '02-mempool-ring - L2 (mempool + ring)',
  bash,
  args : [files('tests/l2_run.sh'), pipeline_ring, pipeline_ring_vazado],
  suite : ['l2', 'dpdk'],
  timeout : 120,
)

# Alternativa sem DPDK para o MESMO problema deste tópico.
subdir('alternativas/cpp23')
