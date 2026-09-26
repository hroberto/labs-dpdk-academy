# Histórico de coletas — isolamento de CPU

Vazio por decisão de 24/09/2026.

## Por que foi limpo

Duas execuções do mesmo dia colidiram no mesmo nome de diretório, e uma delas
ficou rotulada com a configuração de memória errada — o caminho dizia uma
coisa e o conteúdo era outra. O defeito não estava na medição; estava em o
nome da coleta ser derivado da data, e a data não distinguir 4800 de 6000
MT/s nem uma execução da seguinte.

As coletas removidas continuam na história do git, no commit anterior à
remoção. Nada foi perdido; o que foi retirado é a ambiguidade.

## O que as substitui

O roteiro das quatro células, em `temp/run_campanha.sh`: memória 4800 e 6000
MT/s contra canal único e duplo, todas em modo texto. Duas mudanças fecham a
porta por onde o erro entrou:

- o nome da coleta é argumento e carrega hora e minuto, de modo que duas
  execuções nunca ocupam o mesmo caminho;
- a configuração da BIOS é lida do `dmidecode` e comparada com a que o comando
  declara, antes de medir. Errar passa a exigir contrariar o programa.

As células de 4800 MT/s correm campanha completa. Além do fatorial de memória,
elas medem isolamento de CPU em canal único e duplo com todo o resto igual —
o que responde ao confundimento entre configuração de memória e reinício que
a §6.7 do README deste tópico declara em aberto.

## O estado enquanto isto durar

Os números publicados no README deste tópico descrevem coletas que não estão
arquivadas aqui. É estado declarado, não esquecimento, e se fecha quando as
quatro células forem medidas.
