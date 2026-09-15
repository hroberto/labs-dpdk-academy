#!/usr/bin/env python3
"""Controles da análise; compila cópias temporárias, sem alterar fontes do projeto.

Uso: python3 reproduzir-controles.py /caminho/para/resultados
Requer compilador C, pkg-config e DPDK. Não configura NIC nem hugepages.
Não é uma suíte de aprovação: registra o comportamento, inclusive os defeitos.
"""
from pathlib import Path
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
results = []


def run(name, args, env=None):
    p = subprocess.run(args, text=True, capture_output=True, env=env, timeout=90)
    (OUT / f'{name}.txt').write_text(p.stdout + p.stderr)
    results.append({'controle': name, 'comando': args, 'codigo': p.returncode})
    return p


with tempfile.TemporaryDirectory(prefix='dpdk-controles-') as temp:
    temp = Path(temp)
    stat_dir = ROOT / 'docs/01-fundamentos/medicoes'
    source = temp / 'statistics-probe.c'
    source.write_text('''#define _GNU_SOURCE
#include "statistics.h"
#include <math.h>
static void show(const char *name, double *v, int n) {
    struct statistics s = summarize(v, n);
    printf("%s: samples=%d minimum=%g median=%g finite=%d valid=%d badge=[%s]\\n",
           name, s.samples, s.minimum, s.median, isfinite(s.median),
           collection_is_valid(s, n), badge(s));
}
int main(void) {
    double mixed[] = {-1, 10, 10, 10, 10};
    double nan_values[] = {NAN, NAN, NAN};
    double inf_values[] = {INFINITY, INFINITY, INFINITY};
    double mixed_nan[] = {1, 2, NAN, 4, 5, 6, 7};
    show("sentinela misturada", mixed, 5);
    show("NaN", nan_values, 3);
    show("infinito", inf_values, 3);
    show("NaN no interior", mixed_nan, 7);
    return 0;
}
''')
    compiled = run('compilar-estatistica', ['cc', '-std=c11', '-O2', '-I', str(stat_dir),
                                         str(source), '-lm', '-o', str(temp / 'stat')])
    if compiled.returncode == 0:
        run('estatistica-invalida', [str(temp / 'stat')])

    # Mantém o shell e biblioteca reais; omite apenas o helper Python da fixture.
    fixture = temp / 'fixture/scripts'
    (fixture / 'tests').mkdir(parents=True)
    shutil.copy2(ROOT / 'scripts/tests/l1_xdp.sh', fixture / 'tests/l1_xdp.sh')
    shutil.copy2(ROOT / 'scripts/lib-xdp.sh', fixture / 'lib-xdp.sh')
    run('l1-helper-ausente', ['bash', str(fixture / 'tests/l1_xdp.sh')])

    # Mutação mínima: só a função de medição com cache devolve erro.
    alloc_dir = ROOT / 'docs/03-mempool-ring-mbuf/medicoes'
    original = (alloc_dir / 'custo-alocacao.c').read_text()
    old = 'static double m_pool_com_cache(void)\n{\n    return measure_pool_single(pool_cache);\n}'
    new = 'static double m_pool_com_cache(void)\n{\n    return -1.0;\n}'
    if original.count(old) != 1:
        raise RuntimeError('Fonte mudou: revisar a mutação antes de executar.')
    mutated = temp / 'custo-alocacao-invalida.c'
    mutated.write_text(original.replace(old, new))
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'libdpdk'], text=True)
    executable = temp / 'custo-alocacao-invalida'
    compiled = run('compilar-alocacao', ['cc', '-std=c11', '-O2', '-I', str(alloc_dir),
        '-I', str(stat_dir), str(mutated), str(alloc_dir / 'sizing.c'),
        *shlex.split(flags), '-pthread', '-lm', '-o', str(executable)])
    if compiled.returncode == 0:
        env = dict(os.environ, DPDK_ACADEMY_AMOSTRAS='3', DPDK_ACADEMY_RODADAS='20000')
        cpu = min(os.sched_getaffinity(0))
        env['DPDK_ACADEMY_CPU_RUIDO'] = str(max(os.sched_getaffinity(0)))
        run('alocacao-invalida', [str(executable), '-l', str(cpu), '--no-huge', '--no-pci',
            f'--file-prefix=academy_audit_{os.getpid()}'], env)

(OUT / 'controles.json').write_text(json.dumps(results, indent=2, ensure_ascii=False) + '\n')
for item in results:
    print(f"{item['controle']}: codigo {item['codigo']}")
