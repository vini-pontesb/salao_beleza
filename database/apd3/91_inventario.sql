-- =============================================================================
-- APD3 · Script 91 · Inventário da configuração de segurança
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Item (iv) da APD3: evidência da CONFIGURAÇÃO aplicada (usuários, perfis,
-- privilégios, políticas, restrições, gatilhos e rotinas), lida direto do
-- catálogo do PostgreSQL. Não altera nada.
--
-- Também é o roteiro da revisão semestral de acessos: rode, confira cada linha
-- contra a política e investigue o que não estiver previsto.
--
-- Saída: uma única tabela (secao, objeto, situacao, detalhe), com menos de 100
-- linhas (o limite que o SQL Editor do Supabase mostra). Use "Export > CSV"
-- para guardar a evidência.
-- =============================================================================

WITH schemas AS (
  SELECT oid, nspname FROM pg_namespace
   WHERE nspname IN ('public', 'relatorios', 'agenda', 'auditoria', 'seguranca')
),
papeis AS (
  SELECT oid, rolname FROM pg_roles
   WHERE rolname LIKE 'perfil\_%' OR rolname LIKE '%\_salao'
      OR rolname IN ('anon', 'authenticated', 'service_role')
),
inventario AS (
  -- 1. Usuários e perfis -------------------------------------------------------
  SELECT 1 AS ordem, 'Usuários e perfis' AS secao, r.rolname::text AS objeto,
         CASE WHEN r.rolcanlogin THEN 'usuário' ELSE 'perfil' END AS situacao,
         concat_ws(' | ',
           'membro de: ' || coalesce((SELECT string_agg(g.rolname, ', ' ORDER BY g.rolname)
                                        FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid
                                       WHERE m.member = r.oid), '-'),
           'atributos: ' || concat_ws(' ',
              CASE WHEN r.rolsuper THEN 'SUPERUSER' END, CASE WHEN r.rolcreaterole THEN 'CREATEROLE' END,
              CASE WHEN r.rolcreatedb THEN 'CREATEDB' END, CASE WHEN r.rolreplication THEN 'REPLICATION' END,
              CASE WHEN r.rolbypassrls THEN 'BYPASSRLS' END, CASE WHEN r.rolinherit THEN 'INHERIT' ELSE 'NOINHERIT' END),
           'limite de conexões: ' || CASE WHEN r.rolconnlimit < 0 THEN 'nenhum' ELSE r.rolconnlimit::text END,
           'válido até: ' || CASE WHEN r.rolvaliduntil IS NULL OR r.rolvaliduntil = 'infinity' THEN 'sem expiração'
                                  ELSE to_char(r.rolvaliduntil AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY') END,
           'parâmetros: ' || coalesce((SELECT string_agg(cfg, '; ' ORDER BY cfg)
                                         FROM pg_db_role_setting s, unnest(s.setconfig) AS cfg
                                        WHERE s.setrole = r.oid AND s.setdatabase = 0), '-')
         ) AS detalhe
  FROM pg_roles r
  WHERE r.rolname LIKE 'perfil\_%' OR r.rolname LIKE '%\_salao'

  UNION ALL
  -- 2. Privilégios em schemas -------------------------------------------------
  SELECT 2, 'Privilégios em schemas', s.nspname::text, 'USAGE / CREATE',
         coalesce((SELECT string_agg(p.rolname || ': ' || concat_ws(' ',
                                       CASE WHEN has_schema_privilege(p.oid, s.oid, 'USAGE') THEN 'USAGE' END,
                                       CASE WHEN has_schema_privilege(p.oid, s.oid, 'CREATE') THEN 'CREATE' END),
                                     '; ' ORDER BY p.rolname)
                     FROM papeis p
                    WHERE p.rolname NOT LIKE '%\_salao'
                      AND (has_schema_privilege(p.oid, s.oid, 'USAGE') OR has_schema_privilege(p.oid, s.oid, 'CREATE'))),
                  'ninguém além do dono')
  FROM schemas s

  UNION ALL
  -- 3. Privilégios em tabelas e views (tabela inteira e por coluna) ------------
  SELECT 3, 'Privilégios em tabelas e views', format('%I.%I', n.nspname, c.relname),
         CASE c.relkind WHEN 'v' THEN 'view' ELSE 'tabela' END,
         coalesce(nullif(concat_ws('; ',
           (SELECT string_agg(g.papel || ': ' || g.privs, '; ' ORDER BY g.papel)
              FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END AS papel,
                           string_agg(a.privilege_type, ', ' ORDER BY a.privilege_type) AS privs
                      FROM aclexplode(c.relacl) AS a
                     WHERE a.grantee <> c.relowner
                     GROUP BY a.grantee) AS g),
           (SELECT string_agg(g.papel || ': ' || g.priv || '(' || g.colunas || ')', '; ' ORDER BY g.papel, g.priv)
              FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END AS papel,
                           a.privilege_type AS priv,
                           string_agg(at.attname, ', ' ORDER BY at.attnum) AS colunas
                      FROM pg_attribute at
                      CROSS JOIN LATERAL aclexplode(at.attacl) AS a
                     WHERE at.attrelid = c.oid AND at.attacl IS NOT NULL AND NOT at.attisdropped
                     GROUP BY a.grantee, a.privilege_type) AS g)
         ), ''), 'só o dono')
  FROM pg_class c
  JOIN schemas n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r', 'p', 'v')

  UNION ALL
  -- 4. Privilégios em sequências (agrupados por schema) ------------------------
  SELECT 4, 'Privilégios em sequências', n.nspname || ' (' || count(DISTINCT c.oid) || ' sequências)', 'sequência',
         coalesce((SELECT string_agg(DISTINCT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END
                                     || ': ' || a.privilege_type, '; ')
                     FROM pg_class c2
                     CROSS JOIN LATERAL aclexplode(c2.relacl) AS a
                    WHERE c2.relnamespace = n.oid AND c2.relkind = 'S' AND a.grantee <> c2.relowner), 'só o dono')
  FROM pg_class c
  JOIN schemas n ON n.oid = c.relnamespace
  WHERE c.relkind = 'S'
  GROUP BY n.oid, n.nspname

  UNION ALL
  -- 5. Privilégios padrão: o que objetos FUTUROS recebem ------------------------
  SELECT 5, 'Privilégios padrão (objetos futuros)',
         coalesce(n.nspname, '(todos os schemas)') || ' / ' ||
           CASE d.defaclobjtype WHEN 'r' THEN 'tabelas' WHEN 'S' THEN 'sequências' WHEN 'f' THEN 'funções'
                                WHEN 'T' THEN 'tipos' WHEN 'n' THEN 'schemas' END,
         'criados por ' || d.defaclrole::regrole::text,
         string_agg(CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ': ' || a.privilege_type,
                    '; ' ORDER BY a.grantee::regrole::text, a.privilege_type)
  FROM pg_default_acl d
  LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) AS a
  WHERE d.defaclrole = 'postgres'::regrole
  GROUP BY n.nspname, d.defaclobjtype, d.defaclrole

  UNION ALL
  -- 6. Row Level Security e políticas -------------------------------------------
  SELECT 6, 'RLS', format('%I.%I', n.nspname, c.relname),
         CASE WHEN c.relrowsecurity THEN 'RLS ligado' ELSE 'RLS DESLIGADO' END,
         coalesce((SELECT string_agg(format('%s [%s para %s] %s', p.polname,
                                            CASE p.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                                                          WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' ELSE 'ALL' END,
                                            (SELECT string_agg(rr.rolname, ', ') FROM pg_roles rr WHERE rr.oid = ANY (p.polroles)),
                                            concat_ws(' ',
                                              'USING (' || regexp_replace(pg_get_expr(p.polqual, p.polrelid), '\s+', ' ', 'g') || ')',
                                              'WITH CHECK (' || regexp_replace(pg_get_expr(p.polwithcheck, p.polrelid), '\s+', ' ', 'g') || ')')),
                                     '; ' ORDER BY p.polname)
                     FROM pg_policy p WHERE p.polrelid = c.oid), 'sem políticas')
  FROM pg_class c
  JOIN schemas n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('public', 'seguranca') AND c.relkind IN ('r', 'p')

  UNION ALL
  -- 7. Restrições CHECK (agrupadas por tabela) --------------------------------
  SELECT 7, 'Restrições CHECK', c.conrelid::regclass::text,
         count(*) || ' (' || count(*) FILTER (WHERE obj_description(c.oid, 'pg_constraint') LIKE 'APD3 |%') || ' da APD3)',
         string_agg(c.conname || CASE WHEN c.convalidated THEN '' ELSE ' [NÃO VALIDADA]' END, ', ' ORDER BY c.conname)
  FROM pg_constraint c
  WHERE c.contype = 'c' AND c.connamespace = 'public'::regnamespace
  GROUP BY c.conrelid

  UNION ALL
  -- 8. Gatilhos (agrupados por tabela) ------------------------------------------
  SELECT 8, 'Gatilhos', t.tgrelid::regclass::text, count(*) || ' gatilho(s)',
         string_agg(t.tgname || CASE t.tgenabled WHEN 'D' THEN ' [DESLIGADO]' ELSE '' END || ' -> ' ||
                    t.tgfoid::regproc::text, ', ' ORDER BY t.tgname)
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  WHERE NOT t.tgisinternal
    AND c.relnamespace IN (SELECT oid FROM schemas)
  GROUP BY t.tgrelid

  UNION ALL
  -- 9. Funções e procedimentos ----------------------------------------------------
  SELECT 9, 'Rotinas', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         CASE WHEN p.prosecdef THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END,
         concat_ws(' | ',
           'configuração: ' || coalesce(array_to_string(p.proconfig, ', '), '-'),
           'quem executa: ' || coalesce((SELECT string_agg(CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                                                                ELSE a.grantee::regrole::text END, ', '
                                                           ORDER BY a.grantee::regrole::text)
                                           FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
                                          WHERE a.privilege_type = 'EXECUTE' AND a.grantee <> p.proowner), 'só o dono'))
  FROM pg_proc p
  JOIN schemas n ON n.oid = p.pronamespace
  WHERE NOT EXISTS (SELECT 1 FROM pg_depend d
                     WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
)
SELECT secao, objeto, situacao, detalhe
FROM inventario
ORDER BY ordem, objeto;
