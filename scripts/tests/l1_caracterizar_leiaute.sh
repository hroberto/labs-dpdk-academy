#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Os portoes do `caracterizar-leiaute.sh`, exercitados no script REAL.
#
# POR QUE ESTE TESTE EXISTE
#
# A caracterizacao so responde alguma coisa se variar UMA coisa. Cada portao
# aqui fecha um jeito de varrer uma segunda variavel para dentro sem aviso:
#
#   sessao grafica   a faixa entre execucoes fica ilegivel, e o numero
#                    PARECERIA valido -- aconteceu em 27/09/2026, quando uma
#                    execucao perturbada em dez levou a faixa de
#                    `lock, best case` a 84%
#   build velho      `compile_commands.json` recente nao basta: mudanca no
#                    `meson.build` altera as flags sem tocar em nenhum `.c`
#   build-san        configurado com `-Db_sanitize=address,undefined`, ele
#                    passa `-fno-omit-frame-pointer`, que muda alocacao de
#                    registradores e LEIAUTE -- a variavel sob estudo
#
# O TESTE RODA O SCRIPT REAL, numa arvore de mentira com as dependencias
# trocadas por stubs. Extrair trechos por `sed` reconstruiria o grafo a mao,
# que e a classe de falso-verde que o `PADROES.md` agora proibe.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
alvo="$raiz/ferramental/qualidade/caracterizar-leiaute.sh"
[ -r "$alvo" ] || { echo "FALHA: nao achei $alvo"; exit 1; }
falhas=0
total=0
conferir() { # <descricao> <obtido> <esperado>
    total=$((total + 1))
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A arvore de mentira: so o que o script toca antes de medir.
montar() { # <graficos> <uid> <build-all devolve> <cria build/>
    rm -rf "$tmp/arv" "$tmp/bin"
    mkdir -p "$tmp/arv/ferramental/qualidade" "$tmp/arv/scripts" "$tmp/bin" \
             "$tmp/arv/docs/01-fundamentos/medicoes/historico" "$tmp/arv/build-san"
    cp "$alvo" "$tmp/arv/ferramental/qualidade/"
    cp "$raiz/ferramental/qualidade/identidade-artefato.sh" "$tmp/arv/ferramental/qualidade/"
    cp "$raiz/ferramental/qualidade/receita-build.sh" "$tmp/arv/ferramental/qualidade/"
    printf '#!/bin/sh\nexit %s\n' "$3" > "$tmp/arv/scripts/build-all.sh"
    # O ALVO E O BUILD QUE A CAMPANHA MEDE, e nao `build`. A caracterizacao
    # passou a derivar de `build-precommit` porque e dali que o
    # `campanha-hardware.sh` executa: derivar de outro produziria artefatos de
    # outra familia, e a classificacao nao valeria para os rotulos coletados.
    [ "$4" = "sim" ] && { mkdir -p "$tmp/arv/build-precommit"
                          echo '[]' > "$tmp/arv/build-precommit/compile_commands.json"; }
    # O `build-san` SEMPRE existe nesta arvore: e o cenario que interessa.
    echo '[{"file":"x.c","command":"cc -fsanitize=address -fno-omit-frame-pointer -c x.c","directory":"."}]' \
        > "$tmp/arv/build-san/compile_commands.json"
    printf '#!/bin/sh\necho ambiente\n' > "$tmp/arv/scripts/ambiente.sh"
    chmod +x "$tmp/arv/scripts"/*.sh
    printf '#!/bin/sh\necho %s\n' "$2" > "$tmp/bin/id"
    printf '#!/bin/sh\necho %s\n' "$1" > "$tmp/bin/pgrep"
    chmod +x "$tmp/bin"/*
}
rodar() { PATH="$tmp/bin:$PATH" bash "$tmp/arv/ferramental/qualidade/caracterizar-leiaute.sh" \
              --repeticoes 1 custo-comunicacao 2>&1; }

# ---- 1. sem root nao caracteriza ---------------------------------------
montar 0 1000 0 sim
saida=$(rodar); rc=$?
conferir "sem root recusa"            "$rc" "1"
conferir "e diz que precisa de sudo"  "$(printf '%s' "$saida" | grep -c sudo)" "1"

# ---- 2. sessao grafica viva nao caracteriza ----------------------------
# A condicao e o objeto da medicao: com compositor vivo a faixa entre
# execucoes mede a sessao, e nao o binario.
montar 2 0 0 sim
saida=$(rodar); rc=$?
conferir "sessao grafica recusa"          "$rc" "1"
conferir "e manda reiniciar em modo texto" \
    "$(printf '%s' "$saida" | grep -c 'modo texto')" "1"

# ---- 3. build que nao compila nao caracteriza --------------------------
montar 0 0 1 sim
saida=$(rodar); rc=$?
conferir "build quebrado recusa" "$rc" "1"
conferir "e diz que a caracterizacao nao comeca" \
    "$(printf '%s' "$saida" | grep -c 'NAO comeca')" "1"

# ---- 4. SO `build-san` NAO SERVE ---------------------------------------
#
# O portao anterior varria `build build-san` e usava o primeiro que achasse.
# Com `build/` ausente, a caracterizacao leria flags com
# `-fsanitize=address,undefined -fno-omit-frame-pointer` e mediria o efeito do
# sanitizador chamando de leiaute.
montar 0 0 0 nao
saida=$(rodar); rc=$?
conferir "sem build normal, recusa"      "$rc" "1"
conferir "e nomeia o arquivo que falta"  \
    "$(printf '%s' "$saida" | grep -c 'build-precommit/compile_commands.json')" "1"
# `build-san` EXISTE NA ARVORE DE MENTIRA de proposito: e a tentacao. Ele e
# configurado com `-Db_sanitize=address,undefined` e passa
# `-fno-omit-frame-pointer`, que muda alocacao de registradores e leiaute --
# a variavel sob estudo.
conferir "e NAO cai no build-san"        \
    "$(printf '%s' "$saida" | grep -c 'build-san')" "0"

# ---- 5. a reconstrucao NAO e opcional ----------------------------------
# Mesmo com `build/compile_commands.json` presente, o script reconstroi antes
# de ler as flags: mudanca no `meson.build` altera as flags sem tocar em
# nenhum `.c`, e conferir a data do arquivo deixaria isso passar.
montar 0 0 0 sim
saida=$(rodar)
conferir "reconstroi mesmo com o json presente" \
    "$(printf '%s' "$saida" | grep -c 'reconstruindo o build normal')" "1"

# ---- 6. SEM ANCORA, ZERO MEDICOES ---------------------------------------
#
# No alinhamento de producao a variante tem de reproduzir o `.text` do binario
# que a campanha mede. A primeira versao do portao imprimia AVISO e seguia
# quando faltava um dos lados, e aprovava quando `_sha_secao` devolvia
# `nao-disponivel` dos DOIS -- a igualdade era satisfeita pela sentinela.
#
# Tres caminhos fail-open, no portao que existe para fechar fail-open.
montar_ancora() { # <cria binario de producao> <cc falha no al64>
    montar 0 0 0 sim
    printf '[{"directory":"%s","file":"../x.c","command":"cc -falign-loops=64 -c ../x.c -o x.o"}]\n' \
        "$tmp/arv/build-precommit" > "$tmp/arv/build-precommit/compile_commands.json"
    echo 'int main(void){return 0;}' > "$tmp/arv/x.c"
    [ "$1" = "sim" ] && { printf 'producao\n' > "$tmp/arv/build-precommit/x"; chmod +x "$tmp/arv/build-precommit/x"; }
    # `cc` de mentira: cria a saida pedida, exceto quando mandado falhar.
    cat > "$tmp/bin/cc" <<CCFIM
#!/bin/sh
falha_al=$2
for a in "\$@"; do
    case "\$a" in -falign-loops=*) al=\${a#*=} ;; esac
done
[ "\$falha_al" = "sim" ] && [ "\$al" = "64" ] && exit 1
prox=0
for a in "\$@"; do
    [ "\$prox" = 1 ] && { echo variante > "\$a"; chmod +x "\$a"; exit 0; }
    [ "\$a" = "-o" ] && prox=1
done
exit 0
CCFIM
    # `sudo` de mentira: tira `-u <quem>` e `-H`, e executa o resto.
    cat > "$tmp/bin/sudo" <<'SUFIM'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in -u) shift 2 ;; -H|-n) shift ;; *) break ;; esac
done
exec "$@"
SUFIM
    chmod +x "$tmp/bin/cc" "$tmp/bin/sudo"
}
rodar_x() { PATH="$tmp/bin:$PATH" bash "$tmp/arv/ferramental/qualidade/caracterizar-leiaute.sh" \
                --repeticoes 1 --alinhamentos "64" x 2>&1; }

# 6a. BINARIO DE PRODUCAO AUSENTE -> aborta, e nao avisa.
montar_ancora nao nao
saida=$(rodar_x); rc=$?
conferir "sem binario de producao, aborta"       "$rc" "1"
conferir "e diz que nao ha o que ancorar" \
    "$(printf '%s' "$saida" | grep -c 'ancorar')" "1"
conferir "e NAO degrada para aviso" \
    "$(printf '%s' "$saida" | grep -c 'AVISO')" "0"

# 6a2. DOIS BINARIOS COM O MESMO NOME -> aborta, em vez de escolher.
#      Era `find ... | head -1`. No dia em que dois diretorios do build
#      tiverem um executavel homonimo, a ancora escolheria um em SILENCIO e
#      passaria a descrever um instrumento que talvez nao seja o medido.
montar_ancora sim nao
mkdir -p "$tmp/arv/build-precommit/sub"
printf 'outro\n' > "$tmp/arv/build-precommit/sub/x"; chmod +x "$tmp/arv/build-precommit/sub/x"
saida=$(rodar_x); rc=$?
conferir "dois binarios homonimos abortam"       "$rc" "1"
conferir "e os dois sao listados"                \
    "$(printf '%s' "$saida" | grep -c 'build-precommit/x$\|build-precommit/sub/x$')" "2"

# 6b. A VARIANTE DO ALINHAMENTO DE PRODUCAO NAO CONSTRUIU -> aborta.
montar_ancora sim sim
saida=$(rodar_x); rc=$?
conferir "variante de producao ausente, aborta"  "$rc" "1"
conferir "e nomeia a variante que falta" \
    "$(printf '%s' "$saida" | grep -c 'nao foi construida')" "1"

# 6c. A SENTINELA NAO PODE SATISFAZER A IGUALDADE. Os dois lados sao arquivos
#     nao-ELF: `_sha_secao` devolve `nao-disponivel` para ambos, e comparar
#     duas sentinelas aprovaria a ancora sem comparar nada.
montar_ancora sim nao
saida=$(rodar_x); rc=$?
conferir "dois lados sem .text nao aprovam a ancora" "$rc" "1"
conferir "e diz que nao leu a secao" \
    "$(printf '%s' "$saida" | grep -c 'nao li a secao')" "1"

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: $total assercoes; a caracterizacao so corre com uma variavel livre"
