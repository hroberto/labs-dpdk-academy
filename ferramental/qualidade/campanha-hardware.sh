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

D="$RAIZ/docs/01-fundamentos/medicoes/historico/$CONF"
[ -e "$D" ] && { echo "ABORTADO: $D ja existe -- nao sobrescrevo coleta." >&2; exit 1; }
mkdir -p "$D"

B=build-precommit/docs/01-fundamentos/medicoes
ninja -C build-precommit >/dev/null 2>&1 || { echo "build falhou" >&2; exit 1; }
PROGS="custo-syscall custo-comunicacao custo-mckenney efeito-cache custo-espera custo-paralelismo custo-traducao"

./scripts/ambiente.sh > "$D/ambiente.txt"
echo "inicio: $(date -Is)  carga: $(cut -d' ' -f1-3 /proc/loadavg)  uptime: $(uptime -p)" > "$D/diario.txt"
for r in 0 1 2 3 4 5; do
    [ $r -eq 0 ] && rot="aquecimento(descartado)" || rot="rodada$r"
    echo "[$rot] $(date +%H:%M:%S) carga $(cut -d' ' -f1 /proc/loadavg)" >> "$D/diario.txt"
    for p in $PROGS; do ./$B/$p > "$D/${p}.r${r}.txt" 2>&1; done
done
echo "fim: $(date -Is)  carga: $(cut -d' ' -f1-3 /proc/loadavg)" >> "$D/diario.txt"

# O teste do estado da maquina: alterna ocio e medicao. E o protocolo que
# encontrou a quarta escala de dispersao, e por isso acompanha toda coleta.
le() { ./$B/custo-comunicacao 2>/dev/null | awk '/dentro do dominio/{d=$9} /^  ENTRE dominios/{e=$7} END{printf "%s %s",d,e}'; }
{ echo "ciclo  apos-ocio(dentro entre)  imediata(dentro entre)"
  for c in 1 2 3 4; do sleep 30; a=$(le); b=$(le); echo "  $c      $a               $b"; done
} > "$D/teste-estado-maquina.txt"

echo "CONCLUIDA -> $D"
echo "Comparar:  ./ferramental/qualidade/comparar-hardware.py docs/01-fundamentos/medicoes/historico/{outra,$CONF}"
