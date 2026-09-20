#!/usr/bin/env python3
"""Contrato da CLI em copias com sysfs e comandos simulados; nunca altera NIC."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import fcntl

ROOT = Path(__file__).resolve().parents[2]
BDF = '0000:01:00.0'
EXECUTIONS = 0


class Fixture:
    def __init__(self, folder):
        self.folder = folder
        self.sys = folder / 'sys'
        self.dev = self.sys / 'bus/pci/devices' / BDF
        self.group = self.sys / 'kernel/iommu_groups/9'
        self.state = folder / 'state'
        self.record = self.state / (BDF + '.state')
        self.log = folder / 'calls'
        self.bin = folder / 'bin'
        self.bin.mkdir(parents=True)
        folder.chmod(0o700)
        self.scripts = folder / 'scripts'; self.scripts.mkdir()
        for name in ('preparar-nic.sh', 'lib-nic.sh', 'lib-apuracao.sh', 'lib-bind-guard.sh'):
            text = (ROOT / 'scripts' / name).read_text()
            text = text.replace('/sys/', str(self.sys) + '/')
            text = text.replace('/var/lib/dpdk-academy/nic', str(self.state))
            if name == 'preparar-nic.sh':
                assert text.count('(( EUID == 0 ))') == 1
                text = text.replace('(( EUID == 0 ))', 'true')
            (self.scripts / name).write_text(text)
        shutil.copy2(ROOT / 'scripts/verificar-pmd-pci.py', self.scripts)
        (self.dev / 'net/eth0').mkdir(parents=True)
        (self.dev / 'net/eth1').mkdir()
        for iface in ('eth0', 'eth1'):
            (self.dev / 'net' / iface / 'flags').write_text('0x1002\n')
        for name, value in dict(vendor='0x8086', device='0x100e', subsystem_vendor='0x8086', subsystem_device='0x0001', **{'class': '0x020000'}).items():
            (self.dev / name).write_text(value + '\n')
        for driver in ('igb', 'vfio-pci', 'e1000e'):
            (self.sys / 'bus/pci/drivers' / driver).mkdir(parents=True)
        self.set_driver('igb')
        (self.group / 'devices').mkdir(parents=True)
        (self.dev / 'iommu_group').symlink_to(self.group)
        (self.group / 'devices' / BDF).symlink_to(self.dev)
        self.pmd = folder / 'lib/dpdk/pmds-test/librte_net_fixture.so'
        self.pmd.parent.mkdir(parents=True)
        self.pmd.write_bytes(b'\x7fELFfixture')
        self.info = folder / 'pmd.json'
        self.info.write_text(json.dumps([{'name': 'net_fixture', 'pci_ids': [{'vendor': '8086', 'device': '100e'}]}]))
        self.env = dict(os.environ, PATH=str(self.bin) + ':/usr/bin:/bin', FIXTURE=str(folder), MODE='')
        self.stub('pkg-config', 'printf "%s/lib\\n" "$FIXTURE"\n')
        self.stub('ldconfig', 'exit 0\n')
        self.stub('modprobe', 'printf "modprobe %s\\n" "$*" >> "$FIXTURE/calls"\n[ "$MODE" != modprobe_fail ]\n')
        self.stub('ip', '''case "$*" in
*-o*addr*)
    [ "$MODE" != addr_fail ] || exit 1
    if [ "$MODE" = ipv6 ] && [ "$2" = -6 ] && [ "$6" = eth1 ]; then
        printf '2: eth1 inet6 2001:db8::1/64 scope global\\n'
    fi ;;
*route*)
    [ "$MODE" != route_fail ] || exit 1
    [ "$MODE" != default6 ] || printf 'default dev eth1\\n'
    [ "$MODE" != route_malformed ] || printf 'default via 2001:db8::1\\n' ;;
*) printf 'unexpected ip mutation\\n' >> "$FIXTURE/calls"; exit 1 ;;
esac
exit 0
''')
        self.stub('dpdk-pmdinfo.py', '''[ "$MODE" != pmd_fail ] || exit 1
if [ "$MODE" = late_up ]; then printf '0x1003\\n' > "$FIXTURE/sys/bus/pci/devices/0000:01:00.0/net/eth1/flags"; fi
cat "$FIXTURE/pmd.json"
''')
        self.stub('dpdk-devbind.py', '''if [ "$1" = --status-dev ]; then
    [ "$MODE" != status_fail ] || exit 1
    printf '0000:01:00.0 drv=vfio-pci unused=vfio-pci,igb,e1000e\\n'
    exit 0
fi
printf 'devbind %s\\n' "$*" >> "$FIXTURE/calls"
[ "$MODE" != bind_fail ] || exit 1
[ "$MODE" != false_success ] || exit 0
rm "$FIXTURE/sys/bus/pci/devices/0000:01:00.0/driver"
ln -s "$FIXTURE/sys/bus/pci/drivers/${1#--bind=}" "$FIXTURE/sys/bus/pci/devices/0000:01:00.0/driver"
''')

    def stub(self, name, code):
        path = self.bin / name
        path.write_text('#!/bin/bash\nset -u\n' + code)
        path.chmod(0o755)

    def set_driver(self, name):
        link = self.dev / 'driver'
        link.unlink(missing_ok=True)
        link.symlink_to(self.sys / 'bus/pci/drivers' / name)

    def run(self, args, expected, no_mutation=False, contains=None):
        global EXECUTIONS
        EXECUTIONS += 1
        before = self.log.read_text() if self.log.exists() else ''
        p = subprocess.run(['bash', str(self.scripts / 'preparar-nic.sh'), *args], env=self.env, capture_output=True, text=True, timeout=15)
        assert p.returncode == expected, (args, p.returncode, p.stdout, p.stderr)
        if no_mutation:
            assert (self.log.read_text() if self.log.exists() else '') == before, p.stdout + p.stderr
        if contains:
            assert contains in p.stdout + p.stderr, p.stdout + p.stderr
        return p


with tempfile.TemporaryDirectory(prefix='academy-preparar-nic-test-') as tmp:
    root = Path(tmp)
    cases = ['vendor_missing', 'vendor_invalid', 'device_invalid', 'non_ethernet', 'mellanox',
             'group_missing', 'group_broken', 'group_shared', 'group_empty', 'group_wrong_member',
             'route_fail', 'default6', 'route_malformed', 'up', 'flags_missing', 'addr_fail', 'ipv6',
             'pmd_missing', 'pmd_not_elf', 'pmd_fail', 'pmd_json', 'pmd_wrong_device', 'pmd_wrong_subsystem',
             'late_up', 'no_pmd_tool']
    for case in cases:
        f = Fixture(root / case); f.env['MODE'] = case
        if case == 'vendor_missing': (f.dev / 'vendor').unlink()
        if case == 'vendor_invalid': (f.dev / 'vendor').write_text('invalido')
        if case == 'device_invalid': (f.dev / 'device').write_text('invalido')
        if case == 'non_ethernet': (f.dev / 'class').write_text('0x010000')
        if case == 'mellanox': (f.dev / 'vendor').write_text('0x15b3')
        if case in ('group_missing', 'group_broken'):
            (f.dev / 'iommu_group').unlink()
            if case == 'group_broken': (f.dev / 'iommu_group').symlink_to(f.sys / 'missing')
        if case == 'group_shared': (f.group / 'devices/0000:02:00.0').symlink_to(f.dev)
        if case == 'group_empty': (f.group / 'devices' / BDF).unlink()
        if case == 'group_wrong_member':
            (f.group / 'devices' / BDF).unlink(); (f.group / 'devices' / BDF).symlink_to(f.sys)
        if case == 'up': (f.dev / 'net/eth1/flags').write_text('0x1003')
        if case == 'flags_missing': (f.dev / 'net/eth1/flags').unlink()
        if case == 'pmd_missing': f.pmd.unlink()
        if case == 'pmd_not_elf': f.pmd.write_bytes(bytes.fromhex('86800e10'))
        if case == 'pmd_json': f.info.write_text('invalid json')
        if case == 'pmd_wrong_device': f.info.write_text('[{"name":"other","pci_ids":[{"vendor":"8086","device":"1234"}]}]')
        if case == 'pmd_wrong_subsystem': f.info.write_text('[{"name":"other","pci_ids":[{"vendor":"8086","device":"100e","subsystem_device":"0002"}]}]')
        if case == 'no_pmd_tool':
            f.stub('dpdk-pmdinfo.py', 'exit 127\n')
        reason = {
            'vendor_missing': 'vendor nao apurado', 'vendor_invalid': 'vendor nao apurado',
            'device_invalid': 'device invalido', 'non_ethernet': 'nao e uma controladora',
            'mellanox': 'Mellanox/mlx5', 'group_missing': 'sem link de grupo',
            'group_broken': 'grupo IOMMU nao apurado', 'group_shared': 'grupo exclusivo',
            'group_empty': 'grupo exclusivo', 'group_wrong_member': 'nao corresponde',
            'route_fail': 'apurar as rotas', 'default6': 'rota default',
            'route_malformed': 'sem interface identificavel', 'up': 'esta UP',
            'flags_missing': 'apurar estado', 'addr_fail': 'enderecos -4',
            'ipv6': 'eth1 tem endereco -6', 'late_up': 'esta UP',
        }.get(case, 'PMD nao confirmado')
        f.run(['01:00.0'], 1, no_mutation=True, contains=reason)
        print('OK recusa sem alterar:', case)

    f = Fixture(root / 'cli')
    for args in (['01:00.0','02:00.0'], [''], ['../outro'], ['01:20.0'], ['01:00.8'],
                 ['--status','--desfazer','01:00.0'], ['--desfazer'], ['--forcar'],
                 ['--driver=igb','01:00.0'], ['--desfazer','--driver=../bad','01:00.0']):
        f.run(args, 2, no_mutation=True)
    f.run(['--status'], 0, no_mutation=True)
    f.env['MODE'] = 'status_fail'; f.run(['--status'], 1, no_mutation=True)
    print('OK parser e status')

    for mode in ('', 'ipv6', 'legacy_ids'):
        f = Fixture(root / ('success_' + mode)); f.env['MODE'] = mode
        if mode == 'legacy_ids': f.info.write_text('[{"name":"legacy","pci_ids":[[32902,4110,65535,65535]]}]')
        f.run(['--forcar', '01:00.0'] if mode == 'ipv6' else ['--pmd=' + str(f.pmd), '01:00.0'], 0)
        assert f.record.read_text().splitlines()[-1] == 'igb'
        assert (f.dev / 'driver').resolve().name == 'vfio-pci'
        f.run(['01:00.0'], 1, no_mutation=True)
        f.run(['--desfazer','--driver=e1000e','01:00.0'], 1, no_mutation=True)
        f.run(['--desfazer','01:00.0'], 0)
        assert not f.record.exists() and (f.dev / 'driver').resolve().name == 'igb'
        print('OK captura, origem e restauracao:', mode or 'normal')

    for mode in ('bind_fail', 'false_success', 'modprobe_fail'):
        f = Fixture(root / mode); f.env['MODE'] = mode
        f.run(['01:00.0'], 1)
        assert f.record.exists(), 'falha apagou origem'
        f.env['MODE'] = ''; f.run(['--desfazer','01:00.0'], 0)
        print('OK falha preserva origem:', mode)

    f = Fixture(root / 'restore'); f.set_driver('vfio-pci')
    f.run(['--desfazer','01:00.0'], 1, no_mutation=True, contains='--driver')
    f.run(['--desfazer','--driver=vfio-pci','01:00.0'], 1, no_mutation=True)
    f.env['MODE'] = 'false_success'
    f.run(['--desfazer','--driver=igb','01:00.0'], 1, contains='nao confirmado')
    f.env['MODE'] = ''; f.run(['--desfazer','--driver=igb','01:00.0'], 0)
    print('OK retorno sem registro exige escolha e confirmacao')

    f = Fixture(root / 'lock'); f.state.mkdir(mode=0o700)
    with (f.state / (BDF + '.lock')).open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        f.run(['01:00.0'], 1, no_mutation=True, contains='outra operacao')
    f.state.chmod(0o777)
    f.run(['01:00.0'], 1, no_mutation=True, contains='modo 700')
    print('OK concorrencia e permissoes do registro')

    for mode in ('up', 'default6', 'addr_fail'):
        f = Fixture(root / ('force_' + mode)); f.env['MODE'] = mode
        if mode == 'up': (f.dev / 'net/eth1/flags').write_text('0x1003')
        reason = {'up': 'esta UP', 'default6': 'rota default', 'addr_fail': 'nao apurados'}[mode]
        f.run(['--forcar','01:00.0'], 1, no_mutation=True, contains=reason)
    print('OK forcar nao ignora estado, rotas ou falhas de consulta')

    f = Fixture(root / 'identity')
    f.run(['01:00.0'], 0)
    (f.dev / 'device').write_text('0x1234')
    f.run(['--desfazer','01:00.0'], 1, no_mutation=True, contains='identidade PCI diverge')
    assert f.record.exists()
    print('OK restauracao recusa identidade diferente e preserva registro')

print(f'L1: {EXECUTIONS} invocacoes da CLI com sysfs e comandos simulados; sem validacao fisica')
