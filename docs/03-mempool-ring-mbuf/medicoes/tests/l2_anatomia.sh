#!/usr/bin/env bash
# Envolve o anatomia-mbuf para que ele limpe o proprio diretorio de runtime.
#
# O teste rodava direto do meson, com `--file-prefix=academy_anatomia_mbuf`
# fixo. Prefixo fixo nao acumula -- e um diretorio so, reusado --, mas continua
# sendo estado deixado para tras, e uma excecao no verificador de rastros seria
# uma excecao a manter para sempre. Envolver custa quatro linhas.
set -eu
trap 'rm -rf "${XDG_RUNTIME_DIR:-/var/run}"/dpdk/academy_anatomia_$$' EXIT
"${1:?binario}" -l 0 --no-huge --file-prefix="academy_anatomia_$$"
