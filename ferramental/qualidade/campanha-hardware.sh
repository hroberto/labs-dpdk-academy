#!/usr/bin/env bash
# Campanha de medicao para UMA configuracao de hardware.
#
#   ./ferramental/qualidade/campanha-hardware.sh <nome-da-configuracao>
#
# Exemplo:  ... campanha-hardware.sh 2026-09-23-jedec4800-canal-unico
#
# POR QUE ESTE SCRIPT ESTA VERSIONADO
#
# O protocolo E parte do metodo. A primeira campanha rodou de um script solto
# em /tmp, que a limpeza do reboot apagou junto com os dados -- e um protocolo
# que nao sobrevive a um reboot nao e reproduzivel por definicao.
#
# O PORTAO DO CACHE, e ele existe por um cenario concreto
#
# Trocar um perfil de memoria na BIOS exige reiniciar. Se a campanha rodar sem
# que o cache do dmidecode seja refeito, o `ambiente.txt` do braco novo grava a
# velocidade ANTIGA -- e o braco fica rotulado errado, que e pior que nao ter
# rotulo: um comparativo entre "6000" e "6000" parece nulo em vez de invalido.
#
# Dai a regra: o cache tem de ser POSTERIOR ao ultimo boot. Mudou a BIOS,
# reiniciou, entao refaz o cache. A verificacao e de data, nao de conteudo,
# porque ela precisa pegar tambem o caso em que o valor por acaso coincide.
set -u
[ $# -eq 1 ] || { echo "uso: $0 <nome-da-configuracao>" >&2; exit 2; }
CONF="$1"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RAIZ"

BOOT=$(date -d "$(uptime -s)" +%s)
CACHE=$(stat -c %Y .ambiente-memoria 2>/dev/null || echo 0)
if [ "$CACHE" -lt "$BOOT" ]; then
    echo "ABORTADO: o cache de memoria e anterior ao ultimo boot." >&2
    echo "  cache: $([ "$CACHE" -gt 0 ] && date -d "@$CACHE" '+%F %T' || echo ausente)" >&2
    echo "  boot:  $(uptime -s)" >&2
    echo "Refaca antes de medir:  sudo ./scripts/ambiente.sh --cachear-memoria" >&2
    exit 1
fi

# POR QUE A CAMPANHA PASSOU A COBRIR OS TRES MODULOS
#
# Ate 20/09/2026 so os sete programas do modulo 01 eram arquivados. Os outros
# DOZE -- tres do proprio modulo 01 e todos os dos modulos 02 e 03 -- nao
# tinham NENHUMA coleta. Isso significa que um bloco publicado por eles nao
# tinha com o que ser comparado: nem entre execucoes, nem entre estados de
# maquina, nem entre configuracoes de hardware. O projeto media a dispersao de
# um terco dos seus instrumentos e publicava numeros dos outros dois tercos.
#
# Cada modulo guarda a propria coleta, sob o MESMO nome de configuracao, para
# que comparar-hardware.py seja chamado por modulo sem misturar rotulos de
# programas diferentes.
#
# AS INVOCACOES NAO SAO ESCOLHA DESTE SCRIPT
#
# Os argumentos de EAL abaixo sao os que os READMEs de cada modulo PUBLICAM
# como comando de reproducao. Medir com outros argumentos produziria um numero
# que o leitor nao consegue obter -- que e o defeito que este arquivo existe
# para impedir.
D="$RAIZ/docs/01-fundamentos/medicoes/historico/$CONF"
D2="$RAIZ/docs/02-runtime-dpdk/medicoes/historico/$CONF"
D3="$RAIZ/docs/03-mempool-ring-mbuf/medicoes/historico/$CONF"
for d in "$D" "$D2" "$D3"; do
    [ -e "$d" ] && { echo "ABORTADO: $d ja existe -- nao sobrescrevo coleta." >&2; exit 1; }
done
mkdir -p "$D" "$D2" "$D3"

# O ESTADO DE CADA MEDICAO SOBE, e nao morre no redirecionamento.
#
# Ate aqui as ~30 invocacoes deste arquivo eram chamadas soltas. O script roda
# sob `set -u` e NAO sob `set -e`, entao um programa que saia com erro nao
# interrompia nada, e a ultima linha imprimia CONCLUIDA com codigo 0.
#
# O CUSTO DISSO CRESCEU quando `custo-contencao` passou a recusar a amostra
# cujas condicoes nao ocorreram: o programa detecta o experimento invalido,
# devolve 1, este script ignora, `campanha.sh` le "ok" e a coleta entra no
# historico. Um instrumento novo nao vale nada se o orquestrador acima dele
# apaga o sinal.
#
# E O ARQUIVO SEMPRE EXISTE. `programa > saida.txt 2>&1` cria a saida mesmo
# quando o programa falha, entao a conferencia de completude por NOMES -- que
# e a que `campanha.sh` faz -- ve a celula presente e nao sabe que ela contem
# uma execucao reprovada. Presenca do artefato nao e sucesso da medicao, e o
# manifesto e o que separa as duas.
#
# `rodar` NAO propaga o erro pelo retorno de proposito: devolver nao-zero aqui
# abortaria a rodada no meio e perderia as celulas seguintes. A campanha vai
# ate o fim, registra o que aconteceu em cada uma, e o veredito sai no codigo
# de saida do processo.
# O FORMATO E CONTRATO, e nao registro de diario. Tres colunas, uma linha por
# celula, sem espaco dentro de CELL -- e o que permite ao `campanha.sh` ler o
# estado de uma celula sem interpretar prosa.
#
#   CELL                                     STATUS  RC
#   custo-syscall.r1.txt                     PASS    0
#   tlb-real.r1.txt                          SKIP    77
#   custo-contencao.r2.txt                   FAIL    1
MANIFESTO="$D/manifesto.txt"
{
    echo "# manifesto da coleta $CONF -- estado com que cada celula terminou"
    echo "# STATUS: PASS (mediu), SKIP (pre-requisito ausente), FAIL (correu e reprovou)"
    printf '%-40s %-7s %s\n' "CELL" "STATUS" "RC"
} > "$MANIFESTO"

rodar() { # <arquivo-de-saida> <comando...>
    local saida="$1"; shift
    "$@" > "$saida" 2>&1
    local rc=$? estado
    case "$rc" in
        0)  estado="PASS" ;;
        # 77 e PULADO em todo o projeto: pre-requisito ausente, nao defeito.
        77) estado="SKIP" ;;
        *)  estado="FAIL" ;;
    esac
    printf '%-40s %-7s %s\n' "$(basename "$saida")" "$estado" "$rc" >> "$MANIFESTO"
}

# O ESTADO SE CONTA NO MANIFESTO, e nao numa variavel que so este processo ve.
# Derivar de contador em memoria funcionaria igual aqui dentro, e deixaria o
# arquivo como relato paralelo -- dois lugares para a mesma verdade, e nada
# obrigando os dois a concordar. Quem le a coleta depois so tem o arquivo.
contar_estado() { # <PASS|SKIP|FAIL>
    awk -v e="$1" '$2 == e { n++ } END { print n + 0 }' "$MANIFESTO"
}
registrar() { # <celula> <STATUS> <rc>  -- para etapas que nao passam por rodar()
    printf '%-40s %-7s %s\n' "$1" "$2" "$3" >> "$MANIFESTO"
}

B=build-precommit/docs/01-fundamentos/medicoes
B2=build-precommit/docs/02-runtime-dpdk/medicoes
B3=build-precommit/docs/03-mempool-ring-mbuf/medicoes
ninja -C build-precommit >/dev/null 2>&1 || { echo "build falhou" >&2; exit 1; }
PROGS="custo-syscall custo-comunicacao custo-mckenney efeito-cache custo-espera custo-paralelismo custo-traducao orcamento-estourado rajada-nasdaq tlb-real"

# O PAR DO FEED EXIGE HUGETLBFS GRAVAVEL, e por isso e condicional.
#
# feed-primario/feed-secundario sao o unico caso do projeto que precisa de
# memoria compartilhada REAL: --in-memory desliga o suporte a secundario e
# --no-huge usa memoria anonima que o outro processo nao mapeia. Em muitas
# distribuicoes /dev/hugepages e root:root 755, e entao a coleta e impossivel
# sem privilegio.
#
# Prepare antes com:  sudo ./scripts/preparar-hugepages.sh
# e exporte DPDK_ACADEMY_HUGE_DIR. Sem a variavel a campanha segue sem o feed e
# DIZ isso no diario -- ausencia declarada e melhor que coleta invalida, mas
# silencio nao e nenhum dos dois.
#
# O supervisor pode precisar de mais de uma tentativa: o secundario recusa
# publicar veredito valido se qualquer amostra sair degenerada, e a sessao
# reinicia em nova geracao. Arquivamos a sessao que CONCLUIU.
corre_feed() { # <rodada>
    [ -n "${DPDK_ACADEMY_HUGE_DIR:-}" ] || return 0
    local t; t=$(mktemp -d)
    # O supervisor EXIGE que --output ainda nao exista (mkdir exist_ok=False), e
    # `mktemp -d` acabou de criar o diretorio. Dai o subdiretorio: passar "$t"
    # direto aborta em FileExistsError antes de qualquer medicao.
    python3 ./scripts/feed-supervisor.py --primary "$B2/feed-primario" \
        --secondary "$B2/feed-secundario" --huge-dir "$DPDK_ACADEMY_HUGE_DIR" \
        --output "$t/saida" --ticks 200000 >/dev/null 2>&1
    local d; d=$(ls -d "$t"/saida/session-* 2>/dev/null | tail -1)
    if [ -n "$d" ]; then
        cp "$d/secondary.txt" "$D2/feed-secundario.r$1.txt"
        cp "$d/primary.txt"   "$D2/feed-primario.r$1.txt"
        echo "  feed r$1: $(basename "$d")" >> "$D/diario.txt"
cat "$D/diario.txt.tmp" >> "$D/diario.txt" 2>/dev/null; rm -f "$D/diario.txt.tmp"
    else
        # FALHA, E NAO AVISO. Chegar aqui significa que havia hugetlbfs
        # gravavel -- a funcao retorna cedo quando nao ha -- e que mesmo assim
        # o supervisor nao produziu sessao. Hugetlbfs ausente e PULO, decidido
        # em `campanha.sh`; hugetlbfs presente e feed que nao saiu e outra
        # coisa: a coleta foi tentada e nao aconteceu.
        echo "  feed r$1: SEM SAIDA" >> "$D/diario.txt"
        registrar "feed.r$1" FAIL 1
    fi
    rm -rf "$t"
}
corre2() { # <rodada>
    rodar "$D2/custo-init.in-memory.r$1.txt" "$B2/custo-init"    -l 0 --in-memory
    rodar "$D2/custo-init.no-huge.r$1.txt" "$B2/custo-init"    -l 0 --no-huge
    # A VARREDURA DE CONFIGURACOES DA §2.1, que ate 25/09/2026 nao tinha
    # programa. A tabela estava no documento em Markdown, e tabela de prosa nao
    # e conferida pelo `verificar-blocos` -- que olha bloco de cerca. O
    # resultado: a §2 publicava 117,8 ms para `-l 0 --in-memory` e a §2.1
    # publicava 122,4 ms para a MESMA configuracao, no mesmo documento.
    #
    # O argumento da secao -- que o custo e piso fixo, e portanto espera e nao
    # trabalho -- depende de as quatro celulas concordarem entre si, e nao do
    # valor absoluto. Por isso as quatro correm na mesma rodada, aqui.
    rodar "$D2/custo-init.in-memory-no-pci.r$1.txt" "$B2/custo-init" -l 0 --in-memory --no-pci
    rodar "$D2/custo-init.no-huge-no-pci.r$1.txt" "$B2/custo-init" -l 0 --no-huge --in-memory --no-pci
    rodar "$D2/custo-init.4lcores.r$1.txt" "$B2/custo-init" -l 0-3 --in-memory
    rodar "$D2/estado-lcore.r$1.txt" "$B2/estado-lcore"  -l 0-3 --in-memory
    # A SEGUNDA INVOCACAO existe porque o documento publica as DUAS.
    #
    # Com `-l`, os lcores caem onde os numeros mandarem; com `--lcores`, o
    # mapeamento e escolhido, e a §4 do modulo 02 contrasta os dois blocos para
    # mostrar que a quarta coluna -- o core id -- nao muda. Sem arquivar a
    # segunda, esse bloco ficava sem procedencia e so se refazia a mao.
    rodar "$D2/estado-lcore.lcores.r$1.txt" "$B2/estado-lcore"  --lcores '"'"'0@6,1@7,2@18'"'"' --in-memory
}
corre3() { # <rodada>
    for n in custo-alocacao anatomia-mbuf custo-anel pool-esgotado; do
        rodar "$D3/$n.r$1.txt" "$B3/$n" -l 0 --no-huge --file-prefix="camp_${n}_$1"
    done
    # A MAQUINA INTEIRA, e nao seis lcores.
    #
    # `n` dobra ate `rte_lcore_count()`: com `-l 0-5` a tabela parava em 4
    # threads, e o cpp23 publicava uma linha de 8 que o ferramental NAO
    # CONSEGUIA PRODUZIR -- numero sem programa, que e o que este projeto
    # proibe. Com os 24 lcores ela vai a 16.
    #
    # Em modo texto nao ha com quem disputar, entao usar tudo e o que a
    # validacao pede. O custo e que as linhas passam a atravessar fronteiras --
    # CCD em n=8, SMT em n=16 --, e por isso o programa agora DECLARA qual
    # fronteira cada linha cruza, em vez de deixar a curva parecer funcao so do
    # numero de threads.
    rodar "$D3/custo-contencao.r$1.txt" "$B3/custo-contencao" -l 0-23 --no-huge --file-prefix="camp_cont_$1"
}

# O AMBIENTE NAO E ACESSORIO: `condicao_coleta.py` le dele se a coleta correu
# com sessao grafica, e uma coleta cuja condicao nao esta declarada contamina
# toda comparacao posterior.
rodar "$D/ambiente.txt" ./scripts/ambiente.sh
cp "$D/ambiente.txt" "$D2/ambiente.txt"; cp "$D/ambiente.txt" "$D3/ambiente.txt"
echo "feed: ${DPDK_ACADEMY_HUGE_DIR:-AUSENTE (par primario/secundario nao coletado)}" >> "$D/diario.txt.tmp"
echo "inicio: $(date -Is)  carga: $(cut -d' ' -f1-3 /proc/loadavg)  uptime: $(uptime -p)" > "$D/diario.txt"
for r in 0 1 2 3 4 5; do
    [ $r -eq 0 ] && rot="aquecimento(descartado)" || rot="rodada$r"
    echo "[$rot] $(date +%H:%M:%S) carga $(cut -d' ' -f1 /proc/loadavg)" >> "$D/diario.txt"
    for p in $PROGS; do rodar "$D/${p}.r${r}.txt" "./$B/$p"; done
    # Varredura por regiao: o que confronta a previsao de cobertura de TLB com
    # a medicao. 512 MB e o padrao e ja saiu no laco acima.
    for mb in 8 16 32 64; do
        rodar "$D/custo-traducao.regiao${mb}mb.r${r}.txt" "./$B/custo-traducao" "$mb"
    done
    # O mesmo percurso em ordem crescente: muda so a ordem dos enderecos, com
    # a cadeia dependente mantida, para isolar o padrao de acesso.
    for mb in 8 16 32 64 512; do
        rodar "$D/custo-traducao.seq${mb}mb.r${r}.txt" "./$B/custo-traducao" "$mb" sequencial
    done
    corre2 "$r"
    corre3 "$r"
    corre_feed "$r"
done
echo "fim: $(date -Is)  carga: $(cut -d' ' -f1-3 /proc/loadavg)" >> "$D/diario.txt"

# O teste do estado da maquina: alterna ocio e medicao. E o protocolo que
# encontrou a quarta escala de dispersao, e por isso acompanha toda coleta.
# O `2>/dev/null` seguido de pipe ESCONDIA A FALHA DUAS VEZES: o erro sumia e
# o `$?` do pipe era o do `awk`, que tem sucesso sobre entrada vazia. O
# resultado era um arquivo de diagnostico com colunas em branco e nenhum sinal.
le() {
    local saida
    saida=$("./$B/custo-comunicacao" 2>/dev/null) || { LE_FALHOU=1; return 1; }
    printf '%s' "$saida" | awk '/within domain/{d=$8} /^  BETWEEN domains/{e=$7} END{printf "%s %s",d,e}'
}
LE_FALHOU=0
{ echo "ciclo  apos-ocio(dentro entre)  imediata(dentro entre)"
  for c in 1 2 3 4; do sleep 30; a=$(le); b=$(le); echo "  $c      $a               $b"; done
} > "$D/teste-estado-maquina.txt"
if [ "$LE_FALHOU" -ne 0 ]; then
    registrar "teste-estado-maquina.txt" FAIL 1
else
    registrar "teste-estado-maquina.txt" PASS 0
fi

# O VEREDITO, e ele sai no codigo de saida. Os tres estados sao os mesmos que
# `campanha.sh` usa, para que o pai possa distinguir sem interpretar texto:
#   0  todas as celulas mediram
#   2  alguma PULOU por pre-requisito -- nao e defeito, e nao e completa
#   1  alguma FALHOU
cp "$MANIFESTO" "$D2/manifesto.txt" 2>/dev/null
cp "$MANIFESTO" "$D3/manifesto.txt" 2>/dev/null
veredito_hw() {
    local falhas pulos
    falhas=$(contar_estado FAIL)
    pulos=$(contar_estado SKIP)
    if [ "$falhas" -gt 0 ] || [ "$pulos" -gt 0 ]; then
        echo "  celulas que nao mediram (${MANIFESTO#$RAIZ/}):"
        awk '$2 == "FAIL" || $2 == "SKIP"' "$MANIFESTO" | sed 's/^/    /'
    fi
    if [ "$falhas" -gt 0 ]; then
        echo "SUBCAMPANHA COM FALHA: $falhas celula(s) correram e reprovaram${pulos:+ e $pulos pulada(s)}" >&2
        echo "  A coleta em ${D#$RAIZ/} NAO e publicavel." >&2
        return 1
    fi
    if [ "$pulos" -gt 0 ]; then
        echo "SUBCAMPANHA INCOMPLETA: $pulos celula(s) pulada(s) por pre-requisito" >&2
        return 2
    fi
    echo "CONCLUIDA -> ${D#$RAIZ/}"   # relativo: o diario e publico
    return 0
}
veredito_hw || exit $?
echo "          -> ${D2#$RAIZ/}"
echo "          -> ${D3#$RAIZ/}"
echo "Comparar:  ./ferramental/qualidade/comparar-hardware.py docs/01-fundamentos/medicoes/historico/{outra,$CONF}"
