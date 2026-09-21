#!/usr/bin/env python3
"""Confere o que a suite DEIXOU PARA TRAS no sistema, alem de passar ou falhar.

POR QUE ISTO EXISTE

Em 21/09/2026 a suite estava verde e o `l3_multiprocesso.sh` vazava uma
hugepage de 2 MB por execucao. A limpeza do teste removia
`/dev/hugepages/${PREFIXO}*`, com o caminho fixo no codigo, enquanto o teste
rodava com `--huge-dir=$DPDK_ACADEMY_HUGE_DIR`. O arquivo ficava no diretorio
que a limpeza nao olhava.

Nada acusou. O teste passava, o portao ficava verde, e o defeito so apareceu
porque uma pane de video levou a inspecionar o log do sistema por outro motivo.

O ponto que isso estabelece: **passar e deixar o sistema limpo sao duas
afirmacoes diferentes**, e o `meson test` so faz a primeira. Uma suite que
passa vazando recurso e um verde que vale menos do que anuncia -- e o custo
aparece longe, quando uma campanha de medicao falha por falta de hugepage e a
causa parece ser a campanha.

O QUE ELE CONFERE

1. Arquivos residuais nos diretorios hugetlbfs, criados durante a janela.
2. Diretorios de runtime do DPDK (`/var/run/dpdk/<prefixo>`) idem.
3. Paginas livres antes e depois -- corroboracao, nao gatilho: outra coisa na
   maquina pode consumir pagina, e um verificador que acusa o vizinho e
   desligado.
4. O journal do sistema na janela: segfault, trap, OOM e morte por sinal de
   binario nosso.
5. Processos nossos ainda vivos depois que a suite terminou.

O QUE ELE DELIBERADAMENTE NAO FAZ

Nao roda a suite. Ele marca o estado antes e confere depois, para que a janela
seja exatamente a da execucao e nao "desde o boot" -- um verificador que olha
desde o boot acusa o que aconteceu ontem.

Nao falha por journal indisponivel. Mas TAMBEM NAO CALA: a linha de resultado
diz quantas dimensoes foram conferidas e quais nao foram. SKIP silencioso ja
custou a este repositorio, e a regra e que ausencia de verificacao apareca.

USO

    rastros-da-suite.py --marcar  > marca.json
    ... roda a suite ...
    rastros-da-suite.py --conferir marca.json
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

# Prefixos de --file-prefix usados pelos testes e pelos comandos publicados.
# Um arquivo em hugetlbfs que comece por um destes e nosso.
PREFIXOS = ("academia", "topico", "alocacao", "anel", "mbuf", "esgotado",
            "contencao", "producao", "feed", "pipeline", "rte_")

PADRAO_JORNAL = re.compile(
    r"segfault|general protection|traps:|oom-kill|Out of memory|"
    r"Killed process|core dumped", re.I)


def _raiz():
    for d in pathlib.Path(__file__).resolve().parents:
        if (d / "meson.build").is_file() and (d / "docs").is_dir():
            return d
    raise SystemExit("nao achei a raiz do repositorio")


def _dirs_huge():
    d = ["/dev/hugepages"]
    extra = os.environ.get("DPDK_ACADEMY_HUGE_DIR")
    if extra:
        d.append(extra)
    return [p for p in d if pathlib.Path(p).is_dir()]


def _dirs_runtime():
    base = os.environ.get("XDG_RUNTIME_DIR", "/var/run")
    return [p for p in (f"{base}/dpdk", "/var/run/dpdk")
            if pathlib.Path(p).is_dir()]


def _listar(dirs):
    """Nome -> mtime, so do que parece nosso."""
    out = {}
    for d in dirs:
        try:
            for f in pathlib.Path(d).iterdir():
                if f.name.startswith(PREFIXOS):
                    try:
                        out[str(f)] = f.stat().st_mtime
                    except OSError:
                        out[str(f)] = 0.0
        except PermissionError:
            continue
    return out


def _paginas_livres():
    try:
        for linha in pathlib.Path("/proc/meminfo").read_text().splitlines():
            if linha.startswith("HugePages_Free:"):
                return int(linha.split()[1])
    except OSError:
        pass
    return None


def _binarios(raiz):
    """Nomes dos executaveis que o projeto constroi."""
    nomes = set()
    for b in ("build", "builddir", "build-precommit"):
        d = raiz / b
        if not d.is_dir():
            continue
        for f in d.rglob("*"):
            if f.is_file() and os.access(f, os.X_OK) and "." not in f.name:
                nomes.add(f.name)
    return nomes


def marcar():
    return {
        "quando": datetime.datetime.now().astimezone().isoformat(),
        "huge": _listar(_dirs_huge()),
        "runtime": _listar(_dirs_runtime()),
        "paginas_livres": _paginas_livres(),
    }


def _jornal(desde):
    """Linhas do journal na janela, ou None se indisponivel."""
    if not shutil.which("journalctl"):
        return None
    try:
        r = subprocess.run(
            ["journalctl", "--since", desde, "--no-pager", "-q"],
            capture_output=True, text=True, timeout=60)
    except (subprocess.SubprocessError, OSError):
        return None
    if r.returncode != 0 and not r.stdout:
        return None
    return r.stdout.splitlines()


def _vivos(nomes):
    if not nomes or not shutil.which("pgrep"):
        return []
    achados = []
    for n in sorted(nomes):
        try:
            r = subprocess.run(["pgrep", "-x", n], capture_output=True,
                               text=True, timeout=10)
        except (subprocess.SubprocessError, OSError):
            continue
        if r.returncode == 0:
            achados.append(n)
    return achados


def conferir(marca, raiz=None):
    raiz = pathlib.Path(raiz) if raiz else _raiz()
    falhas, notas, dimensoes, nao_conferidas = [], [], 0, []

    # 1 e 2 -- residuos que nao existiam antes.
    dimensoes += 2
    for rotulo, dirs, antes in (
            ("hugetlbfs", _dirs_huge(), marca.get("huge", {})),
            ("runtime do DPDK", _dirs_runtime(), marca.get("runtime", {}))):
        agora = _listar(dirs)
        novos = sorted(set(agora) - set(antes))
        for n in novos:
            falhas.append(f"residuo em {rotulo}: {n}")

    # 3 -- paginas livres: corroboracao, nunca gatilho.
    antes_p = marca.get("paginas_livres")
    agora_p = _paginas_livres()
    if antes_p is None or agora_p is None:
        nao_conferidas.append("paginas livres")
    else:
        dimensoes += 1
        if agora_p < antes_p:
            notas.append(f"HugePages_Free caiu de {antes_p} para {agora_p}"
                         f" ({antes_p - agora_p} pagina(s))")

    # 4 -- journal na janela.
    linhas = _jornal(marca["quando"])
    if linhas is None:
        nao_conferidas.append("journal do sistema")
    else:
        dimensoes += 1
        nomes = _binarios(raiz)
        for l in linhas:
            if not PADRAO_JORNAL.search(l):
                continue
            # So acusa quando a linha cita binario nosso; o resto da maquina
            # nao e problema deste verificador.
            if any(n in l for n in nomes) or "hugepage" in l.lower():
                falhas.append(f"journal: {l.strip()[:120]}")

    # 5 -- processos nossos sobreviventes.
    if shutil.which("pgrep"):
        dimensoes += 1
        for n in _vivos(_binarios(raiz)):
            falhas.append(f"processo ainda vivo apos a suite: {n}")
    else:
        nao_conferidas.append("processos vivos")

    for f in falhas:
        print(f"    {f}")
    for n in notas:
        print(f"    (nota) {n}")
    resumo = f"  {dimensoes} dimensao(oes) de rastro conferida(s);" \
             f" {len(falhas)} residuo(s)"
    if nao_conferidas:
        resumo += f"; NAO CONFERIDO: {', '.join(nao_conferidas)}"
    print(resumo)
    return bool(falhas)


def autoteste():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        os.environ["DPDK_ACADEMY_HUGE_DIR"] = d
        m = marcar()
        if conferir(m, _raiz()):
            print("  AUTOTESTE FALHOU: sistema limpo foi acusado")
            return True
        # Um residuo com prefixo nosso tem de ser acusado.
        pathlib.Path(d, "academia_l2_999map_0").write_text("x")
        if not conferir(m, _raiz()):
            print("  AUTOTESTE FALHOU: residuo nao foi acusado")
            return True
        pathlib.Path(d, "academia_l2_999map_0").unlink()
        # Arquivo que nao e nosso nao e problema nosso.
        pathlib.Path(d, "libvirt-qemu-algo").write_text("x")
        if conferir(m, _raiz()):
            print("  AUTOTESTE FALHOU: arquivo de terceiro foi acusado")
            return True
        del os.environ["DPDK_ACADEMY_HUGE_DIR"]
    print("  autoteste ok: acusa residuo nosso, ignora arquivo de terceiro,"
          " aceita sistema limpo")
    return False


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--marcar", action="store_true")
    ap.add_argument("--conferir", metavar="ARQUIVO")
    ap.add_argument("--autoteste", action="store_true")
    a = ap.parse_args()
    if a.autoteste:
        sys.exit(1 if autoteste() else 0)
    if a.marcar:
        json.dump(marcar(), sys.stdout)
        sys.exit(0)
    if a.conferir:
        with open(a.conferir, encoding="utf-8") as fh:
            sys.exit(1 if conferir(json.load(fh)) else 0)
    ap.error("use --marcar, --conferir ARQUIVO ou --autoteste")
