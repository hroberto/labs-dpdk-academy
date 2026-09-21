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
    python3 ./scripts/feed-supervisor.py --primary "$B2/feed-primario" \
        --secondary "$B2/feed-secundario" --huge-dir "$DPDK_ACADEMY_HUGE_DIR" \
        --output "$t" --ticks 200000 >/dev/null 2>&1
    local d; d=$(ls -d "$t"/session-* 2>/dev/null | tail -1)
    if [ -n "$d" ]; then
        cp "$d/secondary.txt" "$D2/feed-secundario.r$1.txt"
        cp "$d/primary.txt"   "$D2/feed-primario.r$1.txt"
        echo "  feed r$1: $(basename "$d")" >> "$D/diario.txt"
cat "$D/diario.txt.tmp" >> "$D/diario.txt" 2>/dev/null; rm -f "$D/diario.txt.tmp"
    else
        echo "  feed r$1: SEM SAIDA" >> "$D/diario.txt"
    fi
    rm -rf "$t"
}
corre2() { # <rodada>
    "$B2/custo-init"    -l 0 --in-memory                    > "$D2/custo-init.in-memory.r$1.txt" 2>&1
    "$B2/custo-init"    -l 0 --no-huge                      > "$D2/custo-init.no-huge.r$1.txt"   2>&1
    "$B2/estado-lcore"  -l 0-3 --in-memory                  > "$D2/estado-lcore.r$1.txt"         2>&1
}
corre3() { # <rodada>
    for n in custo-alocacao anatomia-mbuf custo-anel pool-esgotado; do
        "$B3/$n" -l 0 --no-huge --file-prefix="camp_${n}_$1" > "$D3/$n.r$1.txt" 2>&1
    done
    "$B3/custo-contencao" -l 0-5 --no-huge --file-prefix="camp_cont_$1" > "$D3/custo-contencao.r$1.txt" 2>&1
}

./scripts/ambiente.sh > "$D/ambiente.txt"
cp "$D/ambiente.txt" "$D2/ambiente.txt"; cp "$D/ambiente.txt" "$D3/ambiente.txt"
echo "feed: ${DPDK_ACADEMY_HUGE_DIR:-AUSENTE (par primario/secundario nao coletado)}" >> "$D/diario.txt.tmp"
echo "inicio: $(date -Is)  carga: $(cut -d' ' -f1-3 /proc/loadavg)  uptime: $(uptime -p)" > "$D/diario.txt"
for r in 0 1 2 3 4 5; do
    [ $r -eq 0 ] && rot="aquecimento(descartado)" || rot="rodada$r"
    echo "[$rot] $(date +%H:%M:%S) carga $(cut -d' ' -f1 /proc/loadavg)" >> "$D/diario.txt"
    for p in $PROGS; do ./$B/$p > "$D/${p}.r${r}.txt" 2>&1; done
    # Varredura por regiao: o que confronta a previsao de cobertura de TLB com
    # a medicao. 512 MB e o padrao e ja saiu no laco acima.
    for mb in 8 16 32 64; do
        ./$B/custo-traducao "$mb" > "$D/custo-traducao.regiao${mb}mb.r${r}.txt" 2>&1
    done
    corre2 "$r"
    corre3 "$r"
    corre_feed "$r"
done
echo "fim: $(date -Is)  carga: $(cut -d' ' -f1-3 /proc/loadavg)" >> "$D/diario.txt"

# O teste do estado da maquina: alterna ocio e medicao. E o protocolo que
# encontrou a quarta escala de dispersao, e por isso acompanha toda coleta.
le() { ./$B/custo-comunicacao 2>/dev/null | awk '/within domain/{d=$8} /^  BETWEEN domains/{e=$7} END{printf "%s %s",d,e}'; }
{ echo "ciclo  apos-ocio(dentro entre)  imediata(dentro entre)"
  for c in 1 2 3 4; do sleep 30; a=$(le); b=$(le); echo "  $c      $a               $b"; done
} > "$D/teste-estado-maquina.txt"

echo "CONCLUIDA -> $D"
echo "          -> $D2"
echo "          -> $D3"
echo "Comparar:  ./ferramental/qualidade/comparar-hardware.py docs/01-fundamentos/medicoes/historico/{outra,$CONF}"
