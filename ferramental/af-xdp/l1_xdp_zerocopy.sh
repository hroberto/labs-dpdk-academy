#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Teste L1 que EXECUTA ferramental/af-xdp/xdp-zerocopy.sh.
#
# POR QUE ESTE ARQUIVO NASCEU
#
# INCIDENTE, e ele e a razao de o defeito fundador deste script ter voltado
# duas vezes. Ate aqui NENHUM teste da arvore executava xdp-zerocopy.sh:
#
#     $ grep -rn xdp-zerocopy scripts/tests/ meson.build
#       (so MENCOES em comentario -- nunca uma invocacao)
#     $ grep -rn '_elf_defeito\|_nm_conta\|_u_le' scripts/tests/
#       (nenhuma ocorrencia)
#
# Consequencia MEDIDA por mutacao deliberada, com a suite L1 inteira rodando:
#
#     mutacao                                                      suite L1
#     remover a comparacao `fim > tamanho` de _elf_defeito          PASSOU
#     trocar `if [ "$rc_nm" -ne 0 ]` por `if false` em _nm_conta    PASSOU
#     desligar a conferencia da magica ELF                          PASSOU
#
# Tres mutacoes que reintroduzem LITERALMENTE o defeito corrigido, e a suite
# ficou verde nas tres. O teste que faltava e este.
#
# QUE ELE PEGA DEFEITO DE VERDADE E MEDIDO, nao alegado. Onze mutacoes
# deliberadas em ferramental/af-xdp/xdp-zerocopy.sh, cada uma aplicada, rodada e
# restaurada (o arquivo volta byte a byte; conferido com `diff -q`):
#
#     mutacao                                               resultado
#     remover a comparacao `fim > tamanho` (_elf_defeito)   4 falhas
#     `if false` no lugar da guarda do rc do nm             4 falhas
#     desligar a conferencia da magica ELF                  1 falha
#     reintroduzir `stat ... 2>/dev/null || printf 0`       2 falhas
#     aceitar qualquer classe no guarda do fallback         3 falhas
#     tirar o `[ -e "$module" ]` antes do `[ ! -r ]`        2 falhas
#     recusa sem olhar o sysfs                              3 falhas
#     reintroduzir `tipo=$(cat type || echo 0)`             3 falhas
#     tirar o `[ ! -e "$HELPER" ]` antes do `[ ! -r ]`      2 falhas
#     `if false` no lugar da guarda do rc do descompressor  2 falhas
#     acrescentar_motivo voltando a descartar a 1a frase    3 falhas
#
# Onze de onze pegas; sem mutacao, 64 de 64 assercoes passam. As duas ultimas
# da lista precisaram de assercao NOVA para serem pegas -- a primeira versao
# deste arquivo deixava a magica ELF e a regressao do `stat` passarem, e isso
# so apareceu porque as mutacoes foram rodadas de verdade.
#
# O QUE ELE PROVA, sem NIC, sem root e em CI
#
#   [1] o script NUNCA publica 0/0/0 quando a coleta falhou -- a celula sai
#       "-" com NAO APURADO e a frase da ferramenta que falhou;
#   [2] o script NUNCA imprime "Resultado INCONCLUSIVO" sem a linha
#       "O que faltou";
#   [3] o script distingue "existe e nao posso ler" de "nao existe", nas tres
#       fontes em que essa confusao ja aconteceu (modulo, helper, sysfs).
#
# COMO, SEM PRIVILEGIO E SEM HARDWARE
#
# Reaproveita o arnes que os agentes verificadores montaram a mao nas rodadas
# de auditoria, e que ate agora existia so nos relatorios:
#
#   - PATH com stubs de `modinfo`, `nm`, `zstd`, `python3` (que faz o papel do
#     helper) e `xdp-loader`, cada um controlado por variavel de ambiente;
#   - modulos FALSOS: um ELF64 integro e um com a tabela de secoes apontando
#     para alem do fim do arquivo -- que e a assinatura exata do modulo
#     truncado do incidente (mlx5_core, 6.627.105 bytes, num TMPDIR de 4 MiB);
#   - um /sys/class/net FALSO, por DPDK_ACADEMY_SYSFS_NET.
#
# O `unshare -Urm` dos relatorios NAO e usado: ele exige user namespaces, que
# nem todo runner concede, e o que ele provava aqui (fonte inacessivel) o
# arnes obtem com `chmod 000` e com diretorio inexistente.
#
# E L1 porque nao abre socket, nao toca /sys real, nao carrega programa XDP,
# nao precisa de python3 (o helper e um stub de shell) e roda em menos de um
# segundo.
#
# O QUE ELE NAO PROVA -- e isto fica DECLARADO, nao omitido
#
#   - o ramo de `infraestrutura_do_kernel`: ele le /boot e /proc/config.gz por
#     caminho ABSOLUTO, e nao ha seam para redireciona-los. Os quatro casos
#     (fonte ausente, /boot sem travessia, leitor ausente, lido sem casamento)
#     continuam verificados so a mao, com `unshare -Urm`, como esta registrado
#     nos comentarios daquela funcao;
#   - `xdp-loader features` de verdade: exige root, e aqui ele e stub;
#   - que o kernel real responda o que o helper stub responde. O que se prova e
#     como o script TRATA cada resposta.
set -u

aqui="$(cd "$(dirname "$0")" && pwd)"
# Os alvos ficam neste mesmo diretorio; lib-apuracao.sh continua em scripts/,
# porque serve ao projeto inteiro e nao so ao AF_XDP.
raiz="$aqui"
scripts_raiz="$(cd "$aqui/../../scripts" && pwd)"

falhas=0
lacunas=0
total=0

check() {
    total=$((total + 1))
    if [ "$2" = "$3" ]; then echo "  ok    - $1"
    else echo "  FALHA - $1 (esperado '$3', obtido '$2')"; falhas=$((falhas + 1)); fi
}
contem() {
    total=$((total + 1))
    if grep -qF -- "$2" <<<"$3"; then echo "  ok    - $1"
    else
        echo "  FALHA - $1 (nao encontrou '$2')"
        sed 's/^/            | /' <<<"$3" | head -12
        falhas=$((falhas + 1))
    fi
}
nao_contem() {
    total=$((total + 1))
    if grep -qF -- "$2" <<<"$3"; then
        echo "  FALHA - $1 (encontrou '$2', que nao deveria estar la)"
        sed 's/^/            | /' <<<"$3" | head -12
        falhas=$((falhas + 1))
    else echo "  ok    - $1"; fi
}
lacuna() { echo "  LACUNA - $1"; lacunas=$((lacunas + 1)); }

echo "== L1: ferramental/af-xdp/xdp-zerocopy.sh executado com fontes controladas =="

# --- o arnes -----------------------------------------------------------------

SB=$(mktemp -d) || { echo "  FALHA - mktemp -d falhou; sem sandbox nao ha teste"; exit 1; }
trap 'chmod -R u+rwX "$SB" 2>/dev/null; rm -rf "$SB"' EXIT

mkdir -p "$SB/app" "$SB/bin" "$SB/mods" "$SB/sys"
cp "$raiz/xdp-zerocopy.sh" "$raiz/lib-xdp.sh" "$scripts_raiz/lib-apuracao.sh" "$SB/app/" || {
    echo "  FALHA - nao consegui copiar o script sob teste para a sandbox"; exit 1; }
APP="$SB/app/xdp-zerocopy.sh"

# Ferramentas externas de que o script depende e que NAO sao stub. Se faltar
# alguma, o teste diz QUAL faltou -- nunca sai verde por nao ter rodado.
faltando=""
for t in od cat ls id uname mktemp rm cp tr sed grep awk basename dirname readlink chmod head; do
    command -v "$t" >/dev/null 2>&1 || faltando="$faltando $t"
done
if [ -n "$faltando" ]; then
    echo "  SKIP  - ferramenta(s) ausente(s) do PATH:$faltando"
    echo "  SKIP    NADA abaixo foi exercitado. Isto e SKIP, nao sucesso."
    exit 77
fi

# --- stubs -------------------------------------------------------------------
#
# Cada stub le o que deve fazer de uma variavel de ambiente. Nenhum deles
# adivinha: quando a variavel nao esta definida, ele se comporta como a
# ferramenta real se comportaria diante de um alvo desconhecido.

# modinfo: mapa driver -> caminho, num arquivo. Sem entrada, responde como o
# modinfo real responde a um nome inventado (rc=1, "Module X not found").
cat > "$SB/bin/modinfo" <<'STUB'
#!/usr/bin/env bash
alvo=""
for a in "$@"; do case "$a" in -*) ;; *) alvo=$a ;; esac; done
linha=$(grep -E "^${alvo}	" "$STUB_MODMAP" 2>/dev/null | head -1)
if [ -z "$linha" ]; then
    echo "modinfo: ERROR: Module $alvo not found." >&2
    exit 1
fi
printf '%s\n' "${linha#*	}"
STUB

# nm: reproduz o comportamento MEDIDO no incidente -- num ELF truncado ele sai
# com rc=0 e nao lista simbolo nenhum, reclamando so no stderr. E o que fazia
# `grep -c ... || true` devolver 0, indistinguivel de "driver sem suporte".
# STUB_NM_RC força o outro caso, o do nm que falha de verdade.
cat > "$SB/bin/nm" <<'STUB'
#!/usr/bin/env bash
arquivo=""
for a in "$@"; do case "$a" in -*) ;; *) arquivo=$a ;; esac; done
if [ "${STUB_NM_RC:-0}" -ne 0 ]; then
    echo "nm: $arquivo: formato de ficheiro nao reconhecido" >&2
    exit "$STUB_NM_RC"
fi
tam=$(wc -c < "$arquivo" 2>/dev/null); [ -n "$tam" ] || tam=0
if [ "$tam" -lt 4096 ]; then
    # Comportamento MEDIDO do nm real num ELF truncado: rc=0, zero simbolos,
    # reclamacao so no stderr. Era isto que `grep -c ... || true` transformava
    # no numero 0.
    echo "nm: $arquivo: nenhum simbolo" >&2
    exit 0
fi
indefinidos='                 U xsk_tx_completed
                 U xsk_tx_peek_desc
                 U xsk_buff_alloc'
definidos='0000000000000010 T fake_xsk_wakeup
0000000000000020 T fake_xsk_setup_pool
0000000000000030 T fake_xdp_xmit
0000000000000040 T fake_xdp_setup_prog'
# As flags SAO honradas de proposito: a assimetria entre `nm -u | grep '\<xsk_'`
# e `nm --defined-only | grep 'xsk_'` e justamente o que a tabela publicada
# mede, e um stub que ignorasse as flags nao distinguiria as duas colunas.
case " $* " in
    *" -u "*)             printf '%s\n' "$indefinidos" ;;
    *" --defined-only "*) printf '%s\n' "$definidos" ;;
    *)                    printf '%s\n%s\n' "$indefinidos" "$definidos" ;;
esac
STUB

# zstd: por padrao descomprime (aqui, copia); STUB_ZSTD_RC reproduz o rc=70
# "No space left on device" que produziu o modulo pela metade do incidente.
cat > "$SB/bin/zstd" <<'STUB'
#!/usr/bin/env bash
arquivo=""
for a in "$@"; do case "$a" in -*) ;; *) arquivo=$a ;; esac; done
if [ "${STUB_ZSTD_RC:-0}" -ne 0 ]; then
    echo "zstd: error 70 : Write error : cannot write block : No space left on device " >&2
    exit "$STUB_ZSTD_RC"
fi
cat "$arquivo"
STUB

# python3: faz o papel do interpretador que roda ferramental/af-xdp/xdp-features.py. O
# bloco KEY=VALUE e o codigo de saida sao ditados por variavel; assim os cinco
# vereditos e as respostas defeituosas sao exercitados sem kernel nenhum.
cat > "$SB/bin/python3" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_HELPER_BLOCO:-}" ] && [ -r "$STUB_HELPER_BLOCO" ] && cat "$STUB_HELPER_BLOCO"
exit "${STUB_HELPER_RC:-0}"
STUB

# id: por padrao delega ao id real; STUB_ID_U finge o uid. So um caso precisa
# disso -- o fallback do xdp-loader so EXECUTA a ferramenta quando o uid e 0,
# e sem fingir o uid aquele ramo continuaria inalcancavel em CI, que e
# exatamente como ele chegou a producao sem nunca ter rodado.
cat > "$SB/bin/id" <<'STUB'
#!/usr/bin/env bash
if [ -n "${STUB_ID_U:-}" ] && [ "${1:-}" = "-u" ]; then
    printf '%s\n' "$STUB_ID_U"
    exit 0
fi
exec "$STUB_ID_REAL" "$@"
STUB

# stat: delega ao stat real; STUB_STAT_RC faz o stat FALHAR estando presente.
# Esse caso e diferente de "stat ausente" e precisa existir separado: a
# regressao da rodada 2 foi um `stat ... 2>/dev/null || printf 0`, e um teste
# que so removesse o binario do PATH nao a alcanca -- a guarda de
# `command -v stat` dispara antes e o teste passa com a mutacao dentro.
cat > "$SB/bin/stat" <<'STUB'
#!/usr/bin/env bash
if [ -n "${STUB_STAT_RC:-}" ] && [ "${STUB_STAT_RC:-0}" -ne 0 ]; then
    echo "stat: nao foi possivel obter o estado do ficheiro" >&2
    exit "$STUB_STAT_RC"
fi
exec "$STUB_STAT_REAL" "$@"
STUB

# xdp-loader: so entra no PATH quando o caso quer o fallback presente.
cat > "$SB/xdp-loader-modelo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${STUB_LOADER_SAIDA:-}"
exit "${STUB_LOADER_RC:-0}"
STUB

chmod +x "$SB/bin/"* "$SB/xdp-loader-modelo"
: > "$SB/modmap"
export STUB_MODMAP="$SB/modmap"
STUB_ID_REAL=$(command -v id); export STUB_ID_REAL
STUB_STAT_REAL=$(command -v stat); export STUB_STAT_REAL

# PATH FECHADO, e a razao e determinismo, nao purismo. Com o PATH do host,
# `command -v xdp-loader` acha a ferramenta REAL quando a maquina tem
# xdp-tools instalado e nao acha quando nao tem -- e o teste passaria a
# afirmar coisas diferentes em maquinas diferentes, que e a categoria de
# resultado que este projeto nao aceita. Aqui so existem os stubs e os
# binarios explicitamente listados; qualquer outra ferramenta que o script
# procure sera declarada ausente, sempre, em qualquer maquina.
BASE="$SB/base"; mkdir -p "$BASE"
for t in bash env cat ls uname mktemp rm cp mv tr sed grep awk basename dirname readlink od head wc chmod stat sort cut; do
    p=$(command -v "$t") && ln -sf "$p" "$BASE/$t"
done

# `python3` so existe como stub aqui, e o helper precisa ser LEGIVEL para o
# script sequer chamar o interpretador.
: > "$SB/app/xdp-features.py"

# roda <args...>  -- executa o script sob teste com o PATH e o sysfs do arnes
roda() {
    PATH="$SB/bin:$BASE" DPDK_ACADEMY_SYSFS_NET="$SB/sys" "$APP" "$@" 2>&1
}

# --- modulos falsos ----------------------------------------------------------
#
# `_elf_defeito` decide truncamento por e_shoff + e_shentsize*e_shnum contra o
# tamanho do arquivo: num .ko a tabela de secoes fica no FIM, e foi assim que o
# mlx5_core cortado em 4 MiB foi pego. Os bytes sao escritos a mao para que o
# teste nao dependa de haver um modulo de verdade na maquina.
le64() {   # le64 <valor> <n bytes>  ->  bytes little-endian, escapados
    local v=$1 n=$2 i
    for ((i = 0; i < n; i++)); do printf '\\x%02x' $(( (v >> (8 * i)) & 0xff )); done
}
escreve_elf() {   # escreve_elf <arquivo> <e_shoff> <e_shentsize> <e_shnum> <tamanho>
    local f=$1 shoff=$2 shentsize=$3 shnum=$4 tam=$5
    {
        printf '\x7fELF\x02\x01\x01\x00'          # magica, ELF64, little-endian
        printf '\x00\x00\x00\x00\x00\x00\x00\x00' # EI_PAD
        printf '\x01\x00\x3e\x00'                 # e_type=REL, e_machine=x86-64
        printf '\x01\x00\x00\x00'                 # e_version
        printf '%b' "$(le64 0 8)"                 # e_entry
        printf '%b' "$(le64 0 8)"                 # e_phoff
        printf '%b' "$(le64 "$shoff" 8)"          # e_shoff
        printf '\x00\x00\x00\x00'                 # e_flags
        printf '\x40\x00\x00\x00\x00\x00'         # e_ehsize, e_phentsize, e_phnum
        printf '%b' "$(le64 "$shentsize" 2)"      # e_shentsize
        printf '%b' "$(le64 "$shnum" 2)"          # e_shnum
        printf '\x00\x00'                         # e_shstrndx
    } > "$f"
    head -c $(( tam - 64 )) /dev/zero >> "$f"
}

# integro: a tabela de secoes cabe no arquivo (4096 + 64*2 = 4224 <= 8192)
escreve_elf "$SB/mods/bom.ko" 4096 64 2 8192
# truncado: a assinatura do incidente -- a tabela termina muito depois do fim
escreve_elf "$SB/mods/truncado.ko" 6621264 64 80 8192
# comprimido, para o caminho do descompressor
cp "$SB/mods/bom.ko" "$SB/mods/comprimido.ko.zst"
# nem sequer e ELF, e e GRANDE o bastante para o nm stub devolver simbolos:
# sem a conferencia da magica, os simbolos de um arquivo que nao e modulo
# seriam publicados como medicao.
head -c 8192 /dev/zero | tr '\0' 'Z' > "$SB/mods/naoelf.ko"

check "o ELF integro tem 8192 bytes" "$(wc -c < "$SB/mods/bom.ko")" "8192"

{
    printf 'drvbom\t%s\n'       "$SB/mods/bom.ko"
    printf 'drvtrunc\t%s\n'     "$SB/mods/truncado.ko"
    printf 'drvzst\t%s\n'       "$SB/mods/comprimido.ko.zst"
    printf 'drvsumiu\t%s\n'     "$SB/mods/este-nao-existe.ko"
    printf 'drvfechado\t%s\n'   "$SB/mods/fechado.ko"
    printf 'drvnaoelf\t%s\n'    "$SB/mods/naoelf.ko"
} > "$SB/modmap"
cp "$SB/mods/bom.ko" "$SB/mods/fechado.ko"

# =============================================================================
# [1] A celula da tabela NUNCA sai 0/0/0 quando a coleta falhou
# =============================================================================
echo ""
echo "-- [1] coleta que falha nao vira numero --"

# CONTROLE POSITIVO, e ele vem primeiro de proposito: sem ele, um "-" em toda
# linha passaria por sucesso, e o teste estaria provando apenas que o arnes
# quebrou tudo. Aqui o modulo e integro e o nm responde: tem que sair NUMERO.
saida=$(roda drvbom)
contem "controle positivo: modulo integro publica as chamadas ao nucleo XSK" \
    "chamadas ao nucleo XSK ... 3" "$saida"
contem "controle positivo: codigo XSK proprio contado a parte" \
    "codigo XSK do driver ..... 2" "$saida"
contem "controle positivo: simbolos xdp_ contados" \
    "simbolos xdp_ (XDP nativo) 2" "$saida"
contem "controle positivo: o diagnostico sai da contagem" \
    "XDP + zero-copy" "$saida"

# O INCIDENTE FUNDADOR, reproduzido: ELF cortado + nm que sai 0 sem simbolo.
# Antes das correcoes esta linha saia "0 0 0 / sem XDP nenhum".
saida=$(roda drvtrunc)
contem "ELF truncado vira NAO APURADO"        "NAO APURADO"   "$saida"
contem "ELF truncado e NOMEADO como tal"      "ELF TRUNCADO"  "$saida"
nao_contem "ELF truncado nao publica 'sem XDP nenhum'" "sem XDP nenhum" "$saida"
nao_contem "ELF truncado nao publica contagem de chamadas" \
    "chamadas ao nucleo XSK ..." "$saida"

# Na TABELA (modo comparacao) o caso insidioso e o PARCIAL: uma linha falsa
# dentro de uma tabela que parece sadia, e essa tabela e publicada.
tabela=$(roda drvbom drvtrunc | sed -n '/^  driver /,/^$/p')
check "tabela: a linha do modulo integro traz os tres numeros" \
    "$(awk '$1 == "drvbom" {print $2, $3, $4}' <<<"$tabela")" "2 3 2"
check "tabela: a linha do modulo truncado sai com tres tracos" \
    "$(awk '$1 == "drvtrunc" {print $2, $3, $4}' <<<"$tabela")" "- - -"
nao_contem "tabela: nenhuma linha sai 0 0 0" "0         0         0" "$tabela"

# Arquivo que nem ELF e: a conferencia da magica tem que NOMEAR a magica. Sem
# ela, a funcao ainda recusaria o arquivo (pelo campo de classe), mas com uma
# frase que aponta para o defeito errado -- e frase que aponta para o defeito
# errado e a categoria que a regressao do `stat` inaugurou aqui.
saida=$(roda drvnaoelf)
contem "arquivo que nao e ELF e recusado pela MAGICA"  "magica ELF" "$saida"
nao_contem "arquivo que nao e ELF nao publica simbolos" "chamadas ao nucleo XSK ..." "$saida"

# nm que FALHA (rc!=0) e coisa diferente de nm que conta zero.
saida=$(STUB_NM_RC=1 roda drvbom)
contem "nm com rc!=0 vira NAO APURADO"           "NAO APURADO"     "$saida"
contem "nm com rc!=0 nomeia a ferramenta e a flag" "nm -u saiu com codigo 1" "$saida"
contem "nm com rc!=0 repete a FRASE do nm"       "formato de ficheiro nao reconhecido" "$saida"
nao_contem "nm com rc!=0 nao publica diagnostico" "sem XDP nenhum"  "$saida"

# descompressor que falha pela metade: o rc=70 do incidente.
saida=$(STUB_ZSTD_RC=70 roda drvzst)
contem "descompressor com rc!=0 vira NAO APURADO" "NAO APURADO"     "$saida"
contem "descompressor com rc!=0 traz o codigo"    "saiu com codigo 70" "$saida"
contem "descompressor com rc!=0 traz a frase dele" "No space left on device" "$saida"

# REGRESSAO DA RODADA 2, primeiro modo: `stat` PRESENTE e falhando. E este o
# caminho que a mutacao reintroduz, e uma unica assercao "sem stat no PATH"
# nao o alcanca -- a guarda de `command -v stat` dispara antes.
saida=$(STUB_STAT_RC=1 roda drvbom)
nao_contem "stat que falha NAO vira acusacao de ELF truncado" "ELF TRUNCADO" "$saida"
contem "stat que falha e nomeado como nao-apuracao do TAMANHO" \
    "nao foi possivel medir o tamanho" "$saida"
nao_contem "stat que falha nao publica contagem de simbolos" \
    "chamadas ao nucleo XSK ..." "$saida"

# REGRESSAO DA RODADA 2, segundo modo: `tamanho=$(stat ... || printf 0)` fazia um modulo
# INTEGRO ser publicado como "ELF TRUNCADO ... o arquivo tem so 0", inventando
# uma causa (TMPDIR sem espaco) que nao tinha nada a ver.
sem_stat="$SB/sem-stat"
mkdir -p "$sem_stat"
for f in "$BASE"/* "$SB/bin"/*; do
    nome=$(basename "$f")
    [ "$nome" = stat ] && continue
    cp -a "$f" "$sem_stat/$nome" 2>/dev/null || ln -sf "$(readlink -f "$f")" "$sem_stat/$nome"
done
if command -v stat >/dev/null 2>&1 && [ ! -e "$sem_stat/stat" ]; then
    saida=$(PATH="$sem_stat" DPDK_ACADEMY_SYSFS_NET="$SB/sys" "$APP" drvbom 2>&1)
    nao_contem "sem 'stat', modulo integro NAO e acusado de truncado" "ELF TRUNCADO" "$saida"
    nao_contem "sem 'stat', nao se inventa a causa 'TMPDIR sem espaco'" "TMPDIR sem espaco" "$saida"
    contem "sem 'stat', a integridade e declarada NAO APURADA" \
        'nao ha "stat" para medir o tamanho' "$saida"
else
    lacuna "nao consegui montar um PATH sem 'stat'; a regressao do stat nao foi exercitada"
fi

# =============================================================================
# [2] "INCONCLUSIVO" nunca sai sem a linha "O que faltou"
# =============================================================================
echo ""
echo "-- [2] inconclusivo sempre diz o que faltou --"

# A invariante e verificada como INVARIANTE: para cada resposta possivel da
# fonte primaria, se a palavra INCONCLUSIVO aparecer, "O que faltou" tambem
# tem que aparecer. Ela se quebrava no ponto de COMPOSICAO, nao na funcao pura
# que o teste vizinho cobre -- por isso aqui o script roda inteiro.
mkdir -p "$SB/blocos"
printf 'FONTE=netlink\nIFACE=fake0\nXDP_FEATURES=0x0\nXDP_BASIC=nao\nXDP_ZEROCOPY=nao\nVEREDITO=sem-xdp\n' > "$SB/blocos/sem-xdp"
printf 'FONTE=netlink\nIFACE=fake0\nXDP_FEATURES=0x9\nXDP_BASIC=sim\nXDP_ZEROCOPY=sim\nVEREDITO=zero-copy\n' > "$SB/blocos/zero-copy"
printf 'FONTE=netlink\nIFACE=fake0\nXDP_FEATURES=\nXDP_BASIC=\nXDP_ZEROCOPY=\nVEREDITO=sem-atributo\n' > "$SB/blocos/sem-atributo"
printf 'FONTE=netlink\nIFACE=fake0\nXDP_FEATURES=0x0\n' > "$SB/blocos/sem-chave"
printf 'FONTE=netlink\nIFACE=fake0\nXDP_FEATURES=0x0\nXDP_BASIC=nao\nXDP_ZEROCOPY=nao\nVEREDITO=no-xdp\n' > "$SB/blocos/classe-estranha"
: > "$SB/blocos/vazio"

# um netdev falso para o modo interface
mkdir -p "$SB/sys/fake0/device" "$SB/drivers/drvbom"
printf '1\n' > "$SB/sys/fake0/type"
printf 'down\n' > "$SB/sys/fake0/operstate"
printf '0\n' > "$SB/sys/fake0/carrier"
# device/driver e um symlink cujo BASENAME e o nome do driver -- e assim que o
# sysfs real o expoe, e e dai que o script tira o nome.
ln -sfn "$SB/drivers/drvbom" "$SB/sys/fake0/device/driver"

invariante_motivo() {   # invariante_motivo <rotulo> <saida>
    total=$((total + 1))
    if grep -qF 'Resultado INCONCLUSIVO' <<<"$2" && ! grep -qF 'O que faltou' <<<"$2"; then
        echo "  FALHA - $1: INCONCLUSIVO sem a linha 'O que faltou'"
        sed -n '/-- Veredito --/,$p' <<<"$2" | sed 's/^/            | /' | head -8
        falhas=$((falhas + 1))
    else
        echo "  ok    - $1"
    fi
}

# (a) fonte primaria nao responde (kernel sem a familia netdev) e nao ha
#     xdp-loader instalado -- o caso classico do uid sem privilegio.
saida=$(STUB_HELPER_RC=3 STUB_HELPER_BLOCO="$SB/blocos/vazio" roda fake0)
invariante_motivo "helper rc=3 (sem familia netdev), sem xdp-loader" "$saida"
contem "rc=3 nomeia a familia netlink que falta" "familia netlink" "$saida"
contem "rc=3 nomeia a ausencia do fallback"      "xdp-loader nao esta instalado" "$saida"

# (b) helper responde 0 e o bloco NAO traz a chave VEREDITO. Este era o caso
#     MUDO: rc=0, nenhum motivo atribuido, "INCONCLUSIVO" sem explicacao.
saida=$(STUB_HELPER_RC=0 STUB_HELPER_BLOCO="$SB/blocos/sem-chave" roda fake0)
invariante_motivo "helper rc=0 com bloco sem a chave VEREDITO" "$saida"
contem "bloco sem VEREDITO gera AVISO visivel" "veio SEM a chave" "$saida"
contem "bloco sem VEREDITO entra no motivo"    "nao trouxe a chave VEREDITO" "$saida"

# (c) REGRESSAO DA RODADA 2: helper de outra versao grafando a classe de outro
#     jeito. O guarda do fallback aceitava qualquer string nao vazia, entao o
#     script dizia "(nao foi preciso o fallback)" -- falso -- e caia no ramo
#     `*)` de texto_veredito com o motivo VAZIO.
saida=$(STUB_HELPER_RC=0 STUB_HELPER_BLOCO="$SB/blocos/classe-estranha" roda fake0)
invariante_motivo "helper rc=0 com VEREDITO de vocabulario desconhecido" "$saida"
contem "classe desconhecida e nomeada no aviso" 'VEREDITO="no-xdp"' "$saida"
nao_contem "classe desconhecida NAO diz que o fallback foi dispensavel" \
    "nao foi preciso o fallback" "$saida"

# (d) as classes conhecidas fecham o veredito e NAO caem em inconclusivo.
for c in sem-xdp zero-copy; do
    saida=$(STUB_HELPER_RC=0 STUB_HELPER_BLOCO="$SB/blocos/$c" roda fake0)
    nao_contem "classe '$c' fecha o veredito (nao e inconclusivo)" \
        "Resultado INCONCLUSIVO" "$saida"
    invariante_motivo "classe '$c' respeita a invariante" "$saida"
done

# (e) sem-atributo: root NAO mudaria a resposta, e por isso nenhuma linha de
#     sudo pode ser oferecida -- a contradicao dentro da mesma saida.
saida=$(STUB_HELPER_RC=0 STUB_HELPER_BLOCO="$SB/blocos/sem-atributo" roda fake0)
contem "sem-atributo diz que root nao mudaria a resposta" "root NAO mudaria a resposta" "$saida"
nao_contem "sem-atributo nao oferece sudo"                "Se quiser conferir mesmo assim: sudo" "$saida"
contem "sem-atributo imprime '(nao anunciado)' em vez de campo vazio" "BASIC ........ (nao anunciado)" "$saida"

# (f) fallback presente que responde 0 com texto irreconhecivel: a classe
#     "inconclusivo" do fallback nao pode sobrescrever nada, e tem que virar
#     motivo.
# STUB_ID_U=0: o fallback so EXECUTA o xdp-loader quando o uid e 0. Sem fingir
# o uid, este ramo continuaria sem teste -- que e como ele foi parar em
# producao contendo o bug que a rodada 2 encontrou.
cp "$SB/xdp-loader-modelo" "$SB/bin/xdp-loader"
saida=$(STUB_ID_U=0 STUB_HELPER_RC=3 STUB_HELPER_BLOCO="$SB/blocos/vazio" \
        STUB_LOADER_RC=0 STUB_LOADER_SAIDA="texto que o parser nao reconhece" roda fake0)
invariante_motivo "fallback rc=0 com saida irreconhecivel" "$saida"
contem "fallback irreconhecivel vira NAO APURADA, nao classe" "classe pelo fallback: NAO APURADA" "$saida"
rm -f "$SB/bin/xdp-loader"

# =============================================================================
# [3] "existe e nao posso ler" nao e "nao existe"
# =============================================================================
echo ""
echo "-- [3] ENOENT e EACCES nao saem com a mesma frase --"

# (a) MODULO: modinfo aponta para um caminho e o arquivo nao esta la. A frase
#     antiga afirmava "existe (modo ?) e o uid N nao pode le-lo" -- as duas
#     coisas falsas, e mandava o leitor atras de um sudo inutil.
saida=$(roda drvsumiu)
contem "modulo inexistente e dito inexistente" "esse arquivo NAO existe" "$saida"
nao_contem "modulo inexistente NAO e culpa de privilegio" "falta de PRIVILEGIO" "$saida"
nao_contem "modulo inexistente nao imprime 'modo ?'" "modo ?" "$saida"

# (b) MODULO: existe e nao pode ser lido.
if [ "$(id -u)" -eq 0 ]; then
    lacuna "rodando como uid 0: 'chmod 000' nao impede leitura, o ramo de PRIVILEGIO do modulo nao foi exercitado"
else
    chmod 000 "$SB/mods/fechado.ko"
    saida=$(roda drvfechado)
    contem "modulo ilegivel e dito ilegivel"   "falta de PRIVILEGIO" "$saida"
    contem "modulo ilegivel nomeia o modo real" "modo 0" "$saida"
    nao_contem "modulo ilegivel nao e dito inexistente" "NAO existe" "$saida"
    chmod 644 "$SB/mods/fechado.ko"
fi

# (c) HELPER ausente: a frase publicada em trilha/04-projeto-final. Ela e
#     interface, e o teste a fixa palavra por palavra.
mv "$SB/app/xdp-features.py" "$SB/helper-guardado"
saida=$(STUB_HELPER_RC=0 roda fake0)
contem "helper ausente usa a frase publicada" \
    "ferramental/af-xdp/xdp-features.py nao encontrado ao lado deste script." "$saida"
contem "helper ausente entra no motivo do veredito" \
    "nao esta ao lado do script" "$saida"
mv "$SB/helper-guardado" "$SB/app/xdp-features.py"

# (d) HELPER presente e ilegivel: NAO pode sair a frase de (c), que manda
#     copiar um arquivo que ja esta la.
if [ "$(id -u)" -eq 0 ]; then
    lacuna "rodando como uid 0: o ramo 'helper existe e nao pode ser lido' nao foi exercitado"
else
    chmod 000 "$SB/app/xdp-features.py"
    saida=$(STUB_HELPER_RC=0 roda fake0)
    nao_contem "helper ilegivel NAO e dito ausente" \
        "nao encontrado ao lado deste script" "$saida"
    contem "helper ilegivel e dito ilegivel" "nao pode le-lo" "$saida"
    chmod 644 "$SB/app/xdp-features.py"
fi

# (e) SYSFS inexistente: a placa desta maquina ja foi declarada inexistente por
#     causa disto. Recusar por "nao existe" quando nao se pode olhar e o
#     defeito fundador no caminho mais visivel do script.
saida=$(PATH="$SB/bin:$PATH" DPDK_ACADEMY_SYSFS_NET="$SB/sys-que-nao-existe" "$APP" fake0 2>&1)
contem "sysfs ausente vira NAO APURADO"  "nao foi possivel APURAR" "$saida"
contem "sysfs ausente nomeia a fonte"    "nao existe (sysfs nao montado" "$saida"
nao_contem "sysfs ausente NAO afirma que a interface nao existe" \
    "nao e uma interface nem um driver conhecido" "$saida"
contem "sysfs ausente diz que a lista de interfaces nao foi apurada" \
    "interfaces: NAO APURADAS" "$saida"

# (f) SYSFS presente e sem travessia.
if [ "$(id -u)" -eq 0 ]; then
    lacuna "rodando como uid 0: o ramo 'sysfs existe e nao pode ser percorrido' nao foi exercitado"
else
    mkdir -p "$SB/sys-fechado"; chmod 000 "$SB/sys-fechado"
    saida=$(PATH="$SB/bin:$PATH" DPDK_ACADEMY_SYSFS_NET="$SB/sys-fechado" "$APP" fake0 2>&1)
    contem "sysfs sem travessia vira NAO APURADO" "nao foi possivel APURAR" "$saida"
    contem "sysfs sem travessia nomeia o privilegio" "nao pode percorre-lo" "$saida"
    chmod 755 "$SB/sys-fechado"
fi

# (g) ELEICAO DA INTERFACE: `type` ilegivel descartava a candidata EM SILENCIO,
#     e o relatorio inteiro passava a falar de outra placa -- numeros corretos
#     sobre a placa que ninguem perguntou. E a pior forma do defeito aqui,
#     porque troca o SUJEITO, nao a frase.
if [ "$(id -u)" -eq 0 ]; then
    lacuna "rodando como uid 0: a candidata com 'type' ilegivel nao foi exercitada"
else
    mkdir -p "$SB/sys2/pci0/device" "$SB/sys2/usb0/device"
    printf '1\n' > "$SB/sys2/pci0/type"; chmod 000 "$SB/sys2/pci0/type"
    printf '1\n' > "$SB/sys2/usb0/type"
    printf 'down\n' > "$SB/sys2/usb0/operstate"; printf '0\n' > "$SB/sys2/usb0/carrier"
    ln -sfn "$SB/mods" "$SB/sys2/pci0/device/driver"
    ln -sfn "$SB/mods" "$SB/sys2/usb0/device/driver"
    saida=$(PATH="$SB/bin:$PATH" DPDK_ACADEMY_SYSFS_NET="$SB/sys2" "$APP" 2>&1)
    contem "candidata com 'type' ilegivel gera AVISO"      "NAO APURADA" "$saida"
    contem "o aviso nomeia a candidata descartada"          "pci0" "$saida"
    contem "o aviso diz que a exclusao foi por leitura, nao por criterio" \
        "por falta de leitura, e nao por criterio" "$saida"
    chmod 644 "$SB/sys2/pci0/type"
fi

# --- veredito ----------------------------------------------------------------
echo ""
if [ $falhas -ne 0 ]; then
    echo "L1 xdp-zerocopy: $falhas falha(s) em $total assercoes"
    exit 1
fi
if [ $lacunas -ne 0 ]; then
    echo "L1 xdp-zerocopy: as $total assercoes que rodaram passaram, com $lacunas bloco(s) SEM COBERTURA (ver LACUNA acima)"
else
    echo "L1 xdp-zerocopy: todas as $total assercoes passaram"
fi
