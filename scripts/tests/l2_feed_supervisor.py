#!/usr/bin/env python3
"""Controle do supervisor com subprocessos reais, sem EAL ou hardware."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    primary = tmp / 'primary'
    secondary = tmp / 'secondary'
    primary.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, time
root = pathlib.Path(__file__).parent
for pid in (root / 'pids').read_text().split() if (root / 'pids').exists() else []:
    try: os.kill(int(pid), 0)
    except ProcessLookupError: pass
    else: (root / 'overlap').touch()
with (root / 'pids').open('a') as f: f.write(str(os.getpid()) + ' ')
prefix = next(a.split('=', 1)[1] for a in sys.argv if a.startswith('--file-prefix='))
(root / (prefix + '_fixture')).touch()
(root / (prefix.rstrip('_') + '9__alheio')).touch()
print('waiting for the subscriber to connect', flush=True)
time.sleep(0.6)
''')
    secondary.write_text('''#!/usr/bin/env python3
import os, pathlib, time
root = pathlib.Path(__file__).parent
with (root / 'pids').open('a') as f: f.write(str(os.getpid()) + ' ')
print('virtual address', flush=True)
mode = (root / 'mode').read_text() if (root / 'mode').exists() else 'valid'
if mode != 'no_active':
    print('ACTIVE BOOK: generation=' + os.environ['DPDK_ACADEMY_GENERATION'] + ' tick=20 sides=8', flush=True)
print('First batch consumed: 20', flush=True)
time.sleep(0.2)
if mode == 'valid': print('Book validity: VALID; reconstructions: 1', flush=True)
''')
    primary.chmod(0o755)
    secondary.chmod(0o755)
    run = subprocess.run([sys.executable, str(root / 'scripts/feed-supervisor.py'),
        '--primary', str(primary), '--secondary', str(secondary), '--huge-dir', str(tmp),
        '--output', str(tmp / 'out'), '--inject-first-crash'], capture_output=True, text=True, timeout=10)
    assert run.returncode == 0, run.stdout + run.stderr
    sessions = json.loads((tmp / 'out/sessions.json').read_text())
    assert len(sessions) == 2
    assert sessions[0]['primary_rc'] == -9 and not sessions[0]['success']
    assert sessions[1]['success']
    assert sessions[0]['generation'] != sessions[1]['generation']
    assert sessions[0]['prefix'] != sessions[1]['prefix']
    assert all(s['old_processes_terminated'] for s in sessions)
    for session in sessions:
        events = session['timeline']
        names = [e['event'] for e in events]
        assert names.index('book_active') < names.index('consumption_observed')
        assert names.index('secondary_terminated') < names.index('resources_removed')
        assert names.index('primary_terminated') < names.index('resources_removed')
        if 'crash_injected' in names:
            assert names.index('consumption_observed') < names.index('crash_injected')
        assert [e['monotonic_ns'] for e in events] == sorted(e['monotonic_ns'] for e in events)
    assert sessions[0]['timeline'][-1]['monotonic_ns'] < sessions[1]['timeline'][0]['monotonic_ns']
    assert not (tmp / 'overlap').exists(), 'nova sessao sobreposta a processo antigo'
    assert not list(tmp.glob('academy_session_*_fixture'))
    assert len(list(tmp.glob('*__alheio'))) == 2, 'limpeza alcancou outra geracao com prefixo parecido'
    print('OK: reinicio apos consumo; geracoes, ordem e ausencia de processos antigos conferidas')
    (tmp / 'arquivo-alheio').write_text('preservar')
    for mode in ('no_active', 'no_final_valid'):
        (tmp / 'mode').write_text(mode)
        run = subprocess.run([sys.executable, str(root / 'scripts/feed-supervisor.py'),
            '--primary', str(primary), '--secondary', str(secondary), '--huge-dir', str(tmp),
            '--output', str(tmp / mode), '--attempts', '1', '--session-seconds', '1',
            *(['--inject-first-crash'] if mode == 'no_active' else [])], capture_output=True, text=True, timeout=5)
        assert run.returncode == 1, run.stdout + run.stderr
        event = json.loads((tmp / mode / 'sessions.json').read_text())[0]
        assert not event['success'] and event['old_processes_terminated']
        if mode == 'no_active':
            assert 'crash_injected' not in [e['event'] for e in event['timeline']]
        assert (tmp / 'arquivo-alheio').read_text() == 'preservar'
        print('OK: rejeita', mode, 'e preserva recurso alheio')
