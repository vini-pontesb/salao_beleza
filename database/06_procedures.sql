-- =====================================================================
-- 06_procedures.sql
-- Projeto Integrador de Banco de Dados II (APD2) - IFRJ Campus Niterói
-- Solução: Sistema de Gestão de Salão de Beleza
-- Equipe: Jean de Pinho Macedo, Vinícius Pontes Braga e Pietro Gomes Borges
-- SGBD: PostgreSQL (Supabase)
--
-- Procedures da base. Executam tarefas do dia a dia do salão e são
-- chamadas com CALL. Se qualquer passo falhar, nada do que a procedure
-- fez é gravado (o CALL inteiro é desfeito).
--
--   P01 sp_concluir_atendimento
--   P02 sp_repor_estoque
--   P03 sp_cancelar_agendamentos_expirados
--
-- Executar DEPOIS de 05_functions.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- P01 - sp_concluir_atendimento
-- Fecha um atendimento: muda o status do agendamento para 'concluido' e
-- registra o pagamento, tudo na mesma operação. Evita o caso de um
-- atendimento ficar concluído sem pagamento (ou o contrário).
--
-- Valor pago = valor do agendamento - desconto.
-- As regras de pagamento (forma, parcelas, desconto) também são
-- conferidas pelo trigger trg_pagamento_valida e pelos CHECKs da tabela.
--
-- Exemplo: CALL sp_concluir_atendimento(45, 'pix', 10.00);
--          CALL sp_concluir_atendimento(46, 'credito', 0, 3);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_concluir_atendimento(
    p_id_agendamento   INTEGER,
    p_forma_pagamento  VARCHAR,
    p_desconto         NUMERIC DEFAULT 0,
    p_parcelas         INTEGER DEFAULT 1
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status  TEXT;
    v_valor   NUMERIC(10,2);
BEGIN
    -- FOR UPDATE trava a linha até o fim da operação, para que duas
    -- pessoas não concluam o mesmo atendimento ao mesmo tempo.
    SELECT status, valor INTO v_status, v_valor
      FROM agendamento
     WHERE id_agendamento = p_id_agendamento
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Agendamento % não encontrado.', p_id_agendamento;
    END IF;

    IF v_status = 'cancelado' THEN
        RAISE EXCEPTION 'Agendamento % está cancelado e não pode ser concluído.', p_id_agendamento;
    END IF;

    IF v_status = 'concluido' THEN
        RAISE EXCEPTION 'Agendamento % já foi concluído.', p_id_agendamento;
    END IF;

    UPDATE agendamento
       SET status = 'concluido'
     WHERE id_agendamento = p_id_agendamento;

    INSERT INTO pagamento (id_agendamento, forma_pagamento, valor_pago, desconto, parcelas)
    VALUES (p_id_agendamento, p_forma_pagamento,
            v_valor - COALESCE(p_desconto, 0), COALESCE(p_desconto, 0), p_parcelas);

    RAISE NOTICE 'Atendimento % concluído. Valor pago: R$ % (%).',
        p_id_agendamento, v_valor - COALESCE(p_desconto, 0), p_forma_pagamento;
END;
$$;

COMMENT ON PROCEDURE sp_concluir_atendimento(INTEGER, VARCHAR, NUMERIC, INTEGER) IS
    'Conclui o agendamento e registra o pagamento na mesma operação.';

-- ---------------------------------------------------------------------
-- P02 - sp_repor_estoque
-- Registra a entrada de mercadoria: soma a quantidade recebida ao
-- estoque do produto e avisa se ele continua abaixo do mínimo.
-- p_estoque_atual (INOUT) devolve o estoque depois da reposição.
--
-- Exemplo: CALL sp_repor_estoque(36, 20, NULL);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_repor_estoque(
    p_id_produto     INTEGER,
    p_quantidade     INTEGER,
    INOUT p_estoque_atual INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_ativo    BOOLEAN;
    v_minimo   INTEGER;
BEGIN
    IF p_quantidade IS NULL OR p_quantidade <= 0 THEN
        RAISE EXCEPTION 'A quantidade de reposição deve ser maior que zero (recebido: %).', p_quantidade;
    END IF;

    SELECT ativo, estoque_minimo INTO v_ativo, v_minimo
      FROM produto
     WHERE id_produto = p_id_produto
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produto % não encontrado.', p_id_produto;
    END IF;

    IF NOT v_ativo THEN
        RAISE EXCEPTION 'Produto % está inativo. Reative o produto antes de repor o estoque.', p_id_produto;
    END IF;

    UPDATE produto
       SET qtd_estoque = qtd_estoque + p_quantidade
     WHERE id_produto = p_id_produto
    RETURNING qtd_estoque INTO p_estoque_atual;

    IF p_estoque_atual <= v_minimo THEN
        RAISE NOTICE 'Produto %: estoque reposto para %, mas ainda está no mínimo ou abaixo dele (%).',
            p_id_produto, p_estoque_atual, v_minimo;
    ELSE
        RAISE NOTICE 'Produto %: estoque reposto para % unidades.', p_id_produto, p_estoque_atual;
    END IF;
END;
$$;

COMMENT ON PROCEDURE sp_repor_estoque(INTEGER, INTEGER, INTEGER) IS
    'Soma a quantidade recebida ao estoque do produto e devolve o estoque atualizado.';

-- ---------------------------------------------------------------------
-- P03 - sp_cancelar_agendamentos_expirados
-- Limpeza da agenda: agendamentos que ficaram com status 'agendado' e
-- cuja data já passou são marcados como 'cancelado'. Isso mantém os
-- relatórios corretos e libera os horários no índice parcial.
-- p_qtd_cancelados (INOUT) devolve quantos foram cancelados.
--
-- Exemplo: CALL sp_cancelar_agendamentos_expirados();              -- usa a data de hoje
--          CALL sp_cancelar_agendamentos_expirados('2026-11-25');  -- data de referência
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_agendamentos_expirados(
    p_data_referencia      DATE DEFAULT CURRENT_DATE,
    INOUT p_qtd_cancelados INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE agendamento
       SET status = 'cancelado'
     WHERE status = 'agendado'
       AND data_agendamento < p_data_referencia;

    GET DIAGNOSTICS p_qtd_cancelados = ROW_COUNT;

    RAISE NOTICE '% agendamento(s) anterior(es) a % cancelado(s).',
        p_qtd_cancelados, p_data_referencia;
END;
$$;

COMMENT ON PROCEDURE sp_cancelar_agendamentos_expirados(DATE, INTEGER) IS
    'Cancela os agendamentos que continuam como agendado com data anterior à data de referência.';
