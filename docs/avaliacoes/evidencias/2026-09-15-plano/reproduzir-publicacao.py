#!/usr/bin/env python3
"""Diagnóstico em cópias temporárias; não é uma suíte de aprovação.

Uso: python3 reproduzir-publicacao.py /diretorio/novo
Registra se a regeneração atual rejeita dados incompletos ou duplicados.
"""
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / 'docs/avaliacoes/evidencias/2026-09-14-controle-anel'
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=False)
original = list(csv.DictReader((SOURCE / 'amostras.csv').open()))
metadata = json.loads((SOURCE / 'metadados.json').read_text())
result = {'fontes_conferidas': {
    n: hashlib.sha256((SOURCE / 'fontes' / n).read_bytes()).hexdigest() == h
    for n, h in metadata['fontes_exatas'].items()}, 'controles': []}
for name in ('integro', 'uma_amostra_removida', 'cenario_removido', 'amostra_duplicada'):
    with tempfile.TemporaryDirectory(prefix='academy-publicacao-') as tmp:
        dest = Path(tmp) / 'dados'
        shutil.copytree(SOURCE, dest)
        rows = original[:]
        if name == 'uma_amostra_removida':
            rows.pop()
        elif name == 'cenario_removido':
            key = tuple(rows[0][k] for k in ('bulk', 'burst', 'producer', 'consumer'))
            rows = [r for r in rows if tuple(r[k] for k in ('bulk', 'burst', 'producer', 'consumer')) != key]
        elif name == 'amostra_duplicada':
            rows.append(rows[0])
        with (dest / 'amostras.csv').open('w') as f:
            writer = csv.DictWriter(f, fieldnames=original[0].keys())
            writer.writeheader()
            writer.writerows(rows)
        run = subprocess.run([sys.executable, str(ROOT / 'scripts/coletar-controle-anel.py'),
                              str(dest), '--regenerar'], capture_output=True, text=True, timeout=30)
        table = (dest / 'tabela.md').read_text()
        (out / (name + '.md')).write_text(table)
        result['controles'].append({'cenario': name, 'linhas_csv': len(rows),
            'codigo': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr,
            'tabela_identica_original': table == (SOURCE / 'tabela.md').read_text()})
(out / 'controles.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False, indent=2))
