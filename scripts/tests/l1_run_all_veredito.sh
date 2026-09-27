#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# `run-all` so devolve sucesso se tudo que ele declarou executar teve sucesso.
#
# POR QUE ESTE TESTE EXISTE
#
# A cadeia que o projeto construiu -- instrumento recusa, subcampanha preserva,
# manifesto registra, campanha agrega -- parava no penultimo elo. O `run-all`,
# que esta acima de todos, tinha tres caminhos de falso sucesso, e os tres
# foram reproduzidos pela auditoria de 26/09:
#
#   --so-ruido            o `exit 0` antecipado descartava o `rc` da campanha
#   SIGTERM               o trap restaurava o governor e DEVOLVIA o controle
#   etapa 4               as saidas eram redirecionadas sem conferir retorno
#
# Os tres viram regressao aqui. O script de reproducao da auditoria extrai
# trechos do fonte por casamento de texto e quebra quando a forma muda; este
# exercita o COMPORTAMENTO, que e o que precisa continuar valendo.
#
# E HA UM CASO POSITIVO, de proposito: um teste que so sabe recusar aprovaria
# um `run-all` que nunca conclui.
set -u
raiz=$(cd "$(dirname "$0")/../.." && pwd)
fonte="$raiz/ferramental/qualidade/run-all.sh"
[ -r "$fonte" ] || { echo "FALHA: nao achei $fonte"; exit 1; }
falhas=0
total=0

conferir() { # <descricao> <obtido> <esperado>
    total=$((total + 1))
    if [ "$2" != "$3" ]; then
        echo "  FALHOU: $1 (esperado '$3', obtido '$2')"
        falhas=$((falhas + 1))
    fi
}

# Recorta do fonte REAL, e nao de uma copia: copiar deixaria este teste verde
# enquanto o `run-all` divergisse.
recorte() { # <marcador-inicial> <marcador-final>
    awk -v ini="$1" -v fim="$2" '
        index($0, ini) { dentro = 1 }
        dentro { print }
        dentro && index($0, fim) && NR > 1 { exit }
    ' "$fonte"
}

# O FECHAMENTO NA COLUNA ZERO, e nao o primeiro `fi` que aparecer.
#
# O bloco do `--so-ruido` contem um `if` interno, e recortar ate o primeiro
# `fi` deixava o externo aberto: o `bash` devolvia 2 por erro de SINTAXE, e o
# teste lia isso como veredito. Um recorte errado nao falha ruidosamente --
# ele responde outra coisa.
recorte_bloco() { # <ancora> <marcador-inicial>
    # A ANCORA IMPORTA: `if [ "$SO_RUIDO" -eq 1 ]` aparece mais de uma vez no
    # arquivo, e recortar a primeira ocorrencia extrai outro trecho -- que
    # roda, nao falha, e responde outra coisa. O script de reproducao da
    # auditoria ja ancorava na etapa 4 pelo mesmo motivo.
    awk -v anc="$1" -v ini="$2" '
        index($0, anc) { achou_ancora = 1 }
        achou_ancora && index($0, ini) { dentro = 1 }
        dentro { print }
        dentro && /^fi$/ { exit }
    ' "$fonte"
}

# ---- 1. o rc da campanha vira o estado agregado -------------------------
agregacao=$(recorte 'rc_final=0' 'esac')
for par in "0 0" "2 2" "42 1" "1 1"; do
    set -- $par
    obtido=$(bash -c "rc=$1
$agregacao
echo \$rc_final" 2>/dev/null)
    conferir "campanha rc=$1 agrega como $2" "$obtido" "$2"
done

# ---- 2. NENHUM RECORTE descarta o resultado, E NENHUM SAI ANTES --------
#
# A etapa 4 saia com `exit` sob recorte. Isso teve dois defeitos em sequencia:
# primeiro descartava o `rc` da campanha -- `--so-ruido` com campanha falhando
# em 42 produzia `run-all CONCLUIDO` e codigo 0 --, e depois, quando a
# caracterizacao virou a ETAPA 5, passaria a PULAR a etapa seguinte sob
# qualquer recorte, inclusive sob `--so-leiaute`, cujo unico proposito e
# chegar nela.
#
# O veredito e unico e fica no fim do arquivo. Nenhum caminho o contorna.
recorte_ate_else() { # <ancora> <marcador> -> do marcador ate o `else` de coluna zero
    awk -v anc="$1" -v ini="$2" '
        index($0, anc) { achou = 1 }
        achou && index($0, ini) { dentro = 1 }
        dentro { print }
        dentro && /^else$/ { exit }
    ' "$fonte"
}
guarda4=$(recorte_ate_else 'ETAPA 4/5' 'if [ -n "$RECORTE" ]; then')
[ -n "$guarda4" ] || { echo "  FALHOU: nao recortei a guarda da etapa 4"; falhas=$((falhas + 1)); }

# O MARCADOR VAI DEPOIS DO `fi`, e nao dentro do `else`.
#
# A primeira versao desta assercao punha `echo SEGUIU` no ramo `else`, que NAO
# corre quando ha recorte -- entao ela reprovava a guarda correta. O que se
# quer provar e que o fluxo ATRAVESSA a guarda, e isso so se ve depois do `fi`.
executar4() { # <recorte> -> o que a guarda da etapa 4 fez
    # `rc_final` VAI DEFINIDO, e isso nao e detalhe do harness.
    #
    # Sem ele, um `exit "$rc_final"` reintroduzido vira `exit ""` -- que o bash
    # RECUSA com "requer argumento numerico" e NAO executa, seguindo o fluxo.
    # A assercao ficava cega justamente a mutacao que ela existe para pegar:
    # o teste exercitava uma versao degradada do defeito.
    bash -c "rc_final=0; RECORTE='$1'
$guarda4
echo CORPO_DA_ETAPA_4
fi
echo ATRAVESSOU_A_ETAPA_4" 2>&1
}
for r in --so-ruido --so-hardware --so-leiaute; do
    saida=$(executar4 "$r")
    conferir "$r pula a etapa 4 dizendo qual recorte" \
        "$(printf '%s' "$saida" | grep -c "PULADA ($r)")" "1"
    conferir "$r nao executa o corpo da etapa 4" \
        "$(printf '%s' "$saida" | grep -c CORPO_DA_ETAPA_4)" "0"
    # O QUE MUDOU: a guarda NAO pode mais terminar o fluxo, senao a ETAPA 5
    # ficaria inalcancavel sob `--so-leiaute`, que existe para chegar nela.
    conferir "$r nao interrompe o fluxo antes da etapa 5" \
        "$(printf '%s' "$saida" | grep -c ATRAVESSOU_A_ETAPA_4)" "1"
done

# E O CASO NEGATIVO: sem recorte, o corpo corre e nada e pulado.
saida=$(executar4 "")
conferir "sem recorte a etapa 4 corre" \
    "$(printf '%s' "$saida" | grep -c CORPO_DA_ETAPA_4)" "1"
conferir "e nao imprime PULADA" \
    "$(printf '%s' "$saida" | grep -c PULADA)" "0"

# ---- 2b. A ETAPA 5 e o unico lugar onde a caracterizacao roda ----------
#
# Ela exige modo texto: com compositor vivo a faixa entre execucoes fica
# ilegivel, e o numero PARECERIA valido -- foi o que aconteceu em 27/09/2026,
# quando uma execucao perturbada em dez levou a faixa de `lock, best case` a
# 84%. Pular e declarar e a resposta certa; medir assim nao e.
guarda5=$(recorte_bloco 'ETAPA 5/5' 'if [ "$SO_RUIDO" -eq 1 ] || [ "$SO_HARDWARE" -eq 1 ]; then')
[ -n "$guarda5" ] || { echo "  FALHOU: nao recortei a guarda da etapa 5"; falhas=$((falhas + 1)); }

executar5() { # <SO_RUIDO> <SO_HARDWARE> <MODO> -> o que a etapa 5 fez
    bash -c "SO_RUIDO=$1; SO_HARDWARE=$2; MODO='$3'; RECORTE='-'; graficos=2
marcar_incompleta() { echo MARCOU_INCOMPLETA; }
marcar_falha() { echo MARCOU_FALHA; }
LEIAUTE_REPETICOES=1; LEIAUTE_PROGRAMAS=x
cd \"\$(mktemp -d)\"; mkdir -p ferramental/qualidade
printf '#!/bin/sh\necho CARACTERIZOU\n' > ferramental/qualidade/caracterizar-leiaute.sh
chmod +x ferramental/qualidade/caracterizar-leiaute.sh
$guarda5" 2>&1
}
conferir "em modo texto e sem recorte, a caracterizacao roda" \
    "$(executar5 0 0 texto | grep -c CARACTERIZOU)" "1"
conferir "em modo grafico ela NAO roda" \
    "$(executar5 0 0 grafico | grep -c CARACTERIZOU)" "0"
# PULAR NAO E PASSAR: a coleta fica incompleta, e o historico precisa saber.
conferir "e o pulo por modo grafico marca a execucao como incompleta" \
    "$(executar5 0 0 grafico | grep -c MARCOU_INCOMPLETA)" "1"
conferir "--so-ruido pula a caracterizacao" \
    "$(executar5 1 0 texto | grep -c CARACTERIZOU)" "0"
conferir "--so-hardware pula a caracterizacao" \
    "$(executar5 0 1 texto | grep -c CARACTERIZOU)" "0"
# E O PULO POR RECORTE NAO E INCOMPLETUDE: foi escolha declarada.
conferir "pulo por recorte nao marca incompleta" \
    "$(executar5 1 0 texto | grep -c MARCOU_INCOMPLETA)" "0"

# ---- 3. SIGTERM TERMINA o fluxo -----------------------------------------
# O trap antigo restaurava o governor e devolvia o controle: `kill -TERM $$`
# nao parava nada, e uma campanha de horas seguia depois de o operador achar
# que a tinha interrompido.
traps=$(grep -E "^\s+trap " "$fonte" | sed 's/^[[:space:]]*//')
saida=$(bash -c "fixar_gov() { :; }; GOV_ANTES=powersave
limpar_governor() { echo LIMPOU; }
$traps
kill -TERM \$\$
echo CONTINUOU_APOS_TERM" 2>&1)
rc_term=0
bash -c "fixar_gov() { :; }; GOV_ANTES=powersave
limpar_governor() { :; }
$traps
kill -TERM \$\$
echo CONTINUOU_APOS_TERM" >/dev/null 2>&1 || rc_term=$?
conferir "SIGTERM nao deixa o fluxo continuar" \
    "$(printf '%s' "$saida" | grep -c CONTINUOU_APOS_TERM)" "0"
conferir "SIGTERM sai com 143" "$rc_term" "143"
conferir "e a limpeza do governor ainda acontece" \
    "$(printf '%s' "$saida" | grep -c LIMPOU)" "1"

# ---- 4. a etapa 4 confere o retorno de cada invocacao -------------------
# `rodar_bloco` promove o arquivo so quando a execucao termina bem. Antes, o
# redirecionamento criava a saida em qualquer caso, e como a completude e
# conferida por NOME, a coleta parecia intacta em disco.
bloco=$(recorte 'rodar_bloco() {' '    }')
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/falha" <<'P'
#!/bin/sh
echo FALHA_SINTETICA >&2
exit 42
P
cat > "$tmp/ok" <<'P'
#!/bin/sh
echo MEDIU
P
chmod +x "$tmp/falha" "$tmp/ok"

res=$(bash -c "DONO=\$(id -un); rc_final=0
sudo() { shift 3; \"\$@\"; }
$bloco
rodar_bloco '$tmp/saida-ruim.txt' '$tmp/falha'
echo \"rc_final=\$rc_final\"" 2>/dev/null)
conferir "invocacao que falha marca o agregado" \
    "$(printf '%s' "$res" | grep -c 'rc_final=1')" "1"
conferir "e o arquivo NAO e promovido" \
    "$([ -e "$tmp/saida-ruim.txt" ] && echo sim || echo nao)" "nao"
conferir "a saida fica no parcial, para diagnostico" \
    "$([ -s "$tmp/saida-ruim.txt.parcial" ] && echo sim || echo nao)" "sim"

res=$(bash -c "DONO=\$(id -un); rc_final=0
sudo() { shift 3; \"\$@\"; }
$bloco
rodar_bloco '$tmp/saida-boa.txt' '$tmp/ok'
echo \"rc_final=\$rc_final\"" 2>/dev/null)
conferir "invocacao boa nao marca o agregado" \
    "$(printf '%s' "$res" | grep -c 'rc_final=0')" "1"
conferir "e o arquivo E promovido" \
    "$([ -s "$tmp/saida-boa.txt" ] && echo sim || echo nao)" "sim"
conferir "sem deixar parcial para tras" \
    "$([ -e "$tmp/saida-boa.txt.parcial" ] && echo sim || echo nao)" "nao"

# ---- 5. o parsing aceita os dois recortes e recusa a contradicao --------
#
# `--so-hardware` nasceu em 26/09/2026 porque nao existia: rodar so a campanha
# de hardware exigia chamar `campanha.sh` direto, o que PULA a etapa 1 -- a
# recompilacao e a procedencia. O atalho foi usado, e a coleta que saiu dele
# nao e publicavel.
parsing=$(recorte_bloco 'SO_RUIDO=0' 'SO_RUIDO=0')
[ -n "$parsing" ] || { echo "  FALHOU: nao recortei o parsing"; falhas=$((falhas + 1)); }

analisar() { # <args...>  -> "<SO_RUIDO> <SO_HARDWARE> [<RECORTE>] <restante>"
    bash -c "uso() { :; }
$parsing
echo \"\$SO_RUIDO \$SO_HARDWARE [\$RECORTE] \$*\"" bash "$@" 2>/dev/null
}
conferir "sem flag, nenhum recorte"          "$(analisar cfg)"                "0 0 [] cfg"
conferir "--so-ruido marca o recorte"        "$(analisar --so-ruido cfg)"     "1 0 [--so-ruido] cfg"
conferir "--so-hardware marca o recorte"     "$(analisar --so-hardware cfg)"  "0 1 [--so-hardware] cfg"
conferir "e a configuracao sobrevive a flag" "$(analisar --so-hardware x-y)"  "0 1 [--so-hardware] x-y"

conferir "--so-leiaute marca o recorte"        "$(analisar --so-leiaute cfg)"   "0 0 [--so-leiaute] cfg"
for par in "--so-ruido --so-hardware" "--so-ruido --so-leiaute" "--so-hardware --so-leiaute"; do
    rc=0; analisar $par >/dev/null 2>&1 || rc=$?
    conferir "recortes juntos sao recusados ($par)" "$rc" "2"
done
rc=0; analisar --nao-existe >/dev/null 2>&1 || rc=$?
conferir "opcao desconhecida e recusada" "$rc" "2"

# ---- 6. a etapa 3 repassa o recorte para a campanha ---------------------
#
# COMPORTAMENTO, e nao texto: um stub no lugar da `campanha.sh` mostra os
# argumentos que ela REALMENTE recebe. Uma segunda lista de flags aqui --
# mantida a mao em sincronia com a do parsing -- e como o `--so-hardware`
# ficou de fora por um mes.
etapa3=$(recorte 'EXTRA="$RECORTE"' 'campanha.sh')
tmp3=$(mktemp -d)
mkdir -p "$tmp3/ferramental/qualidade"
cat > "$tmp3/ferramental/qualidade/campanha.sh" <<'P'
#!/bin/sh
printf '[%s]' "$@"; echo
P
chmod +x "$tmp3/ferramental/qualidade/campanha.sh"
repassa() { # <recorte> -> argumentos vistos pela campanha
    ( cd "$tmp3" && bash -c "MODO=texto; RECORTE='$1'; CARIMBO=2026-01-01-0000; CONFIG=cfg
$etapa3" 2>/dev/null )
}
conferir "sem recorte, a campanha nao recebe flag" \
    "$(repassa '')"              "[--texto][2026-01-01-0000-cfg]"
conferir "--so-ruido chega na campanha" \
    "$(repassa --so-ruido)"      "[--texto][--so-ruido][2026-01-01-0000-cfg]"
conferir "--so-hardware chega na campanha" \
    "$(repassa --so-hardware)"   "[--texto][--so-hardware][2026-01-01-0000-cfg]"
rm -rf "$tmp3"

# ---- 7. o epilogo nao contradiz o modo medido --------------------------
#
# Ele ensinava a "voltar ao modo grafico" e afirmava nao haver sessao grafica
# inibindo o desligamento -- com o compositor vivo e contado no cabecalho da
# mesma execucao. Nao muda numero; corrompe o registro da condicao, que e o
# que decide se duas coletas sao comparaveis.
epilogo=$(recorte_bloco 'O EPILOGO SO VALE EM MODO TEXTO' 'if [ "$MODO" = "texto" ]; then')
[ -n "$epilogo" ] || { echo "  FALHOU: nao recortei o epilogo"; falhas=$((falhas + 1)); }
conferir "em modo texto o epilogo aparece" \
    "$(bash -c "MODO=texto
$epilogo" 2>&1 | grep -c 'voltar ao modo grafico')" "1"
conferir "em modo grafico o epilogo NAO aparece" \
    "$(bash -c "MODO=grafico
$epilogo" 2>&1 | grep -c 'voltar ao modo grafico')" "0"

# ---- 7b. o MOTIVO sai no veredito, e nao so no stderr do momento -------
#
# Em 27/09/2026 uma execucao terminou com `run-all NAO CONCLUIDO` e nenhuma
# razao no registro: os marcadores escrevem em stderr, a narrativa vai para
# stdout, e quem capturou um dos dois recebeu o veredito sem a causa. Um
# relatorio que diz "algo falhou" e nao diz o que obriga a repetir uma
# execucao de horas para descobrir.
marcadores=$(awk '/^MOTIVOS=""/,/^}/' "$fonte")
vl=$(awk '/^veredito_linha\(\) \{/,/^\}/' "$fonte")
saida=$(bash -c "rc=1; rc_final=0
$marcadores
$vl
marcar_falha 'a caracterizacao saiu com erro'
veredito_linha" 2>/dev/null)
conferir "o motivo aparece no veredito, em stdout" \
    "$(printf '%s' "$saida" | grep -c 'a caracterizacao saiu com erro')" "1"
conferir "sob o rotulo que diz o que ele e" \
    "$(printf '%s' "$saida" | grep -c 'o que nao concluiu')" "1"
# E SEM MOTIVO NENHUM o veredito nao inventa cabecalho vazio.
saida=$(bash -c "rc=0; rc_final=0
$marcadores
$vl
veredito_linha" 2>/dev/null)
conferir "sem motivos, o veredito nao imprime o cabecalho" \
    "$(printf '%s' "$saida" | grep -c 'o que nao concluiu')" "0"

# ---- 8. o refresh do cache de memoria nao pode falhar CALADO ----------
#
# A linha era `--cachear-memoria >/dev/null 2>&1 && chown ...`. O `&&`
# curto-circuita, ninguem le o codigo, e o script segue com o cache ANTERIOR
# -- nomeando a coleta com a configuracao de memoria que a maquina tinha
# antes. E o erro que a derivacao do nome existe para impedir, e o portao de
# root logo acima o descreve: ele fecha a falta de privilegio, e `dmidecode`
# ausente produzia o mesmo desfecho passando por ele.
refresh=$(recorte_bloco 'O RESULTADO DO REFRESH E CONFERIDO' 'if ./scripts/ambiente.sh --cachear-memoria')
[ -n "$refresh" ] || { echo "  FALHOU: nao recortei o bloco do refresh"; falhas=$((falhas + 1)); }

tmpr=$(mktemp -d)
mkdir -p "$tmpr/scripts"
executar_refresh() { # <rc do ambiente.sh> <argumentos> -> saida e codigo
    printf '#!/bin/sh\nexit %s\n' "$1" > "$tmpr/scripts/ambiente.sh"
    chmod +x "$tmpr/scripts/ambiente.sh"
    shift
    ( cd "$tmpr" && bash -c "
$refresh
echo SEGUIU" bash "$@" 2>&1 )
}
# REFRESH OK: segue, com ou sem nome na linha de comando.
conferir "refresh bem-sucedido nao interrompe" \
    "$(executar_refresh 0 | grep -c SEGUIU)" "1"
# REFRESH FALHOU E O NOME VEM DELE: aborta, em vez de nomear com dado velho.
rc=0; executar_refresh 1 >/dev/null 2>&1 || rc=$?
conferir "refresh falho sem nome explicito aborta" "$rc" "1"
conferir "e diz que o nome sai do cache" \
    "$(executar_refresh 1 | grep -c 'nome da coleta')" "1"
conferir "e nao segue" \
    "$(executar_refresh 1 | grep -c SEGUIU)" "0"
# REFRESH FALHOU MAS O NOME VEIO DA LINHA: avisa e segue -- a derivacao nao e
# usada, e o portao do `campanha-hardware.sh` ainda confere o cache.
conferir "refresh falho COM nome explicito segue" \
    "$(executar_refresh 1 cfg-explicita | grep -c SEGUIU)" "1"
conferir "mas avisa" \
    "$(executar_refresh 1 cfg-explicita | grep -c AVISO)" "1"
rm -rf "$tmpr"

if [ "$falhas" -gt 0 ]; then
    echo "  $falhas assercao(oes) falharam"
    exit 1
fi
echo "  ok: $total assercoes; run-all so conclui se todas as etapas concluirem,"
echo "      e os tres recortes preservam a etapa 1 e o veredito unico"
