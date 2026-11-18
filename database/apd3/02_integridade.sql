-- =============================================================================
-- APD3 · Script 02 · Restrições de integridade complementares
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- A APD1 já protege a base com chaves primárias e estrangeiras, UNIQUE, 19
-- CHECKs, um índice único parcial (um profissional não tem dois atendimentos
-- no mesmo horário) e três gatilhos de regra de negócio (agenda, pagamento e
-- estoque). Este script fecha as lacunas que sobraram:
--
--   ck_cliente_nome_preenchido        nome não pode ser vazio nem só espaços
--   ck_profissional_nome_preenchido   (o NOT NULL da APD1 aceita '   ')
--   ck_servico_nome_preenchido
--   ck_produto_nome_preenchido
--   ck_cliente_telefone_formato       telefone só com dígitos, espaço, ( ) + -
--   ck_profissional_telefone_formato  e de 8 a 20 caracteres
--   ck_produto_codigo_barras          código de barras com exatamente 13 dígitos
--                                     (EAN-13; char(13) completa com espaços)
--   ck_agendamento_concluido_com_valor  atendimento concluído sempre tem valor
--
-- Cada restrição é criada NOT VALID (rápido, sem travar a tabela enquanto lê
-- tudo) e depois validada contra as linhas existentes. Se alguma linha antiga
-- estiver fora da regra, a restrição continua valendo para dados novos e o
-- script avisa (NOTICE); o diagnóstico (script 00) lista o que corrigir.
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

DO $$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
      ('cliente', 'ck_cliente_nome_preenchido',
       $c$CHECK (btrim(nome) <> '')$c$,
       'Nome do cliente não pode ser vazio nem só espaços.'),
      ('profissional', 'ck_profissional_nome_preenchido',
       $c$CHECK (btrim(nome) <> '')$c$,
       'Nome do profissional não pode ser vazio nem só espaços.'),
      ('servico', 'ck_servico_nome_preenchido',
       $c$CHECK (btrim(nome) <> '')$c$,
       'Nome do serviço não pode ser vazio nem só espaços.'),
      ('produto', 'ck_produto_nome_preenchido',
       $c$CHECK (btrim(nome) <> '' AND btrim(marca) <> '')$c$,
       'Nome e marca do produto não podem ser vazios nem só espaços.'),
      ('cliente', 'ck_cliente_telefone_formato',
       $c$CHECK (telefone IS NULL OR telefone ~ '^[0-9 ()+-]{8,20}$')$c$,
       'Telefone do cliente: só dígitos, espaço, parênteses, + e -, de 8 a 20 caracteres.'),
      ('profissional', 'ck_profissional_telefone_formato',
       $c$CHECK (telefone IS NULL OR telefone ~ '^[0-9 ()+-]{8,20}$')$c$,
       'Telefone do profissional: só dígitos, espaço, parênteses, + e -, de 8 a 20 caracteres.'),
      ('produto', 'ck_produto_codigo_barras',
       $c$CHECK (codigo_barras IS NULL OR codigo_barras ~ '^[0-9]{13}$')$c$,
       'Código de barras do produto: exatamente 13 dígitos (EAN-13).'),
      ('agendamento', 'ck_agendamento_concluido_com_valor',
       $c$CHECK (status <> 'concluido' OR valor IS NOT NULL)$c$,
       'Atendimento concluído precisa ter valor (é a base do pagamento e da comissão).')
    ) AS t(tabela, nome, definicao, descricao)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = ('public.' || v.tabela)::regclass AND conname = v.nome) THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I %s NOT VALID', v.tabela, v.nome, v.definicao);
    END IF;
    EXECUTE format('COMMENT ON CONSTRAINT %I ON public.%I IS %L', v.nome, v.tabela, 'APD3 | ' || v.descricao);

    -- Valida as linhas que já existem. Se alguma estiver fora da regra, a
    -- restrição fica criada (vale para dados novos) e só não é marcada como
    -- validada; o resto do script continua.
    BEGIN
      EXECUTE format('ALTER TABLE public.%I VALIDATE CONSTRAINT %I', v.tabela, v.nome);
    EXCEPTION WHEN check_violation THEN
      RAISE NOTICE 'Restrição % criada, mas há linhas antigas em public.% fora da regra. Ela já vale para dados novos e fica NÃO VALIDADA até as linhas serem corrigidas (o script 00 lista quais).',
                   v.nome, v.tabela;
    END;
  END LOOP;
END $$;

RESET lock_timeout;

-- Evidência: todas as restrições das 7 tabelas, da APD1 e da APD3 -------------
SELECT c.conrelid::regclass::text AS tabela,
       c.conname AS restricao,
       CASE c.contype WHEN 'p' THEN 'chave primária' WHEN 'f' THEN 'chave estrangeira'
                      WHEN 'u' THEN 'única' WHEN 'c' THEN 'verificação (CHECK)'
                      ELSE c.contype::text END AS tipo,
       CASE WHEN obj_description(c.oid, 'pg_constraint') LIKE 'APD3 |%' THEN 'APD3' ELSE 'APD1' END AS origem,
       c.convalidated AS validada,
       pg_get_constraintdef(c.oid) AS definicao
FROM pg_constraint c
WHERE c.conrelid IN ('public.cliente'::regclass, 'public.profissional'::regclass, 'public.servico'::regclass,
                     'public.agendamento'::regclass, 'public.pagamento'::regclass, 'public.produto'::regclass,
                     'public.venda_produto'::regclass)
ORDER BY origem DESC, tabela, tipo, restricao;
