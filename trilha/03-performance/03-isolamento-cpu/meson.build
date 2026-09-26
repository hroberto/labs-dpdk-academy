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
