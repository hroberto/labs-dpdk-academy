from pathlib import Path
import os, tempfile, subprocess, json, hashlib

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(tempfile.mkdtemp(prefix='academy-auditoria-preparar-nic-'))
records = []
for case in ('controle', 'pmd_ausente', 'grupo_ausente', 'ip_falhou', 'ipv6_configurado', 'dois_bdfs', 'vendor_invalido', 'mellanox', 'rota_falhou', 'vendor_ausente', 'undo_ambiguo', 'undo_vfio_primeiro'):
    folder = OUT / case
    scripts = folder / 'scripts'; scripts.mkdir(parents=True)
    sysroot = folder / 'sys'; binroot = folder / 'bin'; binroot.mkdir()
    log = folder / 'chamadas.txt'
    for name in ('preparar-nic.sh', 'lib-nic.sh', 'lib-apuracao.sh', 'lib-bind-guard.sh'):
        source = (ROOT / 'scripts' / name).read_text()
        source = source.replace('/sys/', str(sysroot) + '/')
        source = source.replace('/usr/lib/*/dpdk/pmds-*/', str(folder / 'pmds') + '/')
        (scripts / name).write_text(source)
    bdf = '0000:01:00.0'; dev = sysroot / 'bus/pci/devices' / bdf
    (dev / 'net/ethfixture').mkdir(parents=True)
    (dev / 'net/ethfixture/flags').write_text('0x1002\n')
    if case != 'vendor_ausente':
        (dev / 'vendor').write_text('0x15b3\n' if case == 'mellanox' else 'invalido\n' if case == 'vendor_invalido' else '0x8086\n')
    group = sysroot / 'kernel/iommu_groups/9'; (group / 'devices').mkdir(parents=True)
    if case != 'grupo_ausente':
        (dev / 'iommu_group').symlink_to(group)
        (group / 'devices' / bdf).symlink_to(dev)
    (folder / 'pmds').mkdir()
    if case != 'pmd_ausente':
        # Deliberately NOT an ELF/PMD: the current scanner accepts these four bytes.
        (folder / 'pmds/librte_net_fixture.so').write_bytes(bytes.fromhex('86800e10'))
    stubs = {
        'modprobe': 'printf "modprobe %s\\n" "$*" >> "$CALLS"\nexit 0\n',
        'ip': '''if [ "$1" = link ]; then printf 'ip %s\\n' "$*" >> "$CALLS"; exit 0; fi
if [ "$1" = -br ]; then
    [ "$CASE" = ip_falhou ] && exit 1
    [ "$CASE" = ipv6_configurado ] && printf 'ethfixture DOWN 2001:db8::1/64\\n'
    exit 0
fi
[ "$CASE" = rota_falhou ] && exit 1
exit 0
''',
        'lspci': "printf '01:00.0 0200: 8086:100e\\n'\n",
        'ldconfig': 'exit 0\n',
        'dpdk-devbind.py': '''if [ "$1" = --status-dev ]; then
    if [ "$CASE" = undo_vfio_primeiro ]; then
        printf '0000:01:00.0 fixture drv=vfio-pci unused=vfio-pci,igb\\n'
    else
        printf '0000:01:00.0 fixture drv=vfio-pci unused=igb,e1000e\\n'
    fi
    exit 0
fi
printf 'devbind %s\\n' "$*" >> "$CALLS"
exit 0
''',
    }
    for name, content in stubs.items():
        p = binroot / name; p.write_text('#!/bin/bash\n' + content); p.chmod(0o755)
    args = ['01:00.0']
    if case == 'dois_bdfs': args = ['02:00.0', '01:00.0']
    if case.startswith('undo_'): args = ['--desfazer', '01:00.0']
    env = dict(os.environ, PATH=str(binroot) + ':/usr/bin:/bin', CASE=case, CALLS=str(log))
    run = subprocess.run(['/bin/bash', str(scripts / 'preparar-nic.sh'), *args], env=env, capture_output=True, text=True, timeout=10)
    record = {'caso': case, 'retorno': run.returncode, 'chamadas_simuladas': log.read_text().splitlines() if log.exists() else [], 'stdout': run.stdout, 'stderr': run.stderr}
    records.append(record)
    print(case, run.returncode, record['chamadas_simuladas'])
(OUT / 'resultados.json').write_text(json.dumps(records, indent=2, ensure_ascii=False) + '\n')
(OUT / 'fontes.json').write_text(json.dumps({name: hashlib.sha256((ROOT / 'scripts' / name).read_bytes()).hexdigest() for name in ('preparar-nic.sh', 'lib-nic.sh', 'lib-apuracao.sh', 'lib-bind-guard.sh')}, indent=2) + '\n')
print('Evidencias:', OUT)
