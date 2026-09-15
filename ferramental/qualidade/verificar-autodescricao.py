#!/usr/bin/env python3
"""Confere afirmações que o material faz SOBRE SI MESMO.

POR QUE ISTO EXISTE

As duas afirmações mais fáceis de deixar envelhecer são as que o projeto faz a
respeito do próprio projeto. Elas não saem de medição nenhuma, ninguém as
reexecuta, e o texto continua dizendo o que era verdade no dia em que foi
escrito. Dois casos reais, encontrados em 15/09/2026:

- `trilha/02-pipeline/01-rx-tx-burst/README.md` carregava o banner "**Esqueleto.**
  Registra escopo e compromissos; o conteúdo ainda não foi escrito" -- em 268
  linhas, das quais cerca de 200 eram verificação de ambiente e capacidades de
  NIC medidas com ferramenta real. O documento mentia sobre si para menos;

- `README.md` declarava como requisito "Linux x86_64 **ou arm64**", enquanto
  quatro programas de medição chamavam `__builtin_ia32_pause()` em doze pontos
  sem nenhuma guarda de arquitetura. Em arm64 não compilam. O documento
  prometia uma plataforma que o código não sustentava.

Nenhum dos dois é detectável por quem lê o documento: o primeiro exige contar
linhas, o segundo exige cruzar a porta de entrada com o código. As duas contas
são triviais para um programa e improváveis para uma pessoa.

REGRA 1 -- banner de esqueleto contra conteúdo real

Um documento que se declara esqueleto e tem mais que LIMITE_ESQUELETO linhas de
conteúdo (fora banner, navegação e linhas vazias) falha. O limite é folgado de
propósito: um esqueleto legítimo registra objetivo, escopo e entregáveis, e isso
cabe com sobra.

REGRA 2 -- plataforma prometida contra guarda no código

Arquivo de código que usa construto específico de arquitetura precisa conter
guarda de arquitetura. A guarda pode ser direta (`__x86_64__`, `__aarch64__`) ou
vir do cabeçalho do projeto que encapsula a escolha (`cpu_pause.h`).

O QUE ELE DELIBERADAMENTE NÃO PEGA:

- promessa de plataforma em outros documentos que não o `README.md`;
- construto específico de arquitetura que o compilador aceite em ambas mas se
  comporte diferente (não é sobre compilar, é sobre semântica);
- banner de esqueleto ausente em documento que DEVERIA tê-lo -- o inverso desta
  regra, que exige julgar o que é conteúdo suficiente;
- qualquer outra afirmação do material sobre si (cobertura, níveis, estado).
"""
import os
import re
import sys

IGNORAR = {".git", "build", "subprojects", "__pycache__"}

LIMITE_ESQUELETO = 80

BANNER = re.compile(r"^>\s*\*\*Esqueleto\.\*\*", re.MULTILINE)

# Construtos que só existem em x86. Se a lista crescer, o teste cresce junto.
SO_X86 = ("__builtin_ia32_", "_mm_", "__rdtsc")
GUARDAS = ("__x86_64__", "__i386__", "__aarch64__", "cpu_pause.h", "ACADEMY_CPU_PAUSE_H")

# "Linux x86_64 ou arm64" na porta de entrada.
PROMESSA_ARM = re.compile(r"arm64|aarch64", re.IGNORECASE)


def arquivos(raiz, exts):
    for pasta, subpastas, nomes in os.walk(raiz):
        subpastas[:] = [d for d in subpastas if d not in IGNORAR and not d.startswith("build")]
        for nome in nomes:
            if os.path.splitext(nome)[1] in exts:
                yield os.path.join(pasta, nome)


def linhas_de_conteudo(texto):
    """Linhas que não são vazias, banner, citação de cabeçalho nem navegação."""
    dentro_nav = False
    n = 0
    for linha in texto.splitlines():
        s = linha.strip()
        if s.startswith("## Navegação"):
            dentro_nav = True
            continue
        if dentro_nav:
            continue
        if not s or s.startswith(">") or s.startswith("#"):
            continue
        if set(s) <= set("|-: "):
            continue
        n += 1
    return n


def verificar(raiz="."):
    problemas = 0
    conferidos = 0

    # --- Regra 1 -----------------------------------------------------------
    for doc in sorted(arquivos(raiz, {".md"})):
        try:
            texto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        if not BANNER.search(texto):
            continue
        conferidos += 1
        n = linhas_de_conteudo(texto)
        if n > LIMITE_ESQUELETO:
            print(f"  {os.path.relpath(doc, raiz)}: declara-se ESQUELETO"
                  f" ('o conteúdo ainda não foi escrito') e tem {n} linhas de conteúdo"
                  f" (limite: {LIMITE_ESQUELETO})")
            problemas += 1

    # --- Regra 2 -----------------------------------------------------------
    readme = os.path.join(raiz, "README.md")
    promete_arm = False
    if os.path.exists(readme):
        try:
            promete_arm = bool(PROMESSA_ARM.search(open(readme, encoding="utf-8").read()))
        except (OSError, UnicodeDecodeError):
            pass

    if promete_arm:
        for src in sorted(arquivos(raiz, {".c", ".h", ".cpp", ".hpp"})):
            try:
                texto = open(src, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            usados = [t for t in SO_X86 if t in texto]
            if not usados:
                continue
            conferidos += 1
            if not any(g in texto for g in GUARDAS):
                print(f"  {os.path.relpath(src, raiz)}: usa {', '.join(usados)}"
                      f" (só x86) sem guarda de arquitetura, e o README.md promete arm64")
                problemas += 1

    print(f"\n  {conferidos} afirmação(ões) sobre o próprio material conferida(s);"
          f" {problemas} não se sustenta(m)")
    if not promete_arm:
        print("  (o README.md não promete arm64: a regra 2 não foi aplicada)")
    return problemas


def autoteste():
    import io as _io
    import tempfile
    from contextlib import redirect_stdout

    def rodar(arqs):
        with tempfile.TemporaryDirectory() as d:
            for nome, conteudo in arqs.items():
                caminho = os.path.join(d, nome)
                os.makedirs(os.path.dirname(caminho), exist_ok=True)
                open(caminho, "w", encoding="utf-8").write(conteudo)
            buf = _io.StringIO()
            with redirect_stdout(buf):
                rc = verificar(d)
            return rc, buf.getvalue()

    falhas = 0
    esqueleto = "# t\n\n> **Esqueleto.** O conteúdo ainda não foi escrito.\n\n"

    # 1. Esqueleto de verdade: passa.
    rc, _ = rodar({"e.md": esqueleto + "## Objetivo\n\nRegistrar escopo.\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: esqueleto legítimo acusado"); falhas += 1

    # 2. Banner mentindo sobre 200 linhas de conteúdo: falha.
    rc, _ = rodar({"e.md": esqueleto + "\n".join(f"linha {i} de conteudo real."
                                                 for i in range(200))})
    if rc != 1:
        print(f"  AUTOTESTE FALHOU: banner falso passou (rc={rc})"); falhas += 1

    # 3. Promessa de arm64 com builtin x86 sem guarda: falha.
    rc, _ = rodar({"README.md": "# p\n\n- Linux x86_64 ou arm64\n",
                   "src/a.c": "void f(void){ __builtin_ia32_pause(); }\n"})
    if rc != 1:
        print(f"  AUTOTESTE FALHOU: promessa arm64 sem guarda passou (rc={rc})"); falhas += 1

    # 4. O mesmo builtin COM guarda: passa.
    rc, _ = rodar({"README.md": "# p\n\n- Linux x86_64 ou arm64\n",
                   "src/a.c": "#if defined(__x86_64__)\nvoid f(void){ __builtin_ia32_pause(); }\n#endif\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: guarda de arquitetura não reconhecida"); falhas += 1

    # 5. Sem promessa de arm64, o mesmo código não é defeito: a regra não se aplica.
    rc, _ = rodar({"README.md": "# p\n\n- Linux x86_64\n",
                   "src/a.c": "void f(void){ __builtin_ia32_pause(); }\n"})
    if rc != 0:
        print("  AUTOTESTE FALHOU: regra 2 aplicada sem a promessa"); falhas += 1

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else ".") else 0)
