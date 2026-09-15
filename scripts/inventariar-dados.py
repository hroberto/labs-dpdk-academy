#!/usr/bin/env python3
"""Inventário estrutural delimitado; não decide se uma conclusão é verdadeira."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
TARGETS = (
    'docs/01-fundamentos/README.md', 'docs/02-runtime-dpdk/README.md',
    'docs/03-mempool-ring-mbuf/README.md',
    'trilha/01-fundamentos/02-mempool-ring/README.md',
    'trilha/01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md',
    'trilha/04-projeto-final/README.md',
    'docs/avaliacoes/evidencias/2026-09-14-controle-anel/tabela.md',
    'docs/avaliacoes/evidencias/2026-09-15-controle-anel-validado/tabela.md',
)
OUTPUT = ROOT / 'docs/avaliacoes/inventario-tabelas.json'


def blocks(text):
    lines = text.splitlines()
    heading = ''
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('#'): heading = line.lstrip('# ').strip()
        kind, start = None, i
        if (line.startswith('|') and i + 1 < len(lines) and
            re.fullmatch(r'\|[ |:\-]+\|', lines[i + 1])):
            kind = 'tabela_markdown'
            i += 2
            while i < len(lines) and lines[i].startswith('|'): i += 1
        elif line.startswith('```'):
            language = line[3:].strip()
            i += 1
            while i < len(lines) and not lines[i].startswith('```'): i += 1
            i = min(i + 1, len(lines))
            content = '\n'.join(lines[start:i])
            if language in ('', 'console', 'text') and re.search(r'\d.*(?:ns|µs|us|ms|%|[Mm][Bb]|[Gg][Bb])', content):
                kind = 'bloco_numerico'
        else:
            i += 1
        if kind:
            content = '\n'.join(lines[start:i])
            yield {'linha': start + 1, 'secao': heading, 'tipo': kind,
                   'sha256': hashlib.sha256(content.encode()).hexdigest()}


def inventory():
    entries = []
    for name in TARGETS:
        for block in blocks((ROOT / name).read_text()):
            entries.append(dict(arquivo=name, **block))
    return {'escopo': list(TARGETS),
            'limites': 'Tabelas Markdown e blocos numericos nas oito paginas listadas. '
                       'Nao abrange todos os numeros em prosa nem verifica automaticamente sua origem.',
            'total': len(entries), 'entradas': entries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--atualizar', action='store_true')
    args = parser.parse_args()
    current = inventory()
    if args.atualizar:
        OUTPUT.write_text(json.dumps(current, ensure_ascii=False, indent=2) + '\n')
    elif current != json.loads(OUTPUT.read_text()):
        raise SystemExit('Inventario desatualizado: revisar tabelas alteradas e executar --atualizar')
    print(f"{current['total']} tabelas/blocos em {len(TARGETS)} paginas; escopo e limites declarados")


if __name__ == '__main__':
    main()
