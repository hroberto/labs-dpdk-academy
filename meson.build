project(
  'dpdk-academy',
  'c',
  'cpp',
  version : '1.00.00',
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
# DPDK é dependência de AMBIENTE: recursos de memoria e preparacao da NIC
# dependem do cenario e do PMD (VFIO ou driver bifurcado, como mlx5).
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
# os casos GoogleTest sao pulados; os demais L1 e os L2 seguem rodando.
gtest_dep = dependency('gtest_main', required : false, allow_fallback : true)
if not gtest_dep.found()
  message('GTest indisponivel: os casos GoogleTest de L1 serao pulados; scripts continuam. Para habilita-los, rode "meson subprojects download".')
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
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-ancoras.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 60)

  # O verificador do verificador. `--autoteste` monta uma arvore temporaria com
  # ancora viva, ancora morta e cinco iscas de falso positivo, roda o
  # verificador de verdade contra ela e faz assercoes sobre a saida real.
  #
  # Ele existia e NAO estava registrado em lugar nenhum -- so rodava se alguem
  # lembrasse de invoca-lo a mao, que e a mesma classe de defeito que ele foi
  # escrito para fechar: verificacao que existe e nao e executada. E hermetico
  # (nao toca a arvore) e leva ~0,05 s.
  #
  # RESSALVA MEDIDA, para que este registro nao prometa demais: removendo a
  # guarda DEPOIS_DA_PALAVRA do scanner de heredoc, o --autoteste continua
  # dizendo "0 assercao(oes) falharam". Ele trava as iscas de falso positivo e
  # a checagem de conteudo; NAO trava a reincidencia do heredoc que motivou sua
  # criacao. Registrar e melhor que nao registrar, e nao equivale a cobrir.
  test('docs - autoteste do verificador de ancoras', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-ancoras.py',
               '--autoteste'],
       suite : ['l1', 'docs'], timeout : 60)

  # Links relativos e ancoras de titulo, com a regra REAL do github-slugger:
  # cada espaco vira um hifen, sem colapsar. Um validador que colapse deixa
  # passar ancora morta em titulo com travessao.
  test('docs - links e ancoras de titulo', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-links.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 60)

  # PORTAO: valor retratado nao pode sobreviver fora do bloco que o retrata.
  #
  # Nasceu de reincidencia medida, e nao de teoria: em 15/09/2026, na MESMA
  # sessao em que a regra foi enunciada num estudo, duas retratacoes pararam no
  # meio -- 2,078 ns continuou publicado na pagina de sintese, e um "22 ns"
  # retratado sobreviveu em outros dois pontos do proprio documento que o
  # retratava. Quem errou conhecia a regra e tinha acabado de escreve-la.
  # Correcao manual nao escala para "nenhum numero retratado sobrevive".
  test('docs - numeros retratados nao sobrevivem', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-retratacoes.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 60)

  # O verificador do verificador: tres casos (limpo, sobrevivente, retratacao
  # sem marca). O terceiro trava a contagem de cobertura parcial -- sem ele,
  # um repositorio de retratacoes nao marcadas sairia verde.
  test('docs - autoteste do verificador de retratacoes', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-retratacoes.py',
               '--autoteste'],
       suite : ['l1', 'docs'], timeout : 60)

  # PORTAO: percentual que o proprio texto torna conferivel tem de fechar.
  #
  # "100 dos 123 ms, 83%" punha numerador, denominador e resultado na mesma
  # frase -- e 100/123 e 81,3%. Os 83% vinham de um denominador publicado em
  # outra tabela. O erro sobreviveu a varias leituras porque ninguem multiplica
  # ao ler; computador multiplica sem se cansar.
  test('docs - aritmetica publicada fecha', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-aritmetica.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 60)

  test('docs - autoteste do verificador de aritmetica', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-aritmetica.py',
               '--autoteste'],
       suite : ['l1', 'docs'], timeout : 60)

  # PORTAO: o que o material afirma SOBRE SI tem de corresponder ao disco.
  #
  # Um documento de 268 linhas, com 200 de medicao, carregava o banner "o
  # conteudo ainda nao foi escrito"; e o README prometia arm64 enquanto quatro
  # programas usavam builtin so-x86 em doze pontos sem guarda. Nenhum dos dois e
  # visivel para quem le: um exige contar linhas, o outro exige cruzar a porta
  # de entrada com o codigo.
  test('docs - autodescricao corresponde ao disco', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-autodescricao.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 60)

  test('docs - autoteste do verificador de autodescricao', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-autodescricao.py',
               '--autoteste'],
       suite : ['l1', 'docs'], timeout : 60)
else
  # python3 ausente: registrar marcadores que PULAM (codigo 77) em vez de nao
  # registrar nada. Sem isto a suite l1 encolhia em TRES testes e reportava
  # verde -- e os tres sao justamente os que conferem se o material diz a
  # verdade. Ver ferramental/qualidade/pular-sem-python3.sh.
  foreach nome : ['docs - ancoras de linha atualizadas',
                  'docs - autoteste do verificador de ancoras',
                  'docs - links e ancoras de titulo',
                  'docs - numeros retratados nao sobrevivem',
                  'docs - autoteste do verificador de retratacoes',
                  'docs - aritmetica publicada fecha',
                  'docs - autoteste do verificador de aritmetica',
                  'docs - autodescricao corresponde ao disco',
                  'docs - autoteste do verificador de autodescricao']
    test(nome, bash,
         args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-python3.sh', nome],
         suite : ['l1', 'docs'], timeout : 30)
  endforeach
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

# Shell e decodificador têm dependências diferentes e resultados separados.
test('scripts - L1 (veredito AF_XDP zero-copy)', bash,
     args : [meson.project_source_root() / 'ferramental/af-xdp/l1_xdp.sh'],
     suite : ['l1', 'scripts'], timeout : 30)
test('scripts - L1 (bitmask AF_XDP)', bash,
     args : [meson.project_source_root() / 'ferramental/af-xdp/l1_xdp_bitmask.sh'],
     suite : ['l1', 'scripts'], timeout : 30)

# Camada NETLINK de ferramental/af-xdp/xdp-features.py: parse de TLV, alinhamento NLA,
# truncamento, ext_ack e higienizacao de nome de interface.
#
# E L1 apesar do nome: nao abre socket nenhum. O modulo e importado com
# `socket.socket` trocado por uma sentinela que aborta se for chamada, e os
# bytes de entrada sao montados a mao com `struct.pack` -- nao com o proprio
# construtor do modulo, para que um erro de alinhamento no construtor nao
# cancele o erro simetrico no parser.
#
# Registrado FORA do `if python3.found()` pelo mesmo motivo do teste acima, e
# aqui a diferenca em relacao a ele importa: sem python3 este teste sai 77, que
# o Meson (protocolo 'exitcode', o padrao) le como SKIP -- nao como sucesso.
# Com interpretador, o teste informa a contagem de assercoes; sem ele, zero e
# um SKIP que nomeia as OITO funcoes que ficaram sem cobertura (o numero era
# "sete" aqui e "oito" no proprio SKIP, escritos em paralelo sobre o mesmo
# bloco de saida; conferido com
#     PATH=<sem python3> bash ferramental/af-xdp/l1_xdp_netlink.sh | grep -c '^  SKIP      '
# ). Um gate aqui
# apagaria essa distincao, que e justamente a que este conjunto de arquivos
# existe para defender: "nao consegui apurar" nao pode ter a mesma cara de
# "esta correto".
test('scripts - L1 (camada netlink de xdp-features.py)', bash,
     args : [meson.project_source_root() / 'ferramental/af-xdp/l1_xdp_netlink.sh'],
     suite : ['l1', 'scripts'], timeout : 30)

# xdp-zerocopy.sh EXECUTADO, com fontes controladas.
#
# INCIDENTE que este registro fecha: ate agora nenhum teste da arvore executava
# ferramental/af-xdp/xdp-zerocopy.sh -- `grep -rn xdp-zerocopy scripts/tests/ meson.build`
# so achava mencao em comentario. Por isso o defeito fundador daquele arquivo
# ("informacao nao apurada publicada como fato negativo") voltou DUAS vezes sem
# que a suite mudasse de cor, e a segunda vez veio dentro da propria correcao.
# Medido antes deste teste existir: tres mutacoes que reintroduzem o defeito
# literalmente -- remover a comparacao `fim > tamanho` de `_elf_defeito`,
# trocar a guarda do rc do `nm` por `if false`, desligar a conferencia da
# magica ELF -- passavam pela suite L1 inteira sem uma falha. Com o teste
# registrado, onze mutacoes desse tipo sao pegas.
#
# E L1 e roda em CI porque nao precisa de NIC, de root NEM de python3: as
# fontes (modinfo, nm, zstd, o helper, xdp-loader, o uid) sao stubs no PATH, os
# modulos sao ELFs sinteticos escritos byte a byte, e /sys/class/net e
# redirecionado por DPDK_ACADEMY_SYSFS_NET. Sem gate, pelo mesmo motivo dos
# dois testes acima.
test('scripts - L1 (xdp-zerocopy.sh com fontes controladas)', bash,
     args : [meson.project_source_root() / 'ferramental/af-xdp/l1_xdp_zerocopy.sh'],
     suite : ['l1', 'scripts'], timeout : 60)

subdir('docs/01-fundamentos/medicoes')
test('scripts - L1 (apuracao e mutacoes)', bash,
     args : [meson.project_source_root() / 'scripts/tests/l1_apuracao.sh'],
     suite : ['l1', 'scripts'], timeout : 60)

test('02-runtime - L1 (FAIL e SKIP dos runners multiprocesso)', bash,
     args : [meson.project_source_root() / 'docs/02-runtime-dpdk/medicoes/tests/l1_multiprocesso.sh'],
     suite : ['l1', 'runtime'], timeout : 60)

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

if python3.found()
  test('runtime - L2 (supervisor e nova geracao)', python3,
    args : [meson.project_source_root() / 'scripts/tests/l2_feed_supervisor.py'],
    suite : ['l2', 'runtime'], timeout : 20)
else
  test('runtime - L2 (supervisor e nova geracao)', bash,
    args : ['-c', 'echo "SKIP: supervisor exige python3"; exit 77'],
    suite : ['l2', 'runtime'], timeout : 20)
endif

test('scripts - L1 (dependencias separadas do XDP)', bash,
  args : [meson.project_source_root() / 'ferramental/af-xdp/l1_xdp_dependencias.sh'],
  suite : ['l1', 'scripts'], timeout : 30)
