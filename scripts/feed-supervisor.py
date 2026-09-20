#!/usr/bin/env python3
"""Executa sessões sintéticas, reiniciando em nova geração após falha.

Cada sessão reconstrói o estado desde o início. Não recupera ticks da sessão
anterior nem implementa reassinatura de um feed externo.
"""
import argparse
import json
import math
import os
from pathlib import Path
import secrets
import signal
import subprocess
import tempfile
import time


def stop(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def wait_text(path, needle, process, seconds=20):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if needle in path.read_text(errors='replace'):
            return True
        if process.poll() is not None:
            return False
        time.sleep(0.02)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--primary', required=True)
    parser.add_argument('--secondary', required=True)
    parser.add_argument('--huge-dir', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--attempts', type=int, default=2)
    parser.add_argument('--ticks', type=int, default=20000)
    parser.add_argument('--cpus', default='0,1')
    parser.add_argument('--session-seconds', type=float, default=30)
    parser.add_argument('--inject-first-crash', action='store_true', help='controle de falha deliberada')
    args = parser.parse_args()
    cpus = args.cpus.split(',')
    if (args.attempts < 1 or args.ticks < 1 or not math.isfinite(args.session_seconds) or
        args.session_seconds <= 0 or len(cpus) != 2 or
        any(not cpu.isdecimal() for cpu in cpus) or int(cpus[0]) == int(cpus[1])):
        parser.error('tentativas/ticks/prazo positivos e duas CPUs distintas são obrigatórios')
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    events = []
    try:
        for attempt in range(args.attempts):
            generation = secrets.randbelow(2**63 - 1) + 1
            # Delimitador impede a limpeza da geração 123 alcançar 1234.
            prefix = f'academy_session_{os.getpid()}_{generation}_'
            folder = output / f'session-{attempt + 1}'
            folder.mkdir()
            env = dict(os.environ, DPDK_ACADEMY_GENERATION=str(generation))
            primary = secondary = None
            success = False
            timeline = []
            def mark(name, **details):
                timeline.append(dict(event=name, monotonic_ns=time.monotonic_ns(), **details))
            deadline = time.monotonic() + args.session_seconds
            def remaining():
                return max(0, deadline - time.monotonic())
            mark('session_started', generation=generation)
            with tempfile.TemporaryDirectory(prefix='academy-runtime-') as runtime:
                env['XDG_RUNTIME_DIR'] = runtime
                common = [f'--file-prefix={prefix}', '--no-pci', f'--huge-dir={args.huge_dir}']
                with (folder / 'primary.txt').open('w') as plog, (folder / 'secondary.txt').open('w') as slog:
                    try:
                        primary = subprocess.Popen([args.primary, '-l', cpus[0], *common, '--', str(args.ticks), 'cadencia'],
                                                   stdout=plog, stderr=subprocess.STDOUT, env=env)
                        mark('primary_started', pid=primary.pid)
                        if wait_text(folder / 'primary.txt', 'waiting for the subscriber to connect', primary, remaining()):
                            secondary = subprocess.Popen([args.secondary, '-l', cpus[1], *common, '--proc-type=secondary'],
                                                         stdout=slog, stderr=subprocess.STDOUT, env=env)
                            mark('secondary_started', pid=secondary.pid)
                            attached = wait_text(folder / 'secondary.txt', 'virtual address', secondary, remaining())
                            active = attached and wait_text(folder / 'secondary.txt',
                                f'ACTIVE BOOK: generation={generation} ', secondary, remaining())
                            if active:
                                mark('book_active', generation=generation)
                            consumed = active and wait_text(folder / 'secondary.txt',
                                'First batch consumed:', secondary, remaining())
                            if consumed:
                                mark('consumption_observed')
                            if consumed and args.inject_first_crash and attempt == 0 and primary.poll() is None:
                                primary.send_signal(signal.SIGKILL)
                                mark('crash_injected', pid=primary.pid)
                            while consumed and time.monotonic() < deadline:
                                p, s = primary.poll(), secondary.poll()
                                if p is not None and p != 0 or s is not None and s != 0:
                                    break
                                if p == 0 and s == 0:
                                    success = 'Book validity: VALID;' in (folder / 'secondary.txt').read_text(errors='replace')
                                    if success:
                                        mark('session_completed')
                                    break
                                time.sleep(0.02)
                    finally:
                        # Nenhuma nova sessão antes de ambos os processos antigos terminarem.
                        stop(secondary)
                        mark('secondary_terminated', returncode=secondary.returncode if secondary else None)
                        stop(primary)
                        mark('primary_terminated', returncode=primary.returncode if primary else None)
                        # Somente arquivos pertencentes ao prefixo criado nesta tentativa.
                        for path in Path(args.huge_dir).glob(prefix + '*'):
                            if path.is_file() or path.is_symlink():
                                path.unlink()
                        mark('resources_removed')
                        event = {'attempt': attempt + 1, 'generation': generation, 'prefix': prefix,
                                 'primary_rc': primary.returncode if primary else None,
                                 'secondary_rc': secondary.returncode if secondary else None,
                                 'old_processes_terminated': all(p is None or p.poll() is not None for p in (primary, secondary)),
                                 'success': success, 'timeline': timeline}
                        events.append(event)
                        (output / 'sessions.json').write_text(json.dumps(events, indent=2) + '\n')
                        print(json.dumps(event), flush=True)
            if success:
                return 0
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
