-- =============================================================================
-- APD3 · Script 06 · Segurança em nível de linha (Row Level Security)
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- O GRANT do script 05 diz QUAIS tabelas e colunas cada perfil acessa; o RLS
-- diz QUAIS LINHAS. Na APD1 as 7 tabelas já estavam com RLS ligado e nenhuma
-- política, o que no PostgreSQL significa "ninguém além do dono vê linha
-- nenhuma". Este script cria as políticas de cada perfil:
--
--   gerente       todas as linhas, em todas as operações
--   recepção      lê tudo o que atende; inclui agendamento só como 'agendado';
--                 altera só agendamento ainda 'agendado', e só para remarcar
--                 ou cancelar (concluir no balcão é pelo sp_concluir_atendimento,
--                 que registra o pagamento junto); registra pagamentos e vendas
--   profissional  vê só os PRÓPRIOS agendamentos e conclui só os próprios
--                 (de 'agendado' para 'concluido'); só serviços e produtos
--                 ativos; só a própria linha do vínculo usuário -> profissional
--   backup        lê todas as linhas (pg_dump --enable-row-security)
--   relatórios e auditoria: nenhuma política no public (não leem tabelas;
--                 usam as views dos schemas relatorios e auditoria)
--
-- O dono das tabelas (postgres) continua fora do RLS (sem FORCE): é ele que
-- aplica os scripts, e é com os privilégios dele que rodam as views e as
-- rotinas SECURITY DEFINER.
--
-- Idempotente. Rodar como postgres, depois dos scripts 01 a 05.
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

-- 1. RLS ligado em todas as tabelas e políticas comuns ------------------------
DO $$
DECLARE
  v_tabela text;
BEGIN
  FOREACH v_tabela IN ARRAY ARRAY[
    'public.cliente', 'public.profissional', 'public.servico', 'public.agendamento',
    'public.pagamento', 'public.produto', 'public.venda_produto', 'seguranca.usuario_profissional']
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', v_tabela);

    EXECUTE format('DROP POLICY IF EXISTS pol_gerente_acesso_total ON %s', v_tabela);
    EXECUTE format('CREATE POLICY pol_gerente_acesso_total ON %s FOR ALL TO perfil_gerente '
                   'USING (true) WITH CHECK (true)', v_tabela);

    EXECUTE format('DROP POLICY IF EXISTS pol_backup_leitura_total ON %s', v_tabela);
    EXECUTE format('CREATE POLICY pol_backup_leitura_total ON %s FOR SELECT TO perfil_backup '
                   'USING (true)', v_tabela);
  END LOOP;
END $$;

-- 2. Recepção -------------------------------------------------------------------
DROP POLICY IF EXISTS pol_recepcao_le_clientes ON public.cliente;
CREATE POLICY pol_recepcao_le_clientes ON public.cliente
  FOR SELECT TO perfil_recepcao USING (true);
DROP POLICY IF EXISTS pol_recepcao_cadastra_clientes ON public.cliente;
CREATE POLICY pol_recepcao_cadastra_clientes ON public.cliente
  FOR INSERT TO perfil_recepcao WITH CHECK (true);
DROP POLICY IF EXISTS pol_recepcao_corrige_clientes ON public.cliente;
CREATE POLICY pol_recepcao_corrige_clientes ON public.cliente
  FOR UPDATE TO perfil_recepcao USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pol_recepcao_le_profissionais ON public.profissional;
CREATE POLICY pol_recepcao_le_profissionais ON public.profissional
  FOR SELECT TO perfil_recepcao USING (true);

DROP POLICY IF EXISTS pol_recepcao_le_servicos ON public.servico;
CREATE POLICY pol_recepcao_le_servicos ON public.servico
  FOR SELECT TO perfil_recepcao USING (true);

DROP POLICY IF EXISTS pol_recepcao_le_produtos ON public.produto;
CREATE POLICY pol_recepcao_le_produtos ON public.produto
  FOR SELECT TO perfil_recepcao USING (true);

DROP POLICY IF EXISTS pol_recepcao_le_agendamentos ON public.agendamento;
CREATE POLICY pol_recepcao_le_agendamentos ON public.agendamento
  FOR SELECT TO perfil_recepcao USING (true);
-- Agendamento novo nasce 'agendado'; ninguém da recepção cria um já concluído.
DROP POLICY IF EXISTS pol_recepcao_marca_agendamentos ON public.agendamento;
CREATE POLICY pol_recepcao_marca_agendamentos ON public.agendamento
  FOR INSERT TO perfil_recepcao WITH CHECK (status = 'agendado');
-- Só mexe no que ainda está 'agendado', e o resultado só pode ser 'agendado'
-- (remarcação) ou 'cancelado'. Concluído e cancelado ficam como estão.
DROP POLICY IF EXISTS pol_recepcao_remarca_cancela ON public.agendamento;
CREATE POLICY pol_recepcao_remarca_cancela ON public.agendamento
  FOR UPDATE TO perfil_recepcao
  USING (status = 'agendado')
  WITH CHECK (status IN ('agendado', 'cancelado'));

DROP POLICY IF EXISTS pol_recepcao_le_pagamentos ON public.pagamento;
CREATE POLICY pol_recepcao_le_pagamentos ON public.pagamento
  FOR SELECT TO perfil_recepcao USING (true);
-- O gatilho da APD1 só aceita pagamento de atendimento concluído e calcula o
-- valor; a UNIQUE de id_agendamento impede pagar duas vezes.
DROP POLICY IF EXISTS pol_recepcao_registra_pagamentos ON public.pagamento;
CREATE POLICY pol_recepcao_registra_pagamentos ON public.pagamento
  FOR INSERT TO perfil_recepcao WITH CHECK (true);

DROP POLICY IF EXISTS pol_recepcao_le_vendas ON public.venda_produto;
CREATE POLICY pol_recepcao_le_vendas ON public.venda_produto
  FOR SELECT TO perfil_recepcao USING (true);
DROP POLICY IF EXISTS pol_recepcao_registra_vendas ON public.venda_produto;
CREATE POLICY pol_recepcao_registra_vendas ON public.venda_produto
  FOR INSERT TO perfil_recepcao WITH CHECK (true);

-- 3. Profissional ---------------------------------------------------------------
-- (SELECT ...) faz a função rodar uma vez por consulta, não uma vez por linha.
DROP POLICY IF EXISTS pol_profissional_propria_agenda ON public.agendamento;
CREATE POLICY pol_profissional_propria_agenda ON public.agendamento
  FOR SELECT TO perfil_profissional
  USING (id_profissional = (SELECT seguranca.id_profissional_atual()));
-- Conclui só o que é dele e ainda está 'agendado'; o resultado só pode ser
-- 'concluido' (não cancela, não reabre, não passa o atendimento para outro).
DROP POLICY IF EXISTS pol_profissional_conclui_propria ON public.agendamento;
CREATE POLICY pol_profissional_conclui_propria ON public.agendamento
  FOR UPDATE TO perfil_profissional
  USING (id_profissional = (SELECT seguranca.id_profissional_atual()) AND status = 'agendado')
  WITH CHECK (id_profissional = (SELECT seguranca.id_profissional_atual()) AND status = 'concluido');

DROP POLICY IF EXISTS pol_profissional_servicos_ativos ON public.servico;
CREATE POLICY pol_profissional_servicos_ativos ON public.servico
  FOR SELECT TO perfil_profissional USING (ativo = 1);

DROP POLICY IF EXISTS pol_profissional_produtos_ativos ON public.produto;
CREATE POLICY pol_profissional_produtos_ativos ON public.produto
  FOR SELECT TO perfil_profissional USING (ativo);

DROP POLICY IF EXISTS pol_profissional_proprio_vinculo ON seguranca.usuario_profissional;
CREATE POLICY pol_profissional_proprio_vinculo ON seguranca.usuario_profissional
  FOR SELECT TO perfil_profissional USING (usuario = current_user);

RESET lock_timeout;

-- 4. Evidência: RLS e políticas por tabela --------------------------------------
SELECT format('%I.%I', n.nspname, c.relname) AS tabela,
       c.relrowsecurity AS rls_ligado,
       p.polname AS politica,
       CASE p.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT' WHEN 'w' THEN 'UPDATE'
                     WHEN 'd' THEN 'DELETE' ELSE 'ALL' END AS comando,
       (SELECT string_agg(r.rolname, ', ') FROM pg_roles r WHERE r.oid = ANY (p.polroles)) AS perfis,
       pg_get_expr(p.polqual, p.polrelid) AS linhas_visiveis,
       pg_get_expr(p.polwithcheck, p.polrelid) AS linhas_gravaveis
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_policy p ON p.polrelid = c.oid
WHERE n.nspname IN ('public', 'seguranca') AND c.relkind = 'r'
ORDER BY 1, 3;
