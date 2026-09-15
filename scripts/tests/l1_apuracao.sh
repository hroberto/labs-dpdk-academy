#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L1 de scripts/lib-apuracao.sh -- o tri-estado APURADO / NAO APURADO /
# AUSENTE.
#
# POR QUE ESTE TESTE EXISTE, E POR QUE E L1
#
# A biblioteca que ele cobre existe para tornar irrepresentavel um defeito que
# tres rodadas de correcao nao conseguiram fechar: informacao que nao pode ser
# apurada saindo publicada como fato negativo. Se os acessores errarem, o
# defeito volta em toda a arvore de uma vez, e com autoridade -- porque agora
# o resto do codigo confia neles. Um acessor com teste que nao pega e PIOR que
# nenhum acessor.
#
# E L1 no sentido estrito deste projeto: nao precisa de root, de NIC, de
# hugepages, de DPDK nem de rede. Todos os fatos apurados vem de arquivos de
# verdade criados num diretorio temporario e de programas-isca postos num PATH
# temporario. Roda em milissegundos, em qualquer maquina, inclusive na CI.
#
# ===========================================================================
# O QUE ELE FAZ ALEM DE ASSERTAR: A RODADA DE MUTACOES
# ===========================================================================
#
# Assercao que passa nao prova que o teste PEGA alguma coisa -- prova que o
# codigo de hoje concorda com a expectativa de hoje. O precedente desta arvore
# e explicito: ha um autoteste registrado cujo proprio registro admite que ele
# nao trava a reincidencia que motivou sua criacao.
#
# Por isso a execucao padrao tem duas fases:
#
#   FASE 1  a bateria de assercoes contra a biblioteca de verdade.
#   FASE 2  para cada mutacao da lista, uma COPIA da biblioteca e alterada para
#           reintroduzir um defeito concreto, e a bateria inteira roda contra a
#           copia num processo separado. A mutacao so e dada por PEGA quando a
#           bateria FALHA. Mutacao que passa e falha deste teste, nao da
#           biblioteca.
#
# A fase 2 tambem falha quando uma mutacao NAO SE APLICA MAIS (o texto ancora
# sumiu da biblioteca). Sem essa checagem, renomear uma funcao faria as
# mutacoes virarem no-ops e a fase 2 ficaria verde sem testar nada -- que e a
# mesma classe de defeito que este arquivo inteiro persegue: a verificacao que
# deixou de rodar reportada como verificacao que passou.
#
# ===========================================================================
# O QUE ESTE TESTE NAO PROVA
# ===========================================================================
#
# Que os scripts da arvore USAM os acessores. Nenhuma migracao foi feita aqui;
# a biblioteca nasce coberta e sem chamadores. Enquanto houver leitura crua de
# /sys, /proc e /boot espalhada pela arvore, o defeito continua possivel la --
# so deixou de ser possivel AQUI.
#
# Tambem nao prova o comportamento sob root para os casos de privilegio: com
# uid 0 os fixtures em modo 000 sao legiveis, e os ramos EACCES nao existem.
# Esses blocos sao contados como LACUNA e nomeados na saida -- nao pulados em
# silencio, que seria cometer o defeito dentro do teste do defeito.
#
# USO
#     bash scripts/tests/l1_apuracao.sh              fase 1 + fase 2
#     bash scripts/tests/l1_apuracao.sh --bateria <lib>   so a fase 1, contra <lib>
#                                                        (e como a fase 2 se invoca)
set -u

# O diretorio deste script sai de expansao do proprio shell, nao de `dirname`.
# INCIDENTE, cometido por este arquivo e achado ao roda-lo com um PATH
# reduzido: com `dirname` fora do PATH, `$(dirname "$0")` saia VAZIO, o caminho
# montado virava "//lib-apuracao.sh", e este teste anunciava
# "ERRO: //lib-apuracao.sh nao existe" -- ferramenta ausente renderizada como
# fato negativo sobre um arquivo que estava la o tempo todo. E exatamente o
# defeito que a biblioteca coberta aqui existe para tornar impossivel, cometido
# na quarta linha do teste dela. `${0%/*}` e `cd`/`pwd` sao do proprio bash e
# nao tem como faltar.
_dir_deste_script=${0%/*}
[ "$_dir_deste_script" = "$0" ] && _dir_deste_script=.
RAIZ="$(cd "$_dir_deste_script/.." && pwd)"
LIB_REAL="$RAIZ/lib-apuracao.sh"

falhas=0
lacunas=0
assercoes=0

check() {
    assercoes=$((assercoes + 1))
    if [ "$2" = "$3" ]; then
        echo "  ok    - $1"
    else
        echo "  FALHA - $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}
contem() {
    assercoes=$((assercoes + 1))
    if printf '%s' "$3" | grep -qi -- "$2"; then
        echo "  ok    - $1"
    else
        echo "  FALHA - $1 (nao encontrou '$2' em '$3')"
        falhas=$((falhas + 1))
    fi
}
nao_contem() {
    assercoes=$((assercoes + 1))
    if printf '%s' "$3" | grep -qi -- "$2"; then
        echo "  FALHA - $1 (encontrou '$2' em '$3', e nao devia)"
        falhas=$((falhas + 1))
    else
        echo "  ok    - $1"
    fi
}
lacuna() {
    lacunas=$((lacunas + 1))
    echo "  LACUNA- $1"
}

# ---------------------------------------------------------------------------
# Fixtures: arquivos DE VERDADE, nao simulacoes.
#
# A biblioteca existe justamente para separar respostas do sistema de
# arquivos que se parecem ("vazio", "nao consegui", "nao existe"); testa-la
# contra um mock do sistema de arquivos apagaria a unica coisa que importa.
# ---------------------------------------------------------------------------
montar_fixtures() {
    T=$(mktemp -d) || { echo "ERRO: mktemp -d falhou"; exit 1; }
    trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT

    printf 'valor-de-teste\n'        > "$T/legivel"
    : > "$T/vazio"
    printf '\n\n'                    > "$T/so_quebras"

    # As tres formas de par que esta arvore encontra de verdade, mais uma isca:
    # HugePages_Total_Surplus vem ANTES de HugePages_Total para que um
    # casamento por substring (o vicio do `awk '/chave/'`) devolva o numero
    # errado com toda a cara de certo.
    {
        printf 'MemTotal:       32000000 kB\n'
        printf 'HugePages_Total_Surplus:   7\n'
        printf 'HugePages_Total:    1024\n'
        printf 'Hugepagesize:       2048 kB\n'
        printf 'CONFIG_XDP_SOCKETS=y\n'
        printf 'model name\t: CPU de teste\n'
        printf 'ChaveSozinha\n'
    } > "$T/campos"

    mkdir -p "$T/dir_no_lugar_de_arquivo"
    mkdir -p "$T/dir_vazio"
    mkdir -p "$T/dir_com_tres"
    : > "$T/dir_com_tres/a"; : > "$T/dir_com_tres/b"; mkdir "$T/dir_com_tres/c"

    ln -s "$T/legivel"      "$T/link_bom"
    ln -s "$T/nada_aqui"    "$T/link_quebrado"
    ln -s "$T/dir_com_tres" "$T/link_para_dir"

    # Privilegio: arquivo 000, diretorio 000 e -- o caso decisivo -- um alvo
    # INTACTO atras de um diretorio que nao se pode percorrer.
    printf 'segredo\n' > "$T/sem_leitura"; chmod 000 "$T/sem_leitura"
    mkdir -p "$T/dir_travado"; printf 'intacto\n' > "$T/dir_travado/alvo"
    chmod 000 "$T/dir_travado"
    mkdir -p "$T/dir_sem_x"; : > "$T/dir_sem_x/x"; chmod 000 "$T/dir_sem_x"

    # PATH temporario com iscas cobrindo os quatro desfechos de um programa.
    mkdir -p "$T/bin"
    printf '#!/bin/sh\necho saida-boa\n'                      > "$T/bin/isca_ok"
    printf '#!/bin/sh\necho parcial\necho "deu ruim" >&2\nexit 3\n' > "$T/bin/isca_falha"
    printf '#!/bin/sh\necho valor\necho "aviso inofensivo" >&2\nexit 0\n' > "$T/bin/isca_ruido"
    printf '#!/bin/sh\nexit 0\n'                              > "$T/bin/isca_vazia"
    chmod +x "$T/bin"/*
    PATH="$T/bin:$PATH"
}

# ---------------------------------------------------------------------------
# FASE 1 -- a bateria
# ---------------------------------------------------------------------------
bateria() {
    local lib=$1
    # shellcheck source=../lib-apuracao.sh
    . "$lib"

    local sou_root=0
    [ "${EUID:-1000}" -eq 0 ] && sou_root=1

    echo "== apur_ler =="

    apur_ler "$T/legivel"; check "arquivo legivel -> rc 0" "$?" "0"
    check "  valor sem a quebra de linha final" "$_APUR" "valor-de-teste"
    check "  estado" "$_APUR_ESTADO" "apurado"
    check "  motivo vazio quando apurado" "$_APUR_MOTIVO" ""
    check "  tipo" "$_APUR_TIPO" "arquivo"

    # A distincao que da nome a biblioteca, na sua forma mais crua: arquivo
    # vazio e FATO, com valor vazio. Qualquer outro estado aqui faria o resto
    # da arvore tratar "li e esta vazio" como "nao consegui ler".
    apur_ler "$T/vazio"; check "arquivo VAZIO -> rc 0 (e fato)" "$?" "0"
    check "  valor vazio" "$_APUR" ""
    check "  estado apurado, nao nao-apurado" "$_APUR_ESTADO" "apurado"

    apur_ler "$T/so_quebras"; check "arquivo so com quebras -> rc 0" "$?" "0"
    check "  valor vazio depois de aparar" "$_APUR" ""

    apur_ler "$T/nao_existe_mesmo"; check "inexistente -> rc 2 (AUSENTE)" "$?" "2"
    check "  estado" "$_APUR_ESTADO" "ausente"
    contem "  veneno em _APUR nomeia o estado" "AUSENTE" "$_APUR"
    contem "  motivo nomeia o alvo" "nao_existe_mesmo" "$_APUR_MOTIVO"

    apur_ler "$T/dir_no_lugar_de_arquivo"; check "diretorio no lugar de arquivo -> rc 1" "$?" "1"
    contem "  motivo diz que e diretorio" "DIRETORIO" "$_APUR_MOTIVO"
    nao_contem "  e NAO afirma que nao existe" "nao existe" "$_APUR_MOTIVO"

    apur_ler "$T/link_quebrado"; check "symlink quebrado -> rc 2 (AUSENTE)" "$?" "2"
    contem "  motivo diz symlink" "symlink" "$_APUR_MOTIVO"
    check "  tipo classifica o link" "$_APUR_TIPO" "symlink-quebrado"

    apur_ler "$T/link_bom"; check "symlink bom -> rc 0" "$?" "0"
    check "  valor vem do destino" "$_APUR" "valor-de-teste"

    if [ "$sou_root" -eq 1 ]; then
        lacuna "uid 0: EACCES em arquivo 000 nao existe; os ramos de privilegio de apur_ler ficaram sem cobertura"
    else
        apur_ler "$T/sem_leitura"; check "arquivo 000 -> rc 1 (NAO APURADO, nao ausente)" "$?" "1"
        check "  estado" "$_APUR_ESTADO" "nao-apurado"
        contem "  motivo nomeia o uid" "uid=" "$_APUR_MOTIVO"
        contem "  motivo diz que root mudaria a resposta" "root" "$_APUR_MOTIVO"
        nao_contem "  motivo NAO afirma inexistencia" "nao existe" "$_APUR_MOTIVO"
        contem "  veneno em _APUR nomeia o estado" "NAO APURADO" "$_APUR"

        # O CASO DECISIVO, e o que a arvore ja errou de verdade: o arquivo esta
        # la, intacto, atras de um diretorio que este uid nao percorre. `[ -e ]`
        # responde "falso" -- a mesma resposta que daria se nao existisse.
        apur_ler "$T/dir_travado/alvo"; check "alvo INTACTO atras de dir 000 -> rc 1" "$?" "1"
        check "  estado, e jamais 'ausente'" "$_APUR_ESTADO" "nao-apurado"
        contem "  motivo nomeia o diretorio que barrou" "dir_travado" "$_APUR_MOTIVO"
        contem "  motivo diz que nada se pode afirmar" "NADA se pode dizer" "$_APUR_MOTIVO"
    fi

    echo "== apur_link =="

    # A resolucao depende de `readlink`, a unica ferramenta externa de que a
    # biblioteca precisa para ler o sistema de arquivos. Sem ela a biblioteca
    # continua CORRETA -- devolve NAO APURADO nomeando a ferramenta que falta --
    # e e a PREMISSA destas assercoes que deixa de existir. Chamar isso de falha
    # seria acusar a biblioteca por acertar; chamar de sucesso seria o defeito
    # que este arquivo combate, aplicado ao proprio teste. E lacuna: contada,
    # nomeada, e visivel na saida final.
    if command -v readlink >/dev/null 2>&1; then
        apur_link "$T/link_bom"; check "symlink resolve -> rc 0" "$?" "0"
        check "  destino resolvido" "$_APUR" "$T/legivel"

        apur_link "$T/link_quebrado"; check "symlink quebrado -> rc 2" "$?" "2"
        contem "  motivo nomeia o destino inexistente" "nada_aqui" "$_APUR_MOTIVO"
    else
        # O que AINDA da para provar sem readlink: que a ausencia da ferramenta
        # vira NAO APURADO nomeando-a, e nunca um destino vazio nem um AUSENTE.
        apur_link "$T/link_bom"; check "sem readlink: symlink bom -> rc 1 (nao apurado)" "$?" "1"
        contem "  motivo nomeia a ferramenta que falta" "readlink" "$_APUR_MOTIVO"
        nao_contem "  e nao afirma que o destino nao existe" "nao existe" "$_APUR_MOTIVO"
        lacuna "readlink fora do PATH: a RESOLUCAO de symlink (apur_link em caminho bom e em link quebrado) ficou sem cobertura"
    fi

    apur_link "$T/legivel"; check "arquivo comum (nao e link) -> rc 1" "$?" "1"
    contem "  motivo diz que nao e symlink" "NAO e um symlink" "$_APUR_MOTIVO"

    apur_link "$T/nao_existe_mesmo"; check "link inexistente -> rc 2" "$?" "2"

    echo "== apur_campo =="

    apur_campo "$T/campos" HugePages_Total; check "chave com dois-pontos -> rc 0" "$?" "0"
    # Se este valor virar 7, o casamento deixou de ser literal e passou a ser
    # por substring: a isca HugePages_Total_Surplus vem antes no arquivo.
    check "  valor e o da chave EXATA, nao o da isca" "$_APUR" "1024"
    apur_campo "$T/campos" Hugepagesize
    check "valor com unidade vem inteiro" "$_APUR" "2048 kB"
    apur_campo "$T/campos" CONFIG_XDP_SOCKETS; check "chave com igual -> rc 0" "$?" "0"
    check "  valor" "$_APUR" "y"
    apur_campo "$T/campos" "model name"; check "chave com espaco -> rc 0" "$?" "0"
    check "  valor" "$_APUR" "CPU de teste"
    apur_campo "$T/campos" ChaveSozinha; check "chave sem valor -> rc 0" "$?" "0"
    check "  valor vazio e FATO" "$_APUR" ""

    # A separacao central deste acessor.
    apur_campo "$T/campos" ChaveQueNaoExiste; check "chave ausente do arquivo LIDO -> rc 2 (FATO)" "$?" "2"
    check "  estado" "$_APUR_ESTADO" "ausente"
    contem "  motivo diz que o arquivo foi lido" "foi lido" "$_APUR_MOTIVO"

    apur_campo "$T/nao_existe_mesmo" Chave; check "campo de arquivo inexistente -> rc 2" "$?" "2"
    apur_campo "$T/dir_no_lugar_de_arquivo" Chave; check "campo de diretorio -> rc 1 (nao apurado)" "$?" "1"
    if [ "$sou_root" -eq 1 ]; then
        lacuna "uid 0: apur_campo sobre arquivo ilegivel nao pode ser exercitado"
    else
        apur_campo "$T/sem_leitura" Chave; check "campo de arquivo ilegivel -> rc 1" "$?" "1"
        nao_contem "  e nao diz que a chave nao esta la" "chave" "$_APUR_MOTIVO"
    fi

    echo "== apur_listar =="

    apur_listar "$T/dir_com_tres"; check "diretorio com 3 entradas -> rc 0" "$?" "0"
    check "  contagem" "$_APUR_N" "3"
    apur_listar "$T/dir_vazio"; check "diretorio VAZIO -> rc 0 (e fato)" "$?" "0"
    check "  contagem zero apurada" "$_APUR_N" "0"
    check "  estado" "$_APUR_ESTADO" "apurado"
    apur_listar "$T/nao_existe_mesmo"; check "diretorio inexistente -> rc 2" "$?" "2"
    check "  contagem NAO fica com sobra da chamada anterior" "$_APUR_N" ""
    apur_listar "$T/legivel"; check "arquivo no lugar de diretorio -> rc 1" "$?" "1"
    apur_listar "$T/link_para_dir"; check "symlink para diretorio -> rc 0" "$?" "0"
    check "  contagem atraves do link" "$_APUR_N" "3"
    if [ "$sou_root" -eq 1 ]; then
        lacuna "uid 0: diretorio 000 e listavel; o ramo que separa 'vazio' de 'sem privilegio' ficou sem cobertura"
    else
        apur_listar "$T/dir_sem_x"; check "diretorio 000 -> rc 1, NAO zero entradas" "$?" "1"
        check "  contagem nao virou 0" "$_APUR_N" ""
        contem "  motivo avisa que a lista pode nao estar vazia" "pode nao estar vazia" "$_APUR_MOTIVO"
    fi

    echo "== apur_contar =="

    apur_contar "$T/campos" '^CONFIG_'; check "contagem com casamento -> rc 0" "$?" "0"
    check "  valor" "$_APUR" "1"
    check "  _APUR_N igual ao valor" "$_APUR_N" "1"
    apur_contar "$T/campos" 'kB'; check "duas ocorrencias" "$?" "0"
    check "  valor" "$_APUR" "2"

    # rc=1 do grep (zero casamentos) e FATO -- e a razao de este acessor nao
    # usar grep.
    apur_contar "$T/campos" '^ZZZ_NAO_EXISTE'; check "zero casamentos -> rc 0 (FATO)" "$?" "0"
    check "  valor zero" "$_APUR" "0"
    check "  estado apurado" "$_APUR_ESTADO" "apurado"

    apur_contar "$T/vazio" '.'; check "arquivo vazio -> rc 0" "$?" "0"
    check "  zero casamentos" "$_APUR" "0"
    apur_contar "$T/nao_existe_mesmo" '.'; check "arquivo inexistente -> rc 2" "$?" "2"
    apur_contar "$T/campos" '['; check "regex INVALIDA -> rc 1 (nao apurado)" "$?" "1"
    check "  estado" "$_APUR_ESTADO" "nao-apurado"
    nao_contem "  e o valor nao virou zero" "^0$" "$_APUR"
    contem "  motivo nega explicitamente o zero" "NAO significa zero" "$_APUR_MOTIVO"

    echo "== apur_cmd =="

    apur_cmd isca_ok; check "programa que sai 0 -> rc 0" "$?" "0"
    check "  stdout" "$_APUR" "saida-boa"
    check "  rc do programa" "$_APUR_RC" "0"

    apur_cmd isca_vazia; check "programa que nao imprime nada -> rc 0" "$?" "0"
    check "  saida vazia e FATO" "$_APUR" ""
    check "  estado" "$_APUR_ESTADO" "apurado"

    # Escrever em stderr NAO e falhar. Um aviso perdido e um diagnostico
    # perdido, entao ele fica em _APUR_ERRO em vez de virar erro.
    apur_cmd isca_ruido; check "stderr com codigo 0 -> rc 0" "$?" "0"
    check "  stdout limpo, sem o stderr colado" "$_APUR" "valor"
    check "  stderr preservado a parte" "$_APUR_ERRO" "aviso inofensivo"

    apur_cmd isca_falha; check "programa que sai 3 -> rc 1 (NAO APURADO)" "$?" "1"
    check "  estado" "$_APUR_ESTADO" "nao-apurado"
    contem "  motivo cita o codigo de saida" "codigo 3" "$_APUR_MOTIVO"
    contem "  motivo cita o stderr do programa" "deu ruim" "$_APUR_MOTIVO"
    check "  stdout parcial continua acessivel" "$_APUR_SAIDA" "parcial"
    check "  rc do programa continua acessivel" "$_APUR_RC" "3"

    apur_cmd programa_que_nao_existe_9f3a; check "programa fora do PATH -> rc 1" "$?" "1"
    check "  estado" "$_APUR_ESTADO" "nao-apurado"
    contem "  motivo diz PATH" "PATH" "$_APUR_MOTIVO"
    contem "  motivo nega que seja resposta negativa" "NAO e uma resposta negativa" "$_APUR_MOTIVO"
    check "  nao ha rc de programa, porque nenhum rodou" "$_APUR_RC" ""

    echo "== propriedades do contrato =="

    # [P1] o veneno: quem ignora o rc e imprime _APUR publica uma frase honesta,
    # nunca vazio e nunca zero.
    local caso
    for caso in "$T/nao_existe_mesmo" "$T/dir_no_lugar_de_arquivo"; do
        apur_ler "$caso"
        assercoes=$((assercoes + 1))
        case "$_APUR" in
            "NAO APURADO: "*|"AUSENTE: "*) echo "  ok    - veneno bem formado para $(basename "$caso")" ;;
            *) echo "  FALHA - _APUR sem prefixo de estado para $(basename "$caso"): '$_APUR'"
               falhas=$((falhas + 1)) ;;
        esac
    done

    # [P2] o veneno nao sobrevive a aritmetica sob `set -u`: em vez de render
    # zero, aborta. Medido aqui, nao deduzido -- e o subshell e de proposito,
    # porque o teste precisa SOBREVIVER ao aborto que esta provando.
    apur_ler "$T/nao_existe_mesmo"
    local rc_arit
    ( set -u; v=$_APUR; : $(( v + 0 )) ) >/dev/null 2>&1
    rc_arit=$?
    assercoes=$((assercoes + 1))
    if [ "$rc_arit" -ne 0 ]; then
        echo "  ok    - veneno em contexto aritmetico ABORTA (rc=$rc_arit) em vez de virar 0"
    else
        echo "  FALHA - veneno em contexto aritmetico foi aceito: a forma '0 simbolos' voltou a ser possivel"
        falhas=$((falhas + 1))
    fi

    # Estado limpo entre chamadas: sobra de uma chamada anterior e a versao
    # silenciosa do defeito.
    apur_cmd isca_falha
    apur_ler "$T/legivel"
    check "_APUR_RC limpo por uma chamada de outro acessor" "$_APUR_RC" ""
    check "_APUR_ERRO limpo por uma chamada de outro acessor" "$_APUR_ERRO" ""
    check "_APUR_MOTIVO limpo quando volta a apurar" "$_APUR_MOTIVO" ""
}

# ---------------------------------------------------------------------------
# FASE 2 -- mutacoes deliberadas
#
# Cada entrada e "nome|so-sem-root|expressao sed". Cada expressao reintroduz um
# defeito CONCRETO, quase todos ja cometidos nesta arvore. A mutacao precisa
# (a) alterar mesmo o arquivo, (b) continuar sendo bash valido e (c) fazer a
# bateria FALHAR. Falhar em (a) ou (b) e problema da lista de mutacoes; falhar
# em (c) e problema da bateria -- e nos tres casos este teste fica vermelho.
# ---------------------------------------------------------------------------
mutacoes=(
  'NAO APURADO deixa de envenenar _APUR (volta a ser vazio)|0|s|_APUR="NAO APURADO: \$1"|_APUR=""|'
  'AUSENTE devolve 1, colapsando com NAO APURADO|0|/_APUR_ESTADO="ausente"/{n;s/return 2/return 1/;}'
  # APURACAO-OK: esta linha e DADO, nao codigo -- e o texto-ancora que
  # a mutacao procura DENTRO da biblioteca. Ela nao le arquivo nenhum;
  # o `[ ! -r ]` aparece aqui para ser REMOVIDO da copia mutada, que e
  # justamente como se prova que a bateria pega a leitura sem existencia.
  'ancestral nao percorrivel deixa de ser detectado (o erro "uma pasta acima")|1|s|if \[ ! -x "\$acumulado" \]; then|if false; then|'
  # APURACAO-OK: esta linha e DADO, nao codigo -- e o texto-ancora que
  # a mutacao procura DENTRO da biblioteca. Ela nao le arquivo nenhum;
  # o `[ ! -r ]` aparece aqui para ser REMOVIDO da copia mutada, que e
  # justamente como se prova que a bateria pega a leitura sem existencia.
  'apur_ler nao testa -r: EACCES perde a frase de privilegio|1|s|if \[ ! -r "\$caminho" \]; then|if false; then|'
  'apur_ler aceita diretorio como se fosse arquivo|0|s|if \[ "\$_APUR_TIPO" = "diretorio" \]; then|if false; then|'
  'symlink quebrado deixa de ser reconhecido como tal|0|s|    if \[ -L "\$alvo" \]; then|    if false; then|'
  'chave ausente do arquivo lido vira NAO APURADO em vez de FATO|0|s|_apur_ausente "\$caminho foi lido|_apur_nao_apurado "\$caminho foi lido|'
  'apur_campo casa a chave por substring (o vicio do awk /chave/)|0|s|            "\$chave")             resto="" ;;|            *"\$chave"*)          resto="" ;;|'
  'regex invalida vira zero casamentos|0|s|            \*) _apur_nao_apurado "a expressao regular|            9) _apur_nao_apurado "a expressao regular|'
  # APURACAO-OK: esta linha e DADO, nao codigo -- e o texto-ancora que
  # a mutacao procura DENTRO da biblioteca. Ela nao le arquivo nenhum;
  # o `[ ! -r ]` aparece aqui para ser REMOVIDO da copia mutada, que e
  # justamente como se prova que a bateria pega a leitura sem existencia.
  'apur_listar nao testa -r/-x: dir sem privilegio vira zero entradas|1|s#if \[ ! -r "\$caminho" \] || \[ ! -x "\$caminho" \]; then#if false; then#'
  'apur_cmd ignora o codigo de saida do programa|0|/rm -f "\$arquivo_erro"/,/^\}$/s|if \[ "\$rc" -ne 0 \]; then|if false; then|'
  'apur_cmd trata stderr como falha|0|/rm -f "\$arquivo_erro"/,/^\}$/s|if \[ "\$rc" -ne 0 \]; then|if [ -n "$_APUR_ERRO" ]; then|'
  'apur_cmd deixa de checar o PATH: ferramenta ausente perde a frase|0|s|    if ! command -v "\$programa" >/dev/null 2>&1; then|    if false; then|'
  'valor vazio deixa de ser fato (empurrado para nao apurado)|0|s|^_apur_ok() {|_apur_ok() { [ -z "$1" ] \&\& return 1|'
  '_apur_limpar vira no-op: estado vaza de uma chamada para a seguinte|0|s|^_apur_limpar() {|_apur_limpar() { return 0|'
)

rodar_mutacoes() {
    local sou_root=0
    [ "${EUID:-1000}" -eq 0 ] && sou_root=1
    local tmp entrada nome so_sem_root expr pegas=0 puladas=0

    tmp=$(mktemp -d) || { echo "ERRO: mktemp -d falhou na fase 2"; exit 1; }

    for entrada in "${mutacoes[@]}"; do
        nome=${entrada%%|*}
        local resto=${entrada#*|}
        so_sem_root=${resto%%|*}
        expr=${resto#*|}

        if [ "$so_sem_root" = "1" ] && [ "$sou_root" -eq 1 ]; then
            lacuna "mutacao nao exercitada sob uid 0: $nome"
            puladas=$((puladas + 1))
            continue
        fi

        local copia="$tmp/lib-mutada.sh"
        sed "$expr" "$LIB_REAL" > "$copia"

        assercoes=$((assercoes + 1))
        if cmp -s "$LIB_REAL" "$copia"; then
            echo "  FALHA - mutacao NAO SE APLICA MAIS (ancora sumiu da biblioteca): $nome"
            falhas=$((falhas + 1))
            continue
        fi
        if ! bash -n "$copia" 2>/dev/null; then
            echo "  FALHA - mutacao produziu bash invalido, entao nao prova nada: $nome"
            falhas=$((falhas + 1))
            continue
        fi
        if bash "$0" --bateria "$copia" >"$tmp/saida" 2>&1; then
            echo "  FALHA - mutacao PASSOU pela bateria: $nome"
            echo "          (a bateria nao cobre este defeito; veja $tmp/saida)"
            falhas=$((falhas + 1))
        else
            echo "  ok    - pega: $nome"
            pegas=$((pegas + 1))
        fi
    done

    rm -rf "$tmp"
    echo ""
    echo "  mutacoes pegas: $pegas de ${#mutacoes[@]} (${puladas} nao exercitada(s) sob este uid)"
}

# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------
modo="completo"
lib_alvo="$LIB_REAL"
if [ "${1:-}" = "--bateria" ]; then
    modo="bateria"
    lib_alvo=${2:?"--bateria exige o caminho da biblioteca"}
fi

# Existencia ANTES de leitura, que e a ordem que a biblioteca prega -- e este
# teste a estava invertendo. A versao anterior perguntava `[ ! -r ]` primeiro e
# so depois descobria qual dos dois casos era; com os testes na ordem errada, um
# erro de composicao da mensagem sairia como a frase errada. A varredura de
# apuracao do pre-commit apontou este bloco, no teste do arquivo escrito para
# fechar exatamente esta classe.
if [ ! -e "$lib_alvo" ]; then
    echo "ERRO: $lib_alvo nao existe." >&2
    exit 1
fi
if [ ! -r "$lib_alvo" ]; then
    echo "ERRO: $lib_alvo existe e este processo (uid=${EUID:-?}) nao pode le-lo." >&2
    exit 1
fi

montar_fixtures

if [ "$modo" = "bateria" ]; then
    bateria "$lib_alvo"
else
    echo "== FASE 1: bateria contra a biblioteca de verdade =="
    bateria "$lib_alvo"
    echo ""
    echo "== FASE 2: mutacoes deliberadas -- a bateria PEGA cada uma? =="
    rodar_mutacoes
fi

echo ""
echo "L1 apuracao: $assercoes assercao(oes)."
if [ "$lacunas" -gt 0 ]; then
    echo "  $lacunas lacuna(s): blocos que ESTE ambiente nao consegue exercitar --"
    echo "  privilegio (uid 0 nao sofre EACCES) ou ferramenta ausente do PATH."
    echo "  NAO sao sucessos: estao nomeados acima, um a um, justamente para que"
    echo "  'nao deu para testar' nunca passe por 'testado e correto'."
fi
if [ "$falhas" -eq 0 ]; then
    echo "L1 apuracao: nenhuma falha."
else
    echo "L1 apuracao: $falhas falha(s)."
    exit 1
fi
if [ "$modo" = completo ] && [ "$lacunas" -gt 0 ]; then
    echo 'SKIP: entrada parcialmente exercitada; consulte as lacunas acima'
    exit 77
fi
