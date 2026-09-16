#!/usr/bin/env python3
"""Exercita a CLI de publicação em cópias da campanha preservada."""
import csv
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'scripts/tests/fixtures/controle-anel'
COLLECTOR = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'scripts/coletar-controle-anel.py'
cases = ('integro', 'removida', 'cenario_ausente', 'duplicada', 'compensada',
         'nan', 'valor_divergente', 'unidade', 'fonte', 'execucao_falhou',
         'execucao_ausente', 'comando', 'ambiente_falhou')
for case in cases:
    with tempfile.TemporaryDirectory(prefix='academy-test-publicacao-') as tmp:
        folder = Path(tmp) / 'dados'
        shutil.copytree(SOURCE, folder)
        original_table = (folder / 'tabela.md').read_bytes()
        rows = list(csv.DictReader((folder / 'amostras.csv').open()))
        metadata = json.loads((folder / 'metadados.json').read_text())
        runs = json.loads((folder / 'execucoes.json').read_text())
        if case == 'removida': rows.pop()
        if case == 'duplicada': rows.append(rows[0].copy())
        if case == 'compensada': rows[-1] = rows[0].copy()
        if case == 'cenario_ausente':
            keys = ('bulk', 'burst', 'producer', 'consumer')
            target = tuple(rows[0][k] for k in keys)
            rows = [r for r in rows if tuple(r[k] for k in keys) != target]
        if case == 'nan': rows[0]['ns_per_object'] = 'nan'
        if case == 'valor_divergente': rows[0]['ns_per_object'] = '999.000000000'
        if case == 'unidade': metadata['unidade'] = 'ms'
        if case == 'fonte': (folder / 'fontes/packet.hpp').write_text('fonte alterada')
        if case == 'execucao_falhou': runs[0]['returncode'] = 1
        if case == 'execucao_ausente': runs.pop()
        if case == 'comando': runs[0]['command'][-1] = '2'
        if case == 'ambiente_falhou': metadata.update(schema_version=2, ambiente_returncode=1)
        with (folder / 'amostras.csv').open('w') as f:
            writer = csv.DictWriter(f, fieldnames=rows[0].keys())
            writer.writeheader(); writer.writerows(rows)
        (folder / 'metadados.json').write_text(json.dumps(metadata))
        (folder / 'execucoes.json').write_text(json.dumps(runs))
        run = subprocess.run([sys.executable, str(COLLECTOR),
                              str(folder), '--regenerar'], capture_output=True, text=True, timeout=20)
        status = json.loads((folder / 'publicacao-status.json').read_text())
        if case == 'integro':
            assert run.returncode == 0, run.stderr
            assert status['estado'] == 'VALIDO'
        else:
            assert run.returncode != 0, case
            assert status['estado'] == 'FAIL' and status['motivo'], case
            assert 'Publicacao recusada' in run.stderr, run.stderr
        assert (folder / 'tabela.md').read_bytes() == original_table, case
        print('OK:', case)
