-- =============================================================================
-- APD3 · Script 99 · Reversão (plano de volta)
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Desfaz os scripts 01 a 07, na ordem inversa, e devolve a base ao estado da
-- APD1. Use só se algo der errado depois da aplicação.
--
-- O que NÃO é desfeito, de propósito:
--   * a revogação dos privilégios das roles anon, authenticated e service_role
--     (script 05). Devolver esses privilégios reabriria os dados dos clientes
--     pela chave pública do Supabase. Se for mesmo necessário, os comandos
--     estão comentados no fim deste arquivo;
--   * o RLS das 7 tabelas, que já estava ligado na APD1 e continua ligado.
--
-- Atenção: este script apaga o schema auditoria inteiro, com a trilha. Se ela
-- importar, exporte antes (SQL Editor: SELECT * FROM
-- auditoria.registro_alteracao e depois Export > CSV).
--
-- Idempotente. Rodar como postgres.
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

-- 06. Políticas de linha (o RLS continua ligado, como na APD1) ----------------
DO $$
DECLARE
  p record;
BEGIN
  FOR p IN
    SELECT pol.polname, pol.polrelid::regclass AS tabela
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    WHERE c.relnamespace IN ('public'::regnamespace)
      AND pol.polname IN ('pol_gerente_acesso_total', 'pol_backup_leitura_total',
                          'pol_recepcao_le_clientes', 'pol_recepcao_cadastra_clientes', 'pol_recepcao_corrige_clientes',
                          'pol_recepcao_le_profissionais', 'pol_recepcao_le_servicos', 'pol_recepcao_le_produtos',
                          'pol_recepcao_le_agendamentos', 'pol_recepcao_marca_agendamentos', 'pol_recepcao_remarca_cancela',
                          'pol_recepcao_le_pagamentos', 'pol_recepcao_registra_pagamentos',
                          'pol_recepcao_le_vendas', 'pol_recepcao_registra_vendas',
                          'pol_profissional_propria_agenda', 'pol_profissional_conclui_propria',
                          'pol_profissional_servicos_ativos',
                          'pol_profissional_produtos_ativos')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %s', p.polname, p.tabela);
  END LOOP;
END $$;

-- 07 e 05. Rotinas da APD1 de volta ao original -----------------------------
ALTER FUNCTION public.fn_trg_agendamento_regras() SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.fn_trg_pagamento_valida() SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.fn_trg_venda_estoque() SECURITY INVOKER RESET search_path;
ALTER PROCEDURE public.sp_concluir_atendimento(integer, character varying, numeric, integer) SECURITY INVOKER RESET search_path;
ALTER FUNCTION public.fn_horario_disponivel(integer, date, text, integer, integer) RESET search_path;
ALTER FUNCTION public.fn_total_gasto_cliente(integer) RESET search_path;
ALTER FUNCTION public.fn_comissao_profissional(integer, date, date) RESET search_path;
ALTER PROCEDURE public.sp_repor_estoque(integer, integer, integer) RESET search_path;
ALTER PROCEDURE public.sp_cancelar_agendamentos_expirados(date, integer) RESET search_path;
-- Na APD1 qualquer usuário (PUBLIC) executava as rotinas (padrão do PostgreSQL).
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- 05. Privilégios dos perfis --------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'perfil_gerente') THEN
    ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
      REVOKE ALL ON TABLES FROM perfil_gerente, perfil_backup;
    ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
      REVOKE ALL ON SEQUENCES FROM perfil_gerente, perfil_backup;
    ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
      REVOKE ALL ON FUNCTIONS FROM perfil_gerente;
    REVOKE ALL ON ALL TABLES IN SCHEMA public
      FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA public
      FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;
    REVOKE ALL ON ALL ROUTINES IN SCHEMA public
      FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;
    REVOKE ALL ON SCHEMA public
      FROM perfil_gerente, perfil_recepcao, perfil_profissional, perfil_relatorios, perfil_auditoria, perfil_backup;
  END IF;
END $$;

-- 04. Views ---------------------------------------------------------------------
DROP SCHEMA IF EXISTS relatorios CASCADE;
DROP SCHEMA IF EXISTS agenda CASCADE;

-- 03. Auditoria -------------------------------------------------------------------
DO $$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT tg.tgname, tg.tgrelid::regclass AS tabela
    FROM pg_trigger tg
    JOIN pg_class c ON c.oid = tg.tgrelid
    WHERE NOT tg.tgisinternal
      AND c.relnamespace = 'public'::regnamespace
      AND tg.tgname IN ('trg_auditoria', 'trg_auditoria_truncate')
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', t.tgname, t.tabela);
  END LOOP;
END $$;

DROP SCHEMA IF EXISTS auditoria CASCADE;

-- 02. Restrições complementares ---------------------------------------------------
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT con.conname, con.conrelid::regclass AS tabela
    FROM pg_constraint con
    WHERE con.connamespace = 'public'::regnamespace
      AND con.conname IN ('ck_cliente_nome_preenchido', 'ck_profissional_nome_preenchido', 'ck_servico_nome_preenchido',
                          'ck_produto_nome_preenchido', 'ck_cliente_telefone_formato', 'ck_profissional_telefone_formato',
                          'ck_produto_codigo_barras', 'ck_agendamento_concluido_com_valor')
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', c.tabela, c.conname);
  END LOOP;
END $$;

-- 01. Vínculo usuário -> profissional, usuários e perfis ----------------------
DROP SCHEMA IF EXISTS seguranca CASCADE;

-- Os papéis só podem ser apagados quando não têm mais privilégio em nenhum
-- banco do servidor. No Supabase só existe o banco postgres, já limpo acima.
DROP ROLE IF EXISTS gerente_salao;
DROP ROLE IF EXISTS recepcao_salao;
DROP ROLE IF EXISTS profissional_salao;
DROP ROLE IF EXISTS analista_salao;
DROP ROLE IF EXISTS auditor_salao;
DROP ROLE IF EXISTS backup_salao;
DROP ROLE IF EXISTS perfil_gerente;
DROP ROLE IF EXISTS perfil_recepcao;
DROP ROLE IF EXISTS perfil_profissional;
DROP ROLE IF EXISTS perfil_relatorios;
DROP ROLE IF EXISTS perfil_auditoria;
DROP ROLE IF EXISTS perfil_backup;

RESET lock_timeout;

-- Só em último caso, para voltar ao padrão do Supabase (reabre os dados à API):
--   GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
--   GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
--   GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;
--   ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
--   ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
--   ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;

-- Evidência: o que sobrou da APD3 (deve vir vazio) ------------------------------
SELECT 'papel' AS tipo, rolname::text AS nome FROM pg_roles
 WHERE rolname LIKE 'perfil\_%' OR rolname LIKE '%\_salao'
UNION ALL
SELECT 'schema', nspname::text FROM pg_namespace WHERE nspname IN ('auditoria', 'relatorios', 'agenda', 'seguranca')
UNION ALL
SELECT 'restrição', conname::text FROM pg_constraint
 WHERE connamespace = 'public'::regnamespace
   AND conname IN ('ck_cliente_nome_preenchido', 'ck_profissional_nome_preenchido', 'ck_servico_nome_preenchido',
                   'ck_produto_nome_preenchido', 'ck_cliente_telefone_formato', 'ck_profissional_telefone_formato',
                   'ck_produto_codigo_barras', 'ck_agendamento_concluido_com_valor')
UNION ALL
SELECT 'política', polname::text FROM pg_policy WHERE polname LIKE 'pol\_%'
UNION ALL
SELECT 'rotina com search_path ou SECURITY DEFINER', p.oid::regprocedure::text FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND (p.prosecdef OR p.proconfig IS NOT NULL)
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e');
