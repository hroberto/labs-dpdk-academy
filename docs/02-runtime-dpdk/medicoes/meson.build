# Medições do runtime (nível 3).
#
# Diferente das medições dos fundamentos, estas EXIGEM o DPDK: o objeto de
# estudo é a própria EAL — quanto custa subir, o que ela decide, e o que
# atravessa a fronteira entre um processo primário e um secundário.

runtime_libm = meson.get_compiler('c').find_library('m', required : false)

# estatistica.h é compartilhado com os fundamentos: mesma metodologia, mesma
# forma de publicar mediana, IQR e cauda. Reimplementá-la aqui produziria dois
# conjuntos de números não comparáveis entre si.
estatistica_inc = include_directories('../../01-fundamentos/medicoes')
runtime_inc = include_directories('.')

# --- Quanto custa a EAL nascer -------------------------------------------
custo_init = executable(
  'custo-init',
  'custo-init.c',
  dependencies : [dpdk_dep, runtime_libm],
  include_directories : [estatistica_inc],
  install : false,
)

# --- O que a EAL decidiu, e os estados do lcore ---------------------------
estado_lcore = executable(
  'estado-lcore',
  'estado-lcore.c',
  dependencies : [dpdk_dep],
  install : false,
)

# --- Feed de market data: primário e secundário ---------------------------
#
# Dois BINÁRIOS distintos de propósito. Se fossem duas threads de um processo,
# nada do modelo multiprocesso da EAL seria exercitado — e é justamente esse
# modelo que nenhum outro tópico do projeto cobre.
feed_primario = executable(
  'feed-primario',
  ['feed-primario.c', 'order_book.c'],
  dependencies : [dpdk_dep],
  include_directories : [runtime_inc],
  install : false,
)

feed_secundario = executable(
  'feed-secundario',
  ['feed-secundario.c', 'order_book.c'],
  dependencies : [dpdk_dep, runtime_libm],
  include_directories : [runtime_inc, estatistica_inc],
  install : false,
)

# --- L1: a lógica do livro, sem EAL ---------------------------------------
#
# livro.c não inclui nada do DPDK. É a única parte deste módulo que se testa em
# milissegundos, e a razão pela qual a separação existe.
if gtest_dep.found()
  test_l1_order_book = executable(
    'test_l1_order_book',
    ['tests/test_l1_order_book.cpp', 'order_book.c'],
    dependencies : [gtest_dep],
    include_directories : [runtime_inc],
    install : false,
  )
  test(
    '02-runtime - L1 (livro de ofertas)',
    test_l1_order_book,
    protocol : 'gtest',
    suite : ['l1', 'runtime'],
    timeout : 30,
  )
else
  # GTest ausente: registrar um marcador que PULA (codigo 77) em vez de
  # nao registrar nada. Sem isto a suite l1 encolhia em silencio e
  # reportava verde -- ver scripts/pular-sem-gtest.sh.
  test('02-runtime - L1 (livro de ofertas)', bash,
       args : [meson.project_source_root() / 'scripts/pular-sem-gtest.sh',
               '02-runtime - L1 (livro de ofertas)'],
       suite : ['l1', 'runtime'], timeout : 30)
endif

# --- L2: o runtime de verdade ---------------------------------------------

# `--no-huge` com prefixo próprio, e NÃO `--in-memory --no-huge`.
#
# A combinação que estava aqui é rejeitada pelo DPDK 23.11, que a CI usa:
# `--no-huge` liga `--legacy-mem` por dentro, e `--legacy-mem` é incompatível
# com `--in-memory`. A EAL responde "Option --legacy-mem is not compatible with
# --in-memory" e aborta. No 25.11 da máquina de referência a restrição não
# existe, então o defeito só aparecia no runner.
#
# `--in-memory` também servia para evitar arquivos de runtime em disco, o que
# importa porque o Meson roda os testes em PARALELO: sem isolamento, dois
# processos disputam /run/user/*/dpdk/rte/config e um deles falha com "Is
# another primary process running?". O `--file-prefix` distinto resolve isso
# sem depender de uma opção que não é portável.
test(
  '02-runtime - L2 (custo de init)',
  custo_init,
  args : ['-l', '0', '--no-huge', '--file-prefix=academy_custo_init'],
  suite : ['l2', 'runtime'],
  timeout : 300,
)

test(
  '02-runtime - L2 (estados do lcore)',
  estado_lcore,
  args : ['-l', '0-1', '--no-huge', '--file-prefix=academy_estado_lcore'],
  suite : ['l2', 'runtime'],
  timeout : 120,
)

# NIVEL L3: exige memória compartilhada REAL -- hugetlbfs com permissão de
# escrita. Onde não houver, o script sai com 77 e o Meson conta como PULADO.
#
# Saía com 0 antes, e o Meson reportava OK com as nove verificações do script
# NÃO avaliadas. No runner do CI o requisito nunca existe, então este teste
# jamais verificou coisa alguma e sempre apareceu verde.
test(
  '02-runtime - L3 (primario + secundario)',
  bash,
  args : [files('tests/l3_multiprocesso.sh'), feed_primario, feed_secundario],
  suite : ['l3', 'runtime'],
  timeout : 180,
)

# EIXO DE FALHA (ROADMAP, Etapa 7.5): o mesmo par de processos, mas com o
# primário morto por SIGKILL no meio da publicação. Também L3, e pelo mesmo
# motivo: sem hugetlbfs compartilhado não há o que derrubar.
test(
  '02-runtime - L3 (primario morre, secundario continua)',
  bash,
  args : [files('tests/l3_primario_morre.sh'), feed_primario, feed_secundario],
  suite : ['l3', 'runtime'],
  timeout : 180,
)
