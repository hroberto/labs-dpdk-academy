project(
  'dpdk-academy',
  'c',
  'cpp',
  version : '1.02.01',
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
  # ESTE REGISTRO JA FOI UM VERDE LIGADO A NADA, e a correcao e de 16/09/2026.
  #
  # Ate entao verificar-ancoras.py NAO TINHA a opcao --autoteste. A string virava
  # o diretorio-raiz; `os.walk` de um caminho inexistente nao devolve nada; o
  # script imprimia "0 ancoras verificadas, 0 desatualizadas" e saia ZERO. O
  # teste passava sem conferir coisa alguma, contado entre os da suite e
  # executado pela CI.
  #
  # E o comentario que estava aqui descrevia as garantias desse autoteste em
  # detalhe, citando uma guarda `DEPOIS_DA_PALAVRA` que nunca existiu em codigo
  # nenhum -- `git log -S` a encontra apenas dentro deste proprio comentario.
  # Uma ressalva que parecia cautelosa documentava um programa imaginario.
  #
  # Hoje ha autoteste de verdade, com caso para cada uma das tres regras, isca de
  # falso positivo, e o caso 7 travando o proprio defeito: raiz inexistente
  # precisa ACUSAR em vez de sair zero.
  #
  # Nao-vacuidade, medida: 5 mutantes plantados -- ignorar alvo inexistente,
  # ignorar linha fora do arquivo, ignorar simbolo ausente, remover o
  # fail-closed, e estreitar o padrao para nao casar faixa --, 5 mortos.
  # O verificador de MAIOR alcance da arvore -- ele sozinho confere todos os
  # links relativos e ancoras de titulo de todo .md, e o numero sai na propria
  # execucao -- foi o ultimo a ganhar autoteste, e a assimetria era o problema:
  # quanto mais coisa ele
  # cobre, mais cara sai a falha silenciosa. Um verificador que passa a aceitar
  # tudo continua imprimindo "N links verificados, 0 quebrados", e esse verde e
  # indistinguivel do legitimo.
  #
  # Nao-vacuidade, medida: 4 mutantes plantados -- colapsar espacos no slug,
  # nunca acusar arquivo inexistente, nunca acusar referencia sem definicao,
  # ignorar a desambiguacao de titulo repetido --, 4 mortos, cada um pelo caso
  # desenhado para ele. Reproduza antes de editar esta frase.
  # A promessa que o material faz e EXECUTAVEL, nao retorica: as 17 promessas do
  # corpus sao todas "Rode X e observe Y", e nenhuma e pergunta de compreensao.
  # Isso foi medido antes de este verificador existir, e e o que o torna
  # possivel -- clareza nao tem proxy sintatico, "o programa citado existe e e
  # construido" tem.
  #
  # Guarda a classe que ja custou dois arquivos a este repositorio:
  # controle-anel.cpp na arvore sem registro e sem compilar, e
  # l1_preparar_nic.py desregistrado do meson. Nos dois casos a documentacao
  # seguiu citando o que existia no texto e nao na compilacao.
  test('docs - promessas executaveis existem na arvore', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-promessa.py',
               meson.project_source_root()],
       suite : ['l1', 'docs'], timeout : 30)

  test('docs - autoteste do verificador de promessas', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-promessa.py',
               '--autoteste'],
       suite : ['l1', 'docs'], timeout : 30)

  test('docs - autoteste do verificador de links', python3,
       args : [meson.project_source_root() / 'ferramental/qualidade/verificar-links.py',
               '--autoteste'],
       suite : ['l1', 'docs'], timeout : 30)

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

  # Estes tres verificadores rodam no pre-commit (e, por ele, na CI), mas os
  # AUTOTESTES deles nao rodavam em lugar nenhum. Autoteste que ninguem executa
  # nao protege o verificador de passar a aceitar tudo -- e um verificador que
  # aceita tudo continua imprimindo "0 problemas".
  foreach v : ['idioma', 'paridade', 'tabelas', 'medicao']
    test('docs - autoteste do verificador de ' + v, python3,
         args : [meson.project_source_root() / 'ferramental/qualidade/verificar-' + v + '.py',
                 '--autoteste'],
         suite : ['l1', 'docs'], timeout : 60)
  endforeach
else
  # python3 ausente: registrar marcadores que PULAM (codigo 77) em vez de nao
  # registrar nada. Sem isto a suite l1 encolhia em TRES testes e reportava
  # verde -- e os tres sao justamente os que conferem se o material diz a
  # verdade. Ver ferramental/qualidade/pular-sem-python3.sh.
  foreach nome : ['docs - ancoras de linha atualizadas',
                  'docs - promessas executaveis existem na arvore',
                  'docs - autoteste do verificador de promessas',
                  'docs - autoteste do verificador de links',
                  'docs - autoteste do verificador de ancoras',
                  'docs - links e ancoras de titulo',
                  'docs - numeros retratados nao sobrevivem',
                  'docs - autoteste do verificador de retratacoes',
                  'docs - aritmetica publicada fecha',
                  'docs - autoteste do verificador de aritmetica',
                  'docs - autodescricao corresponde ao disco',
                  'docs - autoteste do verificador de autodescricao',
                  'docs - autoteste do verificador de idioma',
                  'docs - autoteste do verificador de paridade',
                  'docs - autoteste do verificador de tabelas',
                  'docs - autoteste do verificador de medicao']
    test(nome, bash,
         args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-python3.sh', nome],
         suite : ['l1', 'docs'], timeout : 30)
  endforeach
endif

# O VEREDITO DE HUGEPAGES DO check-env.sh.
#
# `check-env.sh` e a primeira coisa que alguem roda aqui, e por muito tempo
# relatou os dois fatos das hugepages SEPARADOS -- "1024 reservadas" e
# "/dev/hugepages montado (root:root 755)" -- sem tirar a conclusao. As duas
# linhas parecem boas; o leitor segue, e so descobre quando os L3 pulam.
#
# Para o DPDK multiprocesso e preciso das duas coisas ao mesmo tempo: paginas
# reservadas E ponto hugetlbfs gravavel pelo usuario. Reservada nao e
# utilizavel, e o caso comum e justamente esse.
#
# O teste confere que o veredito EXISTE e que ele CORRESPONDE a maquina --
# re-apurando a condicao por conta propria, em vez de confiar no script. Um
# veredito que sempre dissesse "pode rodar" passaria na primeira conferencia e
# falharia na segunda.
test('scripts - L1 (veredito de hugepages do check-env)', bash,
     args : [meson.project_source_root() / 'scripts/tests/l1_check_env.sh'],
     suite : ['l1', 'scripts'], timeout : 60)

# Classificacao do modelo de driver de NIC (captura total x bifurcado).
if python3.found()
  # RE-REGISTRADO EM 15/09/2026, DEPOIS DA RECONSTRUCAO DO OBJETO DE TESTE.
  #
  # O teste ficou desregistrado por um dia. A causa esta registrada para nao
  # virar misterio: um `git filter-branch` executado durante a correcao do
  # e-mail de autoria faz checkout ao terminar, e descartou alteracoes nao
  # commitadas de preparar-nic.sh -- a camada inteira que o teste exercita
  # (verificacao de root, estado em /var/lib/dpdk-academy/nic, confirmacao de
  # PMD, leitura de subsystem_vendor e class).
  #
  # O script foi reconstruido A PARTIR DESTE TESTE, que e uma especificacao
  # executavel: 66 invocacoes da CLI, 25 recusas cada uma com a frase exigida,
  # o ciclo de captura e restauracao, e o que precisa sobreviver a uma falha no
  # meio. Nao e o mesmo texto que se perdeu; e equivalente em todos os caminhos
  # que tem assercao.
  #
  # NAO-VACUIDADE, medida: 18 mutantes plantados nas travas, 16 mortos. Os dois
  # sobreviventes sao pares redundantes de proposito -- as duas passagens de
  # `nic_bind_guard` e as duas validacoes de `--driver` --, e removendo o PAR o
  # teste pega os dois. Reproduza antes de editar esta frase.
  test('scripts - L1 (preparar NIC: recusas e restauracao)', python3,
       args : [meson.project_source_root() / 'scripts/tests/l1_preparar_nic.py'],
       suite : ['l1', 'scripts'], timeout : 60)
else
  test('scripts - L1 (preparar NIC: recusas e restauracao)', bash,
       args : ['-c', 'echo "SKIP: python3 ausente; contrato de preparar-nic nao executado"; exit 77'],
       suite : ['l1', 'scripts'], timeout : 30)
endif

#
# E L1 porque e logica pura: recebe o vendor PCI como argumento e nao toca em
# hardware. Existe para que o caminho da Mellanox -- que nenhuma placa desta
# maquina exercita -- esteja testado ANTES de a ConnectX-4 Lx chegar. Errar essa
# decisao significa bindar ao vfio-pci uma placa bifurcada, que para de
# funcionar dos dois lados.
# A trava de captura total, com fontes controladas.
#
# `nic_bind_guard` decide se um dispositivo pode ir para o vfio-pci, e decide
# FECHANDO: enumera as interfaces do dispositivo, confere rota default em IPv4 e
# IPv6, le os flags, e recusa quando NAO CONSEGUE APURAR qualquer um desses --
# nao so quando a resposta e negativa. Cada recusa nomeia o motivo em
# NIC_BIND_REASON.
#
# O teste monta um /sys/bus/pci falso e exercita os caminhos que nao se
# provocam numa maquina real: rota sem interface identificavel, flags malformado,
# arquivo de estado ausente, interface UP. E confere o contrato da linha de
# comando de diagnostico-nic.sh -- alvo vazio, invalido ou duplicado saem com 2
# ANTES de consultar o host, sem exigir root para recusar argumento.
#
# Estava no disco e nao estava registrado: rodava so se alguem lembrasse.
# As duas pecas mais densas em cenario negativo do ferramental de publicacao
# estavam no disco sem registro. Nao sao acessorias: l2_publicacao.py exercita
# os caminhos em que uma coleta NAO pode virar numero (execucao que falhou,
# execucao ausente, comando divergente, ambiente que falhou), e
# l1_mutacoes_publicacao.py e teste de MUTACAO -- remove cada contrato da
# bateria e exige que a bateria acuse a remocao.
#
# Teste de mutacao e a unica prova automatica de nao-vacuidade que existe: ele
# demonstra, a cada execucao, que detecta a ausencia daquilo que protege.
if python3.found()
  test('scripts - L1 (mutacoes da publicacao)', python3,
       args : [meson.project_source_root() / 'scripts/tests/l1_mutacoes_publicacao.py'],
       suite : ['l1', 'scripts'], timeout : 120)

  test('scripts - L2 (contrato de publicacao)', python3,
       args : [meson.project_source_root() / 'scripts/tests/l2_publicacao.py'],
       suite : ['l2', 'scripts'], timeout : 120)
else
  foreach nome : ['scripts - L1 (mutacoes da publicacao)',
                  'scripts - L2 (contrato de publicacao)']
    test(nome, bash,
         args : [meson.project_source_root() / 'ferramental/qualidade/pular-sem-python3.sh', nome],
         suite : ['l1', 'scripts'], timeout : 30)
  endforeach
endif

test('scripts - L1 (trava de bind e contrato do alvo)', bash,
     args : [meson.project_source_root() / 'scripts/tests/l1_bind_guard.sh'],
     suite : ['l1', 'scripts'], timeout : 60)

test('scripts - L1 (modelo de driver de NIC)', bash,
     args : [meson.project_source_root() / 'scripts/tests/l1_lib_nic.sh'],
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
# AF_XDP SAIU DO REPOSITORIO EM 15/09/2026.
#
# O diagnostico inteiro -- 3371 linhas em 10 arquivos, 43% de todo o codigo de
# script do projeto -- foi para temp/, fora do controle de versao, junto com o
# documento de preparacao. A razao e de escopo e esta medida: a NIC de
# referencia anuncia `xdp_features = 0x00`, entao nada ali produz resultado util
# nesta maquina, e o material nao ganha nada com a presenca do codigo.
#
# O que se perde ao remover: quatro testes L1 que exercitavam a logica de
# decisao com fontes controladas e passavam sem hardware. Eram bons testes de um
# assunto que o projeto decidiu nao cobrir nesta versao.
#

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
subdir('trilha/03-performance/03-isolamento-cpu')

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
