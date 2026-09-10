#!/usr/bin/env python3
"""Resolve a âncora Doxygen de um símbolo do DPDK na documentação oficial.

POR QUE ESTE SCRIPT EXISTE

Uma URL de API com fragmento errado devolve HTTP 200 do mesmo jeito — o
fragmento é resolvido no navegador. Pior: páginas Doxygen têm muitas âncoras
próximas umas das outras, então heurísticas de proximidade ("a âncora mais
perto do nome") apontam para o símbolo VIZINHO com facilidade. Já produziram,
neste repositório, links de `rte_eal_init` que levavam a `rte_eal_process_type`
e de `rte_ring_enqueue_burst` que levavam à variante `_sp_`.

O único critério confiável é o título do bloco de detalhe (`memtitle`), que o
Doxygen preenche com o nome exato do símbolo. É o que este script compara.

Uso:
    scripts/ancora-dpdk.py rte__ring_8h.html rte_ring_dequeue_burst
    scripts/ancora-dpdk.py --verificar   # confere o mapa inteiro
"""
import html
import re
import sys
import urllib.request

BASE = "https://doc.dpdk.org/api/"

# Mapa canônico: símbolo -> página. Mantenha em sincronia com
# scripts/mapa-links-dpdk.md.
MAPA = {
    "rte_eal_init": "rte__eal_8h.html",
    "rte_eal_cleanup": "rte__eal_8h.html",
    "rte_lcore_count": "rte__lcore_8h.html",
    "rte_socket_id": "rte__lcore_8h.html",
    "rte_eth_dev_info_get": "rte__ethdev_8h.html",
    "rte_eth_dev_socket_id": "rte__ethdev_8h.html",
    "rte_eth_tx_burst": "rte__ethdev_8h.html",
    "rte_eth_dev_rx_intr_enable": "rte__ethdev_8h.html",
    "rte_pktmbuf_pool_create": "rte__mbuf_8h.html",
    "rte_mempool_put_bulk": "rte__mempool_8h.html",
    "rte_ring_enqueue_burst": "rte__ring_8h.html",
    "rte_ring_dequeue_burst": "rte__ring_8h.html",
    # Runtime (modulo 02): processo, memoria nomeada, lcores e relogio.
    "rte_eal_process_type": "rte__eal_8h.html",
    "rte_eal_iova_mode": "rte__eal_8h.html",
    "rte_memzone_reserve": "rte__memzone_8h.html",
    "rte_memzone_lookup": "rte__memzone_8h.html",
    "rte_memzone_free": "rte__memzone_8h.html",
    "rte_eal_remote_launch": "rte__launch_8h.html",
    "rte_eal_wait_lcore": "rte__launch_8h.html",
    "rte_eal_get_lcore_state": "rte__launch_8h.html",
    "rte_get_main_lcore": "rte__lcore_8h.html",
    "rte_lcore_to_socket_id": "rte__lcore_8h.html",
    "rte_lcore_to_cpu_id": "rte__lcore_8h.html",
    "rte_lcore_cpuset": "rte__lcore_8h.html",
    "rte_get_tsc_hz": "rte__cycles_8h.html",
    "rte_get_tsc_cycles": "rte__cycles_8h.html",
    "rte_pause": "rte__pause_8h.html",
    # Nivel 4: mempool, ring e mbuf.
    "rte_mempool_get": "rte__mempool_8h.html",
    "rte_mempool_get_bulk": "rte__mempool_8h.html",
    "rte_ring_create": "rte__ring_8h.html",
    "rte_ring_enqueue_bulk": "rte__ring_8h.html",
    "rte_pktmbuf_alloc": "rte__mbuf_8h.html",
    "rte_pktmbuf_free": "rte__mbuf_8h.html",
    "rte_pktmbuf_prepend": "rte__mbuf_8h.html",
    "rte_pktmbuf_chain": "rte__mbuf_8h.html",
}

# Este MAPA precisa acompanhar scripts/mapa-links-dpdk.md: o modo --verificar so
# confere o que esta aqui, entao simbolo registrado no documento e ausente daqui
# passa a nao ser verificado -- sem nenhum aviso.


def baixar(pagina):
    req = urllib.request.Request(BASE + pagina, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")


def limpar(trecho):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", trecho))).strip()


def resolver(pagina, simbolo, html_txt=None):
    """Devolve a âncora cujo bloco de detalhe titula exatamente `simbolo`."""
    h = html_txt if html_txt is not None else baixar(pagina)
    for m in re.finditer(r'id="(a[0-9a-f]{32})"', h):
        seg = h[m.end() : m.end() + 2500]
        t = re.search(r'class="memtitle">(.*?)</div>', seg, re.S)
        if not t:
            continue
        titulo = limpar(t.group(1))
        # memtitle vem como "◆ nome_do_simbolo()"; exige casamento exato
        nome = re.search(r"([A-Za-z_][A-Za-z_0-9]*)\s*\(\)", titulo)
        if nome and nome.group(1) == simbolo:
            return m.group(1)
    return None


def verificar_tudo():
    cache, falhas = {}, 0
    for simbolo, pagina in sorted(MAPA.items()):
        if pagina not in cache:
            cache[pagina] = baixar(pagina)
        anc = resolver(pagina, simbolo, cache[pagina])
        if anc:
            print(f"  {simbolo:<28} {BASE}{pagina}#{anc}")
        else:
            print(f"  {simbolo:<28} NAO RESOLVIDO em {pagina}")
            falhas += 1
    return falhas


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--verificar":
        sys.exit(1 if verificar_tudo() else 0)
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    a = resolver(sys.argv[1], sys.argv[2])
    print(f"{BASE}{sys.argv[1]}#{a}" if a else "NAO RESOLVIDO")
    sys.exit(0 if a else 1)
