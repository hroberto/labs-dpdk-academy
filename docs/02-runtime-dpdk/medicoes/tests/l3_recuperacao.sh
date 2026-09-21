#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -eu
. "$(dirname "$0")/lib-hugetlbfs.sh"
huge=$(descobrir_hugetlbfs)
hugetlbfs_disponivel "$huge" || { echo 'SKIP: hugetlbfs gravavel com paginas livres'; exit 77; }
command -v python3 >/dev/null || { echo 'SKIP: python3'; exit 77; }
out=$(mktemp -d "${DPDK_ACADEMY_EVIDENCE_DIR:-${TMPDIR:-/tmp}}/academy-l3-recuperacao.XXXXXX")
# Preservar logs inclusive em falha; o caminho aparece no log do Meson.
echo "Evidencias L3: $out"
python3 "$3" --primary "$1" --secondary "$2" --huge-dir "$huge" \
    --output "$out/sessions" --ticks 1000000 --inject-first-crash
python3 - "$out/sessions/sessions.json" <<'PY'
import json, sys
sessions = json.load(open(sys.argv[1]))
assert len(sessions) == 2
assert sessions[0]['primary_rc'] == -9 and not sessions[0]['success']
assert sessions[1]['success']
assert sessions[0]['generation'] != sessions[1]['generation']
assert all(s['old_processes_terminated'] for s in sessions)
for session in sessions:
    names = [e['event'] for e in session['timeline']]
    assert names.index('book_active') < names.index('consumption_observed')
    assert names.index('secondary_terminated') < names.index('resources_removed')
    assert names.index('primary_terminated') < names.index('resources_removed')
names = [e['event'] for e in sessions[0]['timeline']]
assert names.index('consumption_observed') < names.index('crash_injected')
assert sessions[0]['timeline'][-1]['monotonic_ns'] < sessions[1]['timeline'][0]['monotonic_ns']
assert 'session_completed' in [e['event'] for e in sessions[1]['timeline']]
PY

# O bloco acima confere que `resources_removed` APARECEU na linha do tempo --
# ou seja, que o passo rodou. Isto confere que ele FUNCIONOU: sao afirmacoes
# diferentes, e a segunda e a que faltava quando o l3_multiprocesso vazava uma
# hugepage com a suite verde. Ver `conferir_sem_residuo` em lib-hugetlbfs.sh.
conferir_sem_residuo academy_session_ || exit 1
echo '  ok - o supervisor nao deixou residuo em hugetlbfs'

