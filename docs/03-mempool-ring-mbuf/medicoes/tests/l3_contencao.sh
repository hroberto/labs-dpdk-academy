#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Guarda do teste de contenção — nível L3.
#
# O programa mede N núcleos disputando o mesmo mempool, e precisa de núcleos de
# verdade. A EAL rejeita a linha de comando inteira quando um lcore da lista não
# existe:
#
#   EAL: lcore 3 unavailable
#   EAL: invalid coremask or core-list parameter
#   EAL: Error parsing command line arguments.
#
# Isso acontece ANTES de o programa rodar, então ele não tem como se adaptar. Sem
# este guarda, o teste falharia em VERMELHO num host pequeno — acusando defeito
# onde só falta hardware. Runner de CI de repositório privado tem 2 vCPU.
#
# Uso: l3_contencao.sh <binario>
set -u
BIN=${1:?uso: l3_contencao.sh <binario>}
NECESSARIAS=4

CPUS=$(nproc 2>/dev/null || echo 1)
if [ "$CPUS" -lt "$NECESSARIAS" ]; then
    echo "L3 PULADO: a contencao entre nucleos exige $NECESSARIAS lcores; este host tem $CPUS."
    echo "  O experimento so tem sentido com nucleos disputando de verdade."
    exit 77   # 77 = PULADO para o Meson, nao sucesso
fi

exec "$BIN" -l "0-$((NECESSARIAS - 1))" --no-huge --file-prefix=academy_contencao_$$ --no-pci 64
