# Inventário de dados e decisões

Os números sem cadeia de coleta permanecem como registros didáticos. Eles não
autorizam previsões ou escolha quantitativa da versão atual. A cadeia completa
está demonstrada para o controle SPSC; as demais famílias abaixo ainda exigem
nova coleta se forem usadas para uma recomendação quantitativa.

| ID | Família e origem | Natureza / evidência | Uso admitido e pendência |
|---|---|---|---|
| D01 | Orçamento por pacote, nos fundamentos | Cálculo a partir de taxa e tamanho declarados | Recalcular os operandos do cenário; não é vazão medida. |
| D02 | Syscall, cache, espera e travessia, nos fundamentos | Medições históricas sem registros completos por campanha | Ilustrar o experimento; recoletar para dimensionar um sistema atual. |
| D03 | Comparações com literatura, nos fundamentos | Valores externos com referências e medições históricas locais | Confronto didático; verificar versão e condições antes de generalizar concordância. |
| D04 | Inicialização, encerramento e latência, no runtime | Medições históricas; instrumentação atual mudou | Recoletar após validação funcional. TSC comparável continua hipótese separada. |
| D05 | Alocação e modos de ring, em mempool/ring/mbuf | Tabelas históricas, inclusive agregados de dez execuções sem dados individuais preservados | Não presumir identidade entre campanhas ou estimar ganho atual por essas razões. |
| D06 | Pipeline e comparação C/C++, na trilha | Medições históricas com protocolos diferentes; mudanças no caminho atual | Decisão depende de novo ensaio equivalente; o texto explicita limites. |
| D07 | Síntese do projeto final | Derivação das famílias D01–D06 | Não constitui campanha independente nem valida rede física. |
| D08 | Contratos, estados e recomendações qualitativas nas seis páginas | Referência documental, código e testes associados | Não contar como medição ou amostra. Conferir com a matriz de requisitos. |
| D09 | Controle SPSC: API por objeto/bloco e uma/duas CPUs | Duas campanhas com CSV, fontes, ambiente e registros de execução | Comparar custo amortizado do mesmo trabalho; não é comparação DPDK/C++ nem latência de NIC. |

O [inventário estrutural](inventario-tabelas.json) enumera tabelas Markdown e
blocos numéricos nas seis páginas desenvolvidas e nas duas tabelas de D09.
Inclui posição, seção e hash do conteúdo. A classificação por família acima é
editorial: o scanner não determina causalidade, proveniência ou veracidade e
não cobre todos os números em prosa. Alterar um bloco exige revisar o inventário,
não apenas aceitar automaticamente o hash novo.

```bash
python3 ferramental/qualidade/inventariar-dados.py
# Depois de revisar as mudanças de conteúdo:
python3 ferramental/qualidade/inventariar-dados.py --atualizar
```

As campanhas D09 são a [coleta anterior](evidencias/2026-09-14-controle-anel/tabela.md)
e a [coleta com publicação validada](evidencias/2026-09-15-controle-anel-validado/tabela.md).
A primeira preserva o protocolo antigo; a segunda acrescenta manifesto de
artefatos, retorno da captura do ambiente e validação antes de publicar.
Os resultados de comparação entre campanhas ficam em
[comparacao-campanhas.json](evidencias/2026-09-15-ajustes/comparacao-campanhas.json).

Para regenerar, use uma cópia do diretório da campanha, preservando a original:

```bash
cp -a docs/avaliacoes/evidencias/2026-09-15-controle-anel-validado /tmp/controle-anel-copia
python3 scripts/coletar-controle-anel.py /tmp/controle-anel-copia --regenerar
```

O código deve terminar com zero e `publicacao-status.json` deve registrar
`VALIDO`. Em falha, a tabela anterior não é substituída, o comando termina com
erro e o status registra `FAIL`; uma tabela antiga no diretório não representa
a tentativa malsucedida. O estado de captura e o estado de publicação são
distintos. Hashes permitem detectar divergência dos arquivos preservados, não
atestam autenticidade contra alteração coordenada do manifesto e dos dados.

Para uma nova campanha, registrar hipótese, fatores mantidos e alterados, unidade,
protocolo e limite da conclusão. D09 investiga se publicação em bloco muda o
custo amortizado do mesmo anel. Variação de frequência e interferência continuam
limites; dispersão interna não corrige esses fatores. A segunda campanha pode
confrontar o sinal da diferença sem demonstrar sua causa isolada.
