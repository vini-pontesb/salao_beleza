-- =============================================================================
-- APD3 · Script 90 · Testes de acesso e de operação
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Item (iv) da APD3: evidência de que cada mecanismo FUNCIONA.
--
-- Cada caso assume um papel (SET ROLE), tenta uma operação e compara o que
-- aconteceu com o esperado:
--   permitido   a operação rodou
--   negado      o banco recusou por falta de privilégio ou por política de
--               linha (erro 42501), ou por regra de segurança (trilha de
--               auditoria somente inclusão)
--   rejeitado   o banco recusou por regra de integridade: CHECK, FK, UNIQUE,
--               NOT NULL ou gatilho de regra de negócio da APD1
--   valor=X     a operação rodou e devolveu X (ex.: quantas linhas o RLS mostra)
--
-- NADA FICA GRAVADO: os dados de teste (todos com o prefixo APD3), as
-- alterações e as permissões temporárias para assumir os papéis rodam dentro
-- de um bloco que é desfeito no fim. Pode rodar quantas vezes quiser.
--
-- Rodar depois dos scripts 01 a 07, como postgres (SQL Editor do Supabase ou
-- psql). A saída é uma única tabela (menos de 100 linhas, o limite que o SQL
-- Editor mostra); a última linha é o resumo.
-- =============================================================================

CREATE TEMP TABLE IF NOT EXISTS apd3_resultado (
  n         int,
  grupo     text,
  caso      text,
  papel     text,
  esperado  text,
  obtido    text,
  ok        boolean,
  detalhe   text
);
TRUNCATE pg_temp.apd3_resultado;

-- Roda p_sql como p_papel e diz o que aconteceu. Desfaz tudo no fim, a menos
-- que p_manter seja verdadeiro (usado só para gerar as alterações auditadas).
CREATE OR REPLACE FUNCTION pg_temp.apd3_executar(p_papel text, p_sql text, p_manter boolean DEFAULT false,
                                                 OUT obtido text, OUT detalhe text)
LANGUAGE plpgsql
AS $$
DECLARE
  v_fase  text := 'papel';
  v_valor text;
BEGIN
  BEGIN
    IF p_papel IS NOT NULL THEN
      EXECUTE format('SET LOCAL ROLE %I', p_papel);
    END IF;
    v_fase := 'comando';
    SET CONSTRAINTS ALL IMMEDIATE;
    IF p_sql ~* '^\s*(select|with|values)\M' THEN
      EXECUTE p_sql INTO v_valor;
    ELSE
      EXECUTE p_sql;
    END IF;
    obtido  := 'permitido';
    detalhe := coalesce(v_valor, '');
    IF p_manter THEN
      SET LOCAL ROLE NONE;
    ELSE
      RAISE EXCEPTION 'apd3:desfazer';
    END IF;
  EXCEPTION
    WHEN raise_exception THEN
      -- 'apd3:desfazer' é o nosso; qualquer outro vem de um gatilho da APD1.
      IF SQLERRM <> 'apd3:desfazer' THEN
        obtido := 'rejeitado'; detalhe := SQLERRM;
      END IF;
    WHEN insufficient_privilege OR read_only_sql_transaction THEN
      obtido  := CASE v_fase WHEN 'papel' THEN 'não testado' ELSE 'negado' END;
      detalhe := SQLERRM;
    WHEN check_violation OR not_null_violation OR foreign_key_violation
         OR unique_violation OR restrict_violation OR exclusion_violation OR data_exception THEN
      obtido := 'rejeitado'; detalhe := SQLERRM;
    WHEN OTHERS THEN
      obtido := 'erro'; detalhe := SQLSTATE || ': ' || SQLERRM;
  END;
END
$$;

-- Registra um caso: roda, compara com o esperado e devolve uma linha em JSON.
CREATE OR REPLACE FUNCTION pg_temp.apd3_caso(p_grupo text, p_caso text, p_papel text, p_sql text,
                                             p_esperado text, p_manter boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  r      record;
  v_obt  text;
  v_det  text;
BEGIN
  SELECT * INTO r FROM pg_temp.apd3_executar(p_papel, p_sql, p_manter);
  IF p_esperado LIKE 'valor=%' AND r.obtido = 'permitido' THEN
    v_obt := 'valor=' || r.detalhe;
    v_det := '';
  ELSE
    v_obt := r.obtido;
    v_det := r.detalhe;
  END IF;
  RETURN jsonb_build_object(
    'grupo', p_grupo, 'caso', p_caso, 'papel', coalesce(p_papel, current_user || ' (DBA)'),
    'esperado', p_esperado, 'obtido', v_obt, 'ok', v_obt = p_esperado, 'detalhe', v_det);
END
$$;

DO $testes$
DECLARE
  r              jsonb := '[]'::jsonb;
  v_versao       int := current_setting('server_version_num')::int;
  v_papel        text;
  v_dia          date := current_date + 400;   -- longe de qualquer agendamento real
  v_srv          int;
  v_srv_inativo  int;
  v_prof_a       int;
  v_prof_b       int;
  v_cli          int;
  v_a1           int;
  v_a2           int;
  v_a3           int;
  v_a4           int;
  v_a5           int;
  v_a6           int;
  v_prod         int;
  v_prod_inativo int;
  v_total_cli    text;
BEGIN
  BEGIN  -- tudo dentro deste bloco é desfeito no fim
    SET CONSTRAINTS ALL IMMEDIATE;

    -- 0. Permissão temporária para o usuário atual assumir os papéis testados.
    FOREACH v_papel IN ARRAY ARRAY['gerente_salao', 'recepcao_salao', 'profissional_salao', 'analista_salao',
                                   'auditor_salao', 'backup_salao', 'anon', 'authenticated', 'service_role'] LOOP
      CONTINUE WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_papel);
      BEGIN
        IF v_versao >= 160000 THEN
          EXECUTE format('GRANT %I TO %I WITH INHERIT FALSE, SET TRUE', v_papel, current_user);
        ELSE
          EXECUTE format('GRANT %I TO %I', v_papel, current_user);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        NULL;  -- já é membro, ou não pode se conceder o papel: o caso mostra "não testado"
      END;
    END LOOP;

    -- 1. Dados de teste ---------------------------------------------------------
    INSERT INTO public.servico (nome, descricao, categoria, preco, duracao_minutos, ativo)
    VALUES ('APD3 Serviço Teste', 'Serviço criado pelo teste da APD3', 'Cabelo', 100.00, 60, 1)
    RETURNING id_servico INTO v_srv;
    INSERT INTO public.servico (nome, descricao, categoria, preco, duracao_minutos, ativo)
    VALUES ('APD3 Serviço Inativo', 'Serviço inativo do teste da APD3', 'Barba', 50.00, 30, 0)
    RETURNING id_servico INTO v_srv_inativo;

    INSERT INTO public.profissional (nome, especialidade, telefone, comissao_percentual, data_admissao)
    VALUES ('APD3 Profissional A', 'Teste', '(21) 90000-0001', 30.00, current_date)
    RETURNING id_profissional INTO v_prof_a;
    INSERT INTO public.profissional (nome, especialidade, telefone, comissao_percentual, data_admissao)
    VALUES ('APD3 Profissional B', 'Teste', '(21) 90000-0002', 20.00, current_date)
    RETURNING id_profissional INTO v_prof_b;

    -- O usuário profissional_salao passa a representar o profissional A.
    INSERT INTO seguranca.usuario_profissional (usuario, id_profissional)
    VALUES ('profissional_salao', v_prof_a)
    ON CONFLICT (usuario) DO UPDATE SET id_profissional = EXCLUDED.id_profissional;

    INSERT INTO public.cliente (nome, telefone, email, data_nascimento)
    VALUES ('APD3 Cliente Teste da Silva', '(21) 91234-5678', 'apd3.cliente.teste@exemplo.com', date '1990-05-20')
    RETURNING id_cliente INTO v_cli;

    INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
    VALUES (v_cli, v_prof_a, v_srv, v_dia, '08:00') RETURNING id_agendamento INTO v_a1;
    INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
    VALUES (v_cli, v_prof_a, v_srv, v_dia, '10:00') RETURNING id_agendamento INTO v_a2;
    INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
    VALUES (v_cli, v_prof_b, v_srv, v_dia, '08:00') RETURNING id_agendamento INTO v_a3;
    INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
    VALUES (v_cli, v_prof_a, v_srv, v_dia + 1, '09:00') RETURNING id_agendamento INTO v_a4;
    INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
    VALUES (v_cli, v_prof_a, v_srv, v_dia + 2, '09:00') RETURNING id_agendamento INTO v_a5;
    INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
    VALUES (v_cli, v_prof_a, v_srv, v_dia + 3, '09:00') RETURNING id_agendamento INTO v_a6;
    CALL public.sp_concluir_atendimento(v_a4, 'pix');                  -- a4: concluído e pago (R$ 100)
    UPDATE public.agendamento SET status = 'cancelado' WHERE id_agendamento = v_a5;  -- a5: cancelado
    UPDATE public.agendamento SET status = 'concluido' WHERE id_agendamento = v_a6;  -- a6: concluído, falta pagar

    INSERT INTO public.produto (nome, marca, categoria, preco_venda, qtd_estoque, estoque_minimo, codigo_barras, ativo)
    VALUES ('APD3 Produto Ativo', 'APD3', 'Shampoo', 30.00, 10, 2, '9990000000001', true)
    RETURNING id_produto INTO v_prod;
    INSERT INTO public.produto (nome, marca, categoria, preco_venda, qtd_estoque, estoque_minimo, codigo_barras, ativo)
    VALUES ('APD3 Produto Inativo', 'APD3', 'Shampoo', 30.00, 10, 2, NULL, false)
    RETURNING id_produto INTO v_prod_inativo;

    SELECT count(*)::text INTO v_total_cli FROM public.cliente;

    -- A. API automática do Supabase (chave pública e chave secreta) -------------
    r := r || pg_temp.apd3_caso('A. API do Supabase', 'Chave pública lê clientes (nome, telefone, e-mail)', 'anon',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'negado');
    r := r || pg_temp.apd3_caso('A. API do Supabase', 'Chave pública lê pagamentos', 'anon',
                                $q$SELECT count(*)::text FROM public.pagamento$q$, 'negado');
    r := r || pg_temp.apd3_caso('A. API do Supabase', 'Usuário autenticado da API cadastra cliente', 'authenticated',
                                $q$INSERT INTO public.cliente (nome) VALUES ('Intruso')$q$, 'negado');
    r := r || pg_temp.apd3_caso('A. API do Supabase', 'Chave secreta da API (service_role) lê clientes', 'service_role',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'negado');
    r := r || pg_temp.apd3_caso('A. API do Supabase', 'Chave pública executa fn_total_gasto_cliente', 'anon',
                                format($q$SELECT public.fn_total_gasto_cliente(%s)::text$q$, v_cli), 'negado');
    r := r || pg_temp.apd3_caso('A. API do Supabase', 'Chave pública chama sp_concluir_atendimento', 'anon',
                                format($q$CALL public.sp_concluir_atendimento(%s, 'pix')$q$, v_a1), 'negado');
    r := r || pg_temp.apd3_caso('A. API do Supabase', 'Chave pública lê relatório de faturamento', 'anon',
                                $q$SELECT count(*)::text FROM relatorios.vw_faturamento_mensal$q$, 'negado');

    -- B. Gerência (gerente_salao / perfil_gerente) -------------------------------
    r := r || pg_temp.apd3_caso('B. Gerência', 'Lê todos os clientes', 'gerente_salao',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'valor=' || v_total_cli);
    r := r || pg_temp.apd3_caso('B. Gerência', 'Cadastra serviço', 'gerente_salao',
                                $q$INSERT INTO public.servico (nome, categoria, preco, duracao_minutos) VALUES ('APD3 Serviço Novo', 'Unhas', 40, 30)$q$, 'permitido');
    r := r || pg_temp.apd3_caso('B. Gerência', 'Altera o preço de um serviço', 'gerente_salao',
                                format($q$UPDATE public.servico SET preco = 120 WHERE id_servico = %s$q$, v_srv), 'permitido');
    r := r || pg_temp.apd3_caso('B. Gerência', 'Exclui agendamento cancelado', 'gerente_salao',
                                format($q$DELETE FROM public.agendamento WHERE id_agendamento = %s$q$, v_a5), 'permitido');
    r := r || pg_temp.apd3_caso('B. Gerência', 'Calcula comissão do profissional (30% de R$ 100)', 'gerente_salao',
                                format($q$SELECT public.fn_comissao_profissional(%s, %L, %L)::text$q$, v_prof_a, v_dia, v_dia + 1), 'valor=30.00');
    r := r || pg_temp.apd3_caso('B. Gerência', 'Repõe estoque pelo procedimento', 'gerente_salao',
                                format($q$CALL public.sp_repor_estoque(%s, 5)$q$, v_prod), 'permitido');
    r := r || pg_temp.apd3_caso('B. Gerência', 'TRUNCATE em vendas', 'gerente_salao',
                                $q$TRUNCATE public.venda_produto$q$, 'negado');
    r := r || pg_temp.apd3_caso('B. Gerência', 'DROP TABLE de clientes', 'gerente_salao',
                                $q$DROP TABLE public.cliente$q$, 'negado');
    r := r || pg_temp.apd3_caso('B. Gerência', 'Concede a si mesma o perfil de backup (escalada de privilégio)', 'gerente_salao',
                                $q$GRANT perfil_backup TO gerente_salao$q$, 'negado');
    r := r || pg_temp.apd3_caso('B. Gerência', 'Lê a trilha de auditoria', 'gerente_salao',
                                $q$SELECT count(*)::text FROM auditoria.registro_alteracao$q$, 'negado');
    r := r || pg_temp.apd3_caso('B. Gerência', 'Forja um registro na trilha de auditoria', 'gerente_salao',
                                $q$INSERT INTO auditoria.registro_alteracao (usuario_sessao, papel_efetivo, tabela, operacao) VALUES ('x', 'x', 'x', 'INSERT')$q$, 'negado');

    -- C. Recepção (recepcao_salao / perfil_recepcao) -----------------------------
    r := r || pg_temp.apd3_caso('C. Recepção', 'Lê clientes', 'recepcao_salao',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'valor=' || v_total_cli);
    r := r || pg_temp.apd3_caso('C. Recepção', 'Cadastra cliente', 'recepcao_salao',
                                $q$INSERT INTO public.cliente (nome, telefone) VALUES ('APD3 Cliente Novo', '(21) 95555-0000')$q$, 'permitido');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Exclui cliente', 'recepcao_salao',
                                format($q$DELETE FROM public.cliente WHERE id_cliente = %s$q$, v_cli), 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Lê o nome do profissional (coluna liberada)', 'recepcao_salao',
                                format($q$SELECT nome FROM public.profissional WHERE id_profissional = %s$q$, v_prof_a), 'valor=APD3 Profissional A');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Lê a comissão do profissional (coluna restrita)', 'recepcao_salao',
                                $q$SELECT comissao_percentual::text FROM public.profissional LIMIT 1$q$, 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Altera o preço de um serviço', 'recepcao_salao',
                                format($q$UPDATE public.servico SET preco = 1 WHERE id_servico = %s$q$, v_srv), 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Marca agendamento: o valor vem do preço do serviço', 'recepcao_salao',
                                format($q$WITH novo AS (INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora) VALUES (%s, %s, %s, %L, '14:00') RETURNING valor) SELECT valor::text FROM novo$q$,
                                       v_cli, v_prof_b, v_srv, v_dia), 'valor=100.00');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Marca agendamento digitando o valor', 'recepcao_salao',
                                format($q$INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor) VALUES (%s, %s, %s, %L, '16:00', 1.00)$q$,
                                       v_cli, v_prof_b, v_srv, v_dia), 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'RLS: cria agendamento já como concluído', 'recepcao_salao',
                                format($q$INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora, status) VALUES (%s, %s, %s, %L, '18:00', 'concluido')$q$,
                                       v_cli, v_prof_b, v_srv, v_dia), 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Remarca agendamento', 'recepcao_salao',
                                format($q$UPDATE public.agendamento SET hora = '13:00' WHERE id_agendamento = %s$q$, v_a2), 'permitido');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Cancela agendamento', 'recepcao_salao',
                                format($q$UPDATE public.agendamento SET status = 'cancelado' WHERE id_agendamento = %s$q$, v_a1), 'permitido');
    r := r || pg_temp.apd3_caso('C. Recepção', 'RLS: marca concluído sem registrar pagamento', 'recepcao_salao',
                                format($q$UPDATE public.agendamento SET status = 'concluido' WHERE id_agendamento = %s$q$, v_a3), 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'RLS: altera atendimento já concluído (0 linhas alcançadas)', 'recepcao_salao',
                                format($q$WITH alterados AS (UPDATE public.agendamento SET hora = '11:00' WHERE id_agendamento = %s RETURNING 1) SELECT count(*)::text FROM alterados$q$, v_a4), 'valor=0');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Conclui atendimento pelo procedimento (registra o pagamento)', 'recepcao_salao',
                                format($q$CALL public.sp_concluir_atendimento(%s, 'dinheiro')$q$, v_a3), 'permitido');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Registra pagamento de atendimento concluído: o valor vem do agendamento', 'recepcao_salao',
                                format($q$WITH novo AS (INSERT INTO public.pagamento (id_agendamento, forma_pagamento) VALUES (%s, 'pix') RETURNING valor_pago) SELECT valor_pago::text FROM novo$q$, v_a6), 'valor=100.00');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Registra pagamento digitando o valor pago', 'recepcao_salao',
                                format($q$INSERT INTO public.pagamento (id_agendamento, forma_pagamento, valor_pago) VALUES (%s, 'pix', 1.00)$q$, v_a6), 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Registra venda de produto', 'recepcao_salao',
                                format($q$INSERT INTO public.venda_produto (id_cliente, id_produto, quantidade, forma_pagamento) VALUES (%s, %s, 1, 'pix')$q$, v_cli, v_prod), 'permitido');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Registra venda digitando o preço', 'recepcao_salao',
                                format($q$INSERT INTO public.venda_produto (id_cliente, id_produto, quantidade, valor_unitario, forma_pagamento) VALUES (%s, %s, 1, 0.01, 'pix')$q$, v_cli, v_prod), 'negado');
    r := r || pg_temp.apd3_caso('C. Recepção', 'Consulta horário livre (08:30, que conflita com 08:00-09:00)', 'recepcao_salao',
                                format($q$SELECT public.fn_horario_disponivel(%s, %L, '08:30', 30)::text$q$, v_prof_a, v_dia), 'valor=false');

    -- D. Profissional (profissional_salao / perfil_profissional) -----------------
    r := r || pg_temp.apd3_caso('D. Profissional', 'RLS: vê só os próprios agendamentos', 'profissional_salao',
                                $q$SELECT count(*)::text FROM public.agendamento$q$, 'valor=5');
    r := r || pg_temp.apd3_caso('D. Profissional', 'RLS: agendamentos de outro profissional', 'profissional_salao',
                                format($q$SELECT count(*)::text FROM public.agendamento WHERE id_profissional = %s$q$, v_prof_b), 'valor=0');
    r := r || pg_temp.apd3_caso('D. Profissional', 'View da própria agenda', 'profissional_salao',
                                $q$SELECT count(*)::text FROM agenda.vw_minha_agenda$q$, 'valor=5');
    r := r || pg_temp.apd3_caso('D. Profissional', 'View mostra só o primeiro nome do cliente', 'profissional_salao',
                                $q$SELECT string_agg(DISTINCT cliente_primeiro_nome, ', ') FROM agenda.vw_minha_agenda$q$, 'valor=APD3');
    r := r || pg_temp.apd3_caso('D. Profissional', 'Lê o valor dos agendamentos (coluna restrita)', 'profissional_salao',
                                $q$SELECT sum(valor)::text FROM public.agendamento$q$, 'negado');
    r := r || pg_temp.apd3_caso('D. Profissional', 'Lê clientes', 'profissional_salao',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'negado');
    r := r || pg_temp.apd3_caso('D. Profissional', 'RLS: serviço inativo não aparece', 'profissional_salao',
                                format($q$SELECT count(*)::text FROM public.servico WHERE id_servico = %s$q$, v_srv_inativo), 'valor=0');
    r := r || pg_temp.apd3_caso('D. Profissional', 'Conclui o próprio atendimento', 'profissional_salao',
                                format($q$UPDATE public.agendamento SET status = 'concluido' WHERE id_agendamento = %s$q$, v_a2), 'permitido');
    r := r || pg_temp.apd3_caso('D. Profissional', 'RLS: conclui atendimento de outro profissional (0 linhas alcançadas)', 'profissional_salao',
                                format($q$WITH alterados AS (UPDATE public.agendamento SET status = 'concluido' WHERE id_agendamento = %s RETURNING 1) SELECT count(*)::text FROM alterados$q$, v_a3), 'valor=0');
    r := r || pg_temp.apd3_caso('D. Profissional', 'RLS: cancela o próprio atendimento', 'profissional_salao',
                                format($q$UPDATE public.agendamento SET status = 'cancelado' WHERE id_agendamento = %s$q$, v_a2), 'negado');
    r := r || pg_temp.apd3_caso('D. Profissional', 'Muda a hora do próprio atendimento (coluna restrita)', 'profissional_salao',
                                format($q$UPDATE public.agendamento SET hora = '11:00' WHERE id_agendamento = %s$q$, v_a2), 'negado');
    r := r || pg_temp.apd3_caso('D. Profissional', 'RLS: vê só o próprio vínculo usuário -> profissional', 'profissional_salao',
                                $q$SELECT count(*)::text FROM seguranca.usuario_profissional$q$, 'valor=1');

    -- E. Relatórios (analista_salao / perfil_relatorios) -------------------------
    r := r || pg_temp.apd3_caso('E. Relatórios', 'Lê o faturamento mensal', 'analista_salao',
                                $q$SELECT (count(*) > 0)::text FROM relatorios.vw_faturamento_mensal$q$, 'valor=true');
    r := r || pg_temp.apd3_caso('E. Relatórios', 'Lê os serviços mais realizados', 'analista_salao',
                                format($q$SELECT atendimentos_concluidos::text FROM relatorios.vw_servicos_mais_realizados WHERE id_servico = %s$q$, v_srv), 'valor=2');
    r := r || pg_temp.apd3_caso('E. Relatórios', 'Lê clientes', 'analista_salao',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'negado');
    r := r || pg_temp.apd3_caso('E. Relatórios', 'Lê a agenda dos profissionais', 'analista_salao',
                                $q$SELECT count(*)::text FROM agenda.vw_minha_agenda$q$, 'negado');

    -- F. Auditoria ------------------------------------------------------------------
    -- Primeiro, três alterações que ficam (até o fim do teste).
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Profissional conclui o próprio atendimento (gera registro)', 'profissional_salao',
                                format($q$UPDATE public.agendamento SET status = 'concluido' WHERE id_agendamento = %s$q$, v_a2), 'permitido', true);
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Trilha registra quem, a operação e a coluna alterada', 'auditor_salao',
                                format($q$SELECT papel_efetivo || ' | ' || operacao || ' | ' || array_to_string(colunas_alteradas, ',') FROM auditoria.registro_alteracao WHERE tabela = 'public.agendamento' AND registro_id = %s ORDER BY id DESC LIMIT 1$q$, v_a2),
                                'valor=profissional_salao | UPDATE | status');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Recepção conclui um atendimento (gera registro)', 'recepcao_salao',
                                format($q$CALL public.sp_concluir_atendimento(%s, 'pix')$q$, v_a3), 'permitido', true);
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Trilha registra o pagamento criado pelo procedimento', 'auditor_salao',
                                $q$SELECT papel_efetivo || ' | ' || operacao FROM auditoria.registro_alteracao WHERE tabela = 'public.pagamento' ORDER BY id DESC LIMIT 1$q$,
                                'valor=recepcao_salao | INSERT');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Recepção corrige o telefone de um cliente (gera registro)', 'recepcao_salao',
                                format($q$UPDATE public.cliente SET telefone = '(21) 97777-1234' WHERE id_cliente = %s$q$, v_cli), 'permitido', true);
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Trilha registra a coluna de dado pessoal alterada', 'auditor_salao',
                                format($q$SELECT array_to_string(colunas_alteradas, ',') FROM auditoria.registro_alteracao WHERE tabela = 'public.cliente' AND registro_id = %s ORDER BY id DESC LIMIT 1$q$, v_cli),
                                'valor=telefone');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Trilha NÃO copia o telefone novo (LGPD)', 'auditor_salao',
                                $q$SELECT count(*)::text FROM auditoria.registro_alteracao a WHERE a::text LIKE '%97777-1234%'$q$, 'valor=0');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Consulta usuários e perfis do projeto', 'auditor_salao',
                                $q$SELECT count(*)::text FROM auditoria.vw_usuarios_e_perfis$q$, 'valor=12');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Lê clientes', 'auditor_salao',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'negado');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Apaga registros da trilha', 'auditor_salao',
                                $q$DELETE FROM auditoria.registro_alteracao$q$, 'negado');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Nem o DBA apaga registros da trilha', NULL,
                                $q$DELETE FROM auditoria.registro_alteracao$q$, 'negado');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'Nem o DBA esvazia a trilha (TRUNCATE)', NULL,
                                $q$TRUNCATE auditoria.registro_alteracao$q$, 'negado');
    r := r || pg_temp.apd3_caso('F. Auditoria', 'DBA roda o expurgo por retenção (nada recente é apagado)', NULL,
                                $q$SELECT auditoria.expurgar_registros_antigos(12)::text$q$, 'valor=0');

    -- G. Cópia de segurança (backup_salao / perfil_backup) ------------------------
    r := r || pg_temp.apd3_caso('G. Backup', 'Lê todos os clientes', 'backup_salao',
                                $q$SELECT count(*)::text FROM public.cliente$q$, 'valor=' || v_total_cli);
    r := r || pg_temp.apd3_caso('G. Backup', 'Lê a trilha de auditoria', 'backup_salao',
                                $q$SELECT (count(*) > 0)::text FROM auditoria.registro_alteracao$q$, 'valor=true');
    r := r || pg_temp.apd3_caso('G. Backup', 'Altera clientes', 'backup_salao',
                                $q$UPDATE public.cliente SET nome = nome$q$, 'negado');
    r := r || pg_temp.apd3_caso('G. Backup', 'Apaga pagamentos', 'backup_salao',
                                $q$DELETE FROM public.pagamento$q$, 'negado');

    -- H. Integridade: dado inválido é recusado, venha de quem vier --------------
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: horário que se sobrepõe a outro do profissional', 'recepcao_salao',
                                format($q$INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora) VALUES (%s, %s, %s, %L, '08:30')$q$,
                                       v_cli, v_prof_a, v_srv, v_dia), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: agendar serviço inativo', 'recepcao_salao',
                                format($q$INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora) VALUES (%s, %s, %s, %L, '20:00')$q$,
                                       v_cli, v_prof_b, v_srv_inativo, v_dia), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: pagamento de atendimento não concluído', 'recepcao_salao',
                                format($q$INSERT INTO public.pagamento (id_agendamento, forma_pagamento) VALUES (%s, 'pix')$q$, v_a1), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: valor pago diferente de valor - desconto', 'gerente_salao',
                                format($q$DO $x$ BEGIN UPDATE public.agendamento SET status = 'concluido' WHERE id_agendamento = %s; INSERT INTO public.pagamento (id_agendamento, forma_pagamento, valor_pago) VALUES (%s, 'pix', 1.00); END $x$$q$, v_a1, v_a1),
                                'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: desconto maior que o valor do atendimento', 'recepcao_salao',
                                format($q$CALL public.sp_concluir_atendimento(%s, 'pix', 500)$q$, v_a1), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'CHECK APD1: pagamento em pix parcelado em 3 vezes', 'recepcao_salao',
                                format($q$CALL public.sp_concluir_atendimento(%s, 'pix', 0, 3)$q$, v_a1), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Procedimento APD1: concluir atendimento cancelado', 'recepcao_salao',
                                format($q$CALL public.sp_concluir_atendimento(%s, 'pix')$q$, v_a5), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: cancelar atendimento já pago', 'gerente_salao',
                                format($q$UPDATE public.agendamento SET status = 'cancelado' WHERE id_agendamento = %s$q$, v_a4), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'UNIQUE APD1: pagar duas vezes o mesmo atendimento', 'recepcao_salao',
                                format($q$INSERT INTO public.pagamento (id_agendamento, forma_pagamento) VALUES (%s, 'dinheiro')$q$, v_a4), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: venda acima do estoque', 'recepcao_salao',
                                format($q$INSERT INTO public.venda_produto (id_cliente, id_produto, quantidade, forma_pagamento) VALUES (%s, %s, 999, 'pix')$q$, v_cli, v_prod), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'Gatilho APD1: venda de produto inativo', 'recepcao_salao',
                                format($q$INSERT INTO public.venda_produto (id_cliente, id_produto, quantidade, forma_pagamento) VALUES (%s, %s, 1, 'pix')$q$, v_cli, v_prod_inativo), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'FK APD1: excluir cliente que tem agendamentos', 'gerente_salao',
                                format($q$DELETE FROM public.cliente WHERE id_cliente = %s$q$, v_cli), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'CHECK APD1: nem o DBA grava e-mail sem @', NULL,
                                $q$INSERT INTO public.cliente (nome, email) VALUES ('APD3 E-mail Ruim', 'sem-arroba')$q$, 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'CHECK APD3: nome de cliente só com espaços', 'gerente_salao',
                                $q$INSERT INTO public.cliente (nome) VALUES ('   ')$q$, 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'CHECK APD3: telefone com letras', 'recepcao_salao',
                                format($q$UPDATE public.cliente SET telefone = 'ligar depois' WHERE id_cliente = %s$q$, v_cli), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'CHECK APD3: código de barras com 12 dígitos', 'gerente_salao',
                                format($q$UPDATE public.produto SET codigo_barras = '123456789012' WHERE id_produto = %s$q$, v_prod), 'rejeitado');
    r := r || pg_temp.apd3_caso('H. Integridade', 'CHECK APD3: concluído sem valor, mesmo com o gatilho desligado', NULL,
                                format($q$DO $x$ BEGIN ALTER TABLE public.agendamento DISABLE TRIGGER trg_agendamento_regras; UPDATE public.agendamento SET valor = NULL WHERE id_agendamento = %s; END $x$$q$, v_a4),
                                'rejeitado');

    -- I. Administração: configuração conferida no catálogo ----------------------
    r := r || pg_temp.apd3_caso('I. Administração', 'Nenhum usuário ou perfil do projeto com atributo privilegiado', NULL,
                                $q$SELECT count(*)::text FROM pg_roles WHERE (rolname LIKE 'perfil\_%' OR rolname LIKE '%\_salao') AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls)$q$, 'valor=0');
    r := r || pg_temp.apd3_caso('I. Administração', 'Cada usuário pertence a exatamente um perfil', NULL,
                                $q$SELECT count(*)::text FROM pg_roles u WHERE u.rolname IN ('gerente_salao', 'recepcao_salao', 'profissional_salao', 'analista_salao', 'auditor_salao', 'backup_salao') AND (SELECT count(*) FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid WHERE m.member = u.oid AND g.rolname LIKE 'perfil\_%') <> 1$q$, 'valor=0');
    r := r || pg_temp.apd3_caso('I. Administração', 'Contas que só leem abrem sessão somente leitura', NULL,
                                $q$SELECT count(*)::text FROM pg_db_role_setting s JOIN pg_roles ro ON ro.oid = s.setrole WHERE ro.rolname IN ('analista_salao', 'auditor_salao', 'backup_salao') AND 'default_transaction_read_only=on' = ANY (s.setconfig)$q$, 'valor=3');
    r := r || pg_temp.apd3_caso('I. Administração', 'Contas de pessoas têm data de expiração', NULL,
                                $q$SELECT count(*)::text FROM pg_roles WHERE rolname IN ('gerente_salao', 'recepcao_salao', 'profissional_salao', 'analista_salao', 'auditor_salao') AND rolvaliduntil IS NOT NULL AND rolvaliduntil <> 'infinity'$q$, 'valor=5');
    r := r || pg_temp.apd3_caso('I. Administração', 'Tabelas do public sem RLS', NULL,
                                $q$SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity$q$, 'valor=0');
    r := r || pg_temp.apd3_caso('I. Administração', 'Privilégios da API do Supabase nas tabelas do public', NULL,
                                $q$SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace CROSS JOIN pg_roles ro WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND ro.rolname IN ('anon', 'authenticated', 'service_role') AND has_table_privilege(ro.oid, c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE')$q$, 'valor=0');
    r := r || pg_temp.apd3_caso('I. Administração', 'Rotinas do public que qualquer usuário (PUBLIC) executa', NULL,
                                $q$SELECT count(*)::text FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e') AND EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0)$q$, 'valor=0');
    r := r || pg_temp.apd3_caso('I. Administração', 'Rotinas sem search_path fixo (public, auditoria, seguranca)', NULL,
                                $q$SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('public', 'auditoria', 'seguranca') AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e') AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) AS c WHERE c LIKE 'search_path=%')$q$, 'valor=0');

    -- Objetos criados no futuro: nascem fechados para a API e para PUBLIC e
    -- abertos para a gerência, por causa dos privilégios padrão do script 05.
    CREATE TABLE public.apd3_tabela_futura (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY);
    CREATE FUNCTION public.apd3_funcao_futura() RETURNS integer LANGUAGE sql SET search_path = pg_catalog AS 'SELECT 1';
    r := r || pg_temp.apd3_caso('I. Administração', 'Tabela nova no public: gerência grava, API não lê', NULL,
                                $q$SELECT 'gerente: ' || has_table_privilege('perfil_gerente', 'public.apd3_tabela_futura', 'INSERT')::text || ' | API: ' || coalesce((SELECT bool_or(has_table_privilege(ro.oid, 'public.apd3_tabela_futura', 'SELECT')) FROM pg_roles ro WHERE ro.rolname IN ('anon', 'authenticated', 'service_role')), false)::text$q$,
                                'valor=gerente: true | API: false');
    r := r || pg_temp.apd3_caso('I. Administração', 'Função nova no public: só a gerência executa', NULL,
                                $q$SELECT 'gerente: ' || has_function_privilege('perfil_gerente', 'public.apd3_funcao_futura()', 'EXECUTE')::text || ' | recepção: ' || has_function_privilege('perfil_recepcao', 'public.apd3_funcao_futura()', 'EXECUTE')::text || ' | API: ' || coalesce((SELECT bool_or(has_function_privilege(ro.oid, 'public.apd3_funcao_futura()', 'EXECUTE')) FROM pg_roles ro WHERE ro.rolname IN ('anon', 'authenticated', 'service_role')), false)::text$q$,
                                'valor=gerente: true | recepção: false | API: false');

    RAISE EXCEPTION 'apd3:desfazer';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM <> 'apd3:desfazer' THEN
        RAISE;
      END IF;
  END;

  INSERT INTO pg_temp.apd3_resultado (n, grupo, caso, papel, esperado, obtido, ok, detalhe)
  SELECT e.n, e.v ->> 'grupo', e.v ->> 'caso', e.v ->> 'papel', e.v ->> 'esperado', e.v ->> 'obtido',
         (e.v ->> 'ok')::boolean, e.v ->> 'detalhe'
  FROM jsonb_array_elements(r) WITH ORDINALITY AS e(v, n);
END
$testes$;

SELECT n AS "nº", grupo, caso, papel, esperado, obtido,
       CASE WHEN ok THEN 'PASSOU' ELSE 'FALHOU' END AS resultado,
       detalhe
FROM pg_temp.apd3_resultado
UNION ALL
SELECT 999, 'RESUMO',
       format('%s de %s casos passaram', count(*) FILTER (WHERE ok), count(*)),
       NULL, NULL, NULL,
       CASE WHEN bool_and(ok) THEN 'PASSOU' ELSE 'FALHOU' END,
       NULL
FROM pg_temp.apd3_resultado
ORDER BY 1;
