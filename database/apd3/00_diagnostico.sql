-- =============================================================================
-- APD3 · Script 00 · Diagnóstico de segurança e integridade (antes e depois)
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Item (iv) da APD3: evidência do estado do banco.
--
-- Rode DUAS vezes: antes dos scripts 01 a 07 (foto do "antes") e depois deles
-- (foto do "depois"). Salve as duas saídas na pasta evidencias/apd3/supabase/.
--
-- Não altera nada. As sondagens que assumem o papel anon (o mesmo que a API
-- automática do Supabase usa com a chave pública) rodam dentro de um bloco
-- que é desfeito no fim.
--
-- Saída: uma única tabela (secao, item, valor, situacao), pensada para o
-- SQL Editor do Supabase, que mostra só o resultado do último comando.
-- situacao: OK | RISCO | ATENÇÃO | PENDENTE | INFO
-- =============================================================================

CREATE TEMP TABLE IF NOT EXISTS apd3_diagnostico (
  ordem    serial,
  secao    text,
  item     text,
  valor    text,
  situacao text
);
TRUNCATE pg_temp.apd3_diagnostico RESTART IDENTITY;

-- Executa uma consulta como outro papel e devolve o resultado, sem deixar
-- rastro: tudo roda num subbloco que é desfeito no fim.
CREATE OR REPLACE FUNCTION pg_temp.apd3_sondar(p_papel text, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_fase      text := 'papel';
  v_valor     text;
  v_resultado text;
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_papel);
    v_fase := 'consulta';
    EXECUTE p_sql INTO v_valor;
    v_resultado := 'PERMITIDO: ' || coalesce(v_valor, 'sem retorno');
    RAISE EXCEPTION 'apd3:desfazer';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM <> 'apd3:desfazer' THEN
        v_resultado := 'ERRO: ' || SQLERRM;
      END IF;
    WHEN insufficient_privilege THEN
      v_resultado := CASE v_fase WHEN 'papel' THEN 'NÃO TESTADO: ' ELSE 'NEGADO: ' END || SQLERRM;
    WHEN OTHERS THEN
      v_resultado := 'ERRO: ' || SQLERRM;
  END;
  RETURN v_resultado;
END
$$;

DO $$
DECLARE
  v_total    int;
  v_n        int;
  v_txt      text;
  v_papel    text;
  r          record;
BEGIN
  -- Ambiente -----------------------------------------------------------------
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao) VALUES
    ('Ambiente', 'Servidor', split_part(version(), ',', 1), 'INFO'),
    ('Ambiente', 'Banco e usuário desta sessão', current_database() || ' / ' || session_user, 'INFO'),
    ('Ambiente', 'Momento do diagnóstico', to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI:SS') || ' (Brasília)', 'INFO'),
    ('Ambiente', 'Criptografia de senha (password_encryption)', current_setting('password_encryption'),
     CASE WHEN current_setting('password_encryption') = 'scram-sha-256' THEN 'OK' ELSE 'RISCO' END);

  SELECT count(*), string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_total, v_txt
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Ambiente', 'Tabelas no schema public', v_total || ' (' || coalesce(v_txt, '-') || ')', 'INFO');

  IF to_regclass('public.agendamento') IS NOT NULL AND to_regclass('public.venda_produto') IS NOT NULL THEN
    EXECUTE $q$SELECT format('cliente %s, profissional %s, servico %s, agendamento %s, pagamento %s, produto %s, venda_produto %s',
                    (SELECT count(*) FROM public.cliente), (SELECT count(*) FROM public.profissional),
                    (SELECT count(*) FROM public.servico), (SELECT count(*) FROM public.agendamento),
                    (SELECT count(*) FROM public.pagamento), (SELECT count(*) FROM public.produto),
                    (SELECT count(*) FROM public.venda_produto))$q$ INTO v_txt;
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('Ambiente', 'Linhas por tabela', v_txt, 'INFO');
  END IF;

  -- API automática do Supabase (anon, authenticated, service_role) -------------
  FOREACH v_papel IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_papel) THEN
      INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
      VALUES ('API do Supabase', 'Tabelas do public acessíveis por ' || v_papel, 'role não existe', 'INFO');
      CONTINUE;
    END IF;
    SELECT count(*) FILTER (WHERE has_table_privilege(v_papel, c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE'))
      INTO v_n
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('API do Supabase', 'Tabelas do public com algum privilégio para ' || v_papel,
            v_n || ' de ' || v_total, CASE WHEN v_n > 0 THEN 'RISCO' ELSE 'OK' END);
  END LOOP;

  SELECT count(*) INTO v_n
    FROM pg_default_acl d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) a
   WHERE d.defaclrole = 'postgres'::regrole
     AND a.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon', 'authenticated', 'service_role'));
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('API do Supabase', 'Privilégios padrão que abrem objetos NOVOS do public para a API',
          v_n::text, CASE WHEN v_n > 0 THEN 'RISCO' ELSE 'OK' END);

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    SELECT count(*) INTO v_n
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
       AND has_function_privilege('anon', p.oid, 'EXECUTE');
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('API do Supabase', 'Funções e procedimentos do public que a chave pública (anon) executa',
            v_n::text, CASE WHEN v_n > 0 THEN 'RISCO' ELSE 'OK' END);

    FOR r IN
      SELECT * FROM (VALUES
        ('cliente', 'nome, telefone, e-mail e nascimento dos clientes'),
        ('pagamento', 'valores recebidos e descontos'),
        ('profissional', 'comissão de cada profissional')
      ) AS t(tabela, conteudo)
    LOOP
      IF to_regclass('public.' || r.tabela) IS NULL THEN CONTINUE; END IF;
      v_txt := pg_temp.apd3_sondar('anon', format('SELECT count(*)::text || '' linha(s) visível(is)'' FROM public.%I', r.tabela));
      INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
      VALUES ('API do Supabase', 'Chave pública (anon) lê ' || r.tabela || ' (' || r.conteudo || ')', v_txt,
              CASE WHEN v_txt LIKE 'PERMITIDO: 0 %' THEN 'ATENÇÃO'   -- tem o privilégio; só o RLS segura
                   WHEN v_txt LIKE 'PERMITIDO%' THEN 'RISCO'
                   WHEN v_txt LIKE 'NEGADO%' THEN 'OK' ELSE 'INFO' END);
    END LOOP;
  END IF;

  -- Row Level Security ----------------------------------------------------------
  SELECT count(*) FILTER (WHERE NOT c.relrowsecurity),
         string_agg(c.relname, ', ' ORDER BY c.relname) FILTER (WHERE NOT c.relrowsecurity)
    INTO v_n, v_txt
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('RLS', 'Tabelas do public SEM Row Level Security',
          v_n || ' de ' || v_total || coalesce(' (' || v_txt || ')', ''),
          CASE WHEN v_n > 0 THEN 'RISCO' ELSE 'OK' END);

  SELECT count(*) INTO v_n
    FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public';
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('RLS', 'Políticas de linha no schema public (sem política, só o dono vê as linhas)', v_n::text,
          CASE WHEN v_n > 0 THEN 'OK' ELSE 'PENDENTE' END);

  -- Funções e procedimentos da APD1 ---------------------------------------------
  SELECT count(*), string_agg(p.proname, ', ' ORDER BY p.proname)
    INTO v_n, v_txt
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
     AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) AS c WHERE c LIKE 'search_path=%');
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Funções', 'Rotinas do public sem search_path fixo', v_n || coalesce(' (' || v_txt || ')', ''),
          CASE WHEN v_n > 0 THEN 'RISCO' ELSE 'OK' END);

  SELECT count(*) INTO v_n
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
     AND EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE');
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Funções', 'Rotinas do public que QUALQUER usuário (PUBLIC) executa', v_n::text,
          CASE WHEN v_n > 0 THEN 'RISCO' ELSE 'OK' END);

  SELECT count(*), string_agg(p.oid::regproc::text, ', ' ORDER BY p.proname)
    INTO v_n, v_txt
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'auditoria', 'seguranca') AND p.prosecdef;
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Funções', 'Rotinas SECURITY DEFINER (rodam com o privilégio do dono)', v_n || coalesce(' (' || v_txt || ')', ''), 'INFO');

  -- Perfis e usuários ------------------------------------------------------------
  FOR r IN
    SELECT * FROM (VALUES
      ('perfil_gerente', NULL), ('perfil_recepcao', NULL), ('perfil_profissional', NULL),
      ('perfil_relatorios', NULL), ('perfil_auditoria', NULL), ('perfil_backup', NULL),
      ('gerente_salao', 'perfil_gerente'), ('recepcao_salao', 'perfil_recepcao'),
      ('profissional_salao', 'perfil_profissional'), ('analista_salao', 'perfil_relatorios'),
      ('auditor_salao', 'perfil_auditoria'), ('backup_salao', 'perfil_backup')
    ) AS t(papel, perfil)
  LOOP
    SELECT CASE
             WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.papel) THEN 'não existe'
             ELSE (SELECT CASE WHEN rolcanlogin THEN 'usuário' ELSE 'perfil' END
                          || CASE WHEN rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolreplication
                                  THEN ' COM ATRIBUTO PRIVILEGIADO' ELSE ' sem atributos privilegiados' END
                          || CASE WHEN r.perfil IS NOT NULL THEN
                               CASE WHEN pg_has_role(r.papel, r.perfil, 'MEMBER')
                                    THEN ', membro de ' || r.perfil ELSE ', SEM PERFIL' END
                             ELSE '' END
                     FROM pg_roles WHERE rolname = r.papel)
           END
      INTO v_txt;
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('Perfis e usuários', r.papel, v_txt,
            CASE WHEN v_txt = 'não existe' THEN 'PENDENTE'
                 WHEN v_txt LIKE '%PRIVILEGIADO%' OR v_txt LIKE '%SEM PERFIL%' THEN 'RISCO'
                 ELSE 'OK' END);
  END LOOP;

  -- Integridade -------------------------------------------------------------------
  SELECT format('%s chaves primárias, %s chaves estrangeiras, %s UNIQUE, %s CHECK',
                count(*) FILTER (WHERE contype = 'p'), count(*) FILTER (WHERE contype = 'f'),
                count(*) FILTER (WHERE contype = 'u'), count(*) FILTER (WHERE contype = 'c'))
    INTO v_txt
    FROM pg_constraint c
   WHERE c.connamespace = 'public'::regnamespace
     AND coalesce(obj_description(c.oid, 'pg_constraint'), '') NOT LIKE 'APD3 |%';
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Integridade', 'Restrições criadas na APD1', v_txt, 'INFO');

  SELECT count(*) INTO v_n
    FROM pg_trigger
   WHERE NOT tgisinternal AND tgname IN ('trg_agendamento_regras', 'trg_pagamento_valida', 'trg_venda_estoque');
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Integridade', 'Gatilhos de regra de negócio da APD1 (agenda, pagamento, estoque)', v_n || ' de 3',
          CASE WHEN v_n = 3 THEN 'OK' ELSE 'RISCO' END);

  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Integridade', 'Índice que impede dois atendimentos do profissional no mesmo horário',
          CASE WHEN to_regclass('public.uq_agendamento_horario_profissional') IS NULL THEN 'ausente' ELSE 'presente' END,
          CASE WHEN to_regclass('public.uq_agendamento_horario_profissional') IS NULL THEN 'RISCO' ELSE 'OK' END);

  FOR r IN
    SELECT * FROM (VALUES
      ('cliente', 'ck_cliente_nome_preenchido', $c$btrim(nome) <> ''$c$),
      ('profissional', 'ck_profissional_nome_preenchido', $c$btrim(nome) <> ''$c$),
      ('servico', 'ck_servico_nome_preenchido', $c$btrim(nome) <> ''$c$),
      ('produto', 'ck_produto_nome_preenchido', $c$btrim(nome) <> '' AND btrim(marca) <> ''$c$),
      ('cliente', 'ck_cliente_telefone_formato', $c$telefone IS NULL OR telefone ~ '^[0-9 ()+-]{8,20}$'$c$),
      ('profissional', 'ck_profissional_telefone_formato', $c$telefone IS NULL OR telefone ~ '^[0-9 ()+-]{8,20}$'$c$),
      ('produto', 'ck_produto_codigo_barras', $c$codigo_barras IS NULL OR codigo_barras ~ '^[0-9]{13}$'$c$),
      ('agendamento', 'ck_agendamento_concluido_com_valor', $c$status <> 'concluido' OR valor IS NOT NULL$c$)
    ) AS t(tabela, restricao, regra)
  LOOP
    IF to_regclass('public.' || r.tabela) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE NOT (%s)', r.tabela, r.regra) INTO v_n;
    SELECT CASE WHEN c.oid IS NULL THEN 'ausente'
                WHEN c.convalidated THEN 'presente e validada'
                ELSE 'presente, NÃO VALIDADA' END
      INTO v_txt
      FROM (SELECT 1) AS um
      LEFT JOIN pg_constraint c ON c.conname = r.restricao AND c.conrelid = to_regclass('public.' || r.tabela);
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('Integridade', r.tabela || '.' || r.restricao, v_txt || ' | linhas fora da regra: ' || v_n,
            CASE WHEN v_n > 0 THEN 'RISCO' WHEN v_txt = 'presente e validada' THEN 'OK' ELSE 'PENDENTE' END);
  END LOOP;

  -- Auditoria -----------------------------------------------------------------------
  SELECT count(DISTINCT tgrelid) INTO v_n FROM pg_trigger WHERE tgname = 'trg_auditoria' AND NOT tgisinternal;
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Auditoria', 'Tabelas com gatilho de auditoria (7 do public + vínculo de profissionais)', v_n || ' de 8',
          CASE WHEN v_n >= 8 THEN 'OK' ELSE 'PENDENTE' END);

  IF to_regclass('auditoria.registro_alteracao') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM auditoria.registro_alteracao' INTO v_n;
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('Auditoria', 'Registros na trilha de auditoria', v_n::text, 'INFO');
  ELSE
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('Auditoria', 'Trilha de auditoria (auditoria.registro_alteracao)', 'ausente', 'PENDENTE');
  END IF;

  -- Views e administração -------------------------------------------------------------
  SELECT count(*) FILTER (WHERE schemaname = 'relatorios'), count(*) FILTER (WHERE schemaname = 'agenda')
    INTO v_n, v_total
    FROM pg_views WHERE schemaname IN ('relatorios', 'agenda');
  INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
  VALUES ('Views', 'Views de relatório (relatorios) e de agenda (agenda)', v_n || ' e ' || v_total,
          CASE WHEN v_n >= 5 AND v_total >= 1 THEN 'OK' ELSE 'PENDENTE' END);

  FOR r IN SELECT unnest(ARRAY['gerente_salao', 'recepcao_salao', 'profissional_salao',
                               'analista_salao', 'auditor_salao', 'backup_salao']) AS usuario LOOP
    SELECT (SELECT string_agg(cfg, '; ' ORDER BY cfg)
              FROM pg_db_role_setting s, unnest(s.setconfig) AS cfg
             WHERE s.setrole = ro.oid AND s.setdatabase = 0)
           || ' | limite de conexões: ' || CASE WHEN ro.rolconnlimit < 0 THEN 'nenhum' ELSE ro.rolconnlimit::text END
           || ' | validade: ' || CASE WHEN ro.rolvaliduntil IS NULL OR ro.rolvaliduntil = 'infinity' THEN 'não expira'
                                      ELSE to_char(ro.rolvaliduntil AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY') END
      INTO v_txt
      FROM pg_roles ro WHERE ro.rolname = r.usuario;
    INSERT INTO apd3_diagnostico (secao, item, valor, situacao)
    VALUES ('Administração', 'Parâmetros de sessão de ' || r.usuario, coalesce(v_txt, 'nenhum'),
            CASE WHEN v_txt IS NULL THEN 'PENDENTE' ELSE 'OK' END);
  END LOOP;
END $$;

SELECT secao, item, valor, situacao
FROM apd3_diagnostico
ORDER BY ordem;
