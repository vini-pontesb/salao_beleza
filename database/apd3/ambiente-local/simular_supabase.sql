-- =============================================================================
-- simular_supabase.sql
-- Reproduz, num PostgreSQL local, as roles e os privilégios padrão que o
-- Supabase cria em todo projeto. Serve para testar os scripts da APD3 longe do
-- banco real do salão, com o mesmo ponto de partida.
--
-- Rodar como SUPERUSUÁRIO, num cluster novo e vazio, ANTES de estrutura_apd1.sql
-- (os privilégios padrão só valem para tabelas criadas depois):
--
--   psql "$URL_SUPERUSUARIO" -v ON_ERROR_STOP=1 -f simular_supabase.sql
--
-- O que é reproduzido (roles descritas em
-- https://supabase.com/docs/guides/database/postgres/roles):
--   * postgres      dono do banco; NÃO é superusuário no Supabase
--   * anon          role da API automática (PostgREST) sem login de usuário
--   * authenticated role da API automática com login do Supabase Auth
--   * service_role  role da chave secreta da API; ignora RLS (BYPASSRLS)
--   * authenticator role com que o PostgREST conecta e troca de papel
--   * privilégios padrão: toda tabela que o postgres cria no schema public
--     nasce com ALL concedido a anon, authenticated e service_role
--
-- Nenhuma senha aqui: o banco local usa autenticação definida no pg_hba.conf
-- da máquina de teste (ver README desta pasta).
-- =============================================================================

CREATE ROLE postgres LOGIN CREATEROLE CREATEDB REPLICATION BYPASSRLS;
CREATE ROLE anon NOLOGIN NOINHERIT;
CREATE ROLE authenticated NOLOGIN NOINHERIT;
CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
CREATE ROLE authenticator LOGIN NOINHERIT;

GRANT anon, authenticated, service_role TO authenticator;
-- No Supabase o postgres é membro das roles da API; é o que permite ao editor
-- SQL do painel "rodar como anon/authenticated".
GRANT anon, authenticated, service_role TO postgres;

ALTER ROLE anon SET statement_timeout = '3s';
ALTER ROLE authenticated SET statement_timeout = '8s';

CREATE DATABASE salao OWNER postgres;

\connect salao

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
