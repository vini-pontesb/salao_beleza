-- =============================================================================
-- estrutura_apd1.sql
-- Estrutura da base do salão (APD1) exatamente como está no Supabase em
-- 17/11/2026: 7 tabelas, restrições, índice, funções, procedimentos e gatilhos.
-- Foi extraída do catálogo do banco e serve para reproduzir a base num
-- PostgreSQL local e testar os scripts da APD3 sem tocar no Supabase.
--
-- Rodar como postgres, num banco vazio criado por simular_supabase.sql:
--   psql "$URL" -v ON_ERROR_STOP=1 -1 -f estrutura_apd1.sql
-- =============================================================================

CREATE TABLE public.cliente (
  id_cliente      serial PRIMARY KEY,
  nome            text NOT NULL,
  telefone        text,
  email           text,
  data_nascimento date,
  data_cadastro   date NOT NULL DEFAULT CURRENT_DATE,
  CONSTRAINT cliente_email_key UNIQUE (email),
  CONSTRAINT ck_cliente_email CHECK (email IS NULL OR email LIKE '%_@_%._%'),
  CONSTRAINT ck_cliente_nascimento CHECK (data_nascimento IS NULL OR data_nascimento < data_cadastro)
);

CREATE TABLE public.profissional (
  id_profissional     serial PRIMARY KEY,
  nome                text NOT NULL,
  especialidade       text,
  telefone            text,
  comissao_percentual numeric(5,2) NOT NULL DEFAULT 0,
  data_admissao       date,
  CONSTRAINT ck_profissional_comissao CHECK (comissao_percentual >= 0 AND comissao_percentual <= 100)
);

CREATE TABLE public.servico (
  id_servico      serial PRIMARY KEY,
  nome            text NOT NULL,
  descricao       text,
  categoria       varchar(30) NOT NULL DEFAULT 'Cabelo',
  preco           numeric(10,2) NOT NULL,
  duracao_minutos integer,
  ativo           smallint NOT NULL DEFAULT 1,
  CONSTRAINT servico_nome_key UNIQUE (nome),
  CONSTRAINT ck_servico_ativo CHECK (ativo IN (0, 1)),
  CONSTRAINT ck_servico_categoria CHECK (categoria IN ('Cabelo', 'Barba', 'Unhas', 'Estética', 'Maquiagem', 'Depilação')),
  CONSTRAINT ck_servico_duracao CHECK (duracao_minutos IS NULL OR duracao_minutos > 0),
  CONSTRAINT ck_servico_preco CHECK (preco > 0)
);

CREATE TABLE public.agendamento (
  id_agendamento   serial PRIMARY KEY,
  id_cliente       integer NOT NULL,
  id_profissional  integer NOT NULL,
  id_servico       integer NOT NULL,
  data_agendamento date NOT NULL,
  hora             text,
  valor            numeric(10,2),
  status           text NOT NULL DEFAULT 'agendado',
  CONSTRAINT ck_agendamento_hora CHECK (hora IS NULL OR hora ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  CONSTRAINT ck_agendamento_status CHECK (status IN ('agendado', 'concluido', 'cancelado')),
  CONSTRAINT ck_agendamento_valor CHECK (valor IS NULL OR valor >= 0),
  CONSTRAINT fk_agendamento_cliente FOREIGN KEY (id_cliente)
    REFERENCES public.cliente (id_cliente) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_agendamento_profissional FOREIGN KEY (id_profissional)
    REFERENCES public.profissional (id_profissional) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_agendamento_servico FOREIGN KEY (id_servico)
    REFERENCES public.servico (id_servico) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_agendamento_horario_profissional
  ON public.agendamento (id_profissional, data_agendamento, hora)
  WHERE status <> 'cancelado';

CREATE TABLE public.pagamento (
  id_pagamento        serial PRIMARY KEY,
  id_agendamento      integer NOT NULL,
  forma_pagamento     varchar(20) NOT NULL,
  valor_pago          numeric(10,2) NOT NULL,
  desconto            numeric(10,2) NOT NULL DEFAULT 0,
  parcelas            smallint NOT NULL DEFAULT 1,
  data_hora_pagamento timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pagamento_id_agendamento_key UNIQUE (id_agendamento),
  CONSTRAINT ck_pagamento_forma CHECK (forma_pagamento IN ('dinheiro', 'pix', 'debito', 'credito')),
  CONSTRAINT ck_pagamento_parcelas CHECK (parcelas >= 1 AND parcelas <= 6 AND (forma_pagamento = 'credito' OR parcelas = 1)),
  CONSTRAINT ck_pagamento_valor CHECK (valor_pago > 0 AND desconto >= 0),
  CONSTRAINT fk_pagamento_agendamento FOREIGN KEY (id_agendamento)
    REFERENCES public.agendamento (id_agendamento) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE public.produto (
  id_produto     serial PRIMARY KEY,
  nome           varchar(100) NOT NULL,
  marca          varchar(60) NOT NULL,
  categoria      varchar(30) NOT NULL,
  preco_venda    numeric(10,2) NOT NULL,
  qtd_estoque    integer NOT NULL DEFAULT 0,
  estoque_minimo integer NOT NULL DEFAULT 5,
  codigo_barras  char(13),
  ativo          boolean NOT NULL DEFAULT true,
  CONSTRAINT produto_codigo_barras_key UNIQUE (codigo_barras),
  CONSTRAINT uq_produto_nome_marca UNIQUE (nome, marca),
  CONSTRAINT ck_produto_categoria CHECK (categoria IN ('Shampoo', 'Condicionador', 'Tratamento', 'Finalizador',
                                                       'Coloração', 'Unhas', 'Pele', 'Barba')),
  CONSTRAINT ck_produto_estoque CHECK (qtd_estoque >= 0 AND estoque_minimo >= 0),
  CONSTRAINT ck_produto_preco CHECK (preco_venda > 0)
);

CREATE TABLE public.venda_produto (
  id_venda        serial PRIMARY KEY,
  id_cliente      integer NOT NULL,
  id_produto      integer NOT NULL,
  id_profissional integer,
  quantidade      smallint NOT NULL DEFAULT 1,
  valor_unitario  numeric(10,2) NOT NULL,
  forma_pagamento varchar(20) NOT NULL,
  data_venda      timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_venda_forma CHECK (forma_pagamento IN ('dinheiro', 'pix', 'debito', 'credito')),
  CONSTRAINT ck_venda_quantidade CHECK (quantidade > 0),
  CONSTRAINT ck_venda_valor CHECK (valor_unitario > 0),
  CONSTRAINT fk_venda_cliente FOREIGN KEY (id_cliente)
    REFERENCES public.cliente (id_cliente) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_venda_produto FOREIGN KEY (id_produto)
    REFERENCES public.produto (id_produto) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_venda_profissional FOREIGN KEY (id_profissional)
    REFERENCES public.profissional (id_profissional) ON UPDATE CASCADE ON DELETE SET NULL
);

-- Funções e procedimentos da APD1 -------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_total_gasto_cliente(p_id_cliente integer)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_horario_disponivel(p_id_profissional integer, p_data date, p_hora text, p_duracao_minutos integer, p_ignorar_agendamento integer DEFAULT NULL::integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_comissao_profissional(p_id_profissional integer, p_data_inicio date, p_data_fim date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$;

CREATE OR REPLACE PROCEDURE public.sp_concluir_atendimento(IN p_id_agendamento integer, IN p_forma_pagamento character varying, IN p_desconto numeric DEFAULT 0, IN p_parcelas integer DEFAULT 1)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$;

CREATE OR REPLACE PROCEDURE public.sp_repor_estoque(IN p_id_produto integer, IN p_quantidade integer, INOUT p_estoque_atual integer DEFAULT NULL::integer)
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$;

CREATE OR REPLACE PROCEDURE public.sp_cancelar_agendamentos_expirados(IN p_data_referencia date DEFAULT CURRENT_DATE, INOUT p_qtd_cancelados integer DEFAULT NULL::integer)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    UPDATE agendamento
       SET status = 'cancelado'
     WHERE status = 'agendado'
       AND data_agendamento < p_data_referencia;

    GET DIAGNOSTICS p_qtd_cancelados = ROW_COUNT;

    RAISE NOTICE '% agendamento(s) anterior(es) a % cancelado(s).',
        p_qtd_cancelados, p_data_referencia;
END;
$procedure$;

CREATE OR REPLACE FUNCTION public.fn_trg_venda_estoque()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_pagamento_valida()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_agendamento_regras()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE TRIGGER trg_agendamento_regras
  BEFORE INSERT OR UPDATE ON public.agendamento
  FOR EACH ROW EXECUTE FUNCTION fn_trg_agendamento_regras();

CREATE TRIGGER trg_pagamento_valida
  BEFORE INSERT OR UPDATE ON public.pagamento
  FOR EACH ROW EXECUTE FUNCTION fn_trg_pagamento_valida();

CREATE TRIGGER trg_venda_estoque
  BEFORE INSERT OR DELETE OR UPDATE ON public.venda_produto
  FOR EACH ROW EXECUTE FUNCTION fn_trg_venda_estoque();

-- No Supabase, as 7 tabelas estão com RLS ligado e nenhuma política.
ALTER TABLE public.cliente       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profissional  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.servico       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agendamento   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagamento     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produto       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.venda_produto ENABLE ROW LEVEL SECURITY;
