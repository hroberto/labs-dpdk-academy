# Fixtures de teste

Dados de entrada para os testes, não material de estudo.

`controle-anel/` é uma campanha de medição completa — amostras brutas, metadados
com SHA-256 das fontes, ambiente, comandos e a tabela publicada. Ela vivia em
`docs/avaliacoes/evidencias/` e foi movida para cá quando aquela pasta saiu do
repositório, porque o **papel real** destes arquivos é ser fixture: dois testes
os copiam para um diretório temporário, corrompem cada campo de propósito, e
exigem que a bateria de publicação recuse.

A distinção importa. Como documentação, esta campanha respondia a uma pergunta
que ninguém fazia; como fixture, ela é o insumo sem o qual `l2_publicacao.py` e
`l1_mutacoes_publicacao.py` não podem verificar nada.
