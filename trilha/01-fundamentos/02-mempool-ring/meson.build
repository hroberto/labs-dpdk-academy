# Tópico 02 — mempool, ring e processamento em lote.
#
# A lógica de pacote vive em pacote.c, separada de pipeline_ring.c, justamente
# para poder ser testada sem EAL (L1). O runtime é exercitado no L2.

pacote_inc = include_directories('.')

pipeline_ring = executable(
  'pipeline_ring',
  ['pipeline_ring.c', 'packet.c', versao_h],
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
  # reportava verde -- ver ferramental/qualidade/pular-sem-gtest.sh.
  test('02-mempool-ring - L1 (logica pura)', bash,
       args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-gtest.sh',
               '02-mempool-ring - L1 (logica pura)'],
       suite : ['l1', 'dpdk'], timeout : 30)
endif

# --- Variante com VAZAMENTO DELIBERADO, para o teste negativo -------------
#
# Mesmo fonte, com a devolução ao pool do retorno parcial removida por macro.
# Sem isto, o invariante verificado por pipeline_ring.c nunca seria exercitado
# no caminho de falha, e não haveria evidência de que ele dispara.
# --- Variante com CONSUMIDOR PARADO, para o teste de espera limitada -----
#
# Mesmo fonte, com o consumo removido por macro. Sem ela, o prazo de progresso
# (`-t`) nunca seria exercitado no caminho em que estoura, e prazo que nunca
# estourou e indistinguivel de prazo que nunca e conferido -- mesma razao do
# pipeline_ring_vazado logo abaixo.
pipeline_ring_pausado = executable(
  'pipeline_ring_pausado',
  ['pipeline_ring.c', 'packet.c', versao_h],
  dependencies : [dpdk_dep],
  include_directories : pacote_inc,
  c_args : ['-DDPDK_ACADEMY_INJECT_PAUSE'],
  install : false,
)

pipeline_ring_vazado = executable(
  'pipeline_ring_vazado',
  ['pipeline_ring.c', 'packet.c', versao_h],
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

# --- L2: a espera limitada, exercitada no caminho em que ela dispara ------
#
# `-t` e prazo de PROGRESSO: quanto tempo se aceita sem que nenhum pacote
# avance. A variante com consumidor parado estoura o prazo de proposito, e o
# teste exige as quatro coisas que caracterizam desistencia limpa:
#
#   codigo 3 (distinto de 1, que e invariante violado)
#   a frase SEM PROGRESSO
#   o pool DEVOLVIDO INTEIRO -- desistir nao autoriza encerrar sujo
#   a contagem dos objetos descartados na drenagem
#
# O modo `leak` do mesmo script NAO e registrado aqui, e a razao e concreta: ele
# invoca `-n 64`, e com 64 pacotes o anel de 4096 nunca enche -- o vazamento
# vive no caminho de RETORNO PARCIAL, que so executa com a fila cheia. A
# cobertura do vazamento esta em l2_run.sh, que verifica a pre-condicao antes de
# afirmar, repetindo com -n maior ate a fila encher de fato.
test(
  '02-mempool-ring - L2 (espera limitada, consumidor parado)',
  bash,
  args : [files('tests/l2_failure.sh'), pipeline_ring_pausado, 'paused'],
  suite : ['l2', 'dpdk'],
  timeout : 60,
)

test(
  '02-mempool-ring - L2 (espera limitada, dois lcores)',
  bash,
  args : [files('tests/l2_failure.sh'), pipeline_ring_pausado, 'pausedtwo'],
  suite : ['l2', 'dpdk'],
  timeout : 60,
)

# Alternativa sem DPDK para o MESMO problema deste tópico.
subdir('alternativas/cpp23')
