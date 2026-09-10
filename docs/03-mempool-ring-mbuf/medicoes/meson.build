# Medições do nível 4 — mempool, ring e mbuf.
#
# Diferente dos fundamentos, estas exigem o DPDK: o objeto de estudo são as
# estruturas de dados do próprio DPDK, e o que se mede é o custo delas contra a
# alternativa da biblioteca padrão.

nivel4_libm = meson.get_compiler('c').find_library('m', required : false)
nivel4_estat = include_directories('../../01-fundamentos/medicoes')
nivel4_inc = include_directories('.')

custo_alocacao = executable(
  'custo-alocacao',
  ['custo-alocacao.c', 'sizing.c'],
  dependencies : [dpdk_dep, nivel4_libm, dependency('threads')],
  include_directories : [nivel4_estat, nivel4_inc],
  install : false,
)

# --- L1: as regras de dimensionamento, sem EAL ----------------------------
#
# dimensionamento.c nao inclui nada do DPDK. E a unica parte deste modulo que
# se testa em milissegundos, e existe porque tres das quatro regras de
# dimensionamento de mempool falham em SILENCIO.
if gtest_dep.found()
  test_l1_sizing = executable(
    'test_l1_sizing',
    ['tests/test_l1_sizing.cpp', 'sizing.c'],
    dependencies : [gtest_dep],
    include_directories : [nivel4_inc],
    install : false,
  )
  test(
    '03-nivel4 - L1 (dimensionamento de mempool)',
    test_l1_sizing,
    protocol : 'gtest',
    suite : ['l1', 'nivel4'],
    timeout : 30,
  )
else
  # GTest ausente: registrar um marcador que PULA (codigo 77) em vez de
  # nao registrar nada. Sem isto a suite l1 encolhia em silencio e
  # reportava verde -- ver scripts/pular-sem-gtest.sh.
  test('03-nivel4 - L1 (dimensionamento de mempool)', bash,
       args : [meson.project_source_root() / 'scripts/pular-sem-gtest.sh',
               '03-nivel4 - L1 (dimensionamento de mempool)'],
       suite : ['l1', 'nivel4'], timeout : 30)
endif

test('03-nivel4 - L2 (custo de alocacao)', custo_alocacao,
     args : ['-l', '0', '--in-memory', '--no-huge'],
     suite : ['l2', 'nivel4'], timeout : 300)

# --- Eixo de falha (ROADMAP, Etapa 7.5) -----------------------------------
#
# Nao mede tempo: mede COMPORTAMENTO na fronteira do pool esgotado, e confronta
# a regra 4 de dimensionamento -- ate aqui so aritmetica testada em L1 -- com um
# mempool de verdade. Por isso e L2, e nao L3: nao exige varios nucleos nem
# hugepages, so a EAL.
pool_esgotado = executable(
  'pool-esgotado',
  ['pool-esgotado.c', 'sizing.c'],
  dependencies : [dpdk_dep],
  include_directories : [nivel4_inc],
  install : false,
)
test('03-nivel4 - L2 (pool esgotado e regra 4)', pool_esgotado,
     args : ['-l', '0', '--in-memory', '--no-huge'],
     suite : ['l2', 'nivel4'], timeout : 60)

anatomia_mbuf = executable(
  'anatomia-mbuf',
  'anatomia-mbuf.c',
  dependencies : [dpdk_dep],
  install : false,
)

test('03-nivel4 - L2 (anatomia do mbuf)', anatomia_mbuf,
     args : ['-l', '0', '--in-memory', '--no-huge'],
     suite : ['l2', 'nivel4'], timeout : 120)

custo_anel = executable(
  'custo-anel',
  'custo-anel.c',
  dependencies : [dpdk_dep, nivel4_libm],
  include_directories : [nivel4_estat],
  install : false,
)

test('03-nivel4 - L2 (custo do anel)', custo_anel,
     args : ['-l', '0', '--in-memory', '--no-huge'],
     suite : ['l2', 'nivel4'], timeout : 300)

# --- O regime em que o mempool ganha: contenção entre núcleos --------------
#
# Exige VÁRIOS NÚCLEOS FÍSICOS -- e o programa NÃO se adapta sozinho: a EAL
# rejeita a linha de comando antes de ele rodar quando um lcore da lista não
# existe. Daí o guarda em tests/l3_contencao.sh, que pula com código 77.
custo_contencao = executable(
  'custo-contencao',
  'custo-contencao.c',
  dependencies : [dpdk_dep, dependency('threads'), nivel4_libm],
  include_directories : [nivel4_estat],
  install : false,
)

test('03-nivel4 - L3 (contencao entre nucleos)', bash,
     args : [files('tests/l3_contencao.sh'), custo_contencao],
     suite : ['l3', 'nivel4'], timeout : 300)
