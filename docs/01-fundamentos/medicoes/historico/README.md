# Histórico de configurações de hardware

*Read this in [English](README.en.md).*

Um diretório por **configuração de hardware da máquina de referência**, com a
saída bruta dos programas de medição.

## Por que isto existe

Este projeto tratava a máquina como constante. Ela não é.

Em 20/09/2026 o perfil EXPO 6000 foi ligado na placa. A latência de RAM caiu
11%, a vazão agregada de doze núcleos melhorou 45% — e **nada no repositório
registrava a configuração anterior**, porque `scripts/ambiente.sh` não tinha o
campo. Os números publicados descreviam um hardware que deixou de existir, sem
que houvesse com o que comparar.

A falha não foi de medição. Foi tratar como propriedade da arquitetura o que
era propriedade da configuração.

## O que cada diretório contém

| Arquivo | O que é |
|---|---|
| `<programa>.r<N>.txt` | saída bruta, uma por execução; **`r0` é aquecimento e se descarta** |
| `diario.txt` | horário e carga de cada rodada, e as perturbações deliberadas |
| `ambiente.md` | `scripts/ambiente.sh --markdown` no momento da coleta |
| `teste-reparo.txt`, `controle.txt` | quando a coleta acompanhou um reparo de instrumento |

## Como comparar

```bash
./ferramental/qualidade/comparar-hardware.py \
    docs/01-fundamentos/medicoes/historico/<config-a> \
    docs/01-fundamentos/medicoes/historico/<config-b>
```

**A tabela não está escrita aqui de propósito.** Ela sai das saídas brutas a
cada execução do comando. Um comparativo digitado seria o terceiro lugar onde
um número é copiado neste repositório, e os dois primeiros já custaram um
portão cada — a paridade pt/en e a divergência de rótulos bibliográficos.
Número digitado envelhece em silêncio; número extraído envelhece junto com a
fonte, que é o comportamento certo.

## O que ainda falta

O canal duplo. O segundo pente entra no slot B2, e as previsões estão
registradas **antes** da medição em
[metodologia.md §6](../../metodologia.md#6-pré-registro-o-segundo-pente-de-memória),
com o critério de refutação de cada uma.
