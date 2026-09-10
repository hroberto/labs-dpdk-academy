#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Verificação local antes de commitar.
#
# POR QUE ESTE SCRIPT EXISTE
#
# A primeira execução da CI na história deste projeto falhou com 7 erros e 2
# timeouts. **Todas as causas eram detectáveis nesta máquina**, e nenhuma foi
# detectada, porque a verificação manual antes do commit era "rodei os testes" —
# o que não cobre o que a CI cobre.
#
# Cada bloco abaixo existe por causa de um incidente concreto, e o comentário
# diz qual. Um verificador cujas regras ninguém sabe justificar vira ritual, e
# ritual se ignora no dia em que atrapalha.
#
# O QUE ELE NÃO É
#
# Não substitui a CI: aqui o DPDK é 25.11 e lá é 23.11, e essa diferença já
# produziu dois defeitos. O que ele faz é eliminar as falhas que NÃO dependem
# de ambiente — que foram a maioria.
#
# Uso:
#   ./scripts/pre-commit.sh            # completo (~2 min)
#   ./scripts/pre-commit.sh --rapido   # sem a suíte longa (~20 s)
#   ./scripts/pre-commit.sh --instalar # liga como hook do git
set -u
cd "$(dirname "$0")/.."

MODO="completo"
case "${1:-}" in
    --rapido)   MODO="rapido" ;;
    --instalar) MODO="instalar" ;;
    "")         ;;
    *) echo "uso: $0 [--rapido|--instalar]" >&2; exit 2 ;;
esac

BUILD=${DPDK_ACADEMY_BUILD:-build-precommit}
falhas=0
avisos=0

titulo() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()     { printf '  [ok]    %s\n' "$1"; }
falha()  { printf '  [FALHA] %s\n' "$1"; falhas=$((falhas + 1)); }
aviso()  { printf '  [aviso] %s\n' "$1"; avisos=$((avisos + 1)); }

# --- instalação como hook -------------------------------------------------
if [ "$MODO" = "instalar" ]; then
    mkdir -p .git/hooks
    cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
# Instalado por scripts/pre-commit.sh --instalar
exec ./scripts/pre-commit.sh --rapido
HOOK
    chmod +x .git/hooks/pre-commit
    echo "  hook instalado em .git/hooks/pre-commit (modo --rapido)"
    echo "  para pular pontualmente: git commit --no-verify"
    exit 0
fi

# --- 1. Sintaxe: o mais barato, e falha antes de tudo ---------------------
titulo "1. Sintaxe"

erro_sh=0
for f in $(find scripts docs trilha -name '*.sh' 2>/dev/null); do
    bash -n "$f" 2>/dev/null || { falha "bash -n: $f"; erro_sh=1; }
done
[ $erro_sh -eq 0 ] && ok "todos os scripts shell"

if command -v python3 >/dev/null 2>&1; then
    erro_py=0
    for f in scripts/*.py; do
        [ -e "$f" ] || continue
        python3 -m py_compile "$f" 2>/dev/null || { falha "py_compile: $f"; erro_py=1; }
    done
    [ $erro_py -eq 0 ] && ok "todos os scripts python"

    # O workflow da CI é YAML: um erro aqui só apareceria no GitHub.
    if [ -f .github/workflows/ci.yml ]; then
        python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))" 2>/dev/null \
            && ok "ci.yml é YAML válido" || falha "ci.yml não é YAML válido"
    fi
    if [ -f .github/dependabot.yml ]; then
        python3 -c "import yaml,sys; yaml.safe_load(open('.github/dependabot.yml'))" 2>/dev/null \
            && ok "dependabot.yml é YAML válido" || falha "dependabot.yml não é YAML válido"
    fi
fi

# --- 2. Consistência específica deste projeto -----------------------------
titulo "2. Consistência do projeto"

# INCIDENTE: `--in-memory --no-huge` juntos são rejeitados até o DPDK 23.11
# (`--no-huge` liga `--legacy-mem`, incompatível com `--in-memory`). Passava
# aqui, quebrava na CI. Só vale para INVOCAÇÕES; a prosa pode citar a
# combinação, e cita, para ensinar por que ela falha.
# `-e` e nao `--`: com `--` o grep trata `--include` como NOME DE ARQUIVO, e
# varre tudo -- inclusive a prosa que cita a combinacao para ensinar por que ela
# falha, e este proprio script. Foi assim na primeira versao daqui.
combos=$(grep -rn -e '--in-memory --no-huge' --include='*.sh' --include='meson.build' . 2>/dev/null \
         | grep -vE '^\./build|pre-commit\.sh' | grep -vE ':[0-9]+:\s*#' || true)
if [ -n "$combos" ]; then
    falha "invocação com '--in-memory --no-huge' (rejeitado até o DPDK 23.11)"
    sed 's/^/          /' <<<"$combos"
else
    ok "nenhuma invocação combina --in-memory com --no-huge"
fi

# INCIDENTE: `actions/checkout@v4` era tag móvel. Fixado por SHA; esta regra
# impede que alguém reintroduza a tag sem perceber.
if [ -f .github/workflows/ci.yml ]; then
    if grep -qE 'uses: [a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+@v[0-9]' .github/workflows/ci.yml; then
        falha "ação de CI referenciada por TAG; fixe por SHA de 40 caracteres"
        grep -nE 'uses: .*@v[0-9]' .github/workflows/ci.yml | sed 's/^/          /'
    else
        ok "ações da CI fixadas por SHA"
    fi
    # INCIDENTE: sem bloco `permissions:`, o GITHUB_TOKEN herda escrita.
    grep -q '^permissions:' .github/workflows/ci.yml \
        && ok "GITHUB_TOKEN com permissões declaradas" \
        || falha "ci.yml sem bloco 'permissions:' (o token herda escrita)"

    # INCIDENTE: fixar por SHA impede que a TAG seja reapontada, mas nao diz
    # QUAL versao o SHA e. Horas depois de ligar o Dependabot, ele abriu um PR
    # levando actions/checkout de v4 para v7 -- tres versoes maiores de salto --
    # e a verificacao acima aprovaria, porque continua sendo um SHA valido.
    #
    # Esta checagem resolve o SHA de volta para a tag e compara com o major que
    # o workflow declara no comentario ao lado do pin. E AVISO, nao falha:
    # depende de rede e de `gh`, e um pre-commit que exige os dois nao roda em
    # aviao nem em maquina de terceiros.
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        while read -r acao sha; do
            [ -n "$sha" ] || continue
            major=$(grep -oE "# *Corresponde a v[0-9]+" .github/workflows/ci.yml | grep -oE 'v[0-9]+' | head -1)
            [ -n "$major" ] || { aviso "pin de $acao sem 'Corresponde a vN' no comentario"; continue; }
            esperado=$(timeout 20 gh api "repos/$acao/git/ref/tags/$major" --jq '.object.sha' 2>/dev/null || echo "")
            if [ -z "$esperado" ]; then
                aviso "nao consegui resolver $acao@$major (offline?)"
            elif [ "$esperado" = "$sha" ]; then
                ok "$acao fixada em $major (SHA confere com a tag)"
            else
                aviso "$acao: o SHA fixado NAO e mais o topo de $major"
                printf '          fixado:  %s\n          %s hoje: %s\n' "$sha" "$major" "$esperado"
                printf '          Se veio de um PR do Dependabot, confira se e salto de major.\n'
            fi
        done < <(grep -oE 'uses: [a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+@[0-9a-f]{40}' .github/workflows/ci.yml \
                 | sed 's/uses: //' | tr '@' ' ')
    else
        aviso "gh ausente ou nao autenticado: versao do SHA fixado nao verificada"
    fi
fi

# --- 3. Nada sensível ------------------------------------------------------
titulo "3. Informações sensíveis"

seg=$(git grep -nIE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,})' -- . 2>/dev/null || true)
[ -z "$seg" ] && ok "nenhum padrão de credencial" || { falha "possível credencial no conteúdo"; sed 's/^/          /' <<<"$seg"; }

# Caminho absoluto da máquina de quem escreveu vaza usuário e quebra para
# terceiros que clonarem.
abs=$(git grep -nI '/home/[a-z]' -- . ':!*.md' 2>/dev/null || true)
[ -z "$abs" ] && ok "nenhum caminho absoluto de máquina" || { aviso "caminho absoluto encontrado"; sed 's/^/          /' <<<"$abs" | head -3; }

# Endereço MAC identifica hardware de quem publicou. Saída de testpmd colada
# num documento é o caminho mais provável.
mac=$(git grep -nIE '\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b' -- . 2>/dev/null || true)
[ -z "$mac" ] && ok "nenhum endereço MAC" || { aviso "endereço MAC no conteúdo"; sed 's/^/          /' <<<"$mac" | head -3; }

# --- 4. Documentação --------------------------------------------------------
titulo "4. Documentação"

if [ -x scripts/verificar-links.py ]; then
    if out=$(./scripts/verificar-links.py 2>&1); then
        ok "$(tail -1 <<<"$out" | sed 's/^ *//')"
    else
        falha "links ou referências quebrados"; sed 's/^/          /' <<<"$out" | head -8
    fi
fi
if [ -x scripts/verificar-ancoras.py ]; then
    if out=$(./scripts/verificar-ancoras.py 2>&1); then
        ok "$(tail -1 <<<"$out" | sed 's/^ *//')"
    else
        falha "âncoras de linha desatualizadas"; sed 's/^/          /' <<<"$out" | head -8
    fi
fi

# --- 5. Build e testes ------------------------------------------------------
titulo "5. Build e testes"

if ! pkg-config --exists libdpdk 2>/dev/null; then
    aviso "DPDK ausente: build e testes pulados (a CI os fará)"
else
    if [ ! -f "$BUILD/build.ninja" ]; then
        meson setup "$BUILD" >/dev/null 2>&1 || { falha "meson setup falhou"; }
    fi
    saida_build=$(ninja -C "$BUILD" 2>&1)
    rc=$?
    # A barra do projeto é ZERO avisos, e aviso não falha o build por padrão.
    avs=$(grep -c 'warning:' <<<"$saida_build" | head -1)
    if [ $rc -ne 0 ]; then
        falha "build falhou"; grep -E 'error:' <<<"$saida_build" | head -5 | sed 's/^/          /'
    elif [ "${avs:-0}" -gt 0 ]; then
        falha "$avs aviso(s) de compilação — a barra do projeto é zero"
        grep 'warning:' <<<"$saida_build" | head -4 | sed 's/^/          /'
    else
        ok "build limpo, zero avisos"
    fi

    if [ "$MODO" = "completo" ]; then
        # Suíte com os MESMOS tetos da CI. Rodar só o padrão local esconde
        # timeout: custo-espera leva 40 s aqui e estourou 300 s no runner.
        if DPDK_ACADEMY_AMOSTRAS=3 DPDK_ACADEMY_RODADAS=20000 \
           meson test -C "$BUILD" >/dev/null 2>&1; then
            ok "suíte completa nos tetos da CI"
        else
            falha "suíte falhou (tetos da CI)"
            DPDK_ACADEMY_AMOSTRAS=3 DPDK_ACADEMY_RODADAS=20000 \
              meson test -C "$BUILD" --print-errorlogs 2>&1 | grep -E 'FAIL|TIMEOUT' | head -6 | sed 's/^/          /'
        fi
    else
        if meson test -C "$BUILD" --suite l1 >/dev/null 2>&1; then
            ok "suíte L1 (modo rápido; rode sem --rapido antes de publicar)"
        else
            falha "suíte L1 falhou"
        fi
    fi
fi

# --- 6. Assinatura ----------------------------------------------------------
titulo "6. Assinatura de commit"

# A branch main exige assinatura verificada. Descobrir isso no `git push`,
# depois de escrever a mensagem, é atrito evitável.
if [ "$(git config --get commit.gpgsign || echo false)" = "true" ]; then
    chave=$(git config --get user.signingkey || echo "")
    if [ -n "$chave" ]; then ok "commit.gpgsign ativo (chave ${chave:0:16}…)"
    else falha "commit.gpgsign ativo mas user.signingkey não definido"; fi
else
    falha "commit.gpgsign desligado — a main exige assinatura verificada"
fi

# --- veredito ---------------------------------------------------------------
printf '\n\033[1m== Veredito ==\033[0m\n'
[ $avisos -gt 0 ] && printf '  %d aviso(s) — não bloqueiam\n' "$avisos"
if [ $falhas -eq 0 ]; then
    printf '  \033[1mtudo passou.\033[0m Pode commitar.\n\n'
    exit 0
fi
printf '  \033[1m%d falha(s).\033[0m Corrija antes de commitar.\n' "$falhas"
printf '  Para pular deliberadamente: git commit --no-verify\n\n'
exit 1
