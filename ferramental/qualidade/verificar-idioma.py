#!/usr/bin/env python3
"""Confere que os documentos em ingles nao carregam portugues.

POR QUE ISTO EXISTE

A paridade pt/en foi declarada completa na v1.01.00. Ela nao estava. Sobraram
rotulos de tabela, diagramas ASCII desenhados a mao, comentarios de C e de
shell, e a saida dos programas -- tudo dentro de blocos de codigo, onde busca
por prosa nao chega.

Pior: a deteccao FALHOU QUATRO VEZES SEGUIDAS. Cada varredura era feita por
lista de palavras-chave, declarava o documento limpo, e o caso seguinte
aparecia -- porque a lista nunca cobria o vocabulario inteiro. "antes de
qualquer thread" passou por nao ter acento nem palavra da lista.

A correcao foi trocar adivinhacao por DICIONARIO: uma palavra e portuguesa se
esta no dicionario pt-BR do sistema e nao esta no ingles. Nao depende de quem
escreve lembrar de nenhuma palavra.

O QUE FICA DE FORA, E POR QUE

Identificadores reais do repositorio (`parar_ruido`, `custo-traducao`),
caminhos, nomes de programa, IDs de no do Mermaid e padroes de `grep` que
precisam casar com a saida em portugues dos programas. Esses estao na lista
`MANTER` abaixo, cada um por um motivo, e a lista e a parte deste arquivo que
vai crescer.

REQUISITO

Precisa dos dicionarios do sistema. Sem eles o verificador PULA, e diz que
pulou -- nao finge ter conferido.
  Debian/Ubuntu: apt install wamerican wbrazilian
"""
import collections
import pathlib
import re
import sys
import unicodedata

IGNORAR = {".git", "build", "builddir", "build-precommit", "subprojects", "temp", "__pycache__"}
DIC_EN = "/usr/share/dict/american-english"
DIC_PT = "/usr/share/dict/brazilian"

# Palavras que o dicionario pt-BR reconhece mas que NAO sao portugues aqui.
# Cada entrada existe por um motivo; ao acrescentar, diga qual.
MANTER = {
    # diretorios e arquivos do repositorio
    "trilha", "fundamentos", "medicoes", "alternativas", "plano", "visao",
    "ferramental", "execucao", "validacao", "traducao", "paralelismo", "cadeia",
    "alocacao", "anel", "espera", "comunicacao", "syscall", "sintese",
    # scripts e programas
    "ambiente", "preparar", "diagnostico", "verificar", "inventariar", "custo",
    "efeito", "pipeline", "hello", "probe", "feed", "estado", "sizing",
    # identificadores reais citados no texto
    "parar", "ruido", "amostra", "variavel", "binario", "fatia", "lote", "fila",
    "pool", "bloco", "pacote", "pacotes", "processar", "tamanho", "consumidos",
    "primario", "secundario", "compartilhado", "publicados", "consumidos",
    "producao", "leitura", "estrutura", "estudo", "topico", "opcao", "cadencia",
    # nomes de argumento posicional dos programas, citados nos comandos de
    # reproducao dos dois idiomas -- mesma razao de "cadencia", que ja estava
    "disperso", "sequencial",
    "lidos", "total", "linha", "real", "reais", "papel", "campo", "momento",
    # IDs de no e classes do Mermaid (codigo do diagrama, nao texto exibido)
    "fila", "pilha", "caro", "remoto", "fonte", "perde", "ganha", "vazio",
    # termos tecnicos que os dois idiomas usam
    "cache", "micro", "turbo", "buffer", "kernel", "socket", "hardware",
    "software", "mutex", "prefetcher", "malloc", "memset", "span", "burst",
    # citacoes deliberadas de saida em portugues
    "soquete", "portugues", "português", "leia", "couberam", "nivel", "nível",
    # acronimos e termos que o dicionario pt-BR reconhece por acidente:
    # "numa" e "em uma" em portugues, e NUMA e o acronimo que o material inteiro usa
    "numa", "glossario", "glossary", "fundamentals", "hugepages", "chuge",
    # rotulos de link e nomes de opcao citados em comandos
    "erros", "inexistente", "captura", "rota", "projeto", "isolados", "faixa",
    "desfazer", "chamados", "apipoolcreate",
    # padroes de `grep` que precisam casar com titulos em portugues dos .md
    "quando", "errado", "esqueletos", "documentos",
    # chaves da saida de `ambiente-medicao.sh`, que o leitor vai ver iguais
    "carga",
    # campos e funcoes de `order_book.h`, citados no bloco de codigo da §8.1 e
    # da §9.1 do modulo 02. Traduzi-los faria o documento em ingles mostrar uma
    # estrutura que nao existe no fonte -- e o bloco esta la justamente para
    # que o leitor confira contra o cabecalho.
    "lado", "reservado", "cruzados", "degenerados", "assinatura", "valida",
    "fluxo", "livro", "toleraveis",
    # valores de --file-prefix nos comandos de reproducao do modulo 03. Os dois
    # idiomas mostram o MESMO comando de proposito: o prefixo nomeia um arquivo
    # em /var/run, e traduzi-lo faria os dois documentos criarem instancias
    # diferentes a partir do mesmo passo.
    "esgotado",
    # opcoes de linha de comando do scripts/preparar-dpdk.sh, citadas iguais nos
    # dois idiomas porque sao os nomes reais das flags.
    "conferir", "minimo",
}


def carregar(caminho):
    p = pathlib.Path(caminho)
    if not p.is_file():
        return None
    return {w.split("/")[0].strip().lower()
            for w in p.read_text(encoding="utf-8", errors="ignore").split("\n") if w.strip()}


def sem_acento(w):
    return "".join(c for c in unicodedata.normalize("NFD", w) if not unicodedata.combining(c))


def limpar(linha):
    """Tira o que nao e prosa nem saida: codigo inline, alvos de link, caminhos."""
    linha = re.sub(r"`[^`]*`", "", linha)
    linha = re.sub(r"\]\([^)]*\)", "]", linha)
    linha = re.sub(r"<[^>]*>", "", linha)
    linha = re.sub(r"\S*[/\\]\S*", "", linha)
    linha = re.sub(r"\S+\.(sh|py|c|h|cpp|md|svg|png|json|build)\b", "", linha)
    return linha


def _raiz():
    for d in pathlib.Path(__file__).resolve().parents:
        if (d / "meson.build").is_file() and (d / "docs").is_dir():
            return d
    raise SystemExit("nao achei a raiz do repositorio a partir de " + __file__)


def verificar(raiz, en=None, pt=None):
    en = en if en is not None else carregar(DIC_EN)
    pt = pt if pt is not None else carregar(DIC_PT)
    if en is None or pt is None:
        print("  PULADO: dicionarios do sistema ausentes"
              " (apt install wamerican wbrazilian)")
        return False
    pt_sem = {sem_acento(w) for w in pt}
    raiz = pathlib.Path(raiz)
    achados = collections.defaultdict(list)
    docs = 0
    for f in sorted(raiz.rglob("*.en.md")):
        if any(p in IGNORAR for p in f.parts):
            continue
        docs += 1
        for i, linha in enumerate(f.read_text(encoding="utf-8").split("\n"), 1):
            for w in re.findall(r"[A-Za-zÀ-ÿ]{4,}", limpar(linha)):
                b = w.lower()
                if b in en or b in MANTER or "_" in w:
                    continue
                if b in pt or sem_acento(b) in pt_sem:
                    achados[str(f.relative_to(raiz))].append((i, w, linha.strip()[:70]))
                    break
    total = sum(len(v) for v in achados.values())
    print(f"  {docs} documento(s) em ingles conferidos contra o dicionario pt-BR;"
          f" {total} linha(s) com portugues")
    for arq, v in sorted(achados.items()):
        for i, w, ctx in v[:6]:
            print(f"    {arq}:{i}  [{w}]  {ctx}")
        if len(v) > 6:
            print(f"    ... e mais {len(v) - 6} em {arq}")
    return total > 0


def autoteste():
    import tempfile
    en, pt = {"the", "cost"}, {"custo", "medicao"}
    with tempfile.TemporaryDirectory() as d:
        r = pathlib.Path(d)
        (r / "a.en.md").write_text("the cost is fine\n")
        if verificar(r, en, pt):
            print("  AUTOTESTE FALHOU: texto em ingles foi acusado")
            return True
        (r / "a.en.md").write_text("the medicao is wrong\n")
        if not verificar(r, en, pt):
            print("  AUTOTESTE FALHOU: portugues passou despercebido")
            return True
    print("  autoteste ok: aceita ingles e acusa portugues")
    return False


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else _raiz()) else 0)
