-- =====================================================================
-- 04_testes_integridade.sql
-- Projeto Integrador de Banco de Dados II (APD1) - IFRJ Campus Niterói
-- Solução: Sistema de Gestão de Salão de Beleza
-- Equipe: Jean de Pinho Macedo, Vinícius Pontes Braga e Pietro Gomes Borges
--
-- Testes das restrições de integridade. Cada teste roda dentro de uma
-- transação com ROLLBACK, então nenhum dado da base é alterado.
-- Os testes T01 a T05 DEVEM falhar (o erro é a evidência de que a
-- restrição funciona). Os testes T06 e T07 devem passar.
--
-- No SQL Editor do Supabase, execute um bloco de cada vez.
-- =====================================================================

-- T01 - FK com ON DELETE RESTRICT: excluir cliente que tem agendamento.
-- Esperado: ERRO (violates foreign key constraint "fk_agendamento_cliente").
BEGIN;
DELETE FROM cliente WHERE id_cliente = 1;
ROLLBACK;

-- T02 - FK: agendamento apontando para cliente inexistente.
-- Esperado: ERRO (violates foreign key constraint "fk_agendamento_cliente").
BEGIN;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status)
VALUES (9999, 1, 1, '2026-12-01', '10:00', 80.00, 'agendado');
ROLLBACK;

-- T03 - CHECK: status fora da lista permitida.
-- Esperado: ERRO (violates check constraint "ck_agendamento_status").
BEGIN;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status)
VALUES (1, 1, 1, '2026-12-01', '10:00', 80.00, 'pendente');
ROLLBACK;

-- T04 - Índice único parcial: mesmo profissional, mesma data e hora.
-- Esperado: ERRO (duplicate key ... "uq_agendamento_horario_profissional").
BEGIN;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status)
VALUES (2, 1, 1, '2026-12-02', '09:00', 80.00, 'agendado'),
       (3, 1, 1, '2026-12-02', '09:00', 80.00, 'agendado');
ROLLBACK;

-- T05 - UNIQUE + RESTRICT em pagamento: o agendamento 1 já foi pago,
-- então um segundo pagamento para ele é recusado.
-- Esperado: ERRO (duplicate key ... "pagamento_id_agendamento_key").
BEGIN;
INSERT INTO pagamento (id_agendamento, forma_pagamento, valor_pago)
SELECT id_agendamento, 'pix', 10.00 FROM pagamento ORDER BY id_pagamento LIMIT 1;
ROLLBACK;

-- T06 - FK com ON DELETE SET NULL: ao excluir o profissional que indicou
-- uma venda, a venda continua registrada com id_profissional = NULL.
-- Esperado: SUCESSO; o SELECT final mostra id_profissional vazio (NULL).
BEGIN;
INSERT INTO profissional (nome, especialidade, comissao_percentual)
VALUES ('Profissional Teste', 'Cabeleireira', 30);
INSERT INTO venda_produto (id_cliente, id_produto, id_profissional, quantidade, valor_unitario, forma_pagamento)
VALUES (1, 1, currval('profissional_id_profissional_seq'), 1, 129.90, 'pix');
DELETE FROM profissional WHERE nome = 'Profissional Teste';
SELECT id_venda, id_cliente, id_produto, id_profissional
FROM venda_produto
WHERE id_venda = currval('venda_produto_id_venda_seq');
ROLLBACK;

-- T07 - FK com ON UPDATE CASCADE: ao mudar a chave de um serviço, os
-- agendamentos que apontavam para ela são atualizados juntos.
-- Esperado: SUCESSO; os agendamentos passam a apontar para o id 1000.
BEGIN;
SELECT COUNT(*) AS agendamentos_servico_4_antes FROM agendamento WHERE id_servico = 4;
UPDATE servico SET id_servico = 1000 WHERE id_servico = 4;
SELECT COUNT(*) AS agendamentos_servico_1000_depois FROM agendamento WHERE id_servico = 1000;
ROLLBACK;
