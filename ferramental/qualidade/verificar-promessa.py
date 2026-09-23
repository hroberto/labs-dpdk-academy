#!/usr/bin/env python3
"""Confere que o material só cita programas que a árvore de fato entrega.

POR QUE ISTO EXISTE

Este projeto não promete que o leitor ENTENDA — promete que ele consiga REFAZER.
As 17 promessas executáveis do corpus são todas da mesma forma: "Rode `X` e
observe `Y`". Nenhuma é pergunta de compreensão. Isso foi medido, não suposto, e
muda o que dá para verificar: clareza não tem proxy sintático, mas "o programa
citado existe e é construído" é decidível por caminho.

E é uma promessa que este repositório JÁ QUEBROU DUAS VEZES, pelo mesmo
mecanismo -- um `git filter-branch` faz checkout ao terminar e descarta o que não
estava commitado:

  - `trilha/.../cpp23/controle-anel.cpp` ficou na árvore sem registro em
    meson.build nenhum, e sem compilar, porque a API de lote de `packet.hpp`
    nunca chegou a ser commitada. O portão de "build limpo, zero avisos" não o
    enxergava: fonte que ninguém referencia não entra na compilação, e o portão
    anunciava que tinha conferido;
  - `scripts/tests/l1_preparar_nic.py` foi DESREGISTRADO do meson.build quando o
    script que ele testava perdeu metade da implementação. O teste continuou no
    disco, válido, sem nunca rodar.

Nos dois casos a documentação seguiu citando o que existia no texto e não na
compilação. Um leitor que tentasse seguir o material bateria num arquivo que não
compila ou num programa que não é gerado -- e descobriria isso sozinho, depois
de perder tempo, que é a pior forma de descobrir.

AS DUAS REGRAS

REGRA 1 -- todo programa citado existe.
    Um token entre crases que TEM CARA de programa deste projeto (minúsculas
    separadas por HÍFEN, ou terminado em .sh/.py) precisa ser: um alvo de
    `executable()` em algum meson.build, um arquivo da árvore, ou uma ferramenta
    externa DECLARADA na lista abaixo.

REGRA 3 -- todo comando `./caminho.sh` de bloco de código aponta para arquivo.
    Um bloco ```bash com `./scripts/foo.sh` é a forma mais literal da promessa
    executável: o leitor vai copiar e colar. Se o arquivo não existir, ele
    descobre sozinho, depois de tentar.

    Só entram caminhos que começam com `./`, resolvidos a partir da RAIZ do
    repositório -- que é de onde este projeto manda rodar tudo. Um comando sem
    `./` (`meson`, `dpdk-testpmd`) é ferramenta do sistema e não é conferido
    aqui; quem cuida dele é a regra 1.

REGRA 2 -- toda fonte da trilha entra na compilação.
    Todo `.c`/`.cpp` sob `docs/` e `trilha/` precisa ser referenciado por algum
    meson.build. Fonte órfã não é compilada, e portanto não é conferida por nada
    -- nem pelo compilador, nem pela suíte, nem pelo portão que anuncia "build
    limpo".

O CUSTO DESTA VERIFICAÇÃO, declarado

A lista `EXTERNAS` precisa de manutenção. Não há como distinguir por sintaxe o
nome de um pacote (`dpdk-dev`, `rdma-core`) do nome de um programa deste projeto
(`preparar-nic.sh`): os dois são minúsculas com hífen. Quem citar uma ferramenta
externa nova precisa declará-la aqui, e o erro dirá exatamente isso.

Essa manutenção é o preço de a regra não ter falso negativo. A alternativa --
adivinhar por heurística o que é pacote e o que é programa -- trocaria trabalho
por silêncio, e silêncio é o modo de falha que este arquivo existe para impedir.

O QUE ELE DELIBERADAMENTE NÃO PEGA

- se o programa citado FAZ o que o texto diz que faz: isso é o que a suíte mede;
- se o exercício é respondível: promessa executável se cumpre executando, e a
  execução é dos testes L2/L3, não deste verificador;
- programa citado dentro de bloco de código SEM `./`: ali é saída de terminal ou
  exemplo. Com `./`, é a regra 3 -- e a distinção foi aprendida errando: o
  projeto final mandava rodar `./ferramental/af-xdp/xdp-zerocopy.sh` meses depois
  de o AF_XDP sair do repositório, e a regra 1 não via porque ignorava blocos;
- clareza da prosa, que não tem proxy sintático -- quatro instrumentos foram
  testados contra este corpus e os quatro produziram ruído.
"""
import os
import re
import sys

IGNORAR = {".git", "build", "subprojects", "__pycache__", "temp"}

# Ferramentas EXTERNAS que o material cita e a árvore não entrega: compiladores,
# gerenciadores de pacote, utilitários do sistema, pacotes de distribuição e
# módulos de kernel. Cada entrada é uma declaração de que a ausência dela na
# árvore é esperada, e não um defeito.
EXTERNAS = {
    # cadeia de build e desenvolvimento
    "clang-format", "clang-tidy", "google-benchmark", "pkg-config", "ldconfig",
    # pacotes de distribuição
    "dpdk-dev", "dpdk-devel", "rdma-core", "libibverbs1", "ibverbs-providers",
    # ferramentas do DPDK, instaladas junto com ele
    "dpdk-devbind.py", "dpdk-testpmd", "dpdk-pmdinfo.py", "dpdk-hugepages.py",
    # modulos de kernel e dispositivos virtuais
    "vfio-pci", "pci-stub", "igb-uio", "vhost-user", "virtio-net", "net-null",
    "net-tap", "af-packet", "uio-pci-generic",
    # utilitarios do sistema
    "ibv-devinfo", "xdp-sock", "bpf-tool", "numa-ctl",
    # nomes de EVENTO do `perf stat`, citados na tabela de fontes de parada do
    # topico de isolamento. Nao sao programas: sao contadores que o perf expoe,
    # e a ausencia deles na arvore e a unica forma possivel.
    "ctx-switches",
    # drivers de escalonamento de frequencia, citados pelo submodulo de
    # benchmarking: sao do kernel, nao da arvore
    "amd-pstate", "amd-pstate-epp", "intel-pstate", "acpi-cpufreq",
}

# Um token com CARA de programa deste projeto: HIFEN separando, ou terminado em
# .sh/.py. Palavra unica fica de fora (`meson`, `cat`), e SUBLINHADO tambem.
#
# A regra do hifen nao e estetica, e saiu da medicao. A primeira versao aceitava
# sublinhado e produziu 48 falsos positivos contra este corpus -- `buf_len`,
# `sem_wait`, `sk_buff`, `seq_cst`, `constant_tsc`, `net_null` --, todos
# identificadores de C, do kernel ou do DPDK citados em prosa tecnica, nenhum
# programa. A convencao real da arvore separa os dois sem ambiguidade: programa
# usa hifen (`custo-anel`, `preparar-nic.sh`), identificador usa sublinhado.
#
# O QUE SE PERDE, declarado: um programa com nome em sublinhado que sumisse nao
# seria pego. E uma troca deliberada -- os dois defeitos reais deste repositorio
# (`controle-anel`, `preparar-nic.sh`) tinham hifen, e um portao com 48 falsos
# positivos nao e consultado por ninguem, entao nao pega nada.
CANDIDATO = re.compile(
    r"`([a-z][a-z0-9]*(?:-[a-z0-9]+)+(?:\.(?:sh|py))?|[a-z][a-z0-9_-]*\.(?:sh|py))`")

FONTES = {".c", ".cpp"}

# Bloco cercado, com ou sem linguagem declarada.
BLOCO = re.compile(r"```[a-zA-Z]*\n(.*?)```", re.S)

# `./caminho/para/programa.sh` dentro de um bloco: promessa executável literal.
COMANDO = re.compile(r"(?:^|\s)(\./[A-Za-z0-9_./-]+\.(?:sh|py))")


def arquivos(raiz, exts=None):
    for pasta, subpastas, nomes in os.walk(raiz):
        subpastas[:] = [d for d in subpastas if d not in IGNORAR and not d.startswith("build")]
        for nome in nomes:
            if exts is None or os.path.splitext(nome)[1] in exts:
                yield os.path.join(pasta, nome)


def entregues(raiz):
    """O que a árvore de fato entrega: alvos de executable() e nomes de arquivo.

    Os alvos saem do TEXTO dos meson.build, e não de `meson introspect`, por duas
    razões. A primeira é que introspect exige um diretório de build configurado,
    que não existe em clone novo nem no autoteste -- um verificador que só roda
    depois de `meson setup` não roda no lugar onde mais importa. A segunda é que
    o texto é a fonte da verdade sobre o que está REGISTRADO, que é exatamente a
    pergunta da regra 2; o diretório de build reflete a última configuração, que
    pode estar velha.
    """
    nomes = set()
    mesons = []
    for m in arquivos(raiz):
        if os.path.basename(m) != "meson.build":
            continue
        try:
            texto = open(m, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        mesons.append((m, texto))
        for alvo in re.findall(r"executable\(\s*['\"]([^'\"]+)['\"]", texto):
            nomes.add(alvo)
            nomes.add(alvo.replace("_", "-"))
            nomes.add(alvo.replace("-", "_"))
    for f in arquivos(raiz):
        base = os.path.basename(f)
        nomes.add(base)
        nomes.add(os.path.splitext(base)[0])
    return nomes, mesons


def verificar(raiz="."):
    problemas = 0
    conferidos = 0
    nomes, mesons = entregues(raiz)
    texto_dos_mesons = "\n".join(t for _, t in mesons)

    # --- Regra 1 -----------------------------------------------------------
    citados = {}
    for doc in sorted(arquivos(raiz, {".md"})):
        try:
            bruto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        corpo = re.sub(r"```.*?```", "", bruto, flags=re.S)
        for m in CANDIDATO.finditer(corpo):
            token = m.group(1)
            citados.setdefault(token, set()).add(os.path.relpath(doc, raiz))

    for token in sorted(citados):
        conferidos += 1
        if token in EXTERNAS or token in nomes:
            continue
        onde = ", ".join(sorted(citados[token]))
        print(f"  \"{token}\" e citado em {onde} e a arvore nao entrega:"
              f" nao e alvo de executable(), nao e arquivo, e nao esta em EXTERNAS")
        print(f"      Se for ferramenta externa, declare em EXTERNAS de"
              f" {os.path.basename(__file__)}; se for programa do projeto, ele sumiu.")
        problemas += 1

    # --- Regra 2 -----------------------------------------------------------
    for fonte in sorted(arquivos(os.path.join(raiz, "docs"), FONTES)) + \
                 sorted(arquivos(os.path.join(raiz, "trilha"), FONTES)):
        conferidos += 1
        base = os.path.basename(fonte)
        if base not in texto_dos_mesons:
            print(f"  {os.path.relpath(fonte, raiz)}: nenhum meson.build referencia"
                  f" esta fonte -- ela nao e compilada, e portanto nao e conferida"
                  f" por nada")
            problemas += 1

    # --- Regra 3 -----------------------------------------------------------
    for doc in sorted(arquivos(raiz, {".md"})):
        try:
            bruto = open(doc, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        vistos = set()
        for bloco in BLOCO.findall(bruto):
            for cmd in COMANDO.findall(bloco):
                if cmd in vistos:
                    continue
                vistos.add(cmd)
                conferidos += 1
                if not os.path.exists(os.path.join(raiz, cmd)):
                    print(f"  {os.path.relpath(doc, raiz)}: manda rodar \"{cmd}\""
                          f" e esse arquivo nao existe na arvore")
                    problemas += 1

    print(f"\n  {conferidos} promessa(s) do material conferida(s) contra a arvore;"
          f" {problemas} nao se sustenta(m)")
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

    def caso(n, descricao, arqs, espera_defeito):
        nonlocal falhas
        rc, saida = rodar(arqs)
        ok = (rc >= 1) if espera_defeito else (rc == 0)
        if not ok:
            print(f"  AUTOTESTE {n} FALHOU: {descricao} (rc={rc})")
            print("    " + saida.strip().replace("\n", "\n    "))
            falhas += 1

    MB = "executable(\n  'custo-anel',\n  'custo-anel.c',\n)\n"

    # 1/2. Alvo de executable(): citado e existente passa; citado e removido falha.
    caso(1, "programa que e alvo de executable() acusado",
         {"meson.build": MB, "trilha/custo-anel.c": "int main(void){return 0;}\n",
          "d.md": "# d\n\nRode `custo-anel` e veja.\n"}, False)
    caso(2, "programa citado que sumiu do meson.build passou",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\nRode `custo-anel` e veja.\n"}, True)

    # 3. Arquivo da arvore (script) conta como entregue.
    caso(3, "script existente no repo acusado",
         {"meson.build": "project('x','c')\n", "scripts/preparar-nic.sh": "#!/bin/bash\n",
          "d.md": "# d\n\nRode `preparar-nic.sh`.\n"}, False)

    # 4. Ferramenta externa declarada.
    caso(4, "ferramenta externa declarada acusada",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\nInstale `rdma-core` antes.\n"}, False)

    # 5. API do DPDK nao e programa: `rte_eal_init` tem sublinhado e nao existe
    #    como arquivo, e acusa-la seria ruido em cada documento do projeto.
    # 5. IDENTIFICADOR nao e programa, e quem o exclui e o proprio CANDIDATO --
    #    nao ha lista de prefixos. Havia uma, com "lib" entre eles, e ela
    #    SILENCIAVA quatro arquivos reais desta arvore: lib-nic.sh,
    #    lib-apuracao.sh, lib-bind-guard.sh e lib-hugetlbfs.sh. Uma guarda que
    #    existia para conter o ruido do sublinhado sobreviveu a causa e virou
    #    falso negativo. O caso 11 tranca isso.
    caso(5, "identificador de C/kernel/DPDK tratado como programa",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\n`rte_eal_init`, `sem_wait`, `sk_buff`, `buf_len`,"
                  " `seq_cst`, `net_null` e `constant_tsc` aparecem na prosa.\n"}, False)

    # 6. Dentro de bloco de codigo e saida de terminal, nao referencia do texto.
    caso(6, "token dentro de bloco de codigo acusado",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\n```\n$ programa-que-nao-existe --ajuda\n```\n"}, False)

    # 7/8. REGRA 2, e o caso que motivou o arquivo: fonte que nenhum meson.build
    #      referencia nao e compilada, e o portao de build limpo nao a enxerga.
    caso(7, "fonte registrada no meson.build acusada",
         {"meson.build": MB, "trilha/custo-anel.c": "int main(void){return 0;}\n",
          "d.md": "# d\n"}, False)
    caso(8, "fonte ORFA passou -- e o defeito do controle-anel",
         {"meson.build": "project('x','c')\n",
          "trilha/orfa.cpp": "int main(){return 0;}\n", "d.md": "# d\n"}, True)

    # 9. Palavra unica sem hifen nao e candidata: `meson`, `ninja`, `cat`.
    caso(9, "palavra unica tratada como programa do projeto",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\nUse `meson` e `ninja`, depois `cat` o arquivo.\n"}, False)

    # 11/12. REGRA 3, e o caso real que a motivou: o projeto final mandava rodar
    #        `./ferramental/af-xdp/xdp-zerocopy.sh` depois de o AF_XDP sair do
    #        repositorio, e a regra 1 nao via porque ignorava blocos de codigo.
    caso(11, "comando ./ de bloco apontando para arquivo inexistente passou",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\n```bash\n./scripts/sumiu.sh --status\n```\n"}, True)
    caso(12, "comando ./ de bloco apontando para arquivo existente acusado",
         {"meson.build": "project('x','c')\n", "scripts/existe.sh": "#!/bin/bash\n",
          "d.md": "# d\n\n```bash\n./scripts/existe.sh --status\n```\n"}, False)
    caso(13, "comando do sistema sem ./ dentro de bloco tratado como do projeto",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\n```bash\nmeson test -C build\ndpdk-testpmd --help\n```\n"}, False)

    # 10. REGRESSAO do custo declarado: ferramenta externa NAO declarada falha, e
    #     a mensagem precisa dizer onde declarar. Sem isto o mantenedor futuro
    #     nao sabe se apagou um programa ou esqueceu uma linha de EXTERNAS.
    rc, saida = rodar({"meson.build": "project('x','c')\n",
                       "d.md": "# d\n\nInstale `pacote-inexistente-novo`.\n"})
    if rc < 1 or "EXTERNAS" not in saida:
        print(f"  AUTOTESTE 10 FALHOU: externa nao declarada passou ou a mensagem"
              f" nao diz onde declarar (rc={rc})")
        falhas += 1

    # 11. REGRESSAO: arquivo do projeto cujo nome comeca com "lib" e conferido
    #     como qualquer outro. Uma guarda de prefixo removida em 16/09/2026
    #     silenciava quatro deles.
    caso(11, "biblioteca 'lib-*.sh' do projeto silenciada por prefixo",
         {"meson.build": "project('x','c')\n",
          "d.md": "# d\n\nO script carrega `lib-sumida.sh` no inicio.\n"}, True)
    caso(12, "biblioteca 'lib-*.sh' existente acusada",
         {"meson.build": "project('x','c')\n", "scripts/lib-nic.sh": "#!/bin/bash\n",
          "d.md": "# d\n\nO script carrega `lib-nic.sh` no inicio.\n"}, False)

    print(f"\n  autoteste: {falhas} assercao(oes) falharam")
    return falhas


if __name__ == "__main__":
    if "--autoteste" in sys.argv:
        sys.exit(1 if autoteste() else 0)
    sys.exit(1 if verificar(sys.argv[1] if len(sys.argv) > 1 else ".") else 0)
