#!/usr/bin/env python3
"""Mutações executáveis: a bateria da CLI deve detectar contratos removidos."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'scripts/coletar-controle-anel.py').read_text()
mutations = {
    'duplicidade': ('if key not in expected or key in by_key:', 'if key not in expected:'),
    'unidade': ("if metadata['unidade'] != UNIT:", 'if False:'),
    'fonte': ("if hashlib.sha256((folder / 'fontes' / name).read_bytes()).hexdigest() != digest:", 'if False:'),
    'valor': ('if parsed != [{k: by_key[key][k] for k in FIELDS}]:', 'if False:'),
}
with tempfile.TemporaryDirectory(prefix='academy-mutacoes-publicacao-') as tmp:
    for name, (before, after) in mutations.items():
        assert source.count(before) == 1, 'mutacao desatualizada: ' + name
        mutant = source.replace(before, after)
        compile(mutant, name, 'exec')
        path = Path(tmp) / (name + '.py')
        path.write_text(mutant)
        run = subprocess.run([sys.executable, str(root / 'scripts/tests/l2_publicacao.py'), str(path)],
            capture_output=True, text=True, timeout=20)
        assert run.returncode != 0 and 'AssertionError' in run.stderr, name + run.stdout + run.stderr
        print('OK: bateria detecta remocao do contrato de', name)
