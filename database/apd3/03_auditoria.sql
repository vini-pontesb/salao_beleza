-- =============================================================================
-- APD3 · Script 03 · Trilha de auditoria
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- O que faz
--   * Cria o schema auditoria, fora do public e portanto fora da API
--     automática do Supabase.
--   * Registra toda inclusão, alteração e exclusão nas 7 tabelas da base
--     (clientes, profissionais, serviços, agendamentos, pagamentos, produtos e
--     vendas) e no vínculo usuário -> profissional do schema seguranca. É o
--     que permite responder "quem deu esse desconto?", "quem cancelou esse
--     horário?" ou "quem mudou o preço do serviço?".
--   * Guarda QUEM (usuário da sessão e papel em vigor), QUANDO, DE ONDE
--     (aplicação e IP), O QUÊ (tabela, operação, id e NOMES das colunas
--     alteradas). Nunca guarda os VALORES: a trilha não pode virar uma segunda
--     cópia de telefone, e-mail ou data de nascimento de cliente (LGPD, art.
--     6º, III, necessidade).
--   * A trilha é somente inclusão: UPDATE, DELETE e TRUNCATE são recusados,
--     inclusive para o dono. Só a função de expurgo apaga, e só registros com
--     mais de 12 meses (política de retenção).
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

CREATE SCHEMA IF NOT EXISTS auditoria;
COMMENT ON SCHEMA auditoria IS 'APD3 | Trilha de auditoria das tabelas do salão e inventário de privilégios.';

CREATE TABLE IF NOT EXISTS auditoria.registro_alteracao (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  momento           timestamptz NOT NULL DEFAULT clock_timestamp(),
  usuario_sessao    text        NOT NULL,
  papel_efetivo     text        NOT NULL,
  aplicacao         text,
  endereco_cliente  inet,
  tabela            text        NOT NULL,
  operacao          text        NOT NULL,
  registro_id       bigint,
  colunas_alteradas text[],
  transacao         bigint      NOT NULL DEFAULT txid_current(),
  CONSTRAINT ck_registro_operacao_valida CHECK (operacao IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'))
);

COMMENT ON TABLE auditoria.registro_alteracao IS
  'APD3 | Quem alterou o quê, quando e de onde, nas tabelas do salão. Guarda nomes de colunas, nunca valores.';
COMMENT ON COLUMN auditoria.registro_alteracao.usuario_sessao IS 'Usuário que autenticou a conexão (session_user).';
COMMENT ON COLUMN auditoria.registro_alteracao.papel_efetivo IS 'Papel em vigor no momento da operação (difere do usuário da sessão quando há SET ROLE).';
COMMENT ON COLUMN auditoria.registro_alteracao.registro_id IS 'Chave primária da linha afetada (id_cliente, id_agendamento etc.).';
COMMENT ON COLUMN auditoria.registro_alteracao.colunas_alteradas IS 'Só em UPDATE: nomes das colunas cujo valor mudou. Os valores não são guardados.';

CREATE INDEX IF NOT EXISTS registro_alteracao_tabela_momento_idx
  ON auditoria.registro_alteracao (tabela, momento DESC);

-- 1. Função que grava a trilha ------------------------------------------------
-- SECURITY DEFINER: grava com os privilégios do dono, porque nenhum perfil tem
-- INSERT na trilha. Sem isso, quem pode gravar na trilha poderia forjá-la.
-- O nome da coluna de chave primária chega como argumento do gatilho
-- (TG_ARGV[0]), porque cada tabela do salão tem a sua (id_cliente, id_venda...).
CREATE OR REPLACE FUNCTION auditoria.registrar_alteracao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  -- Dentro de uma função SECURITY DEFINER o current_user é o dono da função;
  -- o parâmetro "role" ainda guarda o papel assumido pela sessão (SET ROLE).
  v_papel   text := coalesce(nullif(current_setting('role', true), 'none'), session_user);
  v_colunas text[];
  v_id      bigint;
BEGIN
  IF TG_LEVEL = 'STATEMENT' THEN
    INSERT INTO auditoria.registro_alteracao
      (usuario_sessao, papel_efetivo, aplicacao, endereco_cliente, tabela, operacao)
    VALUES
      (session_user, v_papel, current_setting('application_name', true), inet_client_addr(),
       TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP);
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    SELECT array_agg(n.key ORDER BY n.key)
      INTO v_colunas
      FROM jsonb_each(to_jsonb(NEW)) AS n(key, value)
     WHERE n.value IS DISTINCT FROM (to_jsonb(OLD) -> n.key);
    IF v_colunas IS NULL THEN
      RETURN NULL;  -- UPDATE que não mudou nada não entra na trilha
    END IF;
  END IF;

  v_id := (CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END ->> TG_ARGV[0])::bigint;

  INSERT INTO auditoria.registro_alteracao
    (usuario_sessao, papel_efetivo, aplicacao, endereco_cliente, tabela, operacao, registro_id, colunas_alteradas)
  VALUES
    (session_user, v_papel, current_setting('application_name', true), inet_client_addr(),
     TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP, v_id, v_colunas);
  RETURN NULL;
END
$$;

COMMENT ON FUNCTION auditoria.registrar_alteracao() IS
  'APD3 | Gatilho de auditoria: grava quem/quando/onde/o quê, sem copiar valores.';

-- 2. A trilha só aceita inclusão ----------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.impedir_alteracao_da_trilha()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE'
     AND current_setting('auditoria.expurgo_autorizado', true) = 'sim'
     AND OLD.momento < now() - interval '12 months' THEN
    RETURN OLD;  -- expurgo por retenção, feito só pela função de expurgo
  END IF;
  RAISE EXCEPTION USING
    ERRCODE = 'insufficient_privilege',
    MESSAGE = 'A trilha de auditoria só aceita inclusão: registros não podem ser alterados nem apagados.',
    HINT    = 'O expurgo por retenção (registros com mais de 12 meses) é feito por auditoria.expurgar_registros_antigos().';
END
$$;

CREATE OR REPLACE TRIGGER trg_trilha_somente_inclusao
  BEFORE UPDATE OR DELETE ON auditoria.registro_alteracao
  FOR EACH ROW EXECUTE FUNCTION auditoria.impedir_alteracao_da_trilha();

CREATE OR REPLACE TRIGGER trg_trilha_sem_truncate
  BEFORE TRUNCATE ON auditoria.registro_alteracao
  FOR EACH STATEMENT EXECUTE FUNCTION auditoria.impedir_alteracao_da_trilha();

-- 3. Expurgo por retenção (só quem pode apagar da tabela, ou seja, o dono) ----
CREATE OR REPLACE FUNCTION auditoria.expurgar_registros_antigos(p_meses integer DEFAULT 12)
RETURNS bigint
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_qtd bigint;
BEGIN
  IF p_meses < 12 THEN
    RAISE EXCEPTION 'A política de retenção guarda a trilha por no mínimo 12 meses.';
  END IF;
  PERFORM set_config('auditoria.expurgo_autorizado', 'sim', true);
  DELETE FROM auditoria.registro_alteracao
   WHERE momento < now() - make_interval(months => p_meses);
  GET DIAGNOSTICS v_qtd = ROW_COUNT;
  PERFORM set_config('auditoria.expurgo_autorizado', 'nao', true);
  RETURN v_qtd;
END
$$;

COMMENT ON FUNCTION auditoria.expurgar_registros_antigos(integer) IS
  'APD3 | Política de retenção: apaga registros da trilha com mais de p_meses (mínimo 12). Uso exclusivo do DBA.';

REVOKE ALL ON FUNCTION auditoria.registrar_alteracao() FROM PUBLIC;
REVOKE ALL ON FUNCTION auditoria.impedir_alteracao_da_trilha() FROM PUBLIC;
REVOKE ALL ON FUNCTION auditoria.expurgar_registros_antigos(integer) FROM PUBLIC;

-- 4. Tabelas auditadas: as 7 da base ------------------------------------------
DO $$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
      ('cliente',       'id_cliente'),       -- dados pessoais (LGPD)
      ('profissional',  'id_profissional'),  -- comissão e dados de funcionário
      ('servico',       'id_servico'),       -- preços
      ('agendamento',   'id_agendamento'),   -- agenda, cancelamentos, valores
      ('pagamento',     'id_pagamento'),     -- dinheiro recebido e descontos
      ('produto',       'id_produto'),       -- preços e estoque
      ('venda_produto', 'id_venda')          -- vendas e estornos
    ) AS t(tabela, chave)
  LOOP
    IF to_regclass('public.' || v.tabela) IS NULL THEN
      RAISE NOTICE 'Tabela public.% não existe; auditoria não instalada nela.', v.tabela;
      CONTINUE;
    END IF;
    EXECUTE format(
      'CREATE OR REPLACE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION auditoria.registrar_alteracao(%L)', v.tabela, v.chave);
    EXECUTE format(
      'CREATE OR REPLACE TRIGGER trg_auditoria_truncate AFTER TRUNCATE ON public.%I '
      'FOR EACH STATEMENT EXECUTE FUNCTION auditoria.registrar_alteracao(%L)', v.tabela, v.chave);
  END LOOP;
END $$;

-- O vínculo usuário -> profissional (script 01) decide qual agenda cada
-- profissional enxerga; mudança nele também entra na trilha.
CREATE OR REPLACE TRIGGER trg_auditoria
  AFTER INSERT OR UPDATE OR DELETE ON seguranca.usuario_profissional
  FOR EACH ROW EXECUTE FUNCTION auditoria.registrar_alteracao('id_profissional');
CREATE OR REPLACE TRIGGER trg_auditoria_truncate
  AFTER TRUNCATE ON seguranca.usuario_profissional
  FOR EACH STATEMENT EXECUTE FUNCTION auditoria.registrar_alteracao('id_profissional');

-- 5. Inventário de privilégios para a revisão periódica de acessos ------------
CREATE OR REPLACE VIEW auditoria.vw_privilegios AS
SELECT n.nspname AS schema,
       c.relname AS objeto,
       CASE c.relkind WHEN 'r' THEN 'tabela' WHEN 'p' THEN 'tabela'
                      WHEN 'v' THEN 'view' WHEN 'S' THEN 'sequência'
                      ELSE c.relkind::text END AS tipo,
       CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END AS papel,
       string_agg(a.privilege_type, ', ' ORDER BY a.privilege_type) AS privilegios
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(c.relacl) AS a
WHERE n.nspname IN ('public', 'relatorios', 'agenda', 'auditoria', 'seguranca')
  AND a.grantee <> c.relowner
GROUP BY n.nspname, c.relname, c.relkind, a.grantee
UNION ALL
SELECT n.nspname,
       c.relname || '.' || at.attname,
       'coluna',
       CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END,
       string_agg(a.privilege_type, ', ' ORDER BY a.privilege_type)
FROM pg_attribute at
JOIN pg_class c ON c.oid = at.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(at.attacl) AS a
WHERE n.nspname IN ('public', 'relatorios', 'agenda', 'auditoria', 'seguranca')
  AND at.attacl IS NOT NULL
  AND NOT at.attisdropped
GROUP BY n.nspname, c.relname, at.attname, a.grantee
UNION ALL
-- Funções e procedimentos: sem ACL explícita, o PostgreSQL deixa PUBLIC executar.
SELECT n.nspname,
       p.oid::regprocedure::text,
       CASE p.prokind WHEN 'p' THEN 'procedimento' ELSE 'função' END,
       CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END,
       string_agg(a.privilege_type, ', ' ORDER BY a.privilege_type)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
WHERE n.nspname IN ('public', 'relatorios', 'agenda', 'auditoria', 'seguranca')
  AND a.grantee <> p.proowner
GROUP BY n.nspname, p.oid, p.prokind, a.grantee;

COMMENT ON VIEW auditoria.vw_privilegios IS
  'APD3 | Quem tem qual privilégio em cada tabela, view, sequência, coluna e rotina. Base da revisão semestral de acessos.';

CREATE OR REPLACE VIEW auditoria.vw_usuarios_e_perfis AS
SELECT r.rolname AS papel,
       CASE WHEN r.rolcanlogin THEN 'usuário' ELSE 'perfil' END AS tipo,
       coalesce((SELECT string_agg(g.rolname, ', ' ORDER BY g.rolname)
                   FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid
                  WHERE m.member = r.oid), '-') AS membro_de,
       r.rolconnlimit AS limite_conexoes,
       r.rolvaliduntil AS valido_ate,
       (SELECT string_agg(cfg, '; ')
          FROM pg_db_role_setting s, unnest(s.setconfig) AS cfg
         WHERE s.setrole = r.oid) AS configuracoes
FROM pg_roles r
WHERE r.rolname LIKE 'perfil\_%' OR r.rolname LIKE '%\_salao';

COMMENT ON VIEW auditoria.vw_usuarios_e_perfis IS
  'APD3 | Usuários e perfis do projeto, com limites, validade e parâmetros de sessão.';

RESET lock_timeout;

-- 6. Evidência: gatilhos de auditoria instalados -------------------------------
SELECT tg.tgrelid::regclass::text AS tabela,
       tg.tgname AS gatilho,
       pg_get_triggerdef(tg.oid) AS definicao
FROM pg_trigger tg
WHERE NOT tg.tgisinternal
  AND tg.tgname IN ('trg_auditoria', 'trg_auditoria_truncate', 'trg_trilha_somente_inclusao', 'trg_trilha_sem_truncate')
ORDER BY 1, 2;
