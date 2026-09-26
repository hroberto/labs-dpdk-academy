#!/usr/bin/env bash
# A campanha de medicao do projeto, nos dois ambientes que ela reconhece.
#
#   --texto    servidor ou console: EXIGE ausencia de sessao grafica
#   --grafico  maquina de trabalho: ACEITA sessao grafica, e declara o custo
#
# POR QUE OS DOIS, E NAO SO O PRIMEIRO
#
# Ate 24/09/2026 este script abortava se houvesse processo grafico vivo. A
# regra estava certa para o que ele media naquele dia -- a sessao grafica era o
# objeto do experimento -- e errada como porta de entrada do projeto: quem
# clona numa maquina de trabalho nao consegue rodar campanha nenhuma, e a
# alternativa que sobra e nao medir.
#
# O modo grafico nao e "o modo ruim". Ele e o modo em que a CPU chega quente e
# com relogio estavel, e em que os valores ABSOLUTOS sao mais confiaveis. O
# modo texto e o modo em que o jitter e menor e a cauda e limpa. Cada um mede
# melhor uma coisa, e a §7 da metodologia dos fundamentos diz qual usar para
# que grandeza.
#
# O que nenhum dos dois aceita e a condicao NAO DECLARADA. Por isso o modo e
# argumento obrigatorio, vai para o `ambiente.txt` da coleta, e o script recusa
# `--texto` com sessao grafica viva em vez de avisar e seguir.
#
# PRE-REGISTRO -- A GPU OU A SESSAO GRAFICA? (`amdgpu.pg_mask=0`)
#
# A §6.7 do topico de isolamento registra como aberta a pergunta que separa as
# duas atribuicoes. O rastro do `osnoise` nomeia
# `amdgpu_device_delay_enable_gfx_off` -- a reativacao do power gating -- e a
# intervencao de modo texto remove a sessao grafica INTEIRA, entao ela confirma
# "e alguma coisa da sessao" sem distinguir o que.
#
# `amdgpu.pg_mask=0` remove UMA das duas e mantem a outra: o power gating sai,
# o compositor, o servidor de display e o driver ficam.
#
#   HIPOTESE. O modo alto vem da reativacao do power gating do bloco GFX, nao
#   da sessao grafica por outro caminho.
#
#   PREVISAO, celula `sem-pg` (grafico, pg desligado). A funcao
#   `amdgpu_device_delay_enable_gfx_off` nao aparece no rastro do `osnoise`, e
#   a mediana da maior parada fica abaixo de 40 us -- faixa das coletas de modo
#   texto, nao os 24,9 a 515,5 us das coletas com sessao grafica.
#
#   REFUTADA SE. O modo alto persistir com frequencia comparavel a das coletas
#   com sessao grafica. Isso significaria que a sessao produz o efeito por um
#   caminho que nao passa pelo power gating, e o rastro que nomeou a funcao
#   estaria apontando para um sintoma, nao para a causa.
#
#   CONTROLE NEGATIVO, celula `sem-pg-texto` (texto, pg desligado). Sem sessao
#   grafica o power gating nao tem o que reativar, entao desliga-lo NAO PODE
#   mudar nada: a coleta tem de ficar indistinguivel de `2026-09-24-1917`. Se
#   mudar, o modelo esta errado, e nenhuma leitura da celula de cima vale.
#
#   O controle existe pela mesma razao que o `custo-comunicacao` existe no
#   pre-registro do segundo pente: um instrumento que responde onde deve e fica
#   quieto onde deve e a unica evidencia de que ele mede o que diz medir.
#
# As duas celulas correm com `--so-ruido`: os passos 3 a 6 medem custo, e
# nenhuma das duas perguntas e sobre custo.

# PRE-REGISTRO DE 24/09/2026 -- O GOVERNOR EM MODO TEXTO
#
# `custo-alocacao` e o unico programa do projeto que reporta a frequencia, e
# ele le duas vezes: antes da primeira coleta e depois da ultima. Em modo
# texto as seis repeticoes deram `4.33 -> 4.94..5.57 GHz`; em modo grafico,
# `5.56..5.61` estavel. A rampa acontece DENTRO da medicao.
#
# O efeito nao e uniforme: ele depende da POSICAO no programa. O `malloc`, que
# e medido primeiro, saiu 2,78 ns nas seis repeticoes de modo texto -- sempre
# no relogio frio. O `sem cache`, medido por ultimo, deu 13,42 ns quando a
# rampa parou em 4,95 GHz e 11,9 quando chegou a 5,57. Razao medida 1,13,
# razao dos relogios 1,125.
#
#   HIPOTESE. Em modo texto o clock e a variavel dominante dos valores
#   absolutos, porque nada aquece a CPU entre invocacoes e toda execucao e a
#   primeira apos ociosidade.
#
#   PREVISAO. Com `--fixar-governor`, `f0` e `f1` ficam a menos de 3% um do
#   outro nas seis repeticoes, e `sem cache` para de alternar entre 11,9 e
#   13,4.
#
#   REFUTADA SE. A rampa persistir com o governor em `performance`, ou se
#   `malloc` continuar em 2,78 -- o que significaria que a diferenca entre os
#   dois modos nao e de clock, e a hipotese esta errada.
#
#   O QUE ESTA EM JOGO. O `ambiente-medicao.sh` registra, de medicao propria,
#   que "fixar o governor ajuda pouco". Aquilo foi medido em modo grafico e
#   esta certo ali. Se a previsao acima se sustentar, aquela conclusao passa a
#   valer so para o modo em que foi feita, e o registro precisa dizer qual.
#
#   DESFECHO, APURADO EM 25/09/2026 SOBRE AS DEZ COLETAS ARQUIVADAS DO MODULO
#   03 -- quatro em `powersave` e seis em `performance`, cinco repeticoes cada.
#   A previsao acerta nos tres criterios que ela mesma fixou:
#
#     f0 contra f1        powersave  4,33 -> 4,89..5,58 GHz, ate 28,9% de
#                                    diferenca dentro da MESMA execucao
#                         performance  5,53..5,60, no maximo 0,7%
#                         -> previsto "menos de 3%"; deu 0,7%.
#
#     `malloc`            powersave  2,78 ns nas VINTE execucoes
#                         performance  2,18 a 2,20 nas TRINTA
#                         -> o criterio de refutacao era "continuar em 2,78".
#                            Nao continuou, e a separacao e perfeita.
#
#     `NO cache`          powersave  alternava 11,88 e 13,42
#                         performance  10,44 a 10,51, faixa de 0,1%
#                         -> previsto "para de alternar". Parou.
#
#   CONSEQUENCIA. A conclusao "fixar o governor ajuda pouco" passa a valer SO
#   para o modo grafico, e o `ambiente-medicao.sh` ja diz qual. E como a
#   intervencao decidiu, ela deixou de ser flag: fixar virou o padrao desta
#   campanha, com `--nao-fixar-governor` guardando a celula `powersave`.
#
# O EXPERIMENTO QUE ORIGINOU ESTE SCRIPT
#
# PRE-REGISTRO -- ESCRITO ANTES DA COLETA, E E POR ISSO QUE ESTE CABECALHO
# EXISTE
#
# O tracador `osnoise` nomeou a fonte da maior parada: a funcao
# `amdgpu_device_delay_enable_gfx_off`, numa workqueue por CPU, com 706 e
# 808 us em dois rastros independentes. O kernel registrou no journal que
# `dm_irq_work_func [amdgpu]` -- mesmo driver, outro trabalho -- chegou a
# passar de 10 000 us sete vezes.
#
# As duas funcoes existem porque ha uma GPU com sessao grafica. Em modo texto
# nao ha composicao, nao ha redesenho e o GFX nao entra e sai de power gating
# atras de trabalho que nao existe.
#
#   HIPOTESE. O modo alto da distribuicao (630-834 us) e produzido por trabalho
#   do driver amdgpu, e depende da sessao grafica estar ativa.
#
#   PREVISAO. Em modo texto, nenhuma das 20 celulas do stall_probe apresenta
#   maior parada acima de 200 us, e o histograma do osnoise nao registra
#   amostra acima de 200 us em dez minutos.
#
#   REFUTADA SE. O modo alto aparecer com frequencia comparavel a das coletas
#   com sessao grafica -- 9 em 60 celulas, ou 15% -- ou se o osnoise registrar
#   amostras de centenas de microssegundos.
#
# A SEGUNDA PERGUNTA, que corre de graca na mesma condicao
#
# Os dois instrumentos discordam por um fator de 5,6 com sessao grafica: o
# osnoise preve 84% de celulas com evento acima de 35 us e o stall_probe
# observa 15%. Rodando os dois na MESMA condicao de modo texto, a discordancia
# ou persiste -- e e propriedade dos instrumentos -- ou desaparece junto com a
# fonte, e era propriedade da fonte.
#
# A TERCEIRA PERGUNTA: QUANTO O MODO TEXTO MOVE O QUE JA ESTA PUBLICADO
#
# A §6.7 do topico de isolamento declara como NAO MEDIDO quanto o modo texto
# desloca o que o `comparar-hardware.py` confronta -- 198 rotulos nos tres
# modulos, dos quais 56 entram na tabela de faixas de dispersao da §6 da
# metodologia. Enquanto isso nao for medido, o argumento de que "a mediana
# resiste" e expectativa.
#
# O PRE-REGISTRO ORIGINAL FOI RESPONDIDO, E POR ISSO FOI APOSENTADO.
#
# Ele previa que, confrontando modo texto contra a coleta de canal duplo COM
# SESSAO GRAFICA, no maximo 5 dos 198 rotulos se moveriam mais de 5%. Essa
# comparacao foi feita em 24/09, e o desfecho levou ao rebase de todas as
# coletas para modo texto. A coleta grafica que era o outro lado dela foi
# apagada, entao a previsao nao tem mais como ser avaliada -- nem precisa.
#
# O QUE O PASSO 6 COMPARA AGORA e outra coisa, e a pergunta mudou junto: a
# referencia passou a ser DERIVADA do disco (a campanha anterior que existe), e
# o confronto virou campanha contra campanha na MESMA condicao. Isso nao mede
# efeito de sessao grafica; mede REPRODUTIBILIDADE.
#
#   HIPOTESE. Duas campanhas na mesma condicao -- modo texto, mesmo hardware,
#   mesmo governor -- concordam nas medianas publicadas, porque o protocolo
#   removeu a fonte que as movia.
#
#   CALIBRACAO, e ela vem ANTES da previsao de proposito. Entre as duas
#   campanhas em modo texto ja existentes -- 24/09 e 25/09 --, doze rotulos
#   passaram de 5%:
#
#     4  colunas `random` do `efeito-cache`, de -31% a -47%. Sao a correcao do
#        acumulador `volatile` em 0907f57: mudanca de CODIGO, explicada.
#     2  travessia local do `custo-comunicacao`, +7,2% e -6,8%. A §4.2 declara
#        esse rotulo como o de maior dispersao do modulo.
#     4  `DIFFERENCE attributable to translation` nas regioes pequenas. Ver a
#        limitacao do limiar, abaixo: sao artefato, nao movimento.
#     2  `custo-traducao.regiao32mb`, +5,6% e +15,0%.
#
#   PREVISAO. No maximo 8 rotulos nao explicados por mudanca de codigo recebem
#   a marca.
#
#   O NUMERO 8 E O OBSERVADO, E ISSO PRECISA ESTAR DITO. Ele nao foi escolhido
#   por ser folgado: e exatamente quantos apareceram no unico par de campanhas
#   comparaveis que existe. Uma previsao calibrada no proprio dado que a
#   testaria nao seria previsao -- seria descricao. Por isso ela vale a partir
#   da PROXIMA campanha, e esta e a primeira vez que ela corre sem conhecer o
#   resultado.
#
#   REFUTADA SE. Mais de 8 rotulos NAO EXPLICADOS por mudanca de codigo
#   receberem a marca. Nesse caso a hipotese de que o protocolo de modo texto
#   estabilizou as medianas nao se sustenta, e o que sobra e descobrir o que
#   ainda se move.
#
#   DESFECHO, E POR QUE ELE NAO DECIDE NADA. A previsao correu tres vezes e
#   saiu REFUTADA nas tres -- 10 rotulos na campanha de 26/09. So que o numero
#   8 e a contagem de uma REGUA que media errado, e isso foi apurado depois:
#   das 95 grandezas com cinco coletas ou mais, 40 ja variam mais de 5% entre
#   coletas em que nada mudou. A marca fixa acusava 8 rotulos na mediana entre
#   dois pares de texto do MESMO hardware -- ou seja, o valor previsto era o
#   ruido da propria regua, e a previsao nunca teve como se sustentar.
#
#   Previsao calibrada em instrumento defeituoso nao e refutada nem sustentada:
#   e sem efeito. Ela fica registrada porque foi feita, e o que a substitui
#   esta abaixo.
#
# PRE-REGISTRO DE 26/09/2026 -- A REGUA NOVA
#
#   O `comparar-hardware.py` passou a marcar quando o passo excede DUAS VEZES a
#   amplitude historica do proprio rotulo, medida sobre as coletas irmas de
#   mesma configuracao e mesma condicao de sessao. Rotulo sem irmas suficientes
#   nao recebe marca e entra na contagem `SEM REGUA`.
#
#   CALIBRACAO, declarada: nos dez pares de coletas expo6000 de modo texto a
#   regra nova da mediana de 1 marca, faixa de 0 a 2 -- contra 8 da regra fixa.
#   E na unica comparacao com efeito real conhecido (texto contra sessao
#   grafica, 26/09) ela marca as duas grandezas que o teste de postos da §7.2
#   da metodologia do modulo 01 identificou, que a regra fixa NAO marcava.
#
#   PREVISAO. No maximo 3 rotulos nao explicados por mudanca de codigo recebem
#   a marca numa campanha de texto contra texto do mesmo hardware.
#
#   O NUMERO 3 VEM DA CALIBRACAO, e nao de folga: e a mediana 1 mais a margem
#   ate o maior par observado, 2. Como o 8 de antes, ele foi tirado do dado que
#   existe -- e como antes, ele vale a partir da PROXIMA campanha, porque
#   previsao avaliada no proprio dado que a calibrou e descricao.
#
#   REFUTADA SE. Mais de 3 rotulos nao explicados receberem a marca num par
#   texto-texto de mesma configuracao. Contra coleta de OUTRA condicao ou de
#   outro hardware a previsao nao se aplica: ali a marca mede a diferenca que
#   se foi buscar.
#
# UMA LIMITACAO DO LIMIAR, DECLARADA PORQUE ELA JA DISPAROU.
#
# `abs(d) > 5%` e relativo, e a `DIFFERENCE attributable to translation` e uma
# DIFERENCA entre duas medidas -- perto de zero nas regioes pequenas. Entre as
# duas campanhas ela foi de 0,008 para 0,013 ns e recebeu +62%: um passo
# ABSOLUTO de 0,005 ns, abaixo de qualquer resolucao que este projeto reivindica.
#
# Marca relativa sobre grandeza proxima de zero nao informa nada, e os quatro
# rotulos de `seq*` que aparecem na lista sao esse artefato. Quem ler a saida
# precisa olhar a coluna dos valores, e nao so a marca.
#
# A campanha de mempool-cache tambem corre aqui, e nao por completude: as
# contagens de ida ao anel foram coletadas com sessao grafica e o tempo foi
# coletado sem ela. A regressao da §1.4 do modulo 03 cruza as duas, e cruzar
# condicoes diferentes e exatamente o defeito que este script existe para
# eliminar.
#
# POR QUE MODO TEXTO E NAO `systemctl isolate multi-user.target`
#
# Parar a sessao grafica sem reiniciar deixa o driver carregado e o estado
# acumulado. Reiniciar em multi-user zera as duas coisas, e o custo e o mesmo
# reboot que a maquina ja leva para qualquer mudanca de linha de boot.
#
# COMO USAR
#
#   1. sudo systemctl set-default multi-user.target
#   2. systemctl reboot -i        (sem sudo -- ver a nota abaixo)
#
# DOIS COMANDOS, E SO O PRIMEIRO LEVA `sudo`.
#
#   sudo grub-reboot modo-texto     escreve em /boot/grub/grubenv, que e de
#                                   root -- este exige privilegio
#   systemctl reboot -i             SEM sudo, como o usuario da sessao
#
# POR QUE O SEGUNDO NAO LEVA SUDO. Com a sessao grafica aberta, `reboot` recusa:
#
#   Operation inhibited by "henrique" (PID ... "gnome-session-s"),
#   reason is "user session inhibited".
#
# O `-i` ignora inibidores, e a politica do polkit decide quem pode usa-lo:
#
#   org.freedesktop.login1.reboot                 implicit active: yes
#   org.freedesktop.login1.reboot-ignore-inhibit  implicit active: auth_admin_keep
#
# "active" e a sessao local em uso -- `loginctl show-session -p Active` diz
# `yes`. Dela, o desktop abre o dialogo de senha e o reinicio acontece. Sob
# `sudo` o terminal nao tem agente de polkit para abrir esse dialogo.
#
# O `-i` e seguro neste protocolo: a maquina esta dedicada a medicao por
# decisao, nao ha sessao de trabalho a preservar, e o proprio protocolo exige
# que nada mais esteja rodando. Vale saber quem inibe -- `systemd-inhibit
# --list`; num desktop tipico sao o gnome-shell, o unattended-upgrades e o
# editor aberto.
#   3. entrar no console e rodar, NOMEANDO a configuracao medida:
#        sudo ferramental/qualidade/campanha.sh 2026-09-24-expo6000-canal-duplo-texto
#
#      Para comparar dois perfis de memoria, a segunda coleta so precisa do
#      passo de hardware -- os passos 1 a 4 nao dependem da BIOS:
#        sudo ferramental/qualidade/campanha.sh --so-hardware \
#             2026-09-24-jedec4800-canal-duplo-texto
#   4. ao terminar, JA EM MODO TEXTO:
#        sudo systemctl set-default graphical.target && sudo reboot
#
#      Aqui o `-i` nao faz falta: nao ha sessao grafica para inibir o
#      desligamento. Ele so e preciso no passo 2, que sai DE um desktop.
#      Ja o `set-default` e necessario nos dois sentidos, porque e
#      persistente -- diferente do `grub-reboot` do `run-all.sh`, que vale
#      para um boot so.
#
# O passo 4 esta impresso no fim da execucao, para nao depender de memoria.
set -u

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"

# `--continuar` retoma uma coleta parcial em vez de exigir tudo de novo. Ele
# existe porque a primeira execucao perdeu os passos 2 e 3 por falta de
# permissao, e repetir os dez minutos de osnoise que JA deram certo seria
# desperdicio -- e tentacao para encurtar o protocolo da proxima vez.
CONTINUAR=0
SO_HARDWARE=0
SO_RUIDO=0
# GOVERNOR FIXO E O PADRAO desde 25/09/2026, e a opcao agora e para DESLIGAR.
# A justificativa esta no bloco comentado mais abaixo, junto do codigo que o
# fixa.
FIXAR_GOV=1
MODO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --texto)        MODO=texto; shift ;;
        --grafico)      MODO=grafico; shift ;;
        --continuar)    CONTINUAR=1; shift ;;
        --so-hardware)  SO_HARDWARE=1; shift ;;
        --so-ruido)     SO_RUIDO=1; shift ;;
        # Aceita e ignora: era a forma de LIGAR quando o padrao era nao fixar,
        # e as chamadas que a passam continuam corretas.
        --fixar-governor) FIXAR_GOV=1; shift ;;
        --nao-fixar-governor) FIXAR_GOV=0; shift ;;
        -*) echo "opcao desconhecida: $1" >&2; exit 2 ;;
        *)  break ;;
    esac
done
# O MODO E OBRIGATORIO, e nao tem padrao de proposito. Um padrao faria a
# condicao ser herdada em vez de declarada, e condicao herdada e o defeito que
# este projeto passou o mes inteiro corrigindo.
if [ -z "$MODO" ]; then
    echo "uso: $0 --texto|--grafico [--continuar]" >&2
    echo "         [--so-hardware | --so-ruido] [--nao-fixar-governor] <configuracao>" >&2
    echo >&2
    echo "  --texto    servidor ou console. Exige ausencia de sessao grafica." >&2
    echo "             Menor jitter; use para dispersao, p99 e cauda." >&2
    echo "  --grafico  maquina de trabalho. Aceita sessao grafica." >&2
    echo "             Relogio estavel; use para medianas e razoes." >&2
    echo >&2
    echo "  A §7 da metodologia dos fundamentos diz qual usar para que grandeza." >&2
    exit 2
fi

# O NOME DA CONFIGURACAO E ARGUMENTO, e nao derivado da data.
#
# A primeira versao fixava "<data>-modo-texto". Uma coleta com a memoria em
# JEDEC 4800 nasceria com o mesmo nome de uma em EXPO 6000, e o comparativo
# entre as duas pareceria nulo em vez de invalido -- exatamente o cenario que
# o portao do cache de memoria do `campanha-hardware.sh` existe para impedir.
# Quem mede duas configuracoes tem de poder nomea-las.
CONFIG="${1:-}"
if [ -z "$CONFIG" ]; then
    echo "uso: $0 [--continuar] [--so-hardware] <configuracao>" >&2
    echo "  exemplo: $0 2026-09-24-jedec4800-canal-duplo-texto" >&2
    echo "  a configuracao vira o nome da coleta nos quatro historicos," >&2
    echo "  com hora e minuto acrescentados: ...-texto-0812" >&2
    exit 2
fi

# CARIMBO `YYYY-MM-DD-HHMM` NA FRENTE DO NOME.
#
# Duas execucoes do mesmo dia colidiam no mesmo diretorio. Quem chegasse
# segundo ou abortava, ou -- pior -- gravava metade ao lado da metade da
# outra, com a data sugerindo que era tudo a mesma medicao. A data sozinha
# nao identifica uma coleta; identifica um dia.
#
# O carimbo vai na FRENTE, e nao no fim, porque e assim que `ls` devolve a
# ordem cronologica sem ninguem pedir. Com a hora no fim, duas coletas do
# mesmo dia apareciam juntas e fora de ordem entre si.
#
# ELE NAO E REAPLICADO se o nome ja vier carimbado. `run-all.sh` carimba uma
# vez e passa o nome inteiro para ca; carimbar de novo criaria um segundo
# horario no meio do nome -- e, pior, um horario DIFERENTE, porque a campanha
# comeca minutos depois das outras etapas. Uma execucao se partiria em dois
# nomes.
#
# `--continuar` tambem nao carimba: ele retoma coleta que ja tem nome, e gerar
# nome novo a cada tentativa seria o oposto de retomar.
ja_carimbado() {
    case "$1" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]-*) return 0 ;;
        *) return 1 ;;
    esac
}
if [ "$CONTINUAR" -eq 0 ] && ! ja_carimbado "$CONFIG"; then
    CONFIG="$(date +%Y-%m-%d-%H%M)-${CONFIG}"
fi
echo "==> coleta: $CONFIG"

SAIDA="$RAIZ/trilha/03-performance/03-isolamento-cpu/historico/$CONFIG"
if [ -e "$SAIDA" ] && [ "$CONTINUAR" -eq 0 ]; then
    echo "ABORTADO: $SAIDA ja existe -- nao sobrescrevo coleta."
    echo "          use --continuar para completar o que faltou."
    exit 1
fi

# --------------------------------------------------------------------------
# PORTAO 1: ROOT. O rtla exige, e falhar no meio da campanha desperdicaria os
# minutos ja gastos.
# --------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { echo "FALHA: rode com sudo (o rtla exige root)."; exit 1; }

# O VEREDITO DA CAMPANHA PRECISA DE CONTADOR, e ate 26/09/2026 nao tinha.
#
# Cada passo dizia `&& echo ok || echo FALHA`, e o `||` CONSOME o codigo de
# saida: o passo falhava, a mensagem saia, e o script seguia ate o `exit 0`.
# Uma campanha com o osnoise e o isolamento falhados -- os dois bracos que
# medem ruido -- imprimia "CONCLUIDA" e o `run-all.sh` reportava `rc=0`.
#
# E o mesmo defeito que este repositorio ja pagou nos testes: PULO nao e verde,
# e FALHA consumida e pior que PULO. Agora sao tres estados, e so um deles
# permite dizer que a campanha esta completa.
#
#   FALHAS   o passo correu e falhou
#   PULOS    o pre-requisito nao existe -- campanha INCOMPLETA, nao completa
#   pulo pedido por flag (--so-ruido, --so-hardware) nao conta: foi escolha.
FALHAS=0
PULOS=0
falhou()  { echo "    FALHA${1:+ $1}"; FALHAS=$((FALHAS + 1)); }
pulou()   { echo "    PULADO: $1"; PULOS=$((PULOS + 1)); }
# O VEREDITO SAI NO CODIGO DE SAIDA, e nao so na tela. Quem le o diario ve as
# linhas de FALHA; quem automatiza le o `$?`, e ate aqui os dois discordavam --
# era o `$?` que decidia se a coleta entrava no historico como completa.
veredito() {
    echo
    if [ "$FALHAS" -gt 0 ]; then
        echo "==> CAMPANHA COM FALHA: $FALHAS passo(s) correram e falharam" \
             "${PULOS:+e $PULOS pulado(s) por pre-requisito}"
        echo "    A coleta em ${SAIDA#$RAIZ/} NAO esta completa."
        exit 1
    fi
    if [ "$PULOS" -gt 0 ]; then
        echo "==> CAMPANHA INCOMPLETA: $PULOS passo(s) pulado(s) por pre-requisito ausente"
        echo "    Nao e falha de medicao, e tambem nao e campanha completa: os"
        echo "    bracos pulados nao foram medidos, e o historico precisa saber."
        exit 2
    fi
    echo "==> CAMPANHA COMPLETA: nenhum passo falhou nem foi pulado por falta de pre-requisito"
    exit 0
}
DONO=${SUDO_USER:-$(logname 2>/dev/null || echo root)}
id "$DONO" >/dev/null 2>&1 || { echo "FALHA: nao identifiquei o usuario dono ($DONO)"; exit 1; }
# O `-H` NAO E OPCIONAL nas chamadas abaixo: sem ele o sudo mantem HOME=/root, e
# `preparar-dpdk.sh --conferir` procura os prefixos em $HOME/opt. A conferencia
# falharia por caminho, nao por conteudo, e a mensagem apontaria para o lugar
# errado -- no meio de uma campanha que ninguem esta olhando.

# --------------------------------------------------------------------------
# PORTAO 2: MODO TEXTO DE VERDADE.
#
# "Rodei em modo texto" precisa ser CONFERIDO, nao declarado -- e a mesma regra
# que este projeto aplica a hugepage, a coleta e ao prefixo do DPDK. Um console
# aberto sobre uma sessao grafica ainda viva mediria a condicao errada e o
# resultado pareceria valido.
# --------------------------------------------------------------------------
# ALVO PADRAO NAO E ALVO EM EXECUCAO, e confundir os dois engana quem le a
# coleta depois. `systemctl get-default` devolve o que a maquina usa NO
# PROXIMO boot; um boot unico por `grub-reboot modo-texto` nao o altera. A
# coleta 2026-09-25-1720 e exatamente esse caso: gravou `graphical.target` e
# correu sem sessao grafica nenhuma, e quem a lesse pelo alvo a classificaria
# errado. Por isso os dois campos ficam, com o nome do que cada um e.
alvo_padrao=$(systemctl get-default 2>/dev/null)
alvo_ativo=$(systemctl is-active graphical.target 2>/dev/null)
alvo_ativo=${alvo_ativo:-desconhecido}
# `pgrep -c` imprime "0" E sai com 1 quando nao acha nada; um `|| echo 0`
# somaria um segundo "0" e o teste inteiro abaixo quebraria.
graficos=$(pgrep -c -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" 2>/dev/null)
graficos=${graficos:-0}
echo "==> conferindo a condicao"
echo "    alvo padrao do systemd : $alvo_padrao"
echo "    graphical.target ativo : $alvo_ativo"
echo "    processos graficos     : $graficos"
# O PORTAO E ASSIMETRICO DE PROPOSITO.
#
# `--texto` RECUSA sessao grafica: a condicao e o objeto da medicao, e medir
# com ela viva daria um resultado que pareceria valido. `--grafico` ACEITA
# qualquer estado -- inclusive a ausencia de sessao grafica, que e so uma
# maquina de trabalho ociosa -- porque ali a condicao nao e a hipotese.
#
# O que os dois fazem igual e GRAVAR o que encontraram. Coleta cuja condicao
# nao esta no arquivo nao e comparavel com nenhuma outra.
if [ "$MODO" = "texto" ] && [ "$graficos" -ne 0 ]; then
    echo "FALHA: --texto exige ausencia de sessao grafica, e ha $graficos processo(s) vivo(s)."
    pgrep -a -x "Xorg|Xwayland|gnome-shell|kwin_wayland|sway" | sed 's/^/           /'
    echo "       Reinicie em multi-user.target, ou meca com --grafico."
    exit 1
fi
if [ "$MODO" = "texto" ]; then
    case "$alvo_padrao" in
        multi-user.target) ;;
        *) echo "AVISO: alvo padrao e '$alvo_padrao', nao multi-user.target."
           echo "       Sem processo grafico vivo a condicao vale, mas o proximo"
           echo "       boot volta ao grafico. Seguindo." ;;
    esac
else
    echo "    modo grafico: $graficos processo(s) grafico(s) durante a medicao"
    if [ "$graficos" -eq 0 ]; then
        echo "    NOTA: nenhum processo grafico vivo. A coleta vale, e e equivalente"
        echo "          a --texto; o rotulo do modo continua sendo o declarado."
    fi
fi

mkdir -p "$SAIDA"
# O DIRETORIO PRECISA PERTENCER AO DONO, e esta linha custou uma coleta.
#
# O script roda como root e cria a saida como root; as campanhas rodam como o
# DONO, via `sudo -u`, e fazem `mkdir` dentro dela. Sem o chown, as duas
# falham com "Permission denied" DEPOIS dos dez minutos do osnoise -- que e o
# pior momento possivel para descobrir.
chown -R "$DONO" "$SAIDA"
# --------------------------------------------------------------------------
# GOVERNOR FIXO, E POR QUE ELE DEIXOU DE SER FLAG E VIROU PADRAO.
#
# O `ambiente-medicao.sh` registrava, de medicao propria, que "fixar o governor
# ajuda pouco; DESCARTAR A PRIMEIRA EXECUCAO ajuda muito". Aquilo foi medido em
# modo grafico, onde o compositor mantem a CPU quente e so a primeira execucao
# apos ociosidade e fria.
#
# Em modo texto nada aquece a CPU, entao TODA execucao e a primeira apos
# ociosidade, e o descarte nao alcanca o problema. A previsao era que ali o
# governor deixasse de "ajudar pouco" e passasse a ser a variavel dominante.
# Ela foi registrada ANTES de medir, e esta e a flag que a testou: uma celula
# com ela, outra sem, o resto identico.
#
# A PREVISAO SE CONFIRMOU, e com separacao perfeita. Nas coletas arquivadas do
# modulo 03, o `malloc/free`:
#
#   powersave     4 coletas, 20 execucoes:  2,78 ns em TODAS as 20
#   performance   6 coletas, 30 execucoes:  2,18 a 2,20 ns
#
# Sao 27% de diferenca sem uma unica sobreposicao em 50 execucoes. E nao e so
# o `malloc`: comparando a coleta grafica de 23/09 com as de texto, por teste
# de postos, cinco grandezas ficam MAIORES em texto sob `powersave` --
# `atomic seq_cst` +8,0%, `atomic relaxed` +2,6%, `mutex lock+unlock` +0,9% --
# e NENHUMA fica maior sob `performance`.
#
# Intervencao de variavel unica existe para decidir, e esta decidiu. Manter a
# flag desligada por padrao seria deixar a condicao pior como a herdada, que e
# o defeito que este projeto passou o mes corrigindo. O padrao inverteu; a
# opcao `--nao-fixar-governor` continua existindo para que a celula
# `powersave` siga reproduzivel.
GOV_ANTERIOR=""
restaurar_governor() {
    [ -n "$GOV_ANTERIOR" ] || return 0
    for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        echo "$GOV_ANTERIOR" > "$c" 2>/dev/null || :
    done
    echo "==> governor restaurado para $GOV_ANTERIOR"
    GOV_ANTERIOR=""
}
# A restauracao vai no trap, nao no fim do script: campanha interrompida no
# meio deixaria a maquina com o governor trocado, e a proxima medicao herdaria
# uma condicao que ninguem declarou.
trap restaurar_governor EXIT INT TERM
if [ "$FIXAR_GOV" -eq 1 ]; then
    GOV_ANTERIOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    if [ -z "$GOV_ANTERIOR" ]; then
        echo "FALHA: nao li o governor atual; nao troco o que nao sei restaurar." >&2
        exit 1
    fi
    for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        echo performance > "$c" 2>/dev/null || :
    done
    agora=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    if [ "$agora" != "performance" ]; then
        echo "FALHA: pedi performance e o governor ficou '$agora'." >&2
        exit 1
    fi
    echo "==> governor: $GOV_ANTERIOR -> performance (restaurado no fim)"
fi

exec > >(tee -a "$SAIDA/diario.txt") 2>&1
echo "==> campanha em modo texto  $(date -Is)"
# CAMINHO RELATIVO, e o motivo nao e estetica. O diario e versionado e o
# repositorio e publico: um caminho absoluto carrega o nome de usuario da
# maquina de quem mediu, que e a mesma classe de vazamento que o
# `verificar-identidade.py` existe para impedir na historia do git.
echo "    saida: ${SAIDA#$RAIZ/}"

# --------------------------------------------------------------------------
# PROCEDENCIA. O que descreve a maquina vai para o arquivo ANTES de medir: se
# a campanha morrer no meio, o que ja se sabe fica registrado.
# --------------------------------------------------------------------------
{
    echo "modo declarado   : $MODO"
    echo "governor fixado  : $([ "$FIXAR_GOV" -eq 1 ] && echo "sim (era $GOV_ANTERIOR)" || echo nao)"
    echo "alvo padrao      : $alvo_padrao"
    echo "graphical ativo  : $alvo_ativo"
    echo "processos grafico: $graficos"
    echo "governor cpu2    : $(cat /sys/devices/system/cpu/cpu2/cpufreq/scaling_governor 2>/dev/null)"
    echo "C3 disable cpu2  : $(cat /sys/devices/system/cpu/cpu2/cpuidle/state3/disable 2>/dev/null)"
    echo "cmdline          : $(cat /proc/cmdline)"
    echo "kernel           : $(uname -r)"
    echo "uptime           : $(uptime -p)"
    awk '/^MemAvailable:|^SwapTotal:|^SwapFree:/{a[$1]=$2}
         END{printf "memoria          : avail %.2f GiB, swap em uso %.2f GiB\n",
             a["MemAvailable:"]/1048576,(a["SwapTotal:"]-a["SwapFree:"])/1048576}' /proc/meminfo
    echo "carga            : $(cut -d' ' -f1-3 /proc/loadavg)"
} > "$SAIDA/ambiente.txt"
sed 's/^/    /' "$SAIDA/ambiente.txt"

# --------------------------------------------------------------------------
# OS PASSOS 1 A 4 MEDEM RUIDO E MEMPOOL, e nenhum deles depende do perfil de
# memoria da BIOS. Numa coleta cujo objetivo e comparar 4800 contra 6000 eles
# consomem a maior parte do tempo sem responder a pergunta -- dai
# `--so-hardware`. A condicao de modo texto ja foi conferida acima, e vale
# igual para os dois caminhos.
# --------------------------------------------------------------------------
if [ "$SO_HARDWARE" -eq 1 ]; then
    echo
    echo "==> passos 1 a 4 PULADOS (--so-hardware): nao dependem do perfil de memoria"
else

# --------------------------------------------------------------------------
# 1. osnoise: histograma de dez minutos. Nao para no primeiro evento, entao
#    da a DISTRIBUICAO -- que e o que responde a previsao.
# --------------------------------------------------------------------------
echo
echo "==> 1/6 osnoise hist, 10 min na CPU 2  ($(date +%T))"
if [ -s "$SAIDA/osnoise-hist.txt" ] && grep -q "^count:" "$SAIDA/osnoise-hist.txt"; then
    echo "    JA COLETADO nesta saida; preservando."
    grep -E "^(over|count|min|avg|max):" "$SAIDA/osnoise-hist.txt" | sed 's/^/    /'
elif command -v rtla >/dev/null; then
    rtla osnoise hist -c 2 -d 10m -T 1 > "$SAIDA/osnoise-hist.txt" 2>&1 \
        && echo "    ok" || falhou "(saida em osnoise-hist.txt)"
    grep -E "^(over|count|min|avg|max):" "$SAIDA/osnoise-hist.txt" | sed 's/^/    /'
else
    echo "PULADO: rtla ausente" > "$SAIDA/osnoise-hist.txt"
    pulou "rtla ausente"
fi

# --------------------------------------------------------------------------
# 2. stall_probe: as mesmas quatro celulas x cinco repeticoes das oito coletas
#    anteriores. Roda como o DONO, nao como root: as coletas arquivadas foram
#    feitas assim, e privilegio muda o que o escalonador faz com a thread.
# --------------------------------------------------------------------------
echo
echo "==> 2/6 campanha de isolamento, 4 celulas x 5 repeticoes  ($(date +%T))"
if [ -x build/trilha/03-performance/03-isolamento-cpu/stall_probe ]; then
    sudo -u "$DONO" -H ./ferramental/qualidade/campanha-isolamento.sh "$SAIDA/isolamento" 5 \
        && echo "    ok" || falhou
else
    pulou "stall_probe ausente; rode scripts/build-all.sh antes"
fi

# --------------------------------------------------------------------------
# `--so-ruido` PARA AQUI, e o motivo e de desenho experimental.
#
# Os passos 1 e 2 medem RUIDO: quem toma a CPU da tarefa, e por quanto tempo.
# Os passos 3 a 6 medem CUSTO: quanto uma operacao leva. Uma intervencao sobre
# a fonte de ruido -- desligar o power gating da GPU, por exemplo -- precisa
# dos dois primeiros e nao e afetada pelos outros.
#
# Rodar os seis para responder uma pergunta dos dois primeiros custaria 55 min
# em vez de 20, e a diferenca vira desculpa para nao repetir o experimento.
if [ "$SO_RUIDO" -eq 1 ]; then
    echo
    echo "==> passos 3 a 6 PULADOS (--so-ruido)"
    echo
    echo "==> CONCLUIDA  $(date -Is)"
    echo "    saida: ${SAIDA#$RAIZ/}"
    # Os passos 3 a 6 foram pulados POR ESCOLHA e nao contam; os 1 e 2, que sao
    # o objeto deste modo, contam como em qualquer campanha.
    veredito
fi

# --------------------------------------------------------------------------
# 3. mempool-tempo: o elo miss x tempo, que espera maquina dedicada desde que
#    os prefixos sem estatisticas ficaram prontos. Modo texto e a condicao mais
#    dedicada que esta maquina alcanca, entao ele corre aqui.
# --------------------------------------------------------------------------
echo
echo "==> 3/6 campanha de tempo do mempool  ($(date +%T))"
if [ -x build-25.11-sem-stats/trilha/01-fundamentos/02-mempool-ring/pipeline_ring ]; then
    sudo -u "$DONO" -H ./ferramental/qualidade/campanha-mempool-tempo.sh "$SAIDA/mempool-tempo" 21 \
        && echo "    ok" || falhou
else
    pulou "binarios -sem-stats ausentes"
fi


# --------------------------------------------------------------------------
# 4. mempool-cache: as contagens de ida ao anel, na MESMA condicao do tempo.
#    A regressao da §1.4 do modulo 03 cruza contagem com tempo; ate aqui a
#    contagem vinha de coleta com sessao grafica e o tempo de coleta sem ela.
#    Cruzar condicoes e o defeito que este script existe para eliminar.
# --------------------------------------------------------------------------
echo
echo "==> 4/6 campanha de miss do mempool  ($(date +%T))"
if [ -x build-25.11/trilha/01-fundamentos/02-mempool-ring/pipeline_ring ]; then
    sudo -u "$DONO" -H ./ferramental/qualidade/campanha-mempool-cache.sh "$SAIDA/mempool-cache" 6 \
        && echo "    ok" || falhou
else
    pulou "binarios COM estatisticas ausentes"
fi

fi   # fim dos passos 1 a 4

# --------------------------------------------------------------------------
# 5. campanha de hardware: os dezenove programas dos tres modulos, que e o que
#    o `comparar-hardware.py` confronta. Sem este passo, o projeto continua
#    declarando como nao medido quanto o modo texto move o que ja publicou.
#
#    O PORTAO DO CACHE DE MEMORIA VEM ANTES, e a ordem importa: a campanha
#    aborta se o cache for anterior ao ultimo boot, e em modo texto SEMPRE e,
#    porque chegar aqui exigiu reiniciar. Descobrir isso depois dos passos
#    1 a 4 desperdicaria mais de uma hora.
# --------------------------------------------------------------------------
echo
echo "==> 5/6 campanha de hardware, 6 repeticoes dos tres modulos  ($(date +%T))"
CONF="$CONFIG"
# A COLETA DE REFERENCIA E DERIVADA DO DISCO, e nao digitada.
#
# Ela serve a dois passos: gabarito de completude aqui, e o outro lado da
# comparacao no passo 6.
#
# Estava fixa em `2026-09-23-expo6000-canal-duplo` -- uma coleta que o projeto
# APAGOU em 24/09 ao adotar o protocolo de modo texto. O efeito nao era um erro
# visivel: `completa()` passava a devolver "incompleta" sempre, e o passo 6
# imprimia "sem par para comparar". A campanha rodaria a hora inteira e
# entregaria a comparacao VAZIA -- que e o passo pelo qual ela existe.
#
# Agora e a coleta mais recente que EXISTE e que nao e a desta execucao. O
# carimbo `AAAA-MM-DD-HHMM` na frente do nome faz `sort` ordenar por tempo, que
# e a razao de ele vir na frente.
#
# A CONDICAO ENTRA NO CRITERIO desde 25/09/2026, quando a primeira coleta com
# sessao grafica viva foi arquivada. Comparar uma campanha de modo texto contra
# ela mede a DIFERENCA DE CONDICAO e chama isso de deriva: no passo 6 daquela
# noite a previsao saiu "REFUTADA" com dez rotulos acima de 5%, e os dez eram o
# par estar em condicoes diferentes. O `condicao_coleta.py` le a condicao do
# `ambiente.txt` de cada coleta, e so entram as do MESMO modo desta campanha.
REF=$(ls -d docs/01-fundamentos/medicoes/historico/*/ 2>/dev/null \
      | sed 's:.*/\([^/]*\)/$:\1:' \
      | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}' \
      | grep -v -- "-ambiente\$" | grep -v -- "-sonda\$" \
      | grep -vF "$CONF" \
      | while read -r c; do
            m=$(python3 ferramental/qualidade/condicao_coleta.py \
                    "docs/01-fundamentos/medicoes/historico/$c" 2>/dev/null \
                | awk '{print $2}')
            case "$m" in
                texto)   [ "$MODO" = "texto" ] && echo "$c" ;;
                grafico) [ "$MODO" = "grafico" ] && echo "$c" ;;
                # Nao declarado entra so na campanha de texto: toda coleta
                # anterior ao campo correu assim, e o portao daquela epoca ja
                # recusava sessao grafica em `--texto`.
                *)       [ "$MODO" = "texto" ] && echo "$c" ;;
            esac
        done \
      | sort | tail -1)
if [ -z "$REF" ]; then
    echo "    AVISO: nenhuma coleta anterior no historico; o passo 6 nao tera par."
else
    echo "    referencia para comparar: $REF"
fi
./scripts/ambiente.sh --cachear-memoria >/dev/null 2>&1 \
    && chown "$DONO" .ambiente-memoria 2>/dev/null

# A HUGEPAGE DO FEED, e por que ela precisa estar aqui.
#
# O par feed-primario/feed-secundario exige um hugetlbfs GRAVAVEL pelo dono.
# `/dev/hugepages` e root:root 755 nesta distribuicao, e a campanha desiste do
# feed em silencio quando `DPDK_ACADEMY_HUGE_DIR` nao esta definida -- um
# `return 0` no `corre_feed`. O resultado pareceria completo e teria doze
# arquivos a menos que a coleta de referencia, e a comparacao do passo 6
# perderia esses rotulos sem dizer que perdeu.
#
# O ponto de montagem e DESFEITO no fim: a decisao registrada e que a hugepage
# de teste nao vira recurso permanente da maquina.
# O preparador sai com sucesso em DOIS desfechos: `/dev/hugepages` ja era
# gravavel pelo dono, e entao ele nao monta nada; ou ele monta /mnt/huge-academia.
# A variavel precisa apontar para o que de fato existe -- apontar para um
# diretorio nao montado daria feed sem hugetlbfs, que falha tarde.
HUGE_PREPARADA=0
unset DPDK_ACADEMY_HUGE_DIR
DPDK_ACADEMY_USUARIO="$DONO" ./scripts/preparar-hugepages.sh >/dev/null 2>&1
# Testar a permissao COMO O DONO, nao como root: `test -w` sob root responde
# sempre que sim, e o preparador deste projeto ja documenta essa armadilha.
grava_como_dono() { # <caminho>
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$DONO" -- test -w "$1" 2>/dev/null
    else
        su -s /bin/sh -c "test -w '$1'" "$DONO" 2>/dev/null
    fi
}
if grava_como_dono /dev/hugepages; then
    export DPDK_ACADEMY_HUGE_DIR=/dev/hugepages
    echo "    hugepage do feed: /dev/hugepages (ja gravavel pelo dono)"
elif mountpoint -q /mnt/huge-academia 2>/dev/null \
     && grava_como_dono /mnt/huge-academia; then
    export DPDK_ACADEMY_HUGE_DIR=/mnt/huge-academia
    HUGE_PREPARADA=1
    echo "    hugepage do feed: /mnt/huge-academia (efemera, desmontada no fim)"
else
    echo "    AVISO: sem hugetlbfs gravavel pelo dono; o feed NAO sera coletado"
    echo "           a comparacao do passo 6 perdera os rotulos do feed"
fi

# COLETA INCOMPLETA NAO E COLETA, e distinguir as duas exige contar.
#
# `campanha-hardware.sh` recusa sobrescrever pasta existente -- e faz certo.
# Mas um guarda que so pergunta "a pasta existe?" trata uma campanha
# interrompida no meio como campanha pronta, e o passo 6 compararia contra
# coleta parcial relatando diferenca que e falta de arquivo. O gabarito e a
# propria coleta de referencia: se a nova nao tem o mesmo numero de arquivos
# nos tres modulos, ela nao esta pronta.
# CONTAR REPETICOES, NAO ARQUIVOS, e a diferenca custou uma coleta.
#
# A primeira versao comparava `ls | wc -l` contra a referencia. A referencia
# carrega um `diario.txt.tmp` que sobrou de uma execucao antiga e um
# `diario.txt` que o modo texto grava noutro lugar -- um arquivo de diferenca
# em cada modulo. Coleta completa era declarada INCOMPLETA por causa de lixo,
# e o passo 5 abortou uma campanha que devia ter rodado.
#
# O que constitui a medicao sao as saidas por repeticao, `*.r<N>.txt`. Contar
# so elas ignora diario, ambiente e qualquer residuo.
completa() { # <configuracao>  -> 0 se os tres modulos batem com a referencia
    local c="$1" m a b
    for m in 01-fundamentos 02-runtime-dpdk 03-mempool-ring-mbuf; do
        a=$(ls "docs/$m/medicoes/historico/$REF"/*.r[0-9]*.txt 2>/dev/null | wc -l)
        b=$(ls "docs/$m/medicoes/historico/$c"/*.r[0-9]*.txt   2>/dev/null | wc -l)
        [ "$a" -gt 0 ] || return 1
        [ "$b" -ge "$a" ] || return 1
    done
    return 0
}
if [ -d "docs/01-fundamentos/medicoes/historico/$CONF" ] && completa "$CONF"; then
    echo "    JA COLETADO em $CONF e completa; preservando."
elif [ -d "docs/01-fundamentos/medicoes/historico/$CONF" ]; then
    echo "    ABORTADO: $CONF existe e esta INCOMPLETA."
    for m in 01-fundamentos 02-runtime-dpdk 03-mempool-ring-mbuf; do
        printf "              %-22s %s de %s saidas de repeticao\n" "$m" \
            "$(ls docs/$m/medicoes/historico/$CONF/*.r[0-9]*.txt 2>/dev/null | wc -l)" \
            "$(ls docs/$m/medicoes/historico/$REF/*.r[0-9]*.txt  2>/dev/null | wc -l)"
    done
    echo "              A campanha de hardware nao sobrescreve. Para refazer:"
    echo "                rm -rf docs/*/medicoes/historico/$CONF"
    echo "              O passo 6 vai comparar contra coleta parcial; leia com isso em mente."
elif [ -x build/docs/01-fundamentos/medicoes/custo-syscall ]; then
    # `sudo -u` limpa o ambiente, entao a variavel vai explicita na chamada:
    # exportar no shell de root nao a faz chegar ao filho.
    sudo -u "$DONO" -H \
        DPDK_ACADEMY_HUGE_DIR="${DPDK_ACADEMY_HUGE_DIR:-}" \
        ./ferramental/qualidade/campanha-hardware.sh "$CONF" \
        && echo "    ok" || falhou
    # O feed some em silencio; conferir a contagem e o unico jeito de saber.
    nfeed=$(ls docs/02-runtime-dpdk/medicoes/historico/$CONF/feed-*.txt 2>/dev/null | wc -l)
    if [ "$nfeed" -eq 12 ]; then
        echo "    feed: 12 arquivos, completo"
    else
        echo "    AVISO: feed com $nfeed arquivos, esperados 12 -- a comparacao"
        echo "           do passo 6 perde esses rotulos"
    fi
else
    pulou "binarios dos modulos ausentes; rode scripts/build-all.sh"
fi

if [ "$HUGE_PREPARADA" -eq 1 ]; then
    ./scripts/preparar-hugepages.sh --desfazer >/dev/null 2>&1 \
        && echo "    hugepage do feed desmontada" \
        || echo "    AVISO: nao desmontei $DPDK_ACADEMY_HUGE_DIR"
fi

# --------------------------------------------------------------------------
# 6. A REVISAO. Coletar sem comparar deixaria a pergunta em aberto com os dados
#    na mao. Este passo confronta o que acabou de ser medido com a coleta de
#    referencia com sessao grafica, e roda o portao de qualidade inteiro --
#    que e quem sabe dizer se algum bloco publicado deixou de bater.
# --------------------------------------------------------------------------
echo
echo "==> 6/6 revisao dos dados do projeto  ($(date +%T))"
{
    for m in 01-fundamentos 02-runtime-dpdk 03-mempool-ring-mbuf; do
        a="docs/$m/medicoes/historico/$REF"
        b="docs/$m/medicoes/historico/$CONF"
        echo "--- $m ---"
        if [ -d "$a" ] && [ -d "$b" ]; then
            ./ferramental/qualidade/comparar-hardware.py "$a" "$b" 2>&1
        else
            echo "  sem par para comparar (falta $( [ -d "$a" ] || echo "$REF"; [ -d "$b" ] || echo "$CONF" ))"
        fi
    done
} > "$SAIDA/comparacao.txt" 2>&1
chown "$DONO" "$SAIDA/comparacao.txt" 2>/dev/null
marcados=$(grep -c '<<<' "$SAIDA/comparacao.txt" || true)
echo "    rotulos que se moveram mais de 5%: $marcados"
if [ "$marcados" -gt 0 ]; then
    grep '<<<' "$SAIDA/comparacao.txt" | sed 's/^/      /' | head -20
fi
# O PRE-REGISTRO E CONFERIDO AQUI, e nao na leitura posterior: previsao que so
# e avaliada depois vira interpretacao do resultado.
#
# O VEREDITO CONTA SO O QUE A PREVISAO COBRE. Ela fala dos rotulos NAO
# explicados por mudanca de codigo; jogar os explicados na mesma conta faria a
# campanha anunciar refutacao toda vez que um programa medido fosse corrigido
# -- e corrigir programa e o trabalho normal deste repositorio.
#
# A lista de exclusao vai NO ARQUIVO, e nao na cabeca de quem le: cada entrada
# nomeia o rotulo e o commit que o explica. Entrada sem explicacao escrita nao
# entra, porque ai a exclusao viraria a porta de saida do veredito.
EXPLICADOS_RE='efeito-cache: (L1d|L2|L3|RAM) random'
#   efeito-cache: * random -- acumulador `volatile` trocado por registrador em
#   0907f57. A cadeia store->load pela pilha limitava o paralelismo de memoria,
#   e removê-la move a coluna `random` de -31% a -47%. Esperado e documentado
#   na §4.2 do modulo 01.
explicados=$(grep '<<<' "$SAIDA/comparacao.txt" | grep -cE "$EXPLICADOS_RE" || true)
nao_explicados=$(( marcados - explicados ))
echo "    dos $marcados marcados, $explicados sao mudanca de codigo declarada"
if [ "$nao_explicados" -le 3 ]; then
    echo "    PREVISAO SUSTENTADA ($nao_explicados rotulo(s) nao explicado(s), <= 3)"
else
    echo "    PREVISAO REFUTADA ($nao_explicados nao explicados, previa-se no maximo 3)"
fi
grep -E "^  SEM REGUA:" "$SAIDA/comparacao.txt" | sed 's/^/    /' || true
grep -E "rotulo\(s\);" "$SAIDA/comparacao.txt" | sed 's/^/    /'
echo "    comparacao completa em ${SAIDA#$RAIZ/}/comparacao.txt"

echo
echo "    portao de qualidade:"
sudo -u "$DONO" -H ./ferramental/qualidade/pre-commit.sh > "$SAIDA/portao.txt" 2>&1
chown "$DONO" "$SAIDA/portao.txt" 2>/dev/null
grep -E "FALHA|aviso|tudo passou" "$SAIDA/portao.txt" | sed 's/^/      /'

echo
echo "==> CONCLUIDA  $(date -Is)"
echo
echo "    O que ficou em ${SAIDA#$RAIZ/}:"
echo "      ambiente.txt      estado da maquina antes de medir"
echo "      osnoise-hist.txt  distribuicao de ruido, dez minutos"
echo "      isolamento/       20 celulas do stall_probe"
echo "      mempool-tempo/    ns por pacote, prefixos sem estatisticas"
echo "      mempool-cache/    idas ao anel, mesma condicao do tempo"
echo "      comparacao.txt    o que se moveu contra a coleta com sessao grafica"
echo "      portao.txt        portao de qualidade completo"
echo
echo "    A campanha de hardware ficou nos historicos dos tres modulos,"
echo "    sob $CONF."
echo
echo "    Para voltar ao modo grafico:"
echo "      sudo systemctl set-default graphical.target && sudo reboot"
echo "      (aqui e modo texto: nao ha sessao grafica inibindo, entao -i nao"
echo "       faz falta. O set-default SIM: ele e persistente.)"

# --------------------------------------------------------------------------
# O VEREDITO, e ele sai no codigo de saida e nao so na tela.
#
# Quem le o diario ve as linhas de FALHA; quem automatiza le o `$?`. Ate aqui
# os dois discordavam, e o segundo e que decide se a coleta entra no historico
# como completa.
# --------------------------------------------------------------------------
veredito
