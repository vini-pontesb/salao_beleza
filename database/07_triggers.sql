-- =====================================================================
-- 07_triggers.sql
-- Projeto Integrador de Banco de Dados II (APD2) - IFRJ Campus Niterói
-- Solução: Sistema de Gestão de Salão de Beleza
-- Equipe: Jean de Pinho Macedo, Vinícius Pontes Braga e Pietro Gomes Borges
-- SGBD: PostgreSQL (Supabase)
--
-- Triggers da base. Disparam sozinhos quando há INSERT, UPDATE ou
-- DELETE na tabela, então a regra vale para qualquer forma de acesso
-- (aplicação web, SQL Editor ou API do Supabase).
--
-- No PostgreSQL, cada trigger chama uma função do tipo RETURNS TRIGGER
-- (prefixo fn_trg_). Essas funções são parte do trigger e não se
-- confundem com as functions do script 05.
--
--   T01 trg_venda_estoque       (venda_produto)
--   T02 trg_pagamento_valida    (pagamento)
--   T03 trg_agendamento_regras  (agendamento)
--
-- Executar DEPOIS de 05_functions.sql (o T03 usa fn_horario_disponivel).
--
-- ATENÇÃO: o script 01 apaga as tabelas e, junto com elas, os triggers.
-- Sempre que recriar a base (01 e 02), execute este script de novo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- T01 - trg_venda_estoque
-- Tabela: venda_produto | BEFORE INSERT OR UPDATE OR DELETE
--
-- INSERT: bloqueia produto inativo ou sem estoque suficiente, preenche
--         valor_unitario com o preço atual (se vier vazio) e dá baixa
--         no estoque. Avisa quando o estoque atinge o mínimo.
-- UPDATE: se mudar produto ou quantidade, devolve a quantidade antiga
--         ao estoque e dá baixa na nova.
-- DELETE: devolve a quantidade ao estoque (estorno da venda).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_venda_estoque()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ativo    BOOLEAN;
    v_estoque  INTEGER;
    v_minimo   INTEGER;
    v_preco    NUMERIC(10,2);
BEGIN
    -- UPDATE que não mexe em produto nem em quantidade não altera o estoque.
    IF TG_OP = 'UPDATE'
       AND NEW.id_produto = OLD.id_produto
       AND NEW.quantidade = OLD.quantidade THEN
        RETURN NEW;
    END IF;

    -- Estorno: devolve ao estoque o que tinha saído (DELETE e UPDATE).
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        UPDATE produto
           SET qtd_estoque = qtd_estoque + OLD.quantidade
         WHERE id_produto = OLD.id_produto;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    -- Baixa: INSERT e UPDATE. FOR UPDATE trava o produto para que duas
    -- vendas simultâneas não usem a mesma unidade do estoque.
    SELECT ativo, qtd_estoque, estoque_minimo, preco_venda
      INTO v_ativo, v_estoque, v_minimo, v_preco
      FROM produto
     WHERE id_produto = NEW.id_produto
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produto % não encontrado.', NEW.id_produto;
    END IF;

    IF NOT v_ativo AND (TG_OP = 'INSERT' OR NEW.id_produto <> OLD.id_produto) THEN
        RAISE EXCEPTION 'Produto % está inativo e não pode ser vendido.', NEW.id_produto;
    END IF;

    IF v_estoque < NEW.quantidade THEN
        RAISE EXCEPTION 'Estoque insuficiente para o produto %: disponível %, solicitado %.',
            NEW.id_produto, v_estoque, NEW.quantidade;
    END IF;

    IF NEW.valor_unitario IS NULL THEN
        NEW.valor_unitario := v_preco;
    END IF;

    UPDATE produto
       SET qtd_estoque = qtd_estoque - NEW.quantidade
     WHERE id_produto = NEW.id_produto;

    IF v_estoque - NEW.quantidade <= v_minimo THEN
        RAISE NOTICE 'Atenção: o produto % ficou com % unidade(s), no estoque mínimo ou abaixo (%).',
            NEW.id_produto, v_estoque - NEW.quantidade, v_minimo;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_venda_estoque ON venda_produto;
CREATE TRIGGER trg_venda_estoque
    BEFORE INSERT OR UPDATE OR DELETE ON venda_produto
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_venda_estoque();

-- ---------------------------------------------------------------------
-- T02 - trg_pagamento_valida
-- Tabela: pagamento | BEFORE INSERT OR UPDATE
--
-- - Só aceita pagamento de agendamento com status 'concluido'.
-- - O desconto não pode ser maior que o valor do agendamento.
-- - valor_pago vazio é calculado (valor - desconto); se for informado,
--   precisa bater com esse cálculo.
-- Essas regras dependem de outra tabela (agendamento), por isso não
-- podem ser feitas com CHECK.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_pagamento_valida()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status  TEXT;
    v_valor   NUMERIC(10,2);
BEGIN
    SELECT status, valor INTO v_status, v_valor
      FROM agendamento
     WHERE id_agendamento = NEW.id_agendamento;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Agendamento % não encontrado.', NEW.id_agendamento;
    END IF;

    IF v_status <> 'concluido' THEN
        RAISE EXCEPTION 'Agendamento % está com status "%". Só é possível registrar pagamento de atendimento concluído.',
            NEW.id_agendamento, v_status;
    END IF;

    IF v_valor IS NULL THEN
        RAISE EXCEPTION 'Agendamento % não tem valor definido.', NEW.id_agendamento;
    END IF;

    NEW.desconto := COALESCE(NEW.desconto, 0);

    IF NEW.desconto > v_valor THEN
        RAISE EXCEPTION 'Desconto de R$ % maior que o valor do atendimento (R$ %).',
            NEW.desconto, v_valor;
    END IF;

    IF NEW.valor_pago IS NULL THEN
        NEW.valor_pago := v_valor - NEW.desconto;
    ELSIF NEW.valor_pago <> v_valor - NEW.desconto THEN
        RAISE EXCEPTION 'Valor pago (R$ %) não confere com valor do atendimento - desconto (R$ % - R$ % = R$ %).',
            NEW.valor_pago, v_valor, NEW.desconto, v_valor - NEW.desconto;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pagamento_valida ON pagamento;
CREATE TRIGGER trg_pagamento_valida
    BEFORE INSERT OR UPDATE ON pagamento
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_pagamento_valida();

-- ---------------------------------------------------------------------
-- T03 - trg_agendamento_regras
-- Tabela: agendamento | BEFORE INSERT OR UPDATE
--
-- - valor vazio recebe o preço atual do serviço.
-- - Não permite agendar serviço inativo (ativo = 0).
-- - Não permite conflito de horário do profissional, considerando a
--   duração do serviço (usa a function fn_horario_disponivel).
-- - Não permite tirar do status 'concluido' um atendimento já pago.
-- Agendamentos cancelados não passam pelas validações de serviço e
-- horário, já que não ocupam a agenda.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_agendamento_regras()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_preco    NUMERIC(10,2);
    v_duracao  INTEGER;
    v_ativo    SMALLINT;
BEGIN
    -- Atendimento pago não pode voltar para 'agendado' nem ser cancelado.
    IF TG_OP = 'UPDATE'
       AND OLD.status = 'concluido'
       AND NEW.status <> 'concluido'
       AND EXISTS (SELECT 1 FROM pagamento WHERE id_agendamento = OLD.id_agendamento) THEN
        RAISE EXCEPTION 'Agendamento % já foi pago e não pode mudar para "%".',
            OLD.id_agendamento, NEW.status;
    END IF;

    SELECT preco, duracao_minutos, ativo INTO v_preco, v_duracao, v_ativo
      FROM servico
     WHERE id_servico = NEW.id_servico;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Serviço % não encontrado.', NEW.id_servico;
    END IF;

    IF NEW.valor IS NULL THEN
        NEW.valor := v_preco;
    END IF;

    IF NEW.status = 'cancelado' THEN
        RETURN NEW;
    END IF;

    IF v_ativo = 0 AND (TG_OP = 'INSERT' OR NEW.id_servico <> OLD.id_servico) THEN
        RAISE EXCEPTION 'Serviço % está inativo e não pode ser agendado.', NEW.id_servico;
    END IF;

    -- Só confere a agenda se for um agendamento novo ou se mudou algo que
    -- afeta o horário (profissional, data, hora, serviço ou reativação).
    IF TG_OP = 'INSERT'
       OR NEW.id_profissional  IS DISTINCT FROM OLD.id_profissional
       OR NEW.data_agendamento IS DISTINCT FROM OLD.data_agendamento
       OR NEW.hora             IS DISTINCT FROM OLD.hora
       OR NEW.id_servico       IS DISTINCT FROM OLD.id_servico
       OR OLD.status = 'cancelado' THEN

        -- Trava o profissional para que dois agendamentos simultâneos não
        -- passem pela verificação ao mesmo tempo.
        PERFORM 1 FROM profissional WHERE id_profissional = NEW.id_profissional FOR UPDATE;

        IF NOT fn_horario_disponivel(NEW.id_profissional, NEW.data_agendamento,
                                     NEW.hora, v_duracao, NEW.id_agendamento) THEN
            RAISE EXCEPTION 'Conflito de horário: o profissional % já tem atendimento que se sobrepõe ao intervalo % - % do dia %.',
                NEW.id_profissional, NEW.hora,
                to_char(NEW.hora::TIME + make_interval(mins => COALESCE(v_duracao, 30)), 'HH24:MI'),
                to_char(NEW.data_agendamento, 'DD/MM/YYYY');
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_agendamento_regras ON agendamento;
CREATE TRIGGER trg_agendamento_regras
    BEFORE INSERT OR UPDATE ON agendamento
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_agendamento_regras();
