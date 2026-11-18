-- =============================================================================
-- APD3 · Script 07 · Políticas de administração das contas
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Configura, para cada usuário, limites que valem desde o login:
--   CONNECTION LIMIT                 quantas conexões simultâneas a conta abre
--   VALID UNTIL                      até quando a senha vale (contas de pessoas
--                                    expiram no fim do semestre e são revistas)
--   statement_timeout                tempo máximo de uma consulta
--   idle_in_transaction_session_timeout  derruba sessão parada no meio de uma
--                                    transação (ela segura travas de linha)
--   default_transaction_read_only    contas que só leem abrem sessão somente
--                                    leitura: mesmo que um privilégio sobre por
--                                    engano, a escrita é recusada
--   search_path                      onde a conta procura os objetos
--
-- As configurações valem a partir do PRÓXIMO login de cada conta.
-- Idempotente. Rodar como postgres, depois do script 01.
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

-- Gerência: trabalho do dia a dia, poucas conexões, validade semestral.
ALTER ROLE gerente_salao CONNECTION LIMIT 3 VALID UNTIL '2027-03-31 23:59:59-03';
ALTER ROLE gerente_salao SET search_path = public;
ALTER ROLE gerente_salao SET statement_timeout = '60s';
ALTER ROLE gerente_salao SET idle_in_transaction_session_timeout = '5min';

-- Recepção: várias estações no balcão; consultas curtas.
ALTER ROLE recepcao_salao CONNECTION LIMIT 5 VALID UNTIL '2027-03-31 23:59:59-03';
ALTER ROLE recepcao_salao SET search_path = public;
ALTER ROLE recepcao_salao SET statement_timeout = '30s';
ALTER ROLE recepcao_salao SET idle_in_transaction_session_timeout = '2min';

-- Profissional: consulta e conclui a própria agenda.
ALTER ROLE profissional_salao CONNECTION LIMIT 2 VALID UNTIL '2027-03-31 23:59:59-03';
ALTER ROLE profissional_salao SET search_path = agenda, public;
ALTER ROLE profissional_salao RESET default_transaction_read_only;
ALTER ROLE profissional_salao SET statement_timeout = '30s';
ALTER ROLE profissional_salao SET idle_in_transaction_session_timeout = '2min';

-- Relatórios: consultas mais pesadas, somente leitura.
ALTER ROLE analista_salao CONNECTION LIMIT 2 VALID UNTIL '2027-03-31 23:59:59-03';
ALTER ROLE analista_salao SET search_path = relatorios;
ALTER ROLE analista_salao SET default_transaction_read_only = on;
ALTER ROLE analista_salao SET statement_timeout = '60s';
ALTER ROLE analista_salao SET idle_in_transaction_session_timeout = '5min';

-- Auditoria: somente leitura.
ALTER ROLE auditor_salao CONNECTION LIMIT 2 VALID UNTIL '2027-03-31 23:59:59-03';
ALTER ROLE auditor_salao SET search_path = auditoria;
ALTER ROLE auditor_salao SET default_transaction_read_only = on;
ALTER ROLE auditor_salao SET statement_timeout = '60s';
ALTER ROLE auditor_salao SET idle_in_transaction_session_timeout = '5min';

-- Backup: conta de máquina (sem expiração), somente leitura e sem limite de
-- tempo por consulta, porque o pg_dump lê cada tabela inteira de uma vez.
ALTER ROLE backup_salao CONNECTION LIMIT 2 VALID UNTIL 'infinity';
ALTER ROLE backup_salao SET search_path = public;
ALTER ROLE backup_salao SET default_transaction_read_only = on;
ALTER ROLE backup_salao SET statement_timeout = 0;
ALTER ROLE backup_salao SET idle_in_transaction_session_timeout = '10min';

-- Evidência: limites e parâmetros de cada conta --------------------------------
SELECT r.rolname AS usuario,
       r.rolconnlimit AS limite_conexoes,
       CASE WHEN r.rolvaliduntil IS NULL OR r.rolvaliduntil = 'infinity' THEN 'sem expiração'
            ELSE to_char(r.rolvaliduntil AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') END AS senha_valida_ate,
       (SELECT string_agg(cfg, '; ' ORDER BY cfg)
          FROM pg_db_role_setting s, unnest(s.setconfig) AS cfg
         WHERE s.setrole = r.oid) AS parametros_de_sessao
FROM pg_roles r
WHERE r.rolname IN ('gerente_salao', 'recepcao_salao', 'profissional_salao',
                    'analista_salao', 'auditor_salao', 'backup_salao')
ORDER BY r.rolname;
