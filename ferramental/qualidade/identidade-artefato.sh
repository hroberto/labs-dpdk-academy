#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Identidade do artefato binario, para o manifesto da coleta.
#
# POR QUE ISTO E UM ARQUIVO, E NAO UM TRECHO DO `campanha-hardware.sh`
#
# O teste extraia estas funcoes do script de producao por `sed`/`eval`, e
# reconstruia o grafo de dependencias A MAO. Isso falhou duas vezes em
# 27/09/2026, sempre do mesmo jeito: a producao ganhou uma funcao auxiliar, a
# lista do `sed` nao acompanhou, e a funcao ausente virou `comando nao
# encontrado` -- que NAO interrompe nada dentro de uma substituicao de comando.
# O campo saiu vazio e a suite ficou VERDE exercitando uma versao mutilada do
# que dizia exercitar.
#
#     identidade_artefato -> _sha_secao -> _secao
#
# Producao e teste carregam agora o MESMO arquivo, e o grafo e o mesmo por
# construcao. Os `declare -F` do teste continuam, como contrato explicito --
# mas deixam de ser a unica coisa entre o defeito e o falso verde.
#
# CONTRATO. Quem carrega define `MANIFESTO` (arquivo de destino) e `RAIZ`
# (para encurtar caminhos). `ARTEFATOS_VISTOS` e o registro de deduplicacao e
# comeca vazio aqui.
# IDENTIDADE DO ARTEFATO, COLHIDA DE FORA DO PROGRAMA MEDIDO
#
# O `origin:` que cada programa imprime identifica a FONTE -- o commit. Isso
# nao identifica o INSTRUMENTO: em 27/09/2026 o mesmo commit compilado com
# `-falign-loops` 16, 32, 64 e 128 produziu quatro binarios com quatro
# `.text` diferentes, e a razao `with/without SMT sibling` foi de 2,29 a 2,75
# entre eles -- 20%, num numero que o material publica com dispersao de 0,1%.
#
# POR QUE AQUI E NAO DENTRO DO BENCHMARK. Acrescentar um `printf` de
# proveniencia ao programa medido mudaria o leiaute do proprio codigo que se
# quer caracterizar. A identidade e do orquestrador, e o manifesto e onde ela
# cabe -- ele ja e a autoridade sobre a validade de cada celula.
#
# POR QUE OS BYTES DA SECAO, E NAO O `readelf`. O `readelf` desta maquina
# responde em portugues -- `ID de compilacao:` em vez de `Build ID:` --, e um
# `awk '/Build ID/'` devolve vazio em silencio. Ler a nota pelos bytes nao
# depende de como o sistema traduz. A licao e a mesma do leitor de ciclos da
# sonda, que passou doze horas quebrado pelo mesmo motivo.
_secao() { # <binario> <secao>  -> conteudo bruto, ou nada
    local t; t=$(mktemp)
    objcopy --dump-section "$2=$t" "$1" /dev/null 2>/dev/null
    cat "$t" 2>/dev/null
    rm -f "${t:?}"
}
_sha_secao() { # <binario> <secao>  -> sha256 da secao, ou nao-disponivel
    local t saida; t=$(mktemp)
    objcopy --dump-section "$2=$t" "$1" /dev/null 2>/dev/null
    if [ -s "$t" ]; then saida=$(sha256sum "$t" | cut -d' ' -f1); else saida="nao-disponivel"; fi
    rm -f "${t:?}"
    printf '%s' "$saida"
}
_flags_de() { # <binario>  -> as flags que o meson usou, ou nao-disponivel
    local real d
    real=$(readlink -f -- "$1" 2>/dev/null) || { echo "nao-disponivel"; return; }
    d=$(dirname "$real")
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        if [ -f "$d/compile_commands.json" ]; then
            python3 - "$d/compile_commands.json" "$(basename "$real")" <<'PYFLAGS'
import json, sys, re
try:
    cc = json.load(open(sys.argv[1]))
except Exception:
    print("nao-disponivel"); raise SystemExit
alvo = sys.argv[2]
for e in cc:
    if re.sub(r'\.[^.]+$', '', e.get('file','').split('/')[-1]) == alvo:
        cmd = e.get('command','')
        print(' '.join(x for x in cmd.split() if x.startswith('-') and
                       not x.startswith(('-I','-MD','-MQ','-MF','-o'))) or "nao-disponivel")
        raise SystemExit
print("nao-disponivel")
PYFLAGS
            return
        fi
        d=$(dirname "$d")
    done
    echo "nao-disponivel"
}
ARTEFATOS_VISTOS=""
identidade_artefato() { # <programa>  -> bloco `# ARTIFACT` no manifesto, uma vez por binario
    local real orig
    real=$(readlink -f -- "$1" 2>/dev/null) || return 0
    [ -n "$real" ] && [ -f "$real" ] || return 0
    case "|$ARTEFATOS_VISTOS|" in *"|$real|"*) return 0 ;; esac
    ARTEFATOS_VISTOS="$ARTEFATOS_VISTOS|$real"
    # O COMENTARIO NAO QUEBRA O CONTRATO DE TRES COLUNAS. Os consumidores
    # casam por `$1 == <celula>` ou `$2 == PASS|SKIP|FAIL`; um `#` na primeira
    # coluna nunca produz nenhum dos dois. O cabecalho ja usava comentario.
    # A TAG EXATA TAMBEM CONTA. O padrao anterior exigia `-N-gSHA`, entao um
    # binario construido exatamente sobre `v0.09.00` -- que e o proximo destino
    # deste repositorio -- sairia como `nao-disponivel`. Aceita tag pura,
    # `git describe` pos-tag, e o sufixo `-dirty` em qualquer das duas.
    orig=$(strings -a "$real" 2>/dev/null \
           | grep -m1 -E '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+-g[0-9a-f]+)?(-dirty)?$' || true)
    {
        echo "# ARTIFACT $(basename "$real")"
        echo "#   path=${real#$RAIZ/}"
        echo "#   source_origin=${orig:-nao-disponivel}"
        echo "#   binary_sha256=$(sha256sum "$real" | cut -d' ' -f1)"
        # SECAO AUSENTE NAO E SECAO VAZIA. `sha256sum` de entrada vazia da
        # sempre `e3b0c442...`, entao todo alvo nao-ELF -- `ambiente.sh`, por
        # exemplo -- receberia o MESMO `text_sha256` e o comparador os trataria
        # como o mesmo instrumento. Num campo declarado autoridade isso e
        # fail-open, e a resposta certa e dizer que nao ha.
        echo "#   text_sha256=$(_sha_secao "$real" .text)"
        # NEM TODO ALVO E ELF: `ambiente.sh` e um script, e ali nao ha nota
        # nenhuma. O `od -j16` sobre entrada vazia reclama na saida de erro; a
        # ausencia e resposta legitima e nao ruido para quem le o diario.
        echo "#   build_id=$(_secao "$real" .note.gnu.build-id \
                             | od -An -tx1 -j16 -v 2>/dev/null | tr -d ' \n')"
        echo "#   compiler=$(_secao "$real" .comment | tr '\0' '\n' | grep -m1 -iE 'gcc|clang' || echo nao-disponivel)"
        echo "#   compile_flags=$(_flags_de "$real")"
    } >> "$MANIFESTO"
}
