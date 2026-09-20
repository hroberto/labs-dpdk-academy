#!/usr/bin/env python3
"""Confere que macro com `getenv()` nao aparece na condicao de um laco medido.

POR QUE ISTO EXISTE

`statistics.h` oferece `samples()` e `rounds()` para a CI poder baixar o custo
das medicoes por variavel de ambiente. As duas chamam `getenv()`.

Em `custo-espera.c` a macro estava na CONDICAO do laco:

    for (int i = 0; i < RODADAS_PRIMITIVO; i++)   /* rounds(2000000) */

O compilador nao pode remover a chamada -- `getenv()` tem efeito observavel --
entao cada iteracao varria o ambiente inteiro. Medido em 18/09/2026, no mesmo
laco: 30,649 ns com a macro na condicao, 0,204 ns com o valor lido uma vez
antes. CENTO E CINQUENTA VEZES, somados a uma operacao atomica que custa 0,2 ns.

O QUE ISSO CUSTOU, E POR QUE NINGUEM VIU

A tabela do 5.2 foi publicada em bf57672. As macros entraram sete minutos
depois, em 25b3547, para tornar a CI viavel. Ninguem reexecutou. O instrumento
passou a devolver numeros ate 150 vezes maiores, e:

  - nenhum numero publicado mudou, porque publicar e colar a saida a mao;
  - a suite continuou verde, porque ela verifica que o programa EXECUTA;
  - o selo continuou limpo, porque a dispersao seguiu baixa -- o erro era
    sistematico, e erro sistematico nao aparece em dispersao.

Um portao que so pergunta "rodou?" nao pega instrumento que mente com
consistencia.

O QUE ESTE VERIFICADOR PEGA

A forma sintatica, que e deterministica: identificador definido como macro que
expande para `rounds(...)` ou `samples(...)`, usado em condicao de `for` ou
`while`. Nao pega um instrumento errado por outra razao -- para isso serve
reexecutar e comparar, que e trabalho de gente.
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]
FONTES = ("*.c", "*.cpp", "*.h")
# re.M NAO E DETALHE: sem ele, `^` so casa no inicio do ARQUIVO, e o
# verificador nunca acha um `#define` que nao seja a primeira linha. Ele passou
# no proprio autoteste assim, porque o caso de teste tinha o define na linha 1 --
# autoteste que nao reproduz a forma do arquivo real da verde de mentira.
CHAMA_GETENV = re.compile(r"^\s*#\s*define\s+(\w+)\s+.*\b(rounds|samples)\s*\(",
                          re.M)
LACO = re.compile(r"\b(for|while)\s*\(")


def conferir(caminho):
    texto = caminho.read_text(errors="replace")
    macros = set(CHAMA_GETENV.findall(texto))
    nomes = {m[0] for m in macros}
    if not nomes:
        return []
    falhas = []
    for n, linha in enumerate(texto.split("\n"), 1):
        # Comentario que EXPLICA o defeito nao e o defeito. Sem esta linha o
        # verificador acusava a propria nota que documenta a regra.
        if linha.lstrip().startswith(("*", "//", "/*")):
            continue
        if not LACO.search(linha):
            continue
        # so o miolo da condicao interessa
        cond = linha[linha.index("("):]
        for nome in nomes:
            if re.search(rf"\b{re.escape(nome)}\b", cond):
                falhas.append((n, nome, linha.strip()[:88]))
    return falhas


def autoteste():
    """O laco culpado tem de ser acusado; o valor hasteado tem de passar."""
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        alvo = pathlib.Path(d) / "t.c"
        # O define NAO fica na primeira linha: era assim que este autoteste
        # dava verde com o verificador cego.
        alvo.write_text("#include <stdio.h>\n\n/* comentario */\n"
                        "#define N rounds(2000000)\n"
                        "void f(void){for (int i = 0; i < N; i++) g();}\n")
        if not conferir(alvo):
            print("  AUTOTESTE FALHOU: macro com getenv na condicao passou")
            return True
        alvo.write_text("#include <stdio.h>\n#define N rounds(2000000)\n"
                        "void f(void){const int n = N;\n"
                        "for (int i = 0; i < n; i++) g();}\n")
        if conferir(alvo):
            print("  AUTOTESTE FALHOU: valor hasteado foi acusado")
            return True
        alvo.write_text("#include <stdio.h>\n#define N 2000000\n"
                        "void f(void){for (int i = 0; i < N; i++) g();}\n")
        if conferir(alvo):
            print("  AUTOTESTE FALHOU: macro sem getenv foi acusada")
            return True
    print("  autoteste ok: acusa macro com getenv no laco, aceita valor hasteado"
          " e macro constante")
    return False


def main():
    if "--autoteste" in sys.argv:
        return 1 if autoteste() else 0
    arquivos = [p for padrao in FONTES for p in RAIZ.rglob(padrao)
                if "build" not in str(p) and ".git" not in str(p)]
    falhas = 0
    for caminho in sorted(arquivos):
        for n, nome, linha in conferir(caminho):
            falhas += 1
            print(f"{caminho.relative_to(RAIZ)}:{n}: `{nome}` chama getenv() e "
                  f"esta na condicao do laco\n    {linha}")
    print(f"  {len(arquivos)} fonte(s) conferida(s); {falhas} laco(s) com "
          f"getenv() por iteracao")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
