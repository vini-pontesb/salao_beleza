-- =============================================================================
-- APD3 · Script 01 · Perfis (papéis de grupo) e usuários do banco
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Item (i) da APD3: criação dos usuários para controle e acesso à base.
--
-- O que faz
--   * Cria 6 PERFIS (roles NOLOGIN). Um perfil agrupa os privilégios de uma
--     função do salão; ninguém conecta com ele.
--   * Cria 6 USUÁRIOS (roles LOGIN). Cada um é membro de um único perfil e
--     herda os privilégios dele (INHERIT).
--   * Cria o schema seguranca com a tabela que liga um usuário do banco a um
--     profissional do salão. É ela que permite ao RLS (script 06) mostrar a
--     cada profissional só a própria agenda.
--   * Nenhuma senha é definida aqui. A conta nasce sem senha, o que torna o
--     login impossível, e o DBA define a senha fora do repositório, só quando
--     a conta for de fato usada (ver database/apd3/README.md).
--
-- Os privilégios de cada perfil são concedidos no script 05 e as políticas de
-- linha (RLS), no 06. Este script só cria as identidades.
--
-- Como rodar: SQL Editor do Supabase (como postgres) ou
--   psql "$URL" -1 -v ON_ERROR_STOP=1 -f 01_perfis_e_usuarios.sql
-- Idempotente: rodar de novo não duplica nada nem altera senha já definida.
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

-- 1. Perfis -------------------------------------------------------------------
DO $$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
      ('perfil_gerente',
       'APD3 | Perfil da gerência do salão: cadastra e corrige todos os dados de negócio, define preços e comissões e roda os procedimentos administrativos. Sem DDL, sem TRUNCATE.'),
      ('perfil_recepcao',
       'APD3 | Perfil da recepção: atende clientes, marca, remarca e cancela agendamentos, registra pagamentos e vendas (o valor vem sempre do cadastro). Não vê comissão, não exclui nada nem altera preços.'),
      ('perfil_profissional',
       'APD3 | Perfil dos profissionais: vê e conclui só a própria agenda (RLS) e consulta o catálogo ativo de serviços e produtos.'),
      ('perfil_relatorios',
       'APD3 | Perfil de relatórios gerenciais: lê só as views agregadas do schema relatorios. Nenhum dado pessoal.'),
      ('perfil_auditoria',
       'APD3 | Perfil de auditoria: lê a trilha de alterações e o inventário de privilégios. Nenhum acesso aos dados do negócio.'),
      ('perfil_backup',
       'APD3 | Perfil de cópia de segurança: leitura de todas as tabelas para o pg_dump, sem nenhuma escrita.')
    ) AS t(nome, descricao)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v.nome) THEN
      -- Sem SUPERUSER, CREATEDB, CREATEROLE, REPLICATION nem BYPASSRLS: são os
      -- padrões do CREATE ROLE e não são concedidos em lugar nenhum.
      EXECUTE format('CREATE ROLE %I NOLOGIN', v.nome);
    END IF;
    EXECUTE format('COMMENT ON ROLE %I IS %L', v.nome, v.descricao);
  END LOOP;
END $$;

-- 2. Usuários -----------------------------------------------------------------
DO $$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
      ('gerente_salao', 'perfil_gerente',
       'APD3 | Conta da gerência do salão.'),
      ('recepcao_salao', 'perfil_recepcao',
       'APD3 | Conta da recepção (sistema de agendamento usado no balcão).'),
      ('profissional_salao', 'perfil_profissional',
       'APD3 | Conta de um profissional; o vínculo com o cadastro fica em seguranca.usuario_profissional.'),
      ('analista_salao', 'perfil_relatorios',
       'APD3 | Conta de consultas e relatórios gerenciais (planilha ou ferramenta de BI).'),
      ('auditor_salao', 'perfil_auditoria',
       'APD3 | Conta de auditoria: revisão periódica da trilha de alterações e dos acessos.'),
      ('backup_salao', 'perfil_backup',
       'APD3 | Conta da rotina de cópia de segurança lógica (pg_dump).')
    ) AS t(nome, perfil, descricao)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v.nome) THEN
      EXECUTE format('CREATE ROLE %I LOGIN INHERIT PASSWORD NULL', v.nome);
    END IF;
    IF NOT pg_has_role(v.nome, v.perfil, 'MEMBER') THEN
      EXECUTE format('GRANT %I TO %I', v.perfil, v.nome);
    END IF;
    EXECUTE format('COMMENT ON ROLE %I IS %L', v.nome, v.descricao);
  END LOOP;
END $$;

-- Exemplo de conta pessoal (uma por pessoa, nunca compartilhada). Descomente,
-- troque o nome, escolha o perfil e, se for profissional, faça o vínculo:
--   CREATE ROLE ana_souza LOGIN INHERIT PASSWORD NULL VALID UNTIL '2027-03-31';
--   GRANT perfil_profissional TO ana_souza;
--   INSERT INTO seguranca.usuario_profissional (usuario, id_profissional) VALUES ('ana_souza', 7);

-- 3. Vínculo usuário do banco -> profissional do salão ------------------------
CREATE SCHEMA IF NOT EXISTS seguranca;
COMMENT ON SCHEMA seguranca IS
  'APD3 | Vínculo entre usuários do banco e profissionais do salão (base do RLS da agenda). Fora da API do Supabase.';

CREATE TABLE IF NOT EXISTS seguranca.usuario_profissional (
  usuario         name        PRIMARY KEY,
  id_profissional integer     NOT NULL UNIQUE
                  REFERENCES public.profissional (id_profissional) ON UPDATE CASCADE ON DELETE CASCADE,
  criado_em       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE seguranca.usuario_profissional IS
  'APD3 | Qual profissional do salão cada usuário do banco representa. Um usuário, um profissional.';

-- Devolve o profissional do usuário conectado (NULL se ele não for profissional).
-- SECURITY INVOKER: lê o vínculo com os privilégios de quem chama, e o RLS da
-- tabela (script 06) só mostra a cada profissional a própria linha.
CREATE OR REPLACE FUNCTION seguranca.id_profissional_atual()
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT id_profissional FROM seguranca.usuario_profissional WHERE usuario = current_user
$$;

COMMENT ON FUNCTION seguranca.id_profissional_atual() IS
  'APD3 | id_profissional do usuário conectado; usado pelo RLS da agenda e pela view agenda.vw_minha_agenda.';

-- A conta de exemplo representa o primeiro profissional cadastrado. Para
-- representar outro, basta trocar o id nesta tabela.
INSERT INTO seguranca.usuario_profissional (usuario, id_profissional)
SELECT 'profissional_salao', p.id_profissional
  FROM public.profissional p
 ORDER BY p.id_profissional
 LIMIT 1
ON CONFLICT DO NOTHING;

-- 4. Evidência: o que existe agora --------------------------------------------
SELECT r.rolname AS papel,
       CASE WHEN r.rolcanlogin THEN 'usuário (LOGIN)' ELSE 'perfil (NOLOGIN)' END AS tipo,
       coalesce((SELECT string_agg(g.rolname, ', ' ORDER BY g.rolname)
                   FROM pg_auth_members m
                   JOIN pg_roles g ON g.oid = m.roleid
                  WHERE m.member = r.oid), '-') AS membro_de,
       r.rolsuper AS superusuario,
       r.rolcreaterole AS cria_roles,
       r.rolcreatedb AS cria_bancos,
       r.rolbypassrls AS ignora_rls,
       coalesce((SELECT 'profissional ' || up.id_profissional
                   FROM seguranca.usuario_profissional up
                  WHERE up.usuario = r.rolname), '-') AS vinculo,
       shobj_description(r.oid, 'pg_authid') AS descricao
FROM pg_roles r
WHERE r.rolname IN ('perfil_gerente', 'perfil_recepcao', 'perfil_profissional',
                    'perfil_relatorios', 'perfil_auditoria', 'perfil_backup',
                    'gerente_salao', 'recepcao_salao', 'profissional_salao',
                    'analista_salao', 'auditor_salao', 'backup_salao')
ORDER BY r.rolcanlogin, r.rolname;
