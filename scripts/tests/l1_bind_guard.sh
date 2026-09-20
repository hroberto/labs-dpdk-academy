#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
. "$root/scripts/lib-apuracao.sh"
. "$root/scripts/lib-bind-guard.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/pci/0000:01:00.0/net/eth0" "$tmp/pci/0000:01:00.0/net/eth1" "$tmp/bin"
cat > "$tmp/bin/ip" <<'IP'
#!/usr/bin/env bash
[ "${FAIL_ROUTE:-0}" = 0 ] || exit 1
if [ "$1" = -4 ]; then printf '%s' "${ROUTES4:-}"; else printf '%s' "${ROUTES6:-}"; fi
IP
chmod +x "$tmp/bin/ip"
export PATH="$tmp/bin:$PATH"
export ROUTES4='' ROUTES6='' FAIL_ROUTE=0
printf '0x1002\n' > "$tmp/pci/0000:01:00.0/net/eth0/flags"
printf '0x1002\n' > "$tmp/pci/0000:01:00.0/net/eth1/flags"
check() {
    local expected=$1 rc=0
    nic_bind_guard 0000:01:00.0 "$tmp/pci" || rc=$?
    [ "$rc" = "$expected" ] || { echo "FALHA: $rc esperado $expected: $NIC_BIND_REASON"; exit 1; }
    [ "$rc" = 0 ] || [ -n "$NIC_BIND_REASON" ]
    echo "OK: $2"
}
check 0 'interfaces DOWN e rotas vazias apuradas'
ROUTES4=$'default dev outra\ndefault via 192.0.2.1 dev eth1\n'
check 1 'segunda rota default protegida'
ROUTES4=''; ROUTES6='default dev eth0'
check 1 'rota IPv6 protegida'
ROUTES6=''; FAIL_ROUTE=1
check 1 'falha da consulta recusa captura'
FAIL_ROUTE=0; ROUTES4='default via 192.0.2.1'
check 1 'rota sem interface nao vira ausencia'
ROUTES4=''
printf '0x1003\n' > "$tmp/pci/0000:01:00.0/net/eth1/flags"
check 1 'interface UP protegida'
printf 'invalido\n' > "$tmp/pci/0000:01:00.0/net/eth1/flags"
check 1 'flags invalidos recusados'
rm "$tmp/pci/0000:01:00.0/net/eth1/flags"
check 1 'estado ausente recusado'
for mode in vazio invalido duplicado; do
    args=()
    case "$mode" in
        invalido) args=('../outro') ;;
        duplicado) args=('0000:01:00.0' '0000:02:00.0') ;;
    esac
    rc=0
    bash "$root/scripts/diagnostico-nic.sh" "${args[@]}" > "$tmp/cli" 2>&1 || rc=$?
    [ "$rc" -eq 2 ] || { cat "$tmp/cli"; exit 1; }
    echo "OK: CLI recusa alvo $mode antes de consultar o host"
done
