#!/usr/bin/env python3
"""Confere suporte PCI declarado pelo dpdk-pmdinfo; nao executa probe da NIC."""
import json
from pathlib import Path
import re
import subprocess
import sys

FIELDS = ('vendor', 'device', 'subsystem_vendor', 'subsystem_device')


def matches(info, target):
    if not isinstance(info, list):
        raise ValueError('saida do pmdinfo nao e lista JSON')
    found = []
    for driver in info:
        if not isinstance(driver, dict) or not isinstance(driver.get('name'), str):
            raise ValueError('registro PMD invalido')
        ids = driver.get('pci_ids', [])
        if not isinstance(ids, list):
            raise ValueError('lista PCI invalida')
        for entry in ids:
            if isinstance(entry, list):
                if len(entry) != 4 or any(type(v) is not int or not 0 <= v <= 65535 for v in entry):
                    raise ValueError('tupla PCI invalida')
                values = entry
            elif isinstance(entry, dict) and entry and not (entry.keys() - set(FIELDS)):
                if any(not isinstance(v, str) or not re.fullmatch('[0-9a-fA-F]{4}', v) for v in entry.values()):
                    raise ValueError('identificador PCI invalido')
                values = [int(entry.get(k, 'ffff'), 16) for k in FIELDS]
            else:
                raise ValueError('identificador PCI invalido')
            if all(v == 65535 or v == t for v, t in zip(values, target)):
                found.append(driver['name'])
    return found


def main():
    if len(sys.argv) < 6:
        raise ValueError('nenhum artefato PMD; informe --pmd=ELF para instalacao nao padrao')
    if any(not re.fullmatch('0x[0-9a-fA-F]{4}', v) for v in sys.argv[1:5]):
        raise ValueError('identidade PCI invalida')
    target = [int(v, 16) for v in sys.argv[1:5]]
    paths = sorted({str(Path(p).resolve(strict=True)) for p in sys.argv[5:]})
    for p in paths:
        with open(p, 'rb') as f:
            if f.read(4) != b'\x7fELF':
                raise ValueError('artefato nao e ELF: ' + p)
    run = subprocess.run(['dpdk-pmdinfo.py', *paths], capture_output=True, text=True, timeout=30)
    if run.returncode != 0:
        raise ValueError('pmdinfo falhou: ' + run.stderr.strip())
    names = matches(json.loads(run.stdout), target)
    if not names:
        raise ValueError('nenhum PMD declara suporte a identidade PCI completa')
    print('Suporte PCI declarado: ' + ', '.join(sorted(set(names))) + '; probe real ainda nao validado')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print('PMD nao confirmado: ' + str(exc), file=sys.stderr)
        sys.exit(1)
