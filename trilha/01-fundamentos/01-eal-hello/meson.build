# Tópico 01 — Inicialização da EAL.
#
# Não há teste L1 aqui: o tópico não tem lógica pura para isolar; ele É a
# inicialização do runtime. Toda a verificação é L2.

hello_dpdk = executable(
  'hello_dpdk',
  'hello_dpdk.c',
  dependencies : [dpdk_dep],
  install : false,
)

test(
  '01-eal-hello - L2 (EAL real)',
  bash,
  args : [files('tests/l2_run.sh'), hello_dpdk],
  suite : ['l2', 'dpdk'],
  timeout : 60,
)
