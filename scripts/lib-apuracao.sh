# SPDX-License-Identifier: MIT
#
# lib-apuracao.sh -- o unico caminho para ler um fato do sistema.
#
# ===========================================================================
# POR QUE ESTE ARQUIVO EXISTE
# ===========================================================================
#
# O DEFEITO, ENUNCIADO: informacao que NAO PODE SER APURADA -- por falta de
# privilegio, por erro engolido, por ferramenta ausente -- sai renderizada
# como um FATO NEGATIVO. "0 simbolos", "nenhuma hugepage reservada", "nao e
# ethernet", "nao carrega a rota default". "Nao sei" virando "nao".
#
# A DISTINCAO que o projeto inteiro vinha perdendo, e que este arquivo existe
# para tornar impossivel de perder:
#
#   AUSENTE e um FATO. "/sys/class/net/eth9 nao existe" e informacao legitima,
#   apurada, publicavel. O leitor pode agir sobre ela.
#
#   NAO APURADO nao e fato nenhum. "nao consegui ler" NUNCA pode virar valor,
#   numero, string vazia interpretada adiante, nem rotulo negativo. Publicar
#   isso como fato e mentir com cara de medicao.
#
# Hoje, na arvore, as duas colapsam em "" ou em "0" -- e e dai que vem o
# defeito inteiro.
#
# POR QUE UMA BIBLIOTECA, E NAO MAIS UMA REGRA DE LINT
#
# Tres rodadas tentaram fechar esta classe corrigindo lugar a lugar e, na
# ultima, com um lint sintatico sobre as formas `|| true` e `|| echo 0`. O
# veredito registrado foi que a regra fecha uma SINTAXE, nao o defeito: regex
# sobre shell enxerga o texto `|| true`, nao enxerga "este valor nao apurado
# vai ser publicado". Decidir isso exigiria saber o que o codigo faz com a
# variavel dez linhas adiante -- indecidivel para um varredor de linhas.
#
# A saida nao e uma regra mais esperta. E tornar o defeito IRREPRESENTAVEL:
# um punhado de acessores passa a ser o unico caminho para ler um fato do
# sistema, cada um devolvendo TRI-ESTADO. A pergunta do lint deixa de ser
# "este `|| true` importa?" (indecidivel) e passa a ser "este arquivo le /sys
# cru?" (decidivel por CAMINHO).
#
# ===========================================================================
# O CONTRATO
# ===========================================================================
#
#   rc=0  APURADO       o valor esta em $_APUR. $_APUR_MOTIVO e vazio.
#   rc=1  NAO APURADO   $_APUR_MOTIVO diz O QUE faltou, em frase completa.
#   rc=2  AUSENTE       confirmado que nao existe. $_APUR_MOTIVO nomeia o alvo.
#
# VARIAVEIS DE MODULO, e o motivo de nao serem valor de retorno:
#
#   _APUR         apurado: o valor. NAO apurado / ausente: o VENENO -- a frase
#                 "NAO APURADO: <motivo>" ou "AUSENTE: <motivo>".
#   _APUR_ESTADO  "apurado" | "nao-apurado" | "ausente".
#   _APUR_MOTIVO  a frase explicativa, sem prefixo. Vazia quando apurado.
#   _APUR_TIPO    lstat do alvo: arquivo | diretorio | symlink-quebrado | outro.
#   _APUR_N       numero de entradas (apur_listar) ou de casamentos (apur_contar).
#   _APUR_RC      codigo de saida do programa externo (apur_cmd).
#   _APUR_SAIDA   stdout do programa externo, mesmo quando ele falhou.
#   _APUR_ERRO    stderr do programa externo, mesmo quando ele teve sucesso.
#
# POR QUE O VALOR NAO VOLTA POR `$( )`, e isto e o aprendizado caro da rodada
# anterior: uma substituicao de comando roda em SUBSHELL, e o subshell morre
# levando junto as variaveis de motivo. O chamador acabava imprimindo
# "NAO APURADO:" seguido de nada -- a forma mais cruel do defeito, porque
# parece tratamento correto. Aqui o valor sai por variavel de modulo e o rc e
# o canal de controle. NUNCA escreva `x=$(apur_ler /proc/meminfo)`.
#
# AS DUAS PROPRIEDADES QUE SUSTENTAM O RESTO, e valem mais que o tri-estado
# em si, porque protegem o chamador DESATENTO -- que e a maioria dos
# chamadores, sempre:
#
#   [P1] $_APUR NUNCA E VAZIO NEM ZERO quando o fato nao foi apurado. Ele
#        carrega o VENENO: a frase inteira. Quem ignorar o rc e imprimir
#        $_APUR publica "NAO APURADO: /proc/meminfo existe e o uid 1000 nao
#        pode le-lo" -- feio, longo, e HONESTO. O caminho preguicoso deixou de
#        produzir mentira e passou a produzir constrangimento, que e
#        exatamente o incentivo que se quer.
#
#   [P2] O VENENO NAO SOBREVIVE A ARITMETICA. Sob `set -u` -- que todo script
#        deste projeto usa -- `n=$(( _APUR ))` sobre o veneno ABORTA o script
#        com "variavel nao associada", em vez de render zero. Foi medido, nao
#        deduzido. Assim a forma mais perigosa de todas ("0 simbolos",
#        "0 hugepages") deixa de ter como acontecer em silencio.
#
# O chamador preguicoso que escreve `apur_ler X || echo "$_APUR_MOTIVO"` fica
# CORRETO de graca nos dois ramos nao-zero, porque AUSENTE tambem preenche
# _APUR_MOTIVO com uma frase verdadeira. Colapsar rc=1 e rc=2 num `else` era
# a forma mais provavel de reintroduzir o defeito; o contrato foi desenhado
# para que esse colapso continue dizendo a verdade.
#
# ===========================================================================
# ENOENT x EACCES: o erro "uma pasta acima"
# ===========================================================================
#
# `[ -e X ]` e FALSO em dois casos que nao tem nada a ver um com o outro:
#   (a) X nao existe                     -> fato, publicavel
#   (b) um DIRETORIO ACIMA de X nao e percorrivel por este uid -> nao apurado
#
# O mesmo vale para `[ -r X ]`, e foi assim que este projeto ja afirmou "nao
# ha /boot/config-<versao>" numa maquina em que o arquivo estava la, intacto,
# atras de um /boot em modo 000. Por isso NENHUM acessor deste arquivo testa
# `-r` ou `-e` diretamente sobre o alvo: todos passam antes por
# _apur_diagnostico(), que CAMINHA a cadeia de ancestrais e so conclui
# "ausente" depois de provar que cada diretorio do caminho era percorrivel.
# Existencia ANTES de leitura, sempre, e existencia do CAMINHO INTEIRO.
#
# ===========================================================================
# DEPENDENCIAS EXTERNAS, e por que sao quase nenhuma
# ===========================================================================
#
# Ferramenta ausente do PATH e uma das tres origens do defeito. A defesa mais
# barata contra ela e nao depender da ferramenta: leitura, extracao de campo,
# listagem e contagem sao feitas com construcoes do proprio shell. Em
# particular apur_contar NAO usa `grep`, e com isso a ambiguidade classica do
# rc do grep (1 = zero casamentos, que e FATO; >1 = erro, que NAO E) deixa de
# precisar de manejo: ela nao existe neste caminho.
#
# Sobram duas dependencias, ambas declaradas e ambas com ramo de NAO APURADO:
# `readlink` (apur_link) e o proprio programa pedido (apur_cmd) mais `mktemp`,
# que apur_cmd usa para separar stderr de stdout.
#
# USO
#     . "$(dirname "$0")/lib-apuracao.sh"
#     if apur_ler /sys/class/net/eth0/mtu; then
#         echo "MTU: $_APUR"
#     else
#         echo "MTU: $_APUR"      # veneno honesto, nos dois ramos nao-zero
#     fi

# As variaveis nascem definidas porque todo script desta arvore roda sob
# `set -u`: uma leitura antes da primeira chamada abortaria o script.
_APUR=""
_APUR_ESTADO=""
_APUR_MOTIVO=""
_APUR_TIPO=""
_APUR_N=""
_APUR_RC=""
_APUR_SAIDA=""
_APUR_ERRO=""

# --- construtores dos tres estados -------------------------------------------
#
# Sao a UNICA forma de sair de um acessor. Passar por eles garante que _APUR,
# _APUR_ESTADO e _APUR_MOTIVO nunca se contradigam -- um estado semi-preenchido
# (motivo de uma chamada, valor de outra) e a versao silenciosa do defeito.
#
# TODO chamador destes tres sai com `return` NU, nunca com `return 1` ou
# `return 2` escrito de novo. O `return` sem argumento devolve o codigo do
# ultimo comando, isto e, o do proprio construtor -- que passa a ser a UNICA
# fonte da verdade sobre qual rc corresponde a qual estado.
#
# Isto nao e preferencia de estilo, e a correcao de um defeito real, achado
# pela rodada de mutacoes do teste L1 deste arquivo: com o literal repetido em
# cada ponto de saida, alterar o `return` do construtor de AUSENTE para 1 --
# colapsando AUSENTE com NAO APURADO, exatamente a distincao que a biblioteca
# existe para manter -- nao mudava o comportamento de acessor nenhum, porque os
# vinte pontos de saida que repetiam o literal mascaravam a mudanca. Um contrato com vinte
# copias do seu valor central nao e um contrato: e vinte chances de divergir.
# Reproduza a contagem dos pontos de saida antes de editar esta frase:
#     grep -cE '^[[:space:]]*return$' scripts/lib-apuracao.sh

_apur_limpar() {
    _APUR=""
    _APUR_ESTADO=""
    _APUR_MOTIVO=""
    _APUR_TIPO=""
    _APUR_N=""
    _APUR_RC=""
    _APUR_SAIDA=""
    _APUR_ERRO=""
}

_apur_ok() {
    _APUR=$1
    _APUR_ESTADO="apurado"
    _APUR_MOTIVO=""
    return 0
}

# O prefixo faz parte do VALOR de proposito -- e a propriedade [P1]. Sem ele,
# quem imprimir $_APUR sem olhar o rc publica uma frase solta que passa por
# medicao.
_apur_nao_apurado() {
    _APUR_MOTIVO=$1
    _APUR="NAO APURADO: $1"
    _APUR_ESTADO="nao-apurado"
    return 1
}

_apur_ausente() {
    _APUR_MOTIVO=$1
    _APUR="AUSENTE: $1"
    _APUR_ESTADO="ausente"
    return 2
}

# _apur_uid -- o uid efetivo, para as frases de EACCES.
#
# `$EUID` e variavel do proprio bash: nao chama `id`, que poderia estar fora do
# PATH. Uma frase de NAO APURADO que depende de ferramenta externa pode sair
# incompleta justamente no ambiente degradado em que ela e mais necessaria.
_apur_uid() { printf '%s' "${EUID:-?}"; }

# --- _apur_diagnostico <caminho> --------------------------------------------
#
# O coracao da biblioteca. Devolve:
#   0  o caminho EXISTE (lstat deu certo). _APUR_TIPO classifica o que e.
#   1  NAO APURADO -- a cadeia de ancestrais foi interrompida por falta de
#      privilegio de travessia, e NADA se pode afirmar sobre o alvo.
#   2  AUSENTE -- provado: todos os ancestrais eram percorriveis e o alvo nao
#      esta la.
#
# A caminhada e o ponto inteiro. Testar `[ -e "$alvo" ]` de uma vez responde
# "falso" para os dois casos, e a mensagem escolhe um deles no chute.
#
# _APUR_TIPO:
#   arquivo           arquivo regular (ou symlink que resolve para um)
#   diretorio         diretorio (ou symlink que resolve para um)
#   symlink-quebrado  o link existe; o destino dele, nao
#   outro             fifo, socket, dispositivo -- existe e nao e nenhum dos acima
_apur_diagnostico() {
    local alvo=$1
    local acumulado restante seg destino
    local -a segmentos=()
    local i total

    if [ -z "$alvo" ]; then
        _apur_nao_apurado "foi pedido o caminho vazio; nao ha o que apurar"
        return
    fi

    case "$alvo" in
        /*) acumulado=""; restante=${alvo#/} ;;
        *)  acumulado="."; restante=$alvo ;;
    esac

    # Split manual por '/': IFS local a este read, sem tocar no IFS do chamador.
    local IFS_ANTERIOR=$IFS
    IFS='/'
    read -r -a segmentos <<<"$restante"
    IFS=$IFS_ANTERIOR

    # Todos os segmentos MENOS o ultimo sao os ancestrais. Um ancestral que nao
    # se pode percorrer encerra a apuracao ali: o que estiver abaixo e
    # desconhecido, e desconhecido nao se publica.
    total=${#segmentos[@]}
    for ((i = 0; i < total - 1; i++)); do
        seg=${segmentos[i]}
        [ -z "$seg" ] && continue          # barras duplicadas: //a//b
        acumulado="$acumulado/$seg"
        if [ -L "$acumulado" ] && [ ! -e "$acumulado" ]; then
            _apur_ausente "o ancestral $acumulado e um symlink quebrado, entao $alvo nao existe"
            return
        fi
        if [ ! -e "$acumulado" ]; then
            # Seguro: os ancestrais ACIMA deste ja foram provados percorriveis
            # nas voltas anteriores do laco, entao este "-e falso" so pode ser
            # ENOENT de verdade.
            _apur_ausente "o diretorio $acumulado nao existe, entao $alvo tambem nao"
            return
        fi
        if [ ! -d "$acumulado" ]; then
            _apur_ausente "$acumulado existe e NAO e diretorio, entao $alvo nao pode existir"
            return
        fi
        if [ ! -x "$acumulado" ]; then
            _apur_nao_apurado "$acumulado existe e este processo (uid=$(_apur_uid)) nao pode percorre-lo; NADA se pode dizer sobre $alvo -- nem que existe, nem que nao existe"
            return
        fi
    done

    # Daqui em diante o caminho ate o pai esta provado percorrivel, e as
    # respostas de `-e` e `-L` sobre o alvo sao confiaveis.
    if [ -e "$alvo" ]; then
        if [ -d "$alvo" ]; then _APUR_TIPO="diretorio"
        elif [ -f "$alvo" ]; then _APUR_TIPO="arquivo"
        else _APUR_TIPO="outro"
        fi
        return 0
    fi

    if [ -L "$alvo" ]; then
        _APUR_TIPO="symlink-quebrado"
        destino=""
        if command -v readlink >/dev/null 2>&1; then
            destino=$(readlink "$alvo" 2>/dev/null)
        fi
        if [ -n "$destino" ]; then
            _apur_ausente "$alvo e um symlink que aponta para \"$destino\", e esse destino nao existe"
        else
            # O destino nao ser apurado NAO contamina o fato: o destino do link
            # nao existe -- isso ja esta provado por `-L` verdadeiro com `-e`
            # falso. So a IDENTIDADE do destino ficou desconhecida, e a frase
            # diz qual das duas coisas e qual.
            _apur_ausente "$alvo e um symlink quebrado (o destino dele nao existe; o nome do destino nao foi apurado: readlink nao esta no PATH)"
        fi
        return
    fi

    _apur_ausente "$alvo nao existe"
    return
}

# --- apur_ler <caminho> ------------------------------------------------------
#
# Conteudo de um arquivo de /sys, /proc, /boot, /lib/modules ou de qualquer
# outro lugar. Substitui `cat X 2>/dev/null` e `$(<X)` nus.
#
#   apurado (0)      $_APUR = conteudo, sem as quebras de linha do fim.
#                    ARQUIVO VAZIO E APURADO, com $_APUR vazio: "li o arquivo e
#                    ele esta vazio" e um FATO, e o unico caso legitimo de
#                    $_APUR vazio na biblioteca inteira. Quem trata vazio como
#                    resposta precisa olhar $_APUR_ESTADO, nao o comprimento.
#   nao apurado (1)  ancestral nao percorrivel; existe e nao e legivel; e
#                    diretorio e nao arquivo; a leitura falhou depois disso.
#   ausente (2)      nao existe, ou e symlink quebrado.
#
# Ler com `$(<"$1")` em vez de `cat` e deliberado: e redirecionamento do
# proprio shell, nao ha processo novo e nao ha como o `cat` faltar no PATH.
apur_ler() {
    local caminho=$1 conteudo rc
    _apur_limpar
    _apur_diagnostico "$caminho" || return $?

    if [ "$_APUR_TIPO" = "diretorio" ]; then
        _apur_nao_apurado "$caminho existe e e um DIRETORIO, nao um arquivo; nao ha conteudo para ler"
        return
    fi
    # APURACAO-OK: a existencia de "$caminho" NAO e testada aqui porque ja foi
    # provada por _apur_diagnostico() logo acima, que caminhou a cadeia inteira
    # de ancestrais e so devolveu 0 depois de confirmar que o alvo existe. E
    # por isso -- e so por isso -- que este `-r` sozinho pode ser lido como
    # "sem privilegio" em vez de "nao existe". A varredura automatica procura um
    # `[ -e ]` literal na mesma funcao e nao tem como enxergar a prova feita uma
    # chamada acima; a prova esta la, e esta testada.
    if [ ! -r "$caminho" ]; then
        _apur_nao_apurado "$caminho existe e este processo (uid=$(_apur_uid)) nao pode le-lo; a informacao pode existir, o acesso e que falta -- aqui root muda a resposta"
        return
    fi

    { conteudo=$(<"$caminho"); } 2>/dev/null
    rc=$?
    if [ "$rc" -ne 0 ]; then
        # Exotico e real: arquivos de /proc que devolvem erro na leitura
        # (EIO, EINVAL) apesar de existirem e terem o bit de leitura.
        _apur_nao_apurado "$caminho existe e e legivel, e a leitura mesmo assim falhou (rc=$rc); pode ser um arquivo de /proc que recusa a leitura neste contexto"
        return
    fi
    _apur_ok "$conteudo"
}

# --- apur_link <caminho> -----------------------------------------------------
#
# Destino RESOLVIDO de um symlink -- `/sys/bus/pci/devices/<bdf>/driver`,
# `/sys/class/net/<if>/device/driver`. Substitui
# `basename "$(readlink -f X 2>/dev/null)" 2>/dev/null`, forma que devolvia
# string vazia para EACCES e para ENOENT igualmente, e cujo vazio virava, uma
# funcao adiante, um nome de driver.
#
#   apurado (0)      $_APUR = caminho absoluto resolvido.
#   nao apurado (1)  ancestral nao percorrivel; o caminho existe e NAO e
#                    symlink; `readlink` fora do PATH; readlink falhou.
#   ausente (2)      nao existe, ou e symlink quebrado.
#
# Existir e nao ser symlink e NAO APURADO, e nao "apurado, o valor e ele
# mesmo": quem chama pediu o destino de um link. Devolver o proprio caminho
# calado faria um diretorio comum passar por driver resolvido.
apur_link() {
    local caminho=$1 destino rc erro
    _apur_limpar
    _apur_diagnostico "$caminho" || return $?

    if [ ! -L "$caminho" ]; then
        _apur_nao_apurado "$caminho existe (tipo: $_APUR_TIPO) e NAO e um symlink; nao ha destino para resolver"
        return
    fi
    if ! command -v readlink >/dev/null 2>&1; then
        _apur_nao_apurado "$caminho e um symlink e \"readlink\" nao esta no PATH (Debian/Ubuntu: apt install coreutils); nao e falta de privilegio nem ausencia da informacao, e ferramenta faltando"
        return
    fi

    erro=$(readlink -f "$caminho" 2>&1 >/dev/null)
    destino=$(readlink -f "$caminho" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$destino" ]; then
        _apur_nao_apurado "$caminho e um symlink e \"readlink -f\" saiu com codigo $rc${erro:+ ($erro)}"
        return
    fi
    _apur_ok "$destino"
}

# --- apur_campo <arquivo> <chave> -------------------------------------------
#
# Um campo de um arquivo de texto, e aqui mora a distincao que da nome a
# biblioteca:
#
#   "li o arquivo e a linha nao esta la"  -> AUSENTE (2). FATO. Foi assim que
#       se apurou que um kernel nao publica HugePages_Total: o arquivo foi
#       lido inteiro e a chave nao aparece.
#   "nao li o arquivo"                    -> NAO APURADO (1). Nao e fato nenhum.
#
# Sem essa separacao as duas saem como campo vazio, e o vazio vira zero.
#
# Aceita as tres formas de par que esta arvore encontra de verdade:
#     HugePages_Total:       0        (/proc/meminfo)
#     CONFIG_XDP_SOCKETS=y            (/boot/config-*, /proc/config.gz)
#     model name	: ...               (chave com espaco, separada por branco)
# O valor e tudo o que vem depois do separador, aparado nas duas pontas -- de
# modo que `Hugepagesize: 2048 kB` devolve "2048 kB", e quem quer so o numero
# pega a primeira palavra. Aparar por conta propria seria adivinhar o formato.
#
# A chave e comparada LITERALMENTE, nao como expressao regular: a forma
# `awk '/HugePages_Total/'` que este projeto usava casa tambem com
# `HugePages_Total_Whatever`, e um casamento largo publica o numero errado com
# toda a cara de certo.
apur_campo() {
    local caminho=$1 chave=$2 conteudo linha resto
    apur_ler "$caminho" || return $?
    conteudo=$_APUR

    while IFS= read -r linha || [ -n "$linha" ]; do
        case "$linha" in
            "$chave")             resto="" ;;
            "$chave":*)           resto=${linha#"$chave":} ;;
            "$chave"=*)           resto=${linha#"$chave"=} ;;
            "$chave"[[:blank:]]*) resto=${linha#"$chave"} ;;
            *) continue ;;
        esac
        # Apara branco das duas pontas e um ':' encostado na chave separada por
        # espaco ("model name\t: x").
        resto=${resto#"${resto%%[![:blank:]]*}"}
        case "$resto" in :*) resto=${resto#:} ;; esac
        resto=${resto#"${resto%%[![:blank:]]*}"}
        resto=${resto%"${resto##*[![:blank:]]}"}
        _apur_ok "$resto"
        return 0
    done <<<"$conteudo"

    _apur_ausente "$caminho foi lido por inteiro e NAO ha linha com a chave \"$chave\"; isto e diferente de nao ter conseguido ler o arquivo"
    return
}

# --- apur_listar <diretorio> -------------------------------------------------
#
# Entradas de um diretorio, uma por linha, em $_APUR; a contagem em $_APUR_N.
# Substitui `ls -d X/* 2>/dev/null | wc -l`, forma que devolve o numero 0 tanto
# para "o diretorio esta vazio" (FATO) quanto para "nao consegui abrir o
# diretorio" (NAO APURADO) -- e foi ela que produziu "grupos IOMMU no sistema: 0"
# em maquinas com IOMMU ligada.
#
#   apurado (0)      $_APUR = entradas; $_APUR_N = quantas. DIRETORIO VAZIO E
#                    APURADO, com $_APUR_N igual a 0: e um fato.
#   nao apurado (1)  ancestral nao percorrivel; existe e nao e diretorio;
#                    existe e falta -r ou -x.
#   ausente (2)      nao existe, ou e symlink quebrado.
#
# Precisa de -r E -x: `-r` lista os nomes, `-x` permite olhar cada entrada. Um
# diretorio --x (executavel, nao legivel) devolveria glob vazio, isto e, zero
# entradas -- o defeito de novo. Entradas ocultas ficam de fora; /sys e /proc
# nao tem nenhuma, e incluir "." e ".." estragaria toda contagem.
apur_listar() {
    local caminho=$1 entrada saida="" n=0
    _apur_limpar
    _apur_diagnostico "$caminho" || return $?

    if [ "$_APUR_TIPO" != "diretorio" ]; then
        _apur_nao_apurado "$caminho existe e NAO e um diretorio (tipo: $_APUR_TIPO); nao ha entradas para listar"
        return
    fi
    if [ ! -r "$caminho" ] || [ ! -x "$caminho" ]; then
        _apur_nao_apurado "$caminho existe e este processo (uid=$(_apur_uid)) nao pode listar seu conteudo; a lista pode nao estar vazia -- nao foi possivel olhar"
        return
    fi

    local nullglob_estava_ligado=0
    shopt -q nullglob && nullglob_estava_ligado=1
    shopt -s nullglob
    for entrada in "$caminho"/*; do
        saida="${saida}${entrada##*/}"$'\n'
        n=$((n + 1))
    done
    [ "$nullglob_estava_ligado" -eq 1 ] || shopt -u nullglob

    _APUR_N=$n
    _apur_ok "${saida%$'\n'}"
}

# --- apur_contar <arquivo> <ere> ---------------------------------------------
#
# Quantas linhas de <arquivo> casam com a expressao regular estendida <ere>.
# Resultado em $_APUR e em $_APUR_N.
#
#   apurado (0)      $_APUR = numero de casamentos. ZERO E APURADO: "li o
#                    arquivo e nenhuma linha casa" e um FATO.
#   nao apurado (1)  o arquivo nao pode ser lido (propagado de apur_ler), ou a
#                    expressao regular e invalida.
#   ausente (2)      o arquivo nao existe.
#
# NAO USA `grep`, e a ausencia e o ponto. `grep -c` sai 1 para zero casamentos
# (informacao legitima) e >1 para erro -- e todo `grep -c ... || true` da
# arvore apagava a diferenca, transformando "nao consegui procurar" no numero
# zero. Aqui a contagem e feita com `[[ =~ ]]`, do proprio shell: o grep nao
# pode faltar no PATH porque nao e chamado, e a ambiguidade do rc nao precisa
# ser manejada porque nao existe.
#
# `[[ =~ ]]` devolve 2 para expressao invalida, e isso e NAO APURADO -- nao
# zero casamentos. Sem essa separacao, um erro de digitacao na regex sairia
# como "nenhuma ocorrencia", que e uma afirmacao sobre o arquivo.
apur_contar() {
    local caminho=$1 ere=$2 conteudo linha n=0 rc_regex
    apur_ler "$caminho" || return $?
    conteudo=$_APUR

    while IFS= read -r linha || [ -n "$linha" ]; do
        { [[ $linha =~ $ere ]]; } 2>/dev/null
        rc_regex=$?
        case "$rc_regex" in
            0) n=$((n + 1)) ;;
            1) ;;
            *) _apur_nao_apurado "a expressao regular \"$ere\" e invalida (o shell recusou com codigo $rc_regex); nenhuma contagem foi feita -- isto NAO significa zero ocorrencias"
               return 1 ;;
        esac
    done <<<"$conteudo"

    _APUR_N=$n
    _apur_ok "$n"
}

# --- apur_cmd <programa> [argumentos...] -------------------------------------
#
# Roda um programa externo capturando stdout, stderr E o codigo de saida
# separadamente -- as tres coisas que `$(cmd 2>/dev/null)` joga fora de uma vez.
#
#   apurado (0)      o programa rodou e saiu 0. $_APUR = stdout (sem quebras de
#                    linha do fim). SAIDA VAZIA E APURADA: "rodou e nao imprimiu
#                    nada" e um fato. $_APUR_ERRO guarda o stderr, que pode
#                    existir mesmo com sucesso -- escrever em stderr NAO e
#                    falhar, e um aviso perdido e um diagnostico perdido.
#   nao apurado (1)  o programa nao esta no PATH; ou rodou e saiu != 0; ou
#                    `mktemp` falhou e nao houve onde separar o stderr.
#
# Nao ha ramo AUSENTE: "este programa nao esta instalado" e um fato sobre a
# MAQUINA, e nao sobre o que se queria apurar. O valor continua desconhecido, e
# o estado que descreve o valor e NAO APURADO. Ferramenta faltando e uma das
# tres origens do defeito, e e a mais facil de disfarcar de resposta.
#
# Codigo != 0 vira NAO APURADO POR PADRAO, que e o lado seguro. Para o punhado
# de programas em que um codigo especifico e informacao (e nao falha), o
# chamador tem $_APUR_RC e $_APUR_SAIDA preenchidos tambem no ramo de falha e
# pode decidir por conta propria -- explicitamente, que e a diferenca.
apur_cmd() {
    local programa=$1 arquivo_erro saida rc
    _apur_limpar

    if [ -z "$programa" ]; then
        _apur_nao_apurado "apur_cmd foi chamado sem programa; nao ha o que executar"
        return
    fi
    if ! command -v "$programa" >/dev/null 2>&1; then
        _apur_nao_apurado "o programa \"$programa\" nao esta no PATH; a consulta nao foi feita -- isto NAO e uma resposta negativa sobre o que ele apuraria"
        return
    fi

    arquivo_erro=$(mktemp 2>/dev/null)
    # APURACAO-OK: a existencia nao e testada porque quem a garante e o proprio
    # `mktemp`, que CRIA o arquivo -- e o `-z` acima ja cobre o caso de ele ter
    # falhado sem imprimir caminho nenhum. Aqui ENOENT e EACCES nao se
    # confundem: se o caminho veio, o arquivo existe.
    if [ -z "$arquivo_erro" ] || [ ! -w "$arquivo_erro" ]; then
        _apur_nao_apurado "nao foi possivel criar arquivo temporario para separar o stderr de \"$programa\" (TMPDIR=${TMPDIR:-/tmp} cheio ou sem permissao?); a consulta nao foi feita"
        return
    fi

    saida=$("$@" 2>"$arquivo_erro")
    rc=$?
    _APUR_RC=$rc
    _APUR_SAIDA=$saida
    { _APUR_ERRO=$(<"$arquivo_erro"); } 2>/dev/null
    rm -f "$arquivo_erro"

    if [ "$rc" -ne 0 ]; then
        # As quebras de linha do stderr viram espaco por expansao do proprio
        # shell, e nao por `tr`. Com `tr` fora do PATH, o `$( )` devolvia VAZIO
        # e o motivo saia como "saiu com codigo 3 ()": some justamente a parte
        # que EXPLICA por que nao se apurou, no ambiente degradado em que ela e
        # mais necessaria. Ferramenta ausente nao pode comer explicacao.
        _apur_nao_apurado "\"$programa\" rodou e saiu com codigo $rc${_APUR_ERRO:+ (${_APUR_ERRO//$'\n'/ })}; o que ele apuraria continua desconhecido"
        return
    fi
    _apur_ok "$saida"
}
