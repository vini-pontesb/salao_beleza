-- =============================================================================
-- APD3 · Script 05 · Privilégios de cada perfil (GRANT / REVOKE)
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Item (ii) da APD3: controle de cada usuário e das suas ações.
--
-- Princípio: privilégio mínimo. Cada perfil recebe só o que a sua função no
-- salão exige, e o script primeiro REVOGA tudo de cada perfil e depois CONCEDE
-- o necessário. Assim o estado do banco é sempre o que está escrito aqui,
-- mesmo que alguém tenha concedido algo a mais pelo painel.
--
-- Também:
--   * fecha a API automática do Supabase (PostgREST e GraphQL). O Supabase
--     concede ALL às roles anon, authenticated e service_role em toda tabela
--     criada no schema public; com a chave anon, que é pública por definição,
--     qualquer pessoa leria nome, telefone, e-mail e data de nascimento dos
--     clientes. Nenhuma tela usa essa API hoje.
--   * tira de PUBLIC (todo mundo) o EXECUTE das funções e procedimentos da
--     APD1 e dá a cada perfil só os que ele usa;
--   * fixa o search_path das 9 rotinas da APD1 e torna SECURITY DEFINER as
--     4 que precisam agir além do privilégio de quem as dispara (os 3 gatilhos
--     e sp_concluir_atendimento), para que a regra de negócio valha para todos
--     os perfis sem dar a eles acesso direto às tabelas que a regra mexe.
--
-- Idempotente. Rodar como postgres, depois dos scripts 01 a 04.
-- =============================================================================

-- Trava de segurança: só continua no banco do salão e rodando como dono das
-- tabelas (o postgres). Em qualquer outro caso, para aqui, antes de alterar
-- qualquer coisa.
DO $$
DECLARE
  v_dono name;
BEGIN
  SELECT tableowner INTO v_dono
    FROM pg_tables
   WHERE schemaname = 'public' AND tablename = 'agendamento';
  IF v_dono IS NULL OR to_regclass('public.cliente') IS NULL OR to_regclass('public.pagamento') IS NULL THEN
    RAISE EXCEPTION 'Banco errado: este script é da base do salão (APD1), e este banco não tem as tabelas agendamento, cliente e pagamento. Nada foi alterado.'
      USING HINT = 'Confira, no topo do painel do Supabase, se o projeto aberto é o salao-agendamento.';
  END IF;
  IF current_user <> v_dono THEN
    RAISE EXCEPTION 'Papel errado: rode este script como % (dono das tabelas); a sessão está como %. Nada foi alterado.',
                    v_dono, current_user
      USING HINT = 'No SQL Editor do Supabase, use o papel postgres.';
  END IF;
END $$;

SET lock_timeout = '10s';

-- 1. Fecha a API automática do Supabase ---------------------------------------
DO $$
DECLARE
  v_papel text;
BEGIN
  FOREACH v_papel IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_papel) THEN
      RAISE NOTICE 'Role % não existe neste banco (não é Supabase); nada a revogar.', v_papel;
      CONTINUE;
    END IF;
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', v_papel);
    EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %I', v_papel);
    EXECUTE format('REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM %I', v_papel);
    -- Tabelas, sequências e rotinas criadas depois também nascem fechadas.
    -- Vale para a regra do schema public e para a regra geral, se existir.
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM %I', v_papel);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %I', v_papel);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM %I', v_papel);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON TABLES FROM %I', v_papel);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON SEQUENCES FROM %I', v_papel);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON FUNCTIONS FROM %I', v_papel);
  END LOOP;
END $$;

-- 2. Rotinas da APD1: search_path fixo e SECURITY DEFINER onde é preciso ------
-- search_path fixo: sem ele, quem cria um objeto com o mesmo nome de uma
-- tabela num schema que vem antes no caminho (ou na área temporária) desvia a
-- rotina para o objeto falso. pg_temp por último fecha essa porta.
--
-- SECURITY DEFINER nos 3 gatilhos: eles leem e alteram outras tabelas (a venda
-- baixa o estoque em produto; o agendamento trava o profissional com FOR
-- UPDATE e confere a agenda inteira). Rodando com o privilégio do dono, a
-- regra vale para qualquer perfil sem que a recepção precise de UPDATE em
-- produto ou em profissional. Gatilhos não exigem EXECUTE de quem os dispara.
--
-- SECURITY DEFINER em sp_concluir_atendimento: conclui e registra o pagamento
-- numa só operação. A recepção não pode marcar 'concluido' direto (RLS do
-- script 06), então é por ele que ela fecha um atendimento no balcão. O
-- procedimento confere o status e grava o valor do próprio agendamento, sem
-- deixar ninguém digitar o valor pago.
ALTER FUNCTION public.fn_trg_agendamento_regras()
  SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_trg_pagamento_valida()
  SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_trg_venda_estoque()
  SECURITY DEFINER SET search_path = public, pg_temp;
ALTER PROCEDURE public.sp_concluir_atendimento(integer, character varying, numeric, integer)
  SECURITY DEFINER SET search_path = public, pg_temp;

-- As demais continuam SECURITY INVOKER (rodam com o privilégio de quem chama).
ALTER FUNCTION public.fn_horario_disponivel(integer, date, text, integer, integer)
  SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_total_gasto_cliente(integer)
  SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_comissao_profissional(integer, date, date)
  SET search_path = public, pg_temp;
ALTER PROCEDURE public.sp_repor_estoque(integer, integer, integer)
  SET search_path = public, pg_temp;
ALTER PROCEDURE public.sp_cancelar_agendamentos_expirados(date, integer)
  SET search_path = public, pg_temp;

-- 3. Ponto de partida limpo para os perfis do projeto -------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public, relatorios, agenda, auditoria, seguranca
  FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public, auditoria
  FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;
REVOKE ALL ON ALL ROUTINES  IN SCHEMA public, auditoria, seguranca
  FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;
REVOKE ALL ON SCHEMA public, relatorios, agenda, auditoria, seguranca
  FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;

-- 4. Schemas -----------------------------------------------------------------
-- Ninguém além do dono cria objetos no public (o PostgreSQL 15+ já nasce assim;
-- a linha deixa a regra explícita).
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
-- Os schemas novos não são de uso geral.
REVOKE ALL ON SCHEMA relatorios, agenda, auditoria, seguranca FROM PUBLIC;

GRANT USAGE ON SCHEMA public     TO perfil_gerente, perfil_recepcao, perfil_profissional, perfil_backup;
GRANT USAGE ON SCHEMA relatorios TO perfil_gerente, perfil_relatorios, perfil_backup;
GRANT USAGE ON SCHEMA agenda     TO perfil_profissional, perfil_backup;
GRANT USAGE ON SCHEMA auditoria  TO perfil_auditoria, perfil_backup;
GRANT USAGE ON SCHEMA seguranca  TO perfil_gerente, perfil_profissional, perfil_backup;

-- 5. Rotinas: ninguém executa por padrão; cada perfil só o que usa ------------
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public, auditoria, seguranca FROM PUBLIC;
-- Rotinas que o postgres criar daqui em diante também nascem sem EXECUTE para
-- PUBLIC (a gerência recebe pelo privilégio padrão da seção 6).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_horario_disponivel(integer, date, text, integer, integer)
  TO perfil_gerente, perfil_recepcao;
GRANT EXECUTE ON PROCEDURE public.sp_concluir_atendimento(integer, character varying, numeric, integer)
  TO perfil_gerente, perfil_recepcao;
GRANT EXECUTE ON FUNCTION public.fn_total_gasto_cliente(integer)                  TO perfil_gerente;
GRANT EXECUTE ON FUNCTION public.fn_comissao_profissional(integer, date, date)    TO perfil_gerente;
GRANT EXECUTE ON PROCEDURE public.sp_repor_estoque(integer, integer, integer)     TO perfil_gerente;
GRANT EXECUTE ON PROCEDURE public.sp_cancelar_agendamentos_expirados(date, integer) TO perfil_gerente;
GRANT EXECUTE ON FUNCTION seguranca.id_profissional_atual()                       TO perfil_profissional;
-- Os 3 gatilhos e as funções de auditoria ficam sem EXECUTE para todos os
-- perfis: gatilho dispara sozinho, e ninguém deve chamá-los diretamente.

-- 6. perfil_gerente: dados de negócio completos, sem DDL nem TRUNCATE ---------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO perfil_gerente;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO perfil_gerente;
GRANT SELECT ON ALL TABLES IN SCHEMA relatorios TO perfil_gerente;
-- A gerência decide qual usuário do banco representa cada profissional.
GRANT SELECT, INSERT, UPDATE, DELETE ON seguranca.usuario_profissional TO perfil_gerente;
-- Tabelas, sequências e rotinas criadas depois no public já nascem acessíveis
-- à gerência.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO perfil_gerente;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO perfil_gerente;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO perfil_gerente;

-- 7. perfil_recepcao: atendimento no balcão -----------------------------------
-- Clientes: cadastra e corrige; não exclui (pedido de exclusão de dados, LGPD
-- art. 18, é tratado pela gerência).
GRANT SELECT, INSERT, UPDATE ON public.cliente TO perfil_recepcao;
-- Profissionais: só o necessário para marcar horário. Comissão e data de
-- admissão (dados de remuneração e de RH) ficam de fora.
GRANT SELECT (id_profissional, nome, especialidade, telefone) ON public.profissional TO perfil_recepcao;
-- Catálogos: só leitura. Preço é decisão da gerência.
GRANT SELECT ON public.servico, public.produto TO perfil_recepcao;
-- Agendamentos: marca, remarca e cancela. A coluna valor fica de fora: o
-- gatilho da APD1 copia o preço do serviço, e a recepção não digita valor.
GRANT SELECT ON public.agendamento TO perfil_recepcao;
GRANT INSERT (id_cliente, id_profissional, id_servico, data_agendamento, hora, status),
      UPDATE (id_cliente, id_profissional, id_servico, data_agendamento, hora, status)
  ON public.agendamento TO perfil_recepcao;
-- Pagamentos: registra o pagamento de atendimento concluído (pelo profissional
-- ou pelo sp_concluir_atendimento). A coluna valor_pago fica de fora: o
-- gatilho da APD1 calcula valor do atendimento - desconto. Não altera nem
-- exclui pagamento.
GRANT SELECT ON public.pagamento TO perfil_recepcao;
GRANT INSERT (id_agendamento, forma_pagamento, desconto, parcelas)
  ON public.pagamento TO perfil_recepcao;
-- Vendas: registra; não altera nem estorna (isso é da gerência). O valor
-- unitário vem do preço do produto, pelo gatilho da APD1.
GRANT SELECT ON public.venda_produto TO perfil_recepcao;
GRANT INSERT (id_cliente, id_produto, id_profissional, quantidade, forma_pagamento)
  ON public.venda_produto TO perfil_recepcao;
-- Sequências das quatro tabelas em que a recepção inclui linhas.
DO $$
DECLARE
  v_seq text;
BEGIN
  FOREACH v_seq IN ARRAY ARRAY[
    pg_get_serial_sequence('public.cliente', 'id_cliente'),
    pg_get_serial_sequence('public.agendamento', 'id_agendamento'),
    pg_get_serial_sequence('public.pagamento', 'id_pagamento'),
    pg_get_serial_sequence('public.venda_produto', 'id_venda')]
  LOOP
    EXECUTE format('GRANT USAGE ON SEQUENCE %s TO perfil_recepcao', v_seq);
  END LOOP;
END $$;

-- 8. perfil_profissional: a própria agenda e o catálogo ativo -----------------
-- Vê os agendamentos sem a coluna valor e só pode mudar a coluna status; o RLS
-- (script 06) limita isso às linhas dele e à passagem 'agendado' -> 'concluido'.
GRANT SELECT ON public.servico, public.produto TO perfil_profissional;
GRANT SELECT (id_agendamento, id_cliente, id_profissional, id_servico, data_agendamento, hora, status)
  ON public.agendamento TO perfil_profissional;
GRANT UPDATE (status) ON public.agendamento TO perfil_profissional;
GRANT SELECT ON agenda.vw_minha_agenda TO perfil_profissional;
GRANT SELECT ON seguranca.usuario_profissional TO perfil_profissional;

-- 9. perfil_relatorios: só as views agregadas ---------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA relatorios TO perfil_relatorios;

-- 10. perfil_auditoria: só a trilha e o inventário ----------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA auditoria TO perfil_auditoria;

-- 11. perfil_backup: leitura de tudo, escrita em nada -------------------------
GRANT SELECT ON ALL TABLES    IN SCHEMA public, auditoria, seguranca TO perfil_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public, auditoria TO perfil_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT ON TABLES TO perfil_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT ON SEQUENCES TO perfil_backup;

RESET lock_timeout;

-- 12. Evidência: matriz de privilégios (uma linha por tabela ou view) ---------
WITH objetos AS (
  SELECT format('%I.%I', schemaname, tablename) AS objeto,
         format('%I.%I', schemaname, tablename)::regclass AS rel
    FROM pg_tables WHERE schemaname IN ('public', 'auditoria', 'seguranca')
  UNION ALL
  SELECT format('%I.%I', schemaname, viewname),
         format('%I.%I', schemaname, viewname)::regclass
    FROM pg_views WHERE schemaname IN ('relatorios', 'agenda', 'auditoria')
), matriz AS (
  SELECT o.objeto, p.papel,
         coalesce(nullif(concat_ws('; ',
           -- privilégio na tabela inteira
           nullif(concat_ws(', ',
             CASE WHEN has_table_privilege(p.papel, o.rel, 'SELECT')   THEN 'SELECT' END,
             CASE WHEN has_table_privilege(p.papel, o.rel, 'INSERT')   THEN 'INSERT' END,
             CASE WHEN has_table_privilege(p.papel, o.rel, 'UPDATE')   THEN 'UPDATE' END,
             CASE WHEN has_table_privilege(p.papel, o.rel, 'DELETE')   THEN 'DELETE' END,
             CASE WHEN has_table_privilege(p.papel, o.rel, 'TRUNCATE') THEN 'TRUNCATE' END), ''),
           -- privilégio só em algumas colunas
           (SELECT string_agg(c.priv || '(' || c.colunas || ')', '; ')
              FROM (SELECT x.priv, string_agg(a.attname, ', ' ORDER BY a.attnum) AS colunas
                      FROM unnest(ARRAY['SELECT', 'INSERT', 'UPDATE']) AS x(priv)
                      JOIN pg_attribute a ON a.attrelid = o.rel AND a.attnum > 0 AND NOT a.attisdropped
                     WHERE NOT has_table_privilege(p.papel, o.rel, x.priv)
                       AND has_column_privilege(p.papel, o.rel, a.attnum, x.priv)
                     GROUP BY x.priv) AS c)
         ), ''), '-') AS privilegios
    FROM objetos o
   CROSS JOIN (VALUES ('perfil_gerente'), ('perfil_recepcao'), ('perfil_profissional'),
                      ('perfil_relatorios'), ('perfil_auditoria'), ('perfil_backup')) AS p(papel)
)
SELECT objeto,
       max(privilegios) FILTER (WHERE papel = 'perfil_gerente')      AS gerente,
       max(privilegios) FILTER (WHERE papel = 'perfil_recepcao')     AS recepcao,
       max(privilegios) FILTER (WHERE papel = 'perfil_profissional') AS profissional,
       max(privilegios) FILTER (WHERE papel = 'perfil_relatorios')   AS relatorios,
       max(privilegios) FILTER (WHERE papel = 'perfil_auditoria')    AS auditoria,
       max(privilegios) FILTER (WHERE papel = 'perfil_backup')       AS backup
  FROM matriz
 GROUP BY objeto
 ORDER BY objeto;
