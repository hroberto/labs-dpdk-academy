# Tópico 03 — afinidade não é isolamento.
#
# A aritmética da janela e o parser de /proc/interrupts vivem em gap_hist.c e
# procstat.c, separados das sondas, justamente para serem testados sem EAL e
# sem privilégio (L1). As sondas não usam DPDK: a pergunta é sobre o sistema
# operacional, e a resposta precisa valer para qualquer laço de polling.

# O segundo diretorio traz `argumento.h`: conversao de argumento que recusa em
# vez de devolver zero, porque aqui zero e uma CPU legitima.
isolamento_inc = include_directories('.', '../../../docs/01-fundamentos/medicoes')

stall_probe = executable(
  'stall_probe',
  ['stall_probe.c', 'gap_hist.c', 'procstat.c'],
  dependencies : [dependency('threads')],
  include_directories : isolamento_inc,
  install : false,
)

# VARIANTE COM O PROVOCADOR LENTO, para exercitar o handshake.
#
# O programa espera o provocador anunciar que esta ativo E que deu a primeira
# volta antes de abrir a janela medida. Numa execucao normal isso acontece em
# microssegundos, e o caminho de recusa nunca roda -- indistinguivel de nao
# existir. Aqui a thread demora 3 s de proposito, contra o limite de 2 s.
stall_probe_inj = executable(
  'stall_probe_injecao',
  ['stall_probe.c', 'gap_hist.c', 'procstat.c'],
  c_args : ['-DDPDK_ACADEMY_INJECAO'],
  dependencies : [dependency('threads')],
  include_directories : isolamento_inc,
  install : false,
)

test('03-performance - L1 (provocador sem carga nao abre a janela)', bash,
     args : [meson.project_source_root() / 'trilha/03-performance/03-isolamento-cpu/tests/l1_provocador_lento.sh',
             stall_probe_inj, stall_probe],
     suite : ['l1', 'performance'], timeout : 60)

executable(
  'ipi_provoker',
  'ipi_provoker.c',
  include_directories : isolamento_inc,
  install : false,
)

# --- L1: aritmética e parser, sem EAL e sem privilégio ---
if gtest_dep.found()
  test_l1_isolamento = executable(
    'test_l1_isolamento',
    ['tests/test_l1.cpp', 'gap_hist.c', 'procstat.c'],
    dependencies : [gtest_dep],
    include_directories : isolamento_inc,
    install : false,
  )
  test('03-performance - L1 (janela e /proc/interrupts)', test_l1_isolamento,
       suite : ['l1', 'performance'], timeout : 30)
endif

# --- L2: a sonda roda e produz relato coerente ---
#
# Não afirma NADA sobre o valor das paradas: isso depende da máquina e é o
# objeto da medição. O que se verifica é que a sonda mede, classifica e relata
# — inclusive quando /proc/interrupts não está legível.
test('03-performance - L2 (a sonda de paradas roda)', bash,
     args : [files('tests/l2_run.sh'), stall_probe],
     suite : ['l2', 'performance'], timeout : 60)
