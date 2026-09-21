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


# PROVENIENCIA: ver o cabecalho de `academy_version.h.in`. O arquivo de entrada
# e o MESMO do modulo 01 -- duplica-lo criaria dois lugares para a mesma regra
# envelhecer em direcoes diferentes.
versao_h = vcs_tag(
  input : files('../../01-fundamentos/medicoes/academy_version.h.in'),
  output : 'academy_version.h',
  command : ['git', 'describe', '--always', '--dirty', '--tags'],
  fallback : 'sem-git',
)

# --- Quanto custa a EAL nascer -------------------------------------------
custo_init = executable(
  'custo-init',
  'custo-init.c',
    versao_h,
  dependencies : [dpdk_dep, runtime_libm],
  include_directories : [estatistica_inc],
  install : false,
)

# --- O que a EAL decidiu, e os estados do lcore ---------------------------
estado_lcore = executable(
  'estado-lcore',
  'estado-lcore.c',
    versao_h,
    include_directories : [estatistica_inc],
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
  ['feed-primario.c',
    versao_h, 'order_book.c'],
  dependencies : [dpdk_dep],
  include_directories : [runtime_inc, estatistica_inc],
  install : false,
)

feed_secundario = executable(
  'feed-secundario',
  ['feed-secundario.c',
    versao_h, 'order_book.c'],
  dependencies : [dpdk_dep, runtime_libm],
  include_directories : [runtime_inc, estatistica_inc],
  install : false,
)

# --- L1: a lógica do livro, sem EAL ---------------------------------------
#
# livro.c não inclui nada do DPDK. É a única parte deste módulo que se testa em
# milissegundos, e a razão pela qual a separação existe.
# A logica de saude do feed -- HEALTHY / SILENT / STALE / WRONG_GENERATION --
# nao tinha NENHUMA cobertura executada: o teste existia no disco e nao era
# compilado nem registrado. E o contrato que distingue "o primario esta vivo" de
# "os dados estao atuais", que e a diferenca entre heartbeat e frescor: um feed
# pode bater o coracao e publicar dado velho.
if gtest_dep.found()
  test_l1_feed_health = executable(
    'test_l1_feed_health',
    ['tests/test_l1_feed_health.cpp'],
    dependencies : [gtest_dep],
    include_directories : [runtime_inc],
    install : false,
  )
  test(
    '02-runtime - L1 (saude do feed)',
    test_l1_feed_health,
    protocol : 'gtest',
    suite : ['l1', 'runtime'],
    timeout : 30,
  )
else
  test('02-runtime - L1 (saude do feed)', bash,
       args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-gtest.sh',
               '02-runtime - L1 (saude do feed)'],
       suite : ['l1', 'runtime'], timeout : 30)
endif

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
  # reportava verde -- ver ferramental/qualidade/pular-sem-gtest.sh.
  test('02-runtime - L1 (livro de ofertas)', bash,
       args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-gtest.sh',
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
  bash,
  args : [files('../../../scripts/tests/com-limpeza.sh'), 'academy_custo_init', custo_init,
          '-l', '0', '--no-huge'],
  suite : ['l2', 'runtime'],
  timeout : 300,
)

# Regressao: EAL rejeitada nao pode virar uma medicao aprovada.
#
# custo-init.c saia com 0 quando a EAL nao subia, com o comentario "ambiente,
# nao defeito: o teste L2 continua valido" -- valido sem ter medido nada. Hoje
# sai com EXIT_FAILURE, e este teste tranca esse comportamento passando uma
# opcao que a EAL rejeita.
#
# E FALHA e nao PULO porque a configuracao foi PEDIDA por argumento: se ela nao
# sobe, o pedido nao foi atendido, e isso e resultado negativo, nao requisito
# ausente.
test(
  '02-runtime - L2 (init invalida deve falhar)',
  custo_init,
  args : ['-l', '0', '--no-huge', '--dpdk-academy-opcao-invalida'],
  should_fail : true,
  suite : ['l2', 'runtime'],
  timeout : 30,
)

test(
  '02-runtime - L2 (estados do lcore)',
  bash,
  args : [files('../../../scripts/tests/com-limpeza.sh'), 'academy_estado_lcore', estado_lcore,
          '-l', '0-1', '--no-huge'],
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


# --- L3: o primario cai e a sessao se recupera -----------------------------
#
# Exercita o supervisor: primario morto por injecao, secundario detectando a
# mudanca de geracao, e a sessao seguinte publicando de novo. E o contrato de
# RECUPERACAO, que SECURITY.md e a matriz de requisitos tratam no mesmo patamar
# da trava -- e que nao tinha nenhuma execucao: o script existia no disco e
# nunca foi registrado em meson.build nenhum.
#
# L3 porque exige hugetlbfs gravavel com paginas livres; onde faltar, o proprio
# script sai com 77 e o Meson conta como PULADO.
test(
  '02-runtime - L3 (recuperacao apos queda do primario)',
  bash,
  args : [files('tests/l3_recuperacao.sh'), feed_primario, feed_secundario,
          meson.project_source_root() / 'scripts/feed-supervisor.py'],
  suite : ['l3', 'runtime'],
  timeout : 300,
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
