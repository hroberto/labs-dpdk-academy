project(
  'dpdk-academy',
  'c',
  'cpp',
  version : '0.01.00',
  meson_version : '>=1.1',
  default_options : [
    'warning_level=3',
    # C11 do padrao ISO -- o mesmo que o DPDK usa upstream.
    #
    # A versao anterior deste arquivo pedia 'gnu11', porque com 'c11' os
    # cabecalhos do DPDK falham em ssize_t e strnlen. O diagnostico estava certo
    # e a correcao, errada: esses simbolos sao POSIX/GNU e vem de _GNU_SOURCE,
    # nao do padrao da linguagem. Trocar o padrao para gnu11 resolvia o sintoma
    # e escondia o mecanismo. Cada fonte declara #define _GNU_SOURCE na primeira
    # linha, que e como o proprio DPDK faz.
    'c_std=c11',
    'cpp_std=c++23',
    'buildtype=debugoptimized',
  ],
)

# ---------------------------------------------------------------------------
# Dependências
#
# DPDK é dependência de AMBIENTE, não de pacote: além das bibliotecas, exige
# hugepages, drivers (vfio-pci/uio) e, para NIC física, binding do dispositivo.
# Por isso vem do sistema (via pkg-config), e não de um gerenciador de pacotes.
# Use scripts/check-env.sh para diagnosticar o que falta.
# ---------------------------------------------------------------------------
# VERSAO MINIMA: 23.11.
#
# Nao e chute: e a release que a CI usa (dpdk-dev do Ubuntu 24.04) e onde a
# suite passa de ponta a ponta. A maquina de referencia roda 25.11, e a
# diferenca entre as duas ja produziu dois defeitos que so apareceram no par:
#
#   - `--in-memory --no-huge` juntos: rejeitado ate o 23.11, aceito no 25.11,
#     porque `--no-huge` ligava `--legacy-mem`;
#   - codigo de saida e mensagem de argumento desconhecido: vem de
#     `librte_argparse`, que so existe a partir do 24.03.
#
# Declarar o minimo transforma "nao compila" numa mensagem util em vez de num
# erro de simbolo ausente no meio do build. Abaixo de 23.11 nao foi testado --
# pode funcionar, e nao afirmamos que funciona.
dpdk_dep = dependency(
  'libdpdk',
  method : 'pkg-config',
  version : '>=23.11',
  required : true,
  not_found_message : 'DPDK nao encontrado, ou anterior a 23.11 (minimo testado). Instale o pacote de desenvolvimento (Debian/Ubuntu: dpdk-dev; Fedora/RHEL: dpdk-devel) e confirme com "pkg-config --modversion libdpdk". Veja scripts/check-env.sh.',
)

# GTest sustenta os testes L1 (lógica pura). É opcional de propósito: sem rede
# para baixar o subprojeto, o build dos tópicos continua funcionando e apenas
# os testes L1 são pulados — os L2 seguem rodando.
gtest_dep = dependency('gtest_main', required : false, allow_fallback : true)
if not gtest_dep.found()
  message('GTest indisponivel: os testes L1 serao pulados. Para habilita-los, rode "meson subprojects download".')
endif

# Runner dos testes L2: eles exercitam o BINARIO como o estudante o executa,
# incluindo argumentos da EAL, por isso sao scripts e nao codigo de teste.
bash = find_program('bash')

# Cada topico e autocontido: documento, codigo, testes e, quando existir,
# a alternativa sem DPDK para o mesmo problema (adicionada pelo proprio topico).
# Ancoras de linha nos documentos apontam para o codigo que produziu cada
# numero. Numeros de linha mudam quando o codigo muda, e um link desatualizado
# aponta em silencio para o trecho errado -- por isso e verificado como teste.
python3 = find_program('python3', required : false)
if python3.found()
  test('docs - ancoras de linha atualizadas', python3,
       args : [meson.project_source_root() / 'scripts/verificar-ancoras.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 60)

  # Links relativos e ancoras de titulo, com a regra REAL do github-slugger:
  # cada espaco vira um hifen, sem colapsar. Um validador que colapse deixa
  # passar ancora morta em titulo com travessao.
  test('docs - links e ancoras de titulo', python3,
       args : [meson.project_source_root() / 'scripts/verificar-links.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 60)
endif

# Classificacao do modelo de driver de NIC (captura total x bifurcado).
#
# E L1 porque e logica pura: recebe o vendor PCI como argumento e nao toca em
# hardware. Existe para que o caminho da Mellanox -- que nenhuma placa desta
# maquina exercita -- esteja testado ANTES de a ConnectX-4 Lx chegar. Errar essa
# decisao significa bindar ao vfio-pci uma placa bifurcada, que para de
# funcionar dos dois lados.
test('scripts - L1 (modelo de driver de NIC)', bash,
     args : [meson.project_source_root() / 'scripts/tests/l1_lib_nic.sh'],
     suite : ['l1', 'scripts'], timeout : 30)

subdir('docs/01-fundamentos/medicoes')
subdir('docs/02-runtime-dpdk/medicoes')
subdir('docs/03-mempool-ring-mbuf/medicoes')
subdir('trilha/01-fundamentos/01-eal-hello')
subdir('trilha/01-fundamentos/02-mempool-ring')

summary({
  'DPDK'          : dpdk_dep.version(),
  'GTest (L1)'    : gtest_dep.found() ? 'sim' : 'nao (testes L1 pulados)',
  'padrao C'      : get_option('c_std'),
  'padrao C++'    : get_option('cpp_std'),
}, section : 'DPDK Academy')
