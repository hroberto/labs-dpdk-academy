#!/usr/bin/env bash
# Roda um binario do DPDK e remove o diretorio de runtime que ele deixa.
#
# POR QUE ISTO EXISTE
#
# O DPDK nao remove `$XDG_RUNTIME_DIR/dpdk/<file-prefix>/` ao encerrar. Cinco
# testes eram declarados direto no meson, com `--file-prefix` fixo nos `args`, e
# por isso nao tinham onde pendurar uma limpeza. Prefixo fixo nao acumula -- e
# um diretorio so, reusado --, mas continua sendo estado deixado para tras, e
# manter excecao no verificador de rastros e pior que envolver a chamada.
#
# USO: com-limpeza.sh <prefixo> <binario> [args...]
#
# O prefixo recebe o PID deste script como sufixo, para que execucoes
# simultaneas nao disputem o mesmo diretorio -- que e o que `--file-prefix`
# existe para evitar.
set -eu
prefixo=${1:?uso: com-limpeza.sh <prefixo> <binario> [args...]}
binario=${2:?uso: com-limpeza.sh <prefixo> <binario> [args...]}
shift 2
completo="${prefixo}_$$"
trap 'rm -rf "${XDG_RUNTIME_DIR:-/var/run}/dpdk/${completo}"' EXIT
"$binario" --file-prefix="$completo" "$@"
