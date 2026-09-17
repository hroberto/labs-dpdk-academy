export const meta = {
  name: 'auditoria-maturidade',
  whenToUse: 'Quando quiser reavaliar a maturidade do material em 12 dimensoes com contestacao adversarial. Leva ~30 min e gasta ~5M tokens; NAO envie mensagens durante a execucao, elas interrompem os agentes.',
  description: 'Auditoria de maturidade do DPDK Academy em 12 dimensoes, com verificacao adversarial e calibracao cruzada',
  phases: [
    { title: 'Auditoria', detail: '12 dimensoes auditadas em paralelo, cada uma com evidencia em arquivo:linha' },
    { title: 'Contestacao', detail: 'duas lentes adversariais por dimensao: nota inflada e nota injusta' },
    { title: 'Reconciliacao', detail: 'nota final por dimensao apos as contestacoes' },
    { title: 'Calibracao', detail: 'normalizacao entre dimensoes e critico de completude' },
  ],
}

// A raiz vem do diretorio de trabalho do processo, nao de um caminho fixo.
//
// Estava escrita a mao com o nome ANTIGO do repositorio e sobreviveu ao rename:
// os agentes recebiam um diretorio que nao existe mais. O `pre-commit.sh` vinha
// avisando ("caminho absoluto encontrado"), mas o aviso nao bloqueia, entao ficou.
// Derivar do processo faz o proximo rename passar despercebido, que e o objetivo.
const RAIZ = process.cwd()

const REGUA = `
REGUA DE MATURIDADE (0-100) - use estas ancoras, nao a sua intuicao:
  0-19   AUSENTE: o atributo nao existe no projeto.
  20-39  INICIAL: existe de forma ad hoc, sem padrao, sem repeticao confiavel.
  40-59  PARCIAL: existe em parte do projeto, inconsistente entre modulos.
  60-74  CONSISTENTE COM LACUNAS: padrao aplicado na maioria, lacunas relevantes e NAO documentadas.
  75-89  MADURO: padrao aplicado, lacunas conhecidas E declaradas pelo proprio projeto.
  90-100 EXEMPLAR: serviria de referencia para outros projetos; lacunas sao de fronteira, nao de execucao.

REGRAS DE PONTUACAO:
- Uma lacuna que o PROPRIO projeto declara explicitamente pesa MENOS que uma lacuna silenciosa.
  Este projeto tem cultura de retratacao publica (blocos "Este bloco publicava X, e o numero era artefato").
  Isso e evidencia de maturidade, nao de imaturidade -- mas so quando a retratacao corrige o texto inteiro,
  e nao apenas adiciona uma nota de rodape. VERIFIQUE isso.
- Nota so vale com EVIDENCIA em arquivo:linha. Afirmacao sem arquivo:linha sera descartada na contestacao.
- Nao pontue intencao declarada no ROADMAP como entrega. Pontue o que existe no disco.
- E material de ESTUDO, nao servico em producao. Calibre o atributo ao proposito:
  "falta autenticacao" nao e defeito aqui; "ensina operacao privilegiada sem declarar o risco" e gravissimo.
`

const CONTEXTO = `
PROJETO: DPDK Academy, em ${RAIZ}
Guia de estudo de DPDK em portugues (pt-BR), com codigo e medicoes junto de cada topico.
Publico: quem sabe C e Linux e quer aprender DPDK do inicio ao avancado.
Estrutura: docs/ (modulos conceituais 00..03, com medicoes/ executaveis), trilha/ (exercicios praticos
01..04, com alternativas/cpp23 comparativas), scripts/ (o que o ESTUDANTE executa: ambiente, build, test, hugepages, e os de NIC,
que protegem a maquina dele), ferramental/qualidade/ (os cinco verificadores de
documentacao e o gancho de pre-commit que a CI roda), ferramental/af-xdp/
(diagnostico AF_XDP preservado; NAO executavel no hardware de referencia).
A separacao entre scripts/ e ferramental/ e recente e deliberada: ver
ferramental/README.md, que traz a medicao que a motivou.
Build: Meson + Ninja, c_std=c11 com _GNU_SOURCE por arquivo, cpp_std=c++23, GoogleTest via subprojeto.
Taxonomia de teste do projeto: L1 = logica pura sem EAL; L2 = EAL real sem privilegio; L3 = exige do host
(hugetlbfs, varios nucleos fisicos, IOMMU, NIC) e PULA com codigo 77.
Maquina de referencia: Ryzen 9 9900X, 12 nucleos fisicos, 2 dominios L3, 1 no NUMA, Ubuntu 26.04, GCC 15.2.

REGRAS EDITORIAIS QUE O PROJETO IMPOE A SI MESMO (verifique se cumpre):
- afirmacao numerica precisa de programa que a produza;
- afirmacao normativa precisa nomear quem define (ITU-T / IEEE / RFC / doc do DPDK);
- Wikipedia nao e fonte aceita;
- prosa em portugues, codigo e identificadores em ingles;
- diagramas em Mermaid.

ATENCAO -- A ARVORE MUDOU RECENTEMENTE, E MUITO. Audite o que esta NO DISCO AGORA.
Ha correcoes aplicadas nos ultimos dias que invalidam qualquer memoria ou relatorio anterior:
programas que antes saiam com 0 sem medir agora reprovam; testes que nao rodavam foram
registrados; um bloco de citacao foi substituido. NAO assuma o estado antigo de nenhum arquivo
e NAO trate nenhum achado como conhecido: abra o arquivo e veja. Se voce identificar um defeito,
confirme que ele existe HOJE na linha que voce citar.

Parte das correcoes recentes foi feita pelo agente que encomendou esta auditoria. Isso NAO e
motivo para ser generoso nem para ser severo: avalie o disco. Se uma correcao estiver
incompleta, mal colocada ou tiver criado problema novo, diga -- e exatamente para isso que
esta auditoria existe.

NAO EXECUTE 'meson test' NEM 'meson compile' -- a suite ja esta rodando em outro processo e voce
causaria conflito de diretorio de build. Leia, faca grep, inspecione, use 'git log'/'git diff', e
rode no maximo comandos de leitura. NAO altere nenhum arquivo do repositorio.
`

const ESQUEMA_AUDITORIA = {
  type: 'object',
  properties: {
    dimensao: { type: 'string' },
    nota: { type: 'integer', description: 'maturidade de 0 a 100' },
    faixa: { type: 'string', description: 'nome da ancora da regua correspondente a nota' },
    justificativa: { type: 'string', description: 'por que esta nota e nao 10 acima ou 10 abaixo' },
    forcas: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          afirmacao: { type: 'string' },
          evidencia: { type: 'string', description: 'arquivo:linha' },
        },
        required: ['afirmacao', 'evidencia'],
      },
    },
    lacunas: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          afirmacao: { type: 'string' },
          evidencia: { type: 'string', description: 'arquivo:linha, ou "ausencia de X" com onde se procurou' },
          gravidade: { type: 'string', enum: ['alta', 'media', 'baixa'] },
          declarada_pelo_projeto: { type: 'boolean', description: 'o projeto ja admite esta lacuna?' },
        },
        required: ['afirmacao', 'evidencia', 'gravidade', 'declarada_pelo_projeto'],
      },
    },
    para_subir_10_pontos: { type: 'array', items: { type: 'string' }, description: 'acoes concretas e verificaveis' },
  },
  required: ['dimensao', 'nota', 'faixa', 'justificativa', 'forcas', 'lacunas', 'para_subir_10_pontos'],
}

const ESQUEMA_CONTESTACAO = {
  type: 'object',
  properties: {
    veredito: { type: 'string', enum: ['nota_justa', 'nota_alta_demais', 'nota_baixa_demais'] },
    nota_sugerida: { type: 'integer' },
    afirmacoes_derrubadas: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          original: { type: 'string' },
          porque_cai: { type: 'string' },
          contra_evidencia: { type: 'string', description: 'arquivo:linha' },
        },
        required: ['original', 'porque_cai', 'contra_evidencia'],
      },
    },
    achados_novos: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          afirmacao: { type: 'string' },
          evidencia: { type: 'string' },
          gravidade: { type: 'string', enum: ['alta', 'media', 'baixa'] },
        },
        required: ['afirmacao', 'evidencia', 'gravidade'],
      },
    },
    raciocinio: { type: 'string' },
  },
  required: ['veredito', 'nota_sugerida', 'afirmacoes_derrubadas', 'achados_novos', 'raciocinio'],
}

const DIMENSOES = [
  {
    chave: 'seguranca',
    titulo: 'Seguranca: operacao privilegiada, host e cadeia de suprimento',
    prompt: `Audite SEGURANCA. O ativo aqui e a maquina de quem estuda e a integridade do conteudo. Investigue:
- SECURITY.md existe: o escopo declarado e coerente com o que os scripts realmente fazem?
- OPERACAO PRIVILEGIADA: todo script que usa sudo/root declara o que altera, antes de alterar? Ha reversao? A reversao foi testada? Leia scripts/preparar-nic.sh, preparar-hugepages.sh, diagnostico-nic.sh, xdp-zerocopy.sh.
- O material ensina 'vfio-pci', binding de NIC, IOMMU: avisa do risco de derrubar a interface de rede da maquina? De perder acesso remoto?
- Injecao de comando: procure uso nao citado de variavel em shell, eval, expansao de nome de arquivo, entrada de usuario indo para comando. Seja concreto: aponte a linha.
- Escrita fora do repositorio: algum script escreve em /sys, /proc, /etc, /dev sem trava? Ha confirmacao do usuario?
- Cadeia de suprimento: acoes do GitHub fixadas por SHA? Subprojeto GoogleTest com hash? Dependabot configurado? .wraplock?
- Permissoes do GITHUB_TOKEN.
- O codigo de exemplo ensina pratica insegura em C? (strcpy, sprintf, sem verificacao de retorno, aritmetica de ponteiro sem limite)`,
  },
  {
    chave: 'estrutura',
    titulo: 'Estrutura documental e navegabilidade',
    prompt: `Audite a ESTRUTURA do conjunto documental. Investigue:
- Navegacao: cada documento tem Anterior/Proximo/Indice? Ha becos sem saida?
- Indices e sumarios: existem, e correspondem ao conteudo?
- Consistencia de formato entre docs/ e trilha/ e entre modulos.
- Ancoras e links: existe validacao automatizada (scripts/verificar-links.py, verificar-ancoras.py). Ela cobre links externos tambem, ou so relativos? Ha links quebrados para a documentacao oficial do DPDK?
- Duplicacao de conteudo entre docs/ e trilha/: o mesmo assunto e explicado duas vezes com numeros diferentes?
- Descoberta: quem chega no README.md sabe por onde comecar? Avalie README.md, docs/README.md, trilha/README.md, docs/plano-estudo-dpdk.md, ROADMAP.md -- ha CINCO pontos de entrada. Isso ajuda ou confunde?
- Arquivos orfaos: temp/, scripts/mapa-links-dpdk.md, README.en.md fazem parte da estrutura ou sao residuo?`,
  },
  {
    chave: 'rigor-medicao',
    titulo: 'Rigor de medicao e reprodutibilidade experimental',
    prompt: `Audite o RIGOR EXPERIMENTAL. Esta e a espinha dorsal do projeto -- seja duro. Investigue:
- statistics.h: leia inteiro. Mediana, IQR, p99, dispersao, coeficiente de variacao, selos de confianca. A implementacao do percentil e correta e declarada (tipo Hyndman-Fan)? Ha vies?
- Toda medicao publicada reporta dispersao, numero de amostras e resolucao do instrumento? AMOSTRE tabelas em docs/ e confira.
- Aquecimento, fixacao de nucleo, ruido controlado, repeticoes, mediana em vez de media: quais programas fazem e quais nao fazem? Aponte os que nao fazem.
- Frequencia de CPU: a maquina esta em powersave com turbo. O material lida com isso ou ignora?
- Comparacoes justas: ao comparar DPDK com alternativa, os dois lados medem a mesma coisa? (o projeto ja errou nisso duas vezes e retratou -- procure se sobrou alguma comparacao assimetrica nao declarada, por exemplo API em bloco contra API individual)
- Rastreabilidade: todo numero publicado tem programa que o produz e esta reproduzivel por um comando? Ha numero orfao?
- Regressao: existe mecanismo que detecte se um numero publicado deixou de corresponder ao que o programa produz hoje?`,
  },
  {
    chave: 'qualidade-scripts',
    titulo: 'Qualidade e robustez do ferramental (shell e Python)',
    prompt: `Audite os SCRIPTS. Eles somam mais de 6000 linhas e sao parte do produto. Investigue:
- Robustez shell: set -euo pipefail, citacao de variaveis, IFS, trap de limpeza, mktemp, codigo de saida significativo. Confira arquivo por arquivo em scripts/.
- Portabilidade: dependencia de saida localizada (lscpu em portugues ja quebrou o projeto antes), de GNU coreutils, de bash vs sh, de versao de kernel.
- xdp-zerocopy.sh tem 1276 linhas e xdp-features.py tem 803. Eles sao manutenivel? Ha decomposicao clara? Duplicacao com lib-xdp.sh?
- Os proprios scripts sao testados? scripts/tests/ tem ~2600 linhas. Avalie a qualidade desses testes: usam fontes controladas (fixtures), ou dependem do hardware real?
- Mensagem de erro: quando falham, dizem o que fazer? Ha diagnostico acionavel?
- Idempotencia e reversao para os que alteram o host.
- pre-commit.sh (479 linhas) e publicar-repo.sh: o que verificam? Sao ganchos reais, instalados?
- Python: tratamento de excecao, tipagem, argparse, saida estruturada.`,
  },
  {
    chave: 'manutenibilidade',
    titulo: 'Manutenibilidade, divida tecnica e evolucao',
    prompt: `Audite a MANUTENIBILIDADE de longo prazo. Investigue:
- Duplicacao: statistics.h e usado por quantos modulos? Ha copia em vez de reuso? Funcoes utilitarias repetidas entre medicoes (freq_ghz, now_ns, aquecer)?
- Acoplamento entre docs/ e trilha/: mudar um numero exige editar quantos arquivos? Ha fonte unica de verdade para os numeros publicados?
- O build: meson.build raiz com 212 linhas mais 8 subarquivos. Esta compreensivel? Ha logica condicional fragil?
- Versionamento: o material fixa versao de DPDK (25.11)? O que quebra quando o DPDK subir de versao? Ha teste que detecte?
- i18n: prosa em portugues, codigo em ingles, README.en.md de 92 linhas contra README.md de 174. A traducao vai escalar? Ha divida acumulando?
- Residuos: temp/, build/, build-ci/, build-precommit/, __pycache__ estao no repositorio ou ignorados? Confira .gitignore e 'git status'.
- Historico: rode 'git log --oneline | head -50' e avalie a disciplina de commit, se houver historico.
- Onboarding de contribuidor: existe CONTRIBUTING? O CLAUDE.md serve de guia de estilo? Um terceiro consegue contribuir?`,
  },
  {
    chave: 'testabilidade',
    titulo: 'Testabilidade: cenarios positivos e negativos',
    prompt: `Audite a TESTABILIDADE, com foco especial em CENARIO NEGATIVO. Investigue:
- Inventarie todo teste que existe (tests/ em docs/ e trilha/, scripts/tests/).
- Para cada um: ele testa caminho feliz, caminho de erro, ou os dois? Conte.
- Cenarios negativos: procure injecao de falha deliberada (grep INJETAR, VAZAMENTO, negativo, deve falhar). Quantos existem? Eles verificam a PRECONDICAO antes de afirmar que o negativo passou?
- NAO-VACUIDADE: um teste que passa mesmo com o codigo quebrado nao testa nada. Procure evidencia de que o projeto verificou isso (comentarios do tipo "revertendo X, N testes falham"). Avalie se os testes L1 sao sensiveis: leia test_l1_statistics.cpp, test_l1_order_book.cpp, test_l1_sizing.cpp e julgue se as assercoes prendem o comportamento ou so o formato.
- Falso verde: ha teste que sai 0 sem ter verificado nada? (o projeto ja corrigiu um caso com exit 77 -- confira se sobrou outro)
- Testes de borda: valores limite, overflow, divisao por zero, entrada vazia, pool esgotado.
- Os scripts em scripts/tests/ (l1_xdp.sh, l1_xdp_netlink.sh, l1_xdp_zerocopy.sh, l1_apuracao.sh, l1_lib_nic.sh) testam com fontes controladas? Eles sao tao rigorosos quanto os testes em C?`,
  },
  {
    chave: 'academica',
    titulo: 'Contribuicao academica',
    prompt: `Audite o RIGOR ACADEMICO deste material. Investigue:
- Metodo declarado e reproduzivel? Existe secao de metodo? (docs/00-visao-geral/README.md)
- Honestidade epistemica: o projeto separa medicao, fato documentado, inferencia e pendencia? Ele cumpre isso na pratica, ou a distincao so existe na convencao declarada? AMOSTRE pelo menos 5 afirmacoes em docs/ e classifique-as.
- Retratacoes: procure os blocos que admitem numero errado (grep por "publicava", "artefato", "estava errado"). A retratacao corrigiu o documento inteiro ou deixou o numero velho circulando em outro arquivo?
- Fontes: afirmacao normativa nomeia o orgao? Existe citacao de literatura primaria (documentacao DPDK, papers, McKenney)? Ha uso de Wikipedia (proibido pelo projeto)?
- Limitacoes: cada documento tem secao de limitacoes, e ela e substantiva ou formalidade?
- Valor original: o que este material produz que NAO esta em fonte existente de DPDK? Ha descoberta propria (ex.: comparacao com alternativa C++23, custo de init, cache por lcore)?
Compare com o que se esperaria de um relatorio tecnico ou dissertacao aplicada.`,
  },
  {
    chave: 'pratica',
    titulo: 'Contribuicao pratica e transferibilidade',
    prompt: `Audite o VALOR PRATICO para quem vai construir software real. Investigue:
- As conclusoes sao acionaveis? Um engenheiro consegue extrair regra de decisao ("use X quando Y")?
- O material ensina a DECIDIR ou so a operar? Procure decisoes de arquitetura justificadas por medicao.
- Transferibilidade: os numeros vem de UMA maquina. O material ensina o leitor a refazer na dele? (scripts/ambiente.sh, check-env.sh)
- Cobre o que quebra na pratica: dimensionamento de pool, esgotamento, contrapressao, NUMA, afinidade, IOMMU, hugepages?
- Lacuna admitida: nao ha rede real medida. Quanto isso custa ao valor pratico? Seja concreto.
- O ferramental (scripts/) e reutilizavel fora do projeto, ou so serve a ele?
- Existe caminho do "hello world" ao sistema? Avalie trilha/ inteira, incluindo os esqueletos.`,
  },
  {
    chave: 'clareza',
    titulo: 'Clareza, objetivo e qualidade didatica',
    prompt: `Audite CLAREZA e DIDATICA. Investigue:
- Cada documento declara objetivo e publico? Ha objetivos de aprendizagem?
- Progressao: conceito -> mecanismo -> trade-off -> implementacao -> medicao -> limitacao. Verifique em docs/01, 02, 03 se a ordem e mesmo seguida.
- Densidade: LEIA trechos longos (docs/01-fundamentos/README.md tem 2016 linhas). Um iniciante em DPDK se perde? Ha excesso de digressao?
- Pre-requisitos declarados e honestos?
- Os diagramas Mermaid ajudam ou decoram? Avalie cada um que encontrar.
- Consistencia de voz e de terminologia entre modulos.
- Onde o texto e dificil por necessidade (o assunto e dificil) e onde e dificil por escrita?
Cite trechos concretos, bons e ruins, com arquivo:linha.`,
  },
  {
    chave: 'niveis-teste',
    titulo: 'Niveis de teste L1/L2/L3 e automacao',
    prompt: `Audite a TAXONOMIA DE NIVEIS de teste e sua automacao. Investigue:
- A taxonomia L1/L2/L3 esta definida em algum documento? Onde? E aplicada de forma consistente nos meson.build?
- COBERTURA POR TOPICO: monte uma matriz -- cada topico de docs/ e trilha/ tem L1? tem L2? precisa de L3? Aponte os topicos SEM teste nenhum.
- Registro no Meson: todo teste esta registrado com a suite certa? Procure teste que existe no disco mas nao esta em nenhum meson.build.
- CI (.github/workflows/ci.yml): roda os tres niveis? O que acontece quando L3 pula -- e visivel ou some?
- Determinismo: ha teste que depende de tempo, de frequencia de CPU, ou de numero de nucleos e por isso pode falhar de forma intermitente? Procure limiares numericos codificados em teste.
- Tempo de execucao e uso de variaveis de ambiente para reduzir amostras no CI: isso enfraquece o teste a ponto de nao verificar mais nada?
- Falta algum nivel? (ex.: teste de integracao entre modulos, teste de documentacao-vs-codigo, teste de regressao de numeros publicados)`,
  },
  {
    chave: 'boas-praticas-c-cpp',
    titulo: 'Boas praticas de engenharia em C e C++23',
    prompt: `Audite a QUALIDADE DE ENGENHARIA do codigo C/C++. Investigue:
- C: verificacao de retorno, tratamento de erro, ownership, ausencia de estado global escondido, const-correctness, tamanho de buffer. Leia docs/*/medicoes/*.c e trilha/**/*.c.
- C++23: o projeto promete RAII, std::span, std::expected, ranges, constexpr. Ele usa? Onde usa por necessidade e onde usa por vitrine? Leia packet.hpp, packet_pipeline.cpp, custo-anel-cpp.cpp.
- Idiomas DPDK: uso correto de rte_eal_init, checagem de retorno, lcore vs cpu, cpuset, mempool cache, bulk, NUMA/socket_id, cleanup.
- Concorrencia: atomics com ordem de memoria justificada, alinhamento de linha de cache, falso compartilhamento.
- Ferramental de qualidade: .clang-format e .clang-tidy existem -- estao configurados de forma substantiva e sao aplicados? (scripts/pre-commit.sh) A CI roda lint?
- Warnings: qual nivel o meson.build usa? Ha -Werror?
- Codigo morto, duplicacao entre medicoes, copia-e-cola de funcao utilitaria entre arquivos.`,
  },
  {
    chave: 'cobertura-escopo',
    titulo: 'Cobertura: prometido contra entregue',
    prompt: `Audite a LACUNA ENTRE PROMESSA E ENTREGA. Seja implacavel e quantitativo. Investigue:
- Leia ROADMAP.md e docs/plano-estudo-dpdk.md e extraia TODA promessa (nivel, etapa, entregavel).
- Para cada uma: entregue, parcial, ou apenas esqueleto? Monte a contagem.
- Conte os documentos que sao esqueleto declarado ("Esqueleto. Registra escopo e compromissos; o conteudo ainda nao foi escrito") contra os que tem conteudo. Qual a fracao?
- O titulo promete "iniciante ao avancado". Onde termina de fato o material? Qual o nivel mais avancado efetivamente coberto?
- Assuntos centrais de DPDK que um guia completo teria e este ainda nao tem: PMD e ciclo RX/TX real, descritores, offloads, multiqueue/RSS, flow API, KNI/virtio, criptografia, eventdev, timers, telemetria. Quais faltam? Quais estao prometidos?
- Promessas nao cumpridas dentro do proprio texto: procure promessa de que algo esta documentado em outro lugar e confirme se esta. (ha uma conhecida no ROADMAP sobre decisoes rejeitadas em docs/00-visao-geral)
- O projeto declara honestamente onde termina? Compare a promessa do README.md com o estado real.`,
  },
]

// ---------------------------------------------------------------------------
// Fase 1-3: auditar -> contestar por duas lentes -> reconciliar. Em pipeline:
// cada dimensao avanca sozinha, sem esperar as outras.
// ---------------------------------------------------------------------------
const resultados = await pipeline(
  DIMENSOES,

  // Fase 1 -- auditoria
  (d) =>
    agent(
      `${CONTEXTO}\n${REGUA}\n\nVoce e auditor da dimensao "${d.titulo}".\n\n${d.prompt}\n\n` +
        `Trabalhe a partir de LEITURA REAL dos arquivos -- nao generalize a partir dos nomes. ` +
        `Abra os arquivos que citar. Toda forca e toda lacuna precisa de arquivo:linha. ` +
        `Atribua a nota de 0 a 100 pela regua, e explique na justificativa por que nao 10 acima nem 10 abaixo. ` +
        `Devolva a dimensao com a chave "${d.titulo}".`,
      { label: `audita:${d.chave}`, phase: 'Auditoria', schema: ESQUEMA_AUDITORIA },
    ),

  // Fase 2 -- duas lentes adversariais, em paralelo, sobre a auditoria daquela dimensao
  (auditoria, d) => {
    if (!auditoria) return null
    const resumo = JSON.stringify(auditoria, null, 1)
    return parallel([
      () =>
        agent(
          `${CONTEXTO}\n${REGUA}\n\nVoce e CETICO DE NOTA INFLADA na dimensao "${d.titulo}".\n\n` +
            `Um auditor produziu o laudo abaixo. Sua tarefa e tentar DERRUBA-LO por generosidade: ` +
            `procure forca afirmada que nao se sustenta ao abrir o arquivo, evidencia que nao diz o que ` +
            `o auditor disse, padrao que vale para UM modulo mas foi generalizado para o projeto, ` +
            `intencao contada como entrega, e lacuna grave que o auditor nao viu.\n\n` +
            `VERIFIQUE PESSOALMENTE cada arquivo:linha citado -- se a citacao nao sustenta a afirmacao, derrube-a.\n` +
            `Procure ativamente pelo menos uma lacuna NOVA que o auditor perdeu.\n\n` +
            `LAUDO:\n${resumo}`,
          { label: `cetico-alto:${d.chave}`, phase: 'Contestacao', schema: ESQUEMA_CONTESTACAO },
        ),
      () =>
        agent(
          `${CONTEXTO}\n${REGUA}\n\nVoce e CETICO DE NOTA INJUSTA na dimensao "${d.titulo}".\n\n` +
            `Um auditor produziu o laudo abaixo. Sua tarefa e verificar se ele foi DURO DEMAIS ou se ` +
            `aplicou criterio de software de producao a material de estudo. Procure: forca real do projeto ` +
            `que o laudo ignorou, lacuna apontada que o projeto JA declara explicitamente (e portanto pesa menos), ` +
            `lacuna que e escolha de escopo legitima e nao defeito, e trabalho de qualidade que o auditor nao abriu.\n\n` +
            `VERIFIQUE PESSOALMENTE no repositorio antes de defender qualquer ponto. ` +
            `Se depois de procurar voce concluir que o laudo foi justo, diga "nota_justa" -- nao invente defesa.\n\n` +
            `LAUDO:\n${resumo}`,
          { label: `cetico-baixo:${d.chave}`, phase: 'Contestacao', schema: ESQUEMA_CONTESTACAO },
        ),
    ]).then((vs) => ({ auditoria, contestacoes: vs.filter(Boolean), d }))
  },

  // Fase 3 -- reconciliacao: nota final da dimensao
  (pacote, d) => {
    if (!pacote) return null
    return agent(
      `${CONTEXTO}\n${REGUA}\n\nVoce e o RELATOR da dimensao "${d.titulo}".\n\n` +
        `Abaixo estao o laudo original e duas contestacoes -- uma acusando a nota de generosa, ` +
        `outra de injusta. Decida a nota final.\n\n` +
        `Voce DEVE verificar no repositorio qualquer ponto em que as tres pecas discordem: ` +
        `abra o arquivo e decida com o que esta la, nao com o argumento mais bem escrito. ` +
        `Descarte afirmacao cuja evidencia nao sustenta. Incorpore achados novos que voce confirmar.\n\n` +
        `Na justificativa, registre explicitamente o que mudou em relacao ao laudo original e por que.\n\n` +
        `LAUDO ORIGINAL:\n${JSON.stringify(pacote.auditoria, null, 1)}\n\n` +
        `CONTESTACOES:\n${JSON.stringify(pacote.contestacoes, null, 1)}`,
      { label: `relator:${d.chave}`, phase: 'Reconciliacao', schema: ESQUEMA_AUDITORIA },
    ).then((final) => ({ chave: d.chave, titulo: d.titulo, final, original: pacote.auditoria }))
  },
)

const validos = resultados.filter(Boolean).filter((r) => r.final)
log(`${validos.length}/${DIMENSOES.length} dimensoes reconciliadas`)

// ---------------------------------------------------------------------------
// Fase 4 -- barreira legitima: calibrar exige TODAS as notas juntas.
// ---------------------------------------------------------------------------
phase('Calibracao')

const tabela = validos
  .map((r) => `${r.titulo} (${r.chave}): ${r.final.nota} [${r.final.faixa}] -- ${r.final.justificativa}`)
  .join('\n')

const detalhe = JSON.stringify(
  validos.map((r) => ({ chave: r.chave, nota: r.final.nota, lacunas: r.final.lacunas, forcas: r.final.forcas })),
  null,
  1,
)

const [calibracao, critico] = await parallel([
  () =>
    agent(
      `${CONTEXTO}\n${REGUA}\n\nVoce e o CALIBRADOR. Doze dimensoes foram auditadas por relatores ` +
        `independentes, que nao viram as notas uns dos outros. Isso produz incoerencia de escala: ` +
        `um 80 numa dimensao pode nao significar o mesmo que 80 em outra.\n\n` +
        `Sua tarefa:\n` +
        `1. Detectar dimensoes cuja nota esta fora de escala em relacao as demais, dado o peso das lacunas. ` +
        `Compare a GRAVIDADE das lacunas entre dimensoes, nao os adjetivos usados.\n` +
        `2. Propor ajuste apenas onde houver incoerencia demonstravel -- diga qual dimensao serve de ancora.\n` +
        `3. Identificar lacunas que aparecem em VARIAS dimensoes: essas sao causa-raiz, e valem mais que ` +
        `doze sintomas separados.\n` +
        `4. Calcular uma nota global ponderada, declarando e justificando os pesos para um material de ESTUDO ` +
        `(rigor de medicao e contribuicao academica pesam mais que, por exemplo, manutenibilidade).\n` +
        `5. Nomear as 5 acoes de maior retorno: as que sobem mais pontos em mais dimensoes por unidade de esforco.\n\n` +
        `NOTAS:\n${tabela}\n\nDETALHE:\n${detalhe}`,
      { label: 'calibrador', phase: 'Calibracao', effort: 'high', schema: {
        type: 'object',
        properties: {
          ajustes: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                chave: { type: 'string' },
                nota_original: { type: 'integer' },
                nota_calibrada: { type: 'integer' },
                motivo: { type: 'string' },
                ancora: { type: 'string', description: 'dimensao usada como referencia de escala' },
              },
              required: ['chave', 'nota_original', 'nota_calibrada', 'motivo', 'ancora'],
            },
          },
          causas_raiz: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                causa: { type: 'string' },
                dimensoes_afetadas: { type: 'array', items: { type: 'string' } },
                evidencia: { type: 'string' },
              },
              required: ['causa', 'dimensoes_afetadas', 'evidencia'],
            },
          },
          pesos: {
            type: 'array',
            items: {
              type: 'object',
              properties: { chave: { type: 'string' }, peso: { type: 'number' }, motivo: { type: 'string' } },
              required: ['chave', 'peso', 'motivo'],
            },
          },
          nota_global: { type: 'integer' },
          faixa_global: { type: 'string' },
          leitura_global: { type: 'string', description: 'o que a nota global significa em uma frase honesta' },
          acoes_de_maior_retorno: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                acao: { type: 'string' },
                dimensoes_que_sobem: { type: 'array', items: { type: 'string' } },
                esforco: { type: 'string', enum: ['baixo', 'medio', 'alto'] },
                ganho_estimado: { type: 'string' },
              },
              required: ['acao', 'dimensoes_que_sobem', 'esforco', 'ganho_estimado'],
            },
          },
        },
        required: ['ajustes', 'causas_raiz', 'pesos', 'nota_global', 'faixa_global', 'leitura_global', 'acoes_de_maior_retorno'],
      } },
    ),
  () =>
    agent(
      `${CONTEXTO}\n\nVoce e o CRITICO DE COMPLETUDE desta auditoria. Doze dimensoes foram auditadas:\n` +
        DIMENSOES.map((d) => `- ${d.titulo}`).join('\n') +
        `\n\nSua tarefa NAO e reauditar. E descobrir O QUE A AUDITORIA NAO OLHOU:\n` +
        `1. Que atributo relevante para o usuario final deste material ficou de fora das doze dimensoes? ` +
        `Pense em: acessibilidade, licenciamento e reuso, custo de entrada (hardware necessario para acompanhar), ` +
        `atualidade da informacao, risco de o leitor aprender algo errado, comparabilidade com alternativas ` +
        `a DPDK que nao sao C++ puro, suporte a quem trava, internacionalizacao, e o que mais voce identificar.\n` +
        `2. Que parte do repositorio provavelmente nao foi aberta por nenhum auditor? Verifique voce mesmo ` +
        `os arquivos menos obvios e diga se ha algo relevante la.\n` +
        `3. Ha alguma afirmacao que o projeto faz sobre si mesmo e que ninguem verificou?\n\n` +
        `Abra arquivos de verdade. Devolva achados com evidencia.`,
      { label: 'critico-completude', phase: 'Calibracao', effort: 'high', schema: {
        type: 'object',
        properties: {
          dimensoes_faltantes: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                atributo: { type: 'string' },
                porque_importa: { type: 'string' },
                avaliacao_preliminar: { type: 'string' },
                nota_sugerida: { type: 'integer' },
                evidencia: { type: 'string' },
              },
              required: ['atributo', 'porque_importa', 'avaliacao_preliminar', 'nota_sugerida', 'evidencia'],
            },
          },
          pontos_cegos: { type: 'array', items: { type: 'string' } },
          afirmacoes_nao_verificadas: {
            type: 'array',
            items: {
              type: 'object',
              properties: { afirmacao: { type: 'string' }, onde: { type: 'string' }, veredito: { type: 'string' } },
              required: ['afirmacao', 'onde', 'veredito'],
            },
          },
        },
        required: ['dimensoes_faltantes', 'pontos_cegos', 'afirmacoes_nao_verificadas'],
      } },
    ),
])

return {
  dimensoes: validos.map((r) => ({
    chave: r.chave,
    titulo: r.titulo,
    nota_original: r.original?.nota,
    nota_final: r.final.nota,
    faixa: r.final.faixa,
    justificativa: r.final.justificativa,
    forcas: r.final.forcas,
    lacunas: r.final.lacunas,
    para_subir_10_pontos: r.final.para_subir_10_pontos,
  })),
  calibracao,
  critico,
}
