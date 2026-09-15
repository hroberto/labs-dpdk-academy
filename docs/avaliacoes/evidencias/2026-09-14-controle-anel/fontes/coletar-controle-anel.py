#!/usr/bin/env python3
"""Coleta serial e rastreável do controle SPSC; também regenera sua tabela."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import math
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def table(folder):
    with (folder / 'amostras.csv').open() as handle:
        rows = list(csv.DictReader(handle))
    groups = {}
    for row in rows:
        value = float(row['ns_per_object'])
        if not math.isfinite(value) or value <= 0:
            raise ValueError('Amostra não publicável')
        key = tuple(row[k] for k in ('bulk', 'burst', 'producer', 'consumer'))
        groups.setdefault(key, []).append(value)
    lines = ['# Controle do anel SPSC', '',
        'Custo amortizado do ciclo de transferência, incluindo geração e conferência de sequência. '
        'Não é latência individual nem comparação com DPDK. Uma passagem de aquecimento por processo; '
        'ordem aleatória registrada, coleta serial. Os quartis descrevem repetições do custo amortizado.', '',
        '| API | Lote | CPUs produtor/consumidor | Repetições | Mediana ns/objeto | p25–p75 |',
        '|---|---:|---|---:|---:|---|']
    for (bulk, burst, p, c), values in sorted(groups.items(), key=lambda item: tuple(map(int,item[0]))):
        q = statistics.quantiles(values, n=4, method='inclusive') if len(values) > 1 else [values[0]] * 3
        lines.append(f'| {"bloco" if bulk == "1" else "objeto"} | {burst} | {p}/{c} | {len(values)} | {statistics.median(values):.3f} | {q[0]:.3f}–{q[2]:.3f} |')
    lines += ['', 'Registros: [amostras](amostras.csv), [metadados](metadados.json), '
              '[ambiente](ambiente.txt), [comandos e status](execucoes.json).', '',
              'A diferença entre APIs inclui o trabalho dos laços e das cópias; não isola o custo '
              'de uma instrução atômica. A comparação entre CPUs inclui sincronização e interferência. '
              'Turbo e frequência não foram fixados; a dispersão não corrige esses fatores.', '']
    (folder / 'tabela.md').write_text('\n'.join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--regenerar', action='store_true')
    parser.add_argument('--repeticoes', type=int, default=25)
    parser.add_argument('--cpus', default='0,2')
    args = parser.parse_args()
    folder = args.output.resolve()
    if args.regenerar:
        table(folder)
        return
    cpus = list(map(int, args.cpus.split(',')))
    if len(cpus) != 2 or cpus[0] == cpus[1] or not set(cpus) <= os.sched_getaffinity(0) or args.repeticoes < 3:
        parser.error('Informe duas CPUs permitidas distintas e pelo menos três repetições')
    folder.mkdir(parents=True, exist_ok=False)
    source = folder / 'fontes'
    source.mkdir()
    originals = ROOT / 'trilha/01-fundamentos/02-mempool-ring/alternativas/cpp23'
    for name in ('packet.hpp', 'controle-anel.cpp'):
        shutil.copy2(originals / name, source / name)
    shutil.copy2(Path(__file__), source / 'coletar-controle-anel.py')
    metadata = {'data_utc': datetime.now(timezone.utc).isoformat(),
        'commit_base': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'fontes_exatas': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in source.iterdir()},
        'compilador': subprocess.check_output(['c++', '--version'], text=True).splitlines()[0],
        'flags': ['-O3', '-std=c++23', '-pthread', '-DNDEBUG'], 'repeticoes': args.repeticoes,
        'seed': 20260914, 'cpus': cpus, 'unidade': 'ns por objeto; custo amortizado',
        'hipotese': 'Publicação em bloco pode reduzir custo por objeto; efeito depende de lote e colocação.',
        'controle': 'Mesmo payload, capacidade 4095, total 200000, geração e verificação FIFO.',
        'limites': 'Sem NIC; não isola cache como causa; não usa p99 de latência individual.'}
    (folder / 'metadados.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    environment = subprocess.run(['bash', str(ROOT / 'scripts/ambiente.sh')], capture_output=True, text=True)
    (folder / 'ambiente.txt').write_text(environment.stdout + environment.stderr)
    runs, samples = [], []
    cases = [(bulk, burst, cpus[0], c) for bulk in (0, 1) for burst in (1, 8, 32, 128) for c in cpus]
    rng = random.Random(metadata['seed'])
    try:
        with tempfile.TemporaryDirectory(prefix='academy-benchmark-') as temp:
            binary = Path(temp) / 'controle-anel'
            command = ['c++', *metadata['flags'], str(source / 'controle-anel.cpp'), '-o', str(binary)]
            built = subprocess.run(command, capture_output=True, text=True)
            (folder / 'build.txt').write_text(built.stdout + built.stderr)
            if built.returncode:
                raise RuntimeError('Compilação falhou; consulte build.txt')
            for repetition in range(args.repeticoes):
                rng.shuffle(cases)
                for case in cases:
                    command = [str(binary), *map(str, case), '1']
                    run = subprocess.run(command, capture_output=True, text=True, timeout=15)
                    item = {'repetition': repetition, 'case': list(case), 'command': command,
                            'returncode': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr}
                    runs.append(item)
                    if run.returncode:
                        raise RuntimeError('Ensaio falhou; sem tabela publicável')
                    parsed = list(csv.DictReader(io.StringIO(run.stdout)))
                    if len(parsed) != 1:
                        raise ValueError('Número de linhas inesperado')
                    samples.append(dict(repetition=repetition, **parsed[0]))
        with (folder / 'amostras.csv').open('w') as handle:
            writer = csv.DictWriter(handle, fieldnames=list(samples[0]))
            writer.writeheader()
            writer.writerows(samples)
        table(folder)
        (folder / 'status.txt').write_text('PASS: todas as execuções concluídas; tabela gerada\n')
    except BaseException:
        (folder / 'status.txt').write_text('FAIL: coleta incompleta; não publicar comparação\n')
        raise
    finally:
        (folder / 'execucoes.json').write_text(json.dumps(runs, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
