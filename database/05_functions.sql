-- =====================================================================
-- 05_functions.sql
-- Projeto Integrador de Banco de Dados II (APD2) - IFRJ Campus Niterói
-- Solução: Sistema de Gestão de Salão de Beleza
-- Equipe: Jean de Pinho Macedo, Vinícius Pontes Braga e Pietro Gomes Borges
-- SGBD: PostgreSQL (Supabase)
--
-- Functions da base. Cada uma recebe parâmetros e DEVOLVE um valor,
-- por isso pode ser usada dentro de SELECT, WHERE e de outras rotinas.
--
--   F01 fn_horario_disponivel      -> BOOLEAN
--   F02 fn_comissao_profissional   -> NUMERIC
--   F03 fn_total_gasto_cliente     -> NUMERIC
--
-- Executar DEPOIS de 01 e 02, e ANTES de 06 e 07 (o trigger de
-- agendamento usa a F01).
-- =====================================================================

-- ---------------------------------------------------------------------
-- F01 - fn_horario_disponivel
-- Verifica se o profissional está livre em uma data e hora, levando em
-- conta a DURAÇÃO dos serviços (o índice único da APD1 só bloqueia o
-- mesmo horário de início).
--
-- Dois atendimentos se sobrepõem quando:
--   inicio_existente < fim_novo  E  fim_existente > inicio_novo
--
-- Agendamentos cancelados não ocupam horário. Serviço sem duração
-- cadastrada é considerado com 30 minutos.
-- p_ignorar_agendamento: id que deve ser desconsiderado (usado ao
-- ALTERAR um agendamento, para ele não conflitar com ele mesmo).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_horario_disponivel(
    p_id_profissional      INTEGER,
    p_data                 DATE,
    p_hora                 TEXT,
    p_duracao_minutos      INTEGER,
    p_ignorar_agendamento  INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
STABLE
LANGUAGE plpgsql
AS $$
DECLARE
    v_inicio  TIMESTAMP;
    v_fim     TIMESTAMP;
BEGIN
    -- Sem hora definida não há como conflitar.
    IF p_hora IS NULL THEN
        RETURN TRUE;
    END IF;

    -- DATE + TIME = TIMESTAMP (evita erro em atendimento que passa da meia-noite).
    v_inicio := p_data + p_hora::TIME;
    v_fim    := v_inicio + make_interval(mins => COALESCE(p_duracao_minutos, 30));

    RETURN NOT EXISTS (
        SELECT 1
          FROM agendamento a
          JOIN servico s ON s.id_servico = a.id_servico
         WHERE a.id_profissional  = p_id_profissional
           AND a.data_agendamento = p_data
           AND a.status <> 'cancelado'
           AND a.hora IS NOT NULL
           AND a.id_agendamento <> COALESCE(p_ignorar_agendamento, -1)
           AND (a.data_agendamento + a.hora::TIME) < v_fim
           AND (a.data_agendamento + a.hora::TIME)
               + make_interval(mins => COALESCE(s.duracao_minutos, 30)) > v_inicio
    );
END;
$$;

COMMENT ON FUNCTION fn_horario_disponivel(INTEGER, DATE, TEXT, INTEGER, INTEGER) IS
    'Retorna TRUE se o profissional estiver livre no intervalo [hora, hora + duração) da data informada.';

-- ---------------------------------------------------------------------
-- F02 - fn_comissao_profissional
-- Comissão de um profissional em um período:
--   soma do valor pago nos atendimentos CONCLUÍDOS do período
--   x comissao_percentual do profissional / 100
-- O período considera a data do atendimento (data_agendamento).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_comissao_profissional(
    p_id_profissional  INTEGER,
    p_data_inicio      DATE,
    p_data_fim         DATE
)
RETURNS NUMERIC(10,2)
STABLE
LANGUAGE plpgsql
AS $$
DECLARE
    v_percentual  NUMERIC(5,2);
    v_faturado    NUMERIC(10,2);
BEGIN
    IF p_data_fim < p_data_inicio THEN
        RAISE EXCEPTION 'Período inválido: a data final (%) é anterior à inicial (%).',
            p_data_fim, p_data_inicio;
    END IF;

    SELECT comissao_percentual INTO v_percentual
      FROM profissional
     WHERE id_profissional = p_id_profissional;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profissional % não encontrado.', p_id_profissional;
    END IF;

    SELECT COALESCE(SUM(pg.valor_pago), 0) INTO v_faturado
      FROM agendamento a
      JOIN pagamento  pg ON pg.id_agendamento = a.id_agendamento
     WHERE a.id_profissional = p_id_profissional
       AND a.status = 'concluido'
       AND a.data_agendamento BETWEEN p_data_inicio AND p_data_fim;

    RETURN ROUND(v_faturado * v_percentual / 100, 2);
END;
$$;

COMMENT ON FUNCTION fn_comissao_profissional(INTEGER, DATE, DATE) IS
    'Retorna o valor de comissão do profissional sobre os atendimentos concluídos e pagos no período.';

-- ---------------------------------------------------------------------
-- F03 - fn_total_gasto_cliente
-- Total que o cliente já gastou no salão:
--   pagamentos de serviços + compras de produtos (quantidade x valor).
-- Base para programas de fidelidade e para identificar os melhores
-- clientes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_gasto_cliente(
    p_id_cliente  INTEGER
)
RETURNS NUMERIC(10,2)
STABLE
LANGUAGE plpgsql
AS $$
DECLARE
    v_servicos  NUMERIC(10,2);
    v_produtos  NUMERIC(10,2);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = p_id_cliente) THEN
        RAISE EXCEPTION 'Cliente % não encontrado.', p_id_cliente;
    END IF;

    SELECT COALESCE(SUM(pg.valor_pago), 0) INTO v_servicos
      FROM agendamento a
      JOIN pagamento  pg ON pg.id_agendamento = a.id_agendamento
     WHERE a.id_cliente = p_id_cliente;

    SELECT COALESCE(SUM(v.quantidade * v.valor_unitario), 0) INTO v_produtos
      FROM venda_produto v
     WHERE v.id_cliente = p_id_cliente;

    RETURN v_servicos + v_produtos;
END;
$$;

COMMENT ON FUNCTION fn_total_gasto_cliente(INTEGER) IS
    'Retorna o total gasto pelo cliente em serviços pagos e compras de produtos.';
