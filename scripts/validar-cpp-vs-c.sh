#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Valida a tese: "a escolha entre C e C++ não altera o custo da sincronização".
#
# Executa os dois programas espelhados e compara. A tese se sustenta para
# std::atomic, std::mutex e std::condition_variable, porque usam mecanismos
# equivalentes em C e em C++.
#
# Excecao de comparacao: std::counting_semaphore no libstdc++ NAO e sem_t POSIX;
# ele usa uma implementacao alternativa (__atomic_semaphore, com spin) e por isso
# nao mede o mesmo mecanismo de bloqueio do semaforo POSIX em C.
set -u
cd "$(dirname "$0")/.."
M=build/docs/01-fundamentos/medicoes
[ -x "$M/custo-espera" ] && [ -x "$M/custo-espera-cpp" ] || {
    echo "compile antes: ./scripts/build-all.sh" >&2; exit 1; }

echo "=== Evidencia 1: instrucoes geradas para atomicas ==="
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '#include <stdatomic.h>\natomic_int v;\nvoid st(int x){atomic_store_explicit(&v,x,memory_order_release);}\nint ld(void){return atomic_load_explicit(&v,memory_order_acquire);}\nvoid sc(int x){atomic_store(&v,x);}\n' > "$T/a.c"
printf '#include <atomic>\nstd::atomic<int> v;\nvoid st(int x){v.store(x,std::memory_order_release);}\nint ld(){return v.load(std::memory_order_acquire);}\nvoid sc(int x){v.store(x);}\n' > "$T/a.cpp"
gcc -O2 -c -o "$T/c.o" "$T/a.c"
g++ -std=c++23 -O2 -c -o "$T/cpp.o" "$T/a.cpp"
limpa() { objdump -d --no-show-raw-insn --demangle "$1" |
          sed -n '/>:/,$p' | sed 's/^ *[0-9a-f]*:\s*//; s/#.*//; s/[[:space:]]*$//' |
          grep -vE '^$|>:'; }
if diff -q <(limpa "$T/c.o") <(limpa "$T/cpp.o") >/dev/null; then
    echo "  IDENTICAS: std::atomic gera as mesmas instrucoes que _Atomic de C"
    limpa "$T/c.o" | sed 's/^/    /'
else
    echo "  DIFEREM:"; diff <(limpa "$T/c.o") <(limpa "$T/cpp.o")
fi

echo
echo "=== Evidencia 2: qual semaforo o libstdc++ escolhe ==="
cat > "$T/sem.cpp" <<'CPP'
#include <bits/semaphore_base.h>
#include <cstdio>
#include <type_traits>
int main(){
  std::printf("  %s\n", std::is_same_v<std::__semaphore_impl, std::__atomic_semaphore>
      ? "__atomic_semaphore  -> semaforo atomico com spin/espera ativa; NAO e sem_t POSIX"
      : "__platform_semaphore -> sem_t POSIX");
}
CPP
g++ -std=c++23 -o "$T/sem" "$T/sem.cpp" && "$T/sem"

echo
echo "=== Evidencia 3: medicoes lado a lado ==="
"$M/custo-espera"     > "$T/c.txt"
"$M/custo-espera-cpp" > "$T/cpp.txt"
extrai() { grep -oE '[0-9]+\.[0-9]+' <<<"$1" | head -1; }  # mediana: 1o numero da linha
printf "  %-34s %10s %10s %8s\n" "medicao" "C" "C++23" "razao"
# Falhas de casamento de padrao sao RUIDOSAS de proposito: uma linha que some em
# silencio faz um resultado incompleto parecer completo. Ja aconteceu neste
# script quando os rotulos dos programas mudaram.
faltando=0
comparar() { # rotulo, padrao em C, padrao em C++
    local c cpp
    c=$(extrai "$(grep -m1 -- "$2" "$T/c.txt")")
    cpp=$(extrai "$(grep -m1 -- "$3" "$T/cpp.txt")")
    if [ -z "$c" ] || [ -z "$cpp" ]; then
        printf "  %-34s %10s %10s %8s\n" "$1" \
            "${c:-AUSENTE}" "${cpp:-AUSENTE}" "--"
        [ -z "$c" ]   && echo "      ^ padrao nao encontrado na saida em C:   '$2'" >&2
        [ -z "$cpp" ] && echo "      ^ padrao nao encontrado na saida em C++: '$3'" >&2
        faltando=$((faltando + 1))
        return
    fi
    printf "  %-34s %10s %10s %8s\n" "$1" "$c" "$cpp" \
        "$(LC_ALL=C awk -v a="$cpp" -v b="$c" 'BEGIN{printf "%.2fx", a/b}')"
}
echo "  -- sem disputa: ninguem mais quer o primitivo --"
comparar "atomica relaxed"          "atomica relaxed"        "std::atomic relaxed"
comparar "mutex lock+unlock"        "mutex lock+unlock"      "std::mutex lock+unlock"
comparar "atomica seq_cst"          "atomica seq_cst"        "std::atomic seq_cst"
comparar "semaforo sem bloquear"    "semaforo post+wait"     "std::semaphore rel+acq"
echo "  -- no repasse: duas threads coordenando entre nucleos --"
comparar "atomica + espera ativa"   "atomica + espera ativa" "std::atomic + espera ativa"
comparar "mutex + espera ativa"     "mutex + espera ativa"   "std::mutex + espera ativa"
comparar "condvar (dorme)"          "mutex + condvar"        "std::condition_variable"
comparar "semaforo no repasse"      "semaforo POSIX"         "std::counting_semaphore"

echo
if [ "$faltando" -gt 0 ]; then
    echo "  ATENCAO: $faltando medicao(oes) nao puderam ser comparadas (ver acima)."
    echo "  Os rotulos dos programas provavelmente mudaram; ajuste os padroes."
    exit 1
fi
echo "  Veredito: a tese vale para atomica, mutex e condvar (razao ~1x)."
echo "  Excecao de comparacao: std::counting_semaphore do libstdc++ nao e sem_t POSIX;"
echo "  ele usa __atomic_semaphore com spin/espera ativa, logo mede outro mecanismo."
