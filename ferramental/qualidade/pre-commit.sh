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
#   ./ferramental/qualidade/pre-commit.sh            # completo (~2 min)
#   ./ferramental/qualidade/pre-commit.sh --rapido   # sem a suíte longa (~20 s)
#   ./ferramental/qualidade/pre-commit.sh --instalar # liga como hook do git
set -u
# Sobe ate a raiz do repositorio em vez de contar niveis.
#
# Contar quebrou quando este script saiu de scripts/ para
# ferramental/qualidade/: `..` passou a ser ferramental/, e o efeito foi
# enganoso -- `meson setup` "falhava", o ninja dizia que build.ninja nao existia,
# e o arquivo estava la, na raiz. Tres falhas relatadas, nenhuma real.
_raiz="$(cd "$(dirname "$0")" && pwd)"
while [ "$_raiz" != "/" ] && { [ ! -f "$_raiz/meson.build" ] || [ ! -d "$_raiz/docs" ]; }; do
    _raiz="$(dirname "$_raiz")"
done
[ -f "$_raiz/meson.build" ] || { echo "nao achei a raiz do repositorio" >&2; exit 2; }
cd "$_raiz"

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
# Instalado por ferramental/qualidade/pre-commit.sh --instalar
exec ./ferramental/qualidade/pre-commit.sh --rapido
HOOK
    chmod +x .git/hooks/pre-commit
    echo "  hook instalado em .git/hooks/pre-commit (modo --rapido)"
    echo "  para pular pontualmente: git commit --no-verify"
    exit 0
fi

# --- 1. Sintaxe: o mais barato, e falha antes de tudo ---------------------
titulo "1. Sintaxe"

erro_sh=0
# `ferramental` entrou na lista, e a ausencia dele era defeito com data: apos a
# separacao do ferramental, o maior diretorio de script do projeto -- 4779
# linhas em 20 arquivos -- ficou fora desta varredura, e o gancho seguiu
# anunciando que conferiu a sintaxe. Controle que anuncia o que nao cobriu e
# pior que controle ausente.
for f in $(find scripts docs trilha ferramental -name '*.sh' 2>/dev/null); do
    bash -n "$f" 2>/dev/null || { falha "bash -n: $f"; erro_sh=1; }
done
[ $erro_sh -eq 0 ] && ok "todos os scripts shell"

if command -v python3 >/dev/null 2>&1; then
    erro_py=0
    for f in scripts/*.py ferramental/qualidade/*.py ferramental/af-xdp/*.py scripts/tests/*.py; do
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

if [ -x ferramental/qualidade/verificar-links.py ]; then
    if out=$(./ferramental/qualidade/verificar-links.py 2>&1); then
        ok "$(tail -1 <<<"$out" | sed 's/^ *//')"
    else
        falha "links ou referências quebrados"; sed 's/^/          /' <<<"$out" | head -8
    fi
fi
if [ -x ferramental/qualidade/verificar-ancoras.py ]; then
    if out=$(./ferramental/qualidade/verificar-ancoras.py 2>&1); then
        ok "$(tail -1 <<<"$out" | sed 's/^ *//')"
    else
        falha "âncoras de linha desatualizadas"; sed 's/^/          /' <<<"$out" | head -8
    fi
fi

# OS QUATRO VERIFICADORES QUE EXISTIAM E NUNCA RODAVAM
#
# `verificar-aritmetica`, `verificar-autodescricao`, `verificar-promessa` e
# `verificar-retratacoes` foram escritos, testados (cada um tem --autoteste),
# tornados executaveis... e nunca ligados a nada. Nem ao pre-commit, nem a CI.
# Rodavam so quando alguem lembrava.
#
# A consequencia e pior que nao te-los: o projeto acreditava estar conferindo
# retratacao, promessa e autodescricao. O de retratacoes chegou a pegar um erro
# real em 18/09/2026 -- um valor declarado que colidia com texto legitimo --
# e so porque foi invocado a mao.
#
# O LACO ABAIXO E DE PROPOSITO GENERICO: qualquer `verificar-*.py` novo entra
# na barra sem precisar editar este arquivo. Um verificador que existe e nao
# roda e falso verde com trabalho extra.
for v in ferramental/qualidade/verificar-*.py; do
    case "$v" in
        */verificar-links.py|*/verificar-ancoras.py) continue ;;   # ja rodaram acima
    esac
    nome=$(basename "$v" .py | sed 's/^verificar-//')
    # SEM `continue` SILENCIOSO: `verificar-tabelas.py` nasceu sem bit de
    # execucao e sumiu da barra sem uma linha sequer de saida. Verificador
    # que nao roda precisa DIZER que nao rodou.
    if [ ! -x "$v" ]; then
        aviso "$nome nao roda: falta bit de execucao (chmod +x $v)"
        continue
    fi
    if out=$("./$v" 2>&1); then
        # Primeira linha nao vazia COM NUMERO: e o resumo nos seis verificadores.
        # `tail -1` parecia obvio e trazia a ultima linha de uma LISTA em dois
        # deles, o que faz um verificador que passou parecer que reclamou.
        ok "$nome: $(grep -vE '^[[:space:]]*$' <<<"$out" | grep -m1 '[0-9]' | sed 's/^ *//' | cut -c1-70)"
    else
        falha "$nome nao passou"; sed 's/^/          /' <<<"$out" | head -8
    fi
done

# O RELATORIO DE ARREDONDADOS: visivel, e fora do veredito.
#
# Em 19/09/2026 tres numeros retratados foram achados vivos em seis lugares,
# todos escapando pela mesma porta: `verificar-retratacoes` compara strings, e
# "18" nao casa com "18.2". O relatorio de arredondados fecha a VISIBILIDADE da
# classe sem virar gate -- a razao esta medida no cabecalho daquele arquivo:
# um gate por arredondamento acusaria sete vezes o texto correto so no modulo
# 01, e verificador que acusa o correto e desligado.
#
# Ele aparece como AVISO: quem commita ve o numero e decide. Silencio aqui
# seria voltar ao estado em que a classe nao existia.
if [ -x ferramental/qualidade/verificar-retratacoes.py ]; then
    # CONTA O QUE FALTA TRIAR, nao o total.
    #
    # O aviso dizia "38" e ficou parado em 38 por dias. Numero que nao se move
    # nao e fila de trabalho: e ruido de fundo, e ruido de fundo se ignora.
    # Contando os NAO CLASSIFICADOS, cada numero triado desaparece do aviso.
    n=$(./ferramental/qualidade/verificar-retratacoes.py --arredondados 2>&1 \
        | grep -oP '^\s+\K[0-9]+(?= SEM CLASSIFICACAO)' || true)
    if [ -n "$n" ] && [ "$n" -gt 0 ]; then
        aviso "$n numero(s) arredondados SEM CLASSIFICACAO (triagem: --arredondados)"
    fi
fi

# O inventario de tabelas NAO entra no laco acima porque nao se chama
# `verificar-*`. Ficou anos fora da barra por causa do nome: ele detecta
# desatualizacao e sai diferente de zero, mas ninguem o executava. Entrou aqui
# depois que quatro tabelas novas do 6.3 nao apareceram nele.
if [ -x ferramental/qualidade/inventariar-dados.py ]; then
    if out=$(./ferramental/qualidade/inventariar-dados.py 2>&1); then
        ok "inventario: $(grep -m1 '[0-9]' <<<"$out" | cut -c1-66)"
    else
        falha "inventario de tabelas desatualizado"
        echo "          rode: ./ferramental/qualidade/inventariar-dados.py --atualizar"
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

# A branch main exige assinatura verificada -- o ruleset `main protegida` do
# GitHub tem `required_signatures` e lista de bypass vazia. Descobrir isso no
# `git push`, depois de escrever a mensagem, é atrito evitável.
#
# DUAS PERGUNTAS DIFERENTES, e confundi-las deixou a CI vermelha em cinco
# publicações seguidas.
#
# Na máquina de quem escreve, a pergunta é sobre o FUTURO: os próximos commits
# vão sair assinados? Quem responde é `commit.gpgsign`, configuração local.
#
# No runner da CI, essa pergunta não tem sentido: ele não faz commit e não tem
# chave, então `commit.gpgsign` é sempre falso e o teste falhava SEMPRE, por
# construção. Pior: falhava na etapa 6, antes de `meson setup`, de modo que a
# CI nunca chegava a compilar nem testar -- o X vermelho não dizia nada sobre a
# saúde do código, e escondia qualquer defeito real atrás de um falso.
#
# Lá a pergunta é sobre o PASSADO: o commit que está sendo construído carrega
# assinatura?
#
# E a resposta NÃO pode vir de `%G?`, que foi a primeira tentativa e falhou pelo
# motivo que este projeto inteiro combate. `%G?` responde sobre VERIFICAÇÃO, não
# sobre existência: estes commits são assinados por SSH, e sem
# `gpg.ssh.allowedSignersFile` configurado o runner não tem como verificar --
# então o git devolve `N`, que se lê "não há assinatura". Não apurado saindo
# como fato negativo, dentro do conserto do teste que falhava por isso.
#
# `git cat-file` lê o OBJETO do commit, onde o cabeçalho `gpgsig` está presente
# ou ausente. Serve para GPG e para SSH, não chama verificador nenhum, não
# precisa de chave e não tem terceiro estado: o cabeçalho está lá ou não está.
if [ -n "${CI:-}${GITHUB_ACTIONS:-}" ]; then
    if ! cabecalho=$(git cat-file commit HEAD 2>/dev/null); then
        falha "não consegui ler o objeto de HEAD; nada se pode dizer sobre a assinatura"
    elif printf '%s' "$cabecalho" | grep -qE '^gpgsig'; then
        ok "HEAD carrega assinatura no objeto (lida sem verificador, como o runner exige)"
    else
        falha "HEAD NÃO carrega assinatura — a main exige assinatura verificada"
    fi
elif [ "$(git config --get commit.gpgsign || echo false)" = "true" ]; then
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
