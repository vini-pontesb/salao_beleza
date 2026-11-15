-- =====================================================================
-- 08_testes_apd2.sql
-- Projeto Integrador de Banco de Dados II (APD2) - IFRJ Campus Niterói
-- Solução: Sistema de Gestão de Salão de Beleza
-- Equipe: Jean de Pinho Macedo, Vinícius Pontes Braga e Pietro Gomes Borges
--
-- Evidências de funcionamento das functions, procedures e triggers.
-- Cada teste roda dentro de BEGIN ... ROLLBACK, então nenhum dado da
-- base é alterado. Testes marcados como "Esperado: ERRO" devem falhar:
-- a mensagem de erro é a evidência de que a regra funciona.
--
-- Pré-requisito: base carregada com 01 e 02, e rotinas criadas com
-- 05, 06 e 07.
--
-- No SQL Editor do Supabase, execute um bloco de cada vez.
-- =====================================================================


-- V01 - Conferência: rotinas e triggers criados na base.
-- Esperado: 3 functions (f), 3 procedures (p), 3 funções de trigger e
-- 3 triggers.
SELECT p.proname AS rotina,
       CASE p.prokind WHEN 'p' THEN 'procedure'
                      WHEN 'f' THEN CASE WHEN p.prorettype = 'trigger'::regtype
                                         THEN 'função de trigger' ELSE 'function' END
       END AS tipo,
       pg_get_function_identity_arguments(p.oid) AS parametros
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname ~ '^(fn_|sp_)'
 ORDER BY tipo, rotina;

SELECT tgname AS trigger, tgrelid::regclass AS tabela
  FROM pg_trigger
 WHERE NOT tgisinternal
 ORDER BY tabela;


-- #####################################################################
-- FUNCTIONS
-- #####################################################################

-- F01.1 - fn_horario_disponivel
-- O profissional 1 tem atendimento em 19/11/2026 às 18:00 (Hidratação,
-- 45 min, termina 18:45).
-- Esperado: 17:00 (60 min) = true | 17:30 (60 min) = false |
--           18:30 (30 min) = false | 18:45 (30 min) = true
SELECT fn_horario_disponivel(1, '2026-11-19', '17:00', 60) AS "17:00 por 60 min",
       fn_horario_disponivel(1, '2026-11-19', '17:30', 60) AS "17:30 por 60 min",
       fn_horario_disponivel(1, '2026-11-19', '18:30', 30) AS "18:30 por 30 min",
       fn_horario_disponivel(1, '2026-11-19', '18:45', 30) AS "18:45 por 30 min";

-- F01.2 - fn_horario_disponivel ignorando o próprio agendamento (caso de
-- alteração). Esperado: true, porque o único conflito é o agendamento 45.
SELECT fn_horario_disponivel(1, '2026-11-19', '18:00', 45, 45) AS livre_ignorando_o_45;

-- F02.1 - fn_comissao_profissional: comissão de cada profissional em 2026.
-- Esperado: lista com as 5 maiores comissões do ano.
SELECT p.id_profissional,
       p.nome,
       p.comissao_percentual,
       fn_comissao_profissional(p.id_profissional, '2026-01-01', '2026-12-31') AS comissao_2026
  FROM profissional p
 ORDER BY comissao_2026 DESC
 LIMIT 5;

-- F02.2 - Conferência manual da F02 para o profissional 1.
-- Esperado: as duas colunas com o mesmo valor.
SELECT fn_comissao_profissional(1, '2026-01-01', '2026-12-31') AS pela_function,
       ROUND(SUM(pg.valor_pago) * MAX(p.comissao_percentual) / 100, 2) AS calculo_manual
  FROM agendamento a
  JOIN pagamento    pg ON pg.id_agendamento = a.id_agendamento
  JOIN profissional p  ON p.id_profissional = a.id_profissional
 WHERE a.id_profissional = 1
   AND a.status = 'concluido'
   AND a.data_agendamento BETWEEN '2026-01-01' AND '2026-12-31';

-- F02.3 - Período inválido.
-- Esperado: ERRO (Período inválido: a data final ... é anterior à inicial ...).
SELECT fn_comissao_profissional(1, '2026-12-31', '2026-01-01');

-- F02.4 - Profissional inexistente.
-- Esperado: ERRO (Profissional 9999 não encontrado.).
SELECT fn_comissao_profissional(9999, '2026-01-01', '2026-12-31');

-- F03.1 - fn_total_gasto_cliente: os 5 clientes que mais gastaram.
-- Esperado: lista ordenada pelo total gasto.
SELECT c.id_cliente,
       c.nome,
       fn_total_gasto_cliente(c.id_cliente) AS total_gasto
  FROM cliente c
 ORDER BY total_gasto DESC
 LIMIT 5;

-- F03.2 - Cliente que nunca agendou nem comprou (cliente 6).
-- Esperado: 0.00.
SELECT fn_total_gasto_cliente(6) AS total_cliente_6;

-- F03.3 - Cliente inexistente.
-- Esperado: ERRO (Cliente 9999 não encontrado.).
SELECT fn_total_gasto_cliente(9999);


-- #####################################################################
-- PROCEDURES
-- #####################################################################

-- P01.1 - sp_concluir_atendimento: conclui o agendamento 45 (agendado,
-- R$ 90,00) com desconto de R$ 10,00 no pix.
-- Esperado: SUCESSO; status 'concluido' e pagamento de R$ 80,00.
BEGIN;
SELECT id_agendamento, status, valor FROM agendamento WHERE id_agendamento = 45;
CALL sp_concluir_atendimento(45, 'pix', 10.00);
SELECT a.id_agendamento, a.status, a.valor, pg.forma_pagamento, pg.desconto, pg.valor_pago
  FROM agendamento a
  JOIN pagamento pg ON pg.id_agendamento = a.id_agendamento
 WHERE a.id_agendamento = 45;
ROLLBACK;

-- P01.2 - Concluir agendamento cancelado (o 27 está cancelado).
-- Esperado: ERRO (Agendamento 27 está cancelado e não pode ser concluído.).
BEGIN;
CALL sp_concluir_atendimento(27, 'pix');
ROLLBACK;

-- P01.3 - Concluir agendamento que já foi concluído (o 1).
-- Esperado: ERRO (Agendamento 1 já foi concluído.).
BEGIN;
CALL sp_concluir_atendimento(1, 'pix');
ROLLBACK;

-- P01.4 - Atomicidade: crédito com 8 parcelas viola o CHECK de pagamento.
-- Esperado: ERRO (ck_pagamento_parcelas) e o agendamento 46 CONTINUA
-- 'agendado' (a mudança de status também é desfeita). Depois do erro,
-- rode o ROLLBACK e o SELECT para conferir.
BEGIN;
CALL sp_concluir_atendimento(46, 'credito', 0, 8);
ROLLBACK;
SELECT id_agendamento, status FROM agendamento WHERE id_agendamento = 46;

-- P02.1 - sp_repor_estoque: o produto 36 está com estoque 0.
-- Esperado: SUCESSO; p_estoque_atual = 20.
BEGIN;
SELECT id_produto, nome, qtd_estoque, estoque_minimo FROM produto WHERE id_produto = 36;
CALL sp_repor_estoque(36, 20, NULL);
SELECT id_produto, nome, qtd_estoque, estoque_minimo FROM produto WHERE id_produto = 36;
ROLLBACK;

-- P02.2 - Reposição que não alcança o mínimo (produto 27: estoque 2, mínimo 5).
-- Esperado: SUCESSO com aviso (NOTICE) de que ainda está no mínimo ou abaixo.
BEGIN;
CALL sp_repor_estoque(27, 1, NULL);
ROLLBACK;

-- P02.3 - Quantidade inválida.
-- Esperado: ERRO (A quantidade de reposição deve ser maior que zero ...).
BEGIN;
CALL sp_repor_estoque(36, 0, NULL);
ROLLBACK;

-- P02.4 - Produto inativo (o 33 está inativo).
-- Esperado: ERRO (Produto 33 está inativo ...).
BEGIN;
CALL sp_repor_estoque(33, 10, NULL);
ROLLBACK;

-- P03.1 - sp_cancelar_agendamentos_expirados com a data de hoje.
-- Esperado: SUCESSO; quantidade de agendamentos com data passada que
-- ainda estavam como 'agendado' (0 se a agenda estiver em dia).
BEGIN;
CALL sp_cancelar_agendamentos_expirados();
ROLLBACK;

-- P03.2 - Simulação com data de referência 25/11/2026.
-- Esperado: SUCESSO; p_qtd_cancelados = 2 (agendamentos 45 e 46).
BEGIN;
SELECT id_agendamento, data_agendamento, status FROM agendamento
 WHERE status = 'agendado' ORDER BY data_agendamento;
CALL sp_cancelar_agendamentos_expirados('2026-11-25');
SELECT id_agendamento, data_agendamento, status FROM agendamento
 WHERE id_agendamento IN (45, 46, 47);
ROLLBACK;


-- #####################################################################
-- TRIGGERS
-- #####################################################################

-- T01.1 - trg_venda_estoque: venda de 3 unidades do produto 1 (estoque 56)
-- sem informar valor_unitario.
-- Esperado: SUCESSO; valor_unitario = 129.90 (preço atual) e estoque 53.
BEGIN;
SELECT id_produto, qtd_estoque, preco_venda FROM produto WHERE id_produto = 1;
INSERT INTO venda_produto (id_cliente, id_produto, quantidade, forma_pagamento)
VALUES (1, 1, 3, 'pix')
RETURNING id_venda, id_produto, quantidade, valor_unitario;
SELECT id_produto, qtd_estoque FROM produto WHERE id_produto = 1;
ROLLBACK;

-- T01.2 - Estorno: excluir a venda devolve a quantidade ao estoque.
-- Esperado: SUCESSO; estoque volta para 56.
BEGIN;
INSERT INTO venda_produto (id_cliente, id_produto, quantidade, forma_pagamento)
VALUES (1, 1, 3, 'pix');
SELECT qtd_estoque AS depois_da_venda FROM produto WHERE id_produto = 1;
DELETE FROM venda_produto WHERE id_venda = currval('venda_produto_id_venda_seq');
SELECT qtd_estoque AS depois_do_estorno FROM produto WHERE id_produto = 1;
ROLLBACK;

-- T01.3 - Alteração da quantidade: de 3 para 5 unidades.
-- Esperado: SUCESSO; estoque 56 -> 53 -> 51.
BEGIN;
INSERT INTO venda_produto (id_cliente, id_produto, quantidade, forma_pagamento)
VALUES (1, 1, 3, 'pix');
UPDATE venda_produto SET quantidade = 5 WHERE id_venda = currval('venda_produto_id_venda_seq');
SELECT qtd_estoque AS depois_da_alteracao FROM produto WHERE id_produto = 1;
ROLLBACK;

-- T01.4 - Aviso de estoque mínimo (produto 18: estoque 3, mínimo 5).
-- Esperado: SUCESSO com NOTICE "Atenção: o produto 18 ficou com 2 unidade(s) ...".
BEGIN;
INSERT INTO venda_produto (id_cliente, id_produto, quantidade, forma_pagamento)
VALUES (2, 18, 1, 'dinheiro');
ROLLBACK;

-- T01.5 - Estoque insuficiente (produto 27: estoque 2).
-- Esperado: ERRO (Estoque insuficiente para o produto 27: disponível 2, solicitado 5.).
BEGIN;
INSERT INTO venda_produto (id_cliente, id_produto, quantidade, forma_pagamento)
VALUES (1, 27, 5, 'pix');
ROLLBACK;

-- T01.6 - Produto inativo (o 33 está inativo).
-- Esperado: ERRO (Produto 33 está inativo e não pode ser vendido.).
BEGIN;
INSERT INTO venda_produto (id_cliente, id_produto, quantidade, forma_pagamento)
VALUES (1, 33, 1, 'pix');
ROLLBACK;

-- T02.1 - trg_pagamento_valida: pagamento de agendamento ainda 'agendado' (o 45).
-- Esperado: ERRO (Agendamento 45 está com status "agendado" ...).
BEGIN;
INSERT INTO pagamento (id_agendamento, forma_pagamento, valor_pago)
VALUES (45, 'pix', 90.00);
ROLLBACK;

-- T02.2 - Pagamento de agendamento cancelado (o 27).
-- Esperado: ERRO (Agendamento 27 está com status "cancelado" ...).
BEGIN;
INSERT INTO pagamento (id_agendamento, forma_pagamento, valor_pago)
VALUES (27, 'pix', 20.00);
ROLLBACK;

-- T02.3 - Valor pago calculado automaticamente.
-- Esperado: SUCESSO; valor_pago = 450.00 - 50.00 = 400.00.
BEGIN;
UPDATE agendamento SET status = 'concluido' WHERE id_agendamento = 46;
INSERT INTO pagamento (id_agendamento, forma_pagamento, desconto, parcelas)
VALUES (46, 'credito', 50.00, 3)
RETURNING id_agendamento, desconto, valor_pago, parcelas;
ROLLBACK;

-- T02.4 - Valor pago que não confere com valor - desconto.
-- Esperado: ERRO (Valor pago (R$ 100.00) não confere ...).
BEGIN;
UPDATE agendamento SET status = 'concluido' WHERE id_agendamento = 46;
INSERT INTO pagamento (id_agendamento, forma_pagamento, valor_pago)
VALUES (46, 'pix', 100.00);
ROLLBACK;

-- T02.5 - Desconto maior que o valor do atendimento.
-- Esperado: ERRO (Desconto de R$ 500.00 maior que o valor do atendimento ...).
BEGIN;
UPDATE agendamento SET status = 'concluido' WHERE id_agendamento = 46;
INSERT INTO pagamento (id_agendamento, forma_pagamento, desconto)
VALUES (46, 'pix', 500.00);
ROLLBACK;

-- T03.1 - trg_agendamento_regras: agendamento sem valor recebe o preço do serviço.
-- Esperado: SUCESSO; valor = 80.00 (preço do Corte Feminino).
BEGIN;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
VALUES (10, 1, 1, '2026-12-01', '10:00')
RETURNING id_agendamento, id_servico, valor, status;
ROLLBACK;

-- T03.2 - Conflito de horário pela duração: o profissional 1 atende das
-- 18:00 às 18:45 em 19/11/2026; novo agendamento às 18:30.
-- (O índice único da APD1 não pegaria esse caso, porque a hora é diferente.)
-- Esperado: ERRO (Conflito de horário: o profissional 1 ...).
BEGIN;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
VALUES (10, 1, 2, '2026-11-19', '18:30');
ROLLBACK;

-- T03.3 - Horário logo após o término do atendimento existente.
-- Esperado: SUCESSO (18:45 é exatamente o fim do atendimento anterior).
BEGIN;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
VALUES (10, 1, 2, '2026-11-19', '18:45')
RETURNING id_agendamento, data_agendamento, hora, valor;
ROLLBACK;

-- T03.4 - Cancelar libera o horário: cancela o 45 e agenda outro cliente
-- no mesmo horário.
-- Esperado: SUCESSO nos dois comandos.
BEGIN;
UPDATE agendamento SET status = 'cancelado' WHERE id_agendamento = 45;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
VALUES (10, 1, 5, '2026-11-19', '18:00')
RETURNING id_agendamento, hora, status;
ROLLBACK;

-- T03.5 - Serviço inativo (o 18 está inativo).
-- Esperado: ERRO (Serviço 18 está inativo e não pode ser agendado.).
BEGIN;
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
VALUES (10, 1, 18, '2026-12-01', '10:00');
ROLLBACK;

-- T03.6 - Cancelar atendimento que já foi pago (o 1).
-- Esperado: ERRO (Agendamento 1 já foi pago e não pode mudar para "cancelado".).
BEGIN;
UPDATE agendamento SET status = 'cancelado' WHERE id_agendamento = 1;
ROLLBACK;
