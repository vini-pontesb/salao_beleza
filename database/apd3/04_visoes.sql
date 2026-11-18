-- =============================================================================
-- APD3 · Script 04 · Visões (views) de relatórios e da agenda do profissional
-- Base de dados do salão de beleza (APD1) · PostgreSQL do Supabase
--
-- Views são a forma de dar acesso a uma RESPOSTA sem dar acesso às tabelas.
--
--   relatorios.*            indicadores agregados para a gerência e para o
--                           perfil de relatórios. Nenhuma coluna de dado
--                           pessoal (nome, telefone, e-mail, nascimento de
--                           cliente) e nenhuma comissão de profissional.
--   agenda.vw_minha_agenda  a agenda do profissional conectado: só os
--                           atendimentos dele e só o primeiro nome do cliente
--                           (minimização, LGPD art. 6º, III).
--
-- As views pertencem ao postgres e leem as tabelas com os privilégios dele;
-- quem consulta precisa só do SELECT na view. Todas são security_barrier, para
-- que nenhuma função escrita por quem consulta rode antes dos filtros da view.
-- Os schemas relatorios e agenda ficam fora da API automática do Supabase.
--
-- Idempotente. Rodar como postgres, depois dos scripts 01 a 03.
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

CREATE SCHEMA IF NOT EXISTS relatorios;
COMMENT ON SCHEMA relatorios IS 'APD3 | Views agregadas para relatórios gerenciais. Sem dado pessoal.';

CREATE SCHEMA IF NOT EXISTS agenda;
COMMENT ON SCHEMA agenda IS 'APD3 | Agenda de cada profissional (só os próprios atendimentos).';

-- 1. Faturamento por mês: serviços pagos + produtos vendidos ------------------
CREATE OR REPLACE VIEW relatorios.vw_faturamento_mensal
WITH (security_barrier = true) AS
WITH servicos AS (
  SELECT date_trunc('month', pg.data_hora_pagamento)::date AS mes,
         count(*)           AS atendimentos_pagos,
         sum(pg.valor_pago) AS receita_servicos,
         sum(pg.desconto)   AS descontos_concedidos
    FROM public.pagamento pg
   GROUP BY 1
), produtos AS (
  SELECT date_trunc('month', v.data_venda)::date AS mes,
         sum(v.quantidade)                    AS itens_vendidos,
         sum(v.quantidade * v.valor_unitario) AS receita_produtos
    FROM public.venda_produto v
   GROUP BY 1
)
SELECT coalesce(s.mes, p.mes)                 AS mes,
       coalesce(s.atendimentos_pagos, 0)      AS atendimentos_pagos,
       coalesce(s.receita_servicos, 0)        AS receita_servicos,
       coalesce(s.descontos_concedidos, 0)    AS descontos_concedidos,
       coalesce(p.itens_vendidos, 0)          AS itens_vendidos,
       coalesce(p.receita_produtos, 0)        AS receita_produtos,
       coalesce(s.receita_servicos, 0) + coalesce(p.receita_produtos, 0) AS receita_total
  FROM servicos s
  FULL JOIN produtos p ON p.mes = s.mes;

COMMENT ON VIEW relatorios.vw_faturamento_mensal IS
  'APD3 | Receita mensal de serviços (pagamentos) e de produtos (vendas), com descontos concedidos.';

-- 2. Serviços mais realizados ---------------------------------------------------
CREATE OR REPLACE VIEW relatorios.vw_servicos_mais_realizados
WITH (security_barrier = true) AS
SELECT s.id_servico,
       s.nome      AS servico,
       s.categoria,
       s.ativo = 1 AS ativo,
       count(a.id_agendamento) FILTER (WHERE a.status = 'concluido') AS atendimentos_concluidos,
       count(a.id_agendamento) FILTER (WHERE a.status = 'cancelado') AS cancelamentos,
       coalesce(sum(a.valor) FILTER (WHERE a.status = 'concluido'), 0) AS receita_bruta
  FROM public.servico s
  LEFT JOIN public.agendamento a ON a.id_servico = s.id_servico
 GROUP BY s.id_servico, s.nome, s.categoria, s.ativo;

COMMENT ON VIEW relatorios.vw_servicos_mais_realizados IS
  'APD3 | Por serviço: atendimentos concluídos, cancelamentos e receita bruta.';

-- 3. Ocupação dos profissionais (sem comissão) --------------------------------
CREATE OR REPLACE VIEW relatorios.vw_ocupacao_profissionais
WITH (security_barrier = true) AS
SELECT p.id_profissional,
       p.nome AS profissional,
       p.especialidade,
       date_trunc('month', a.data_agendamento)::date AS mes,
       count(*) FILTER (WHERE a.status = 'agendado')  AS agendados,
       count(*) FILTER (WHERE a.status = 'concluido') AS concluidos,
       count(*) FILTER (WHERE a.status = 'cancelado') AS cancelados
  FROM public.profissional p
  JOIN public.agendamento a ON a.id_profissional = p.id_profissional
 GROUP BY p.id_profissional, p.nome, p.especialidade, date_trunc('month', a.data_agendamento);

COMMENT ON VIEW relatorios.vw_ocupacao_profissionais IS
  'APD3 | Atendimentos por profissional e mês. A comissão fica de fora (dado de remuneração).';

-- 4. Produtos ativos no estoque mínimo ou abaixo dele -------------------------
CREATE OR REPLACE VIEW relatorios.vw_produtos_estoque_baixo
WITH (security_barrier = true) AS
SELECT pr.id_produto,
       pr.nome AS produto,
       pr.marca,
       pr.categoria,
       pr.qtd_estoque,
       pr.estoque_minimo,
       pr.estoque_minimo - pr.qtd_estoque AS abaixo_do_minimo
  FROM public.produto pr
 WHERE pr.ativo
   AND pr.qtd_estoque <= pr.estoque_minimo;

COMMENT ON VIEW relatorios.vw_produtos_estoque_baixo IS
  'APD3 | Produtos ativos que precisam de reposição (qtd_estoque <= estoque_minimo).';

-- 5. Clientes novos por mês (só contagem) -------------------------------------
CREATE OR REPLACE VIEW relatorios.vw_clientes_novos_por_mes
WITH (security_barrier = true) AS
SELECT date_trunc('month', c.data_cadastro)::date AS mes,
       count(*) AS clientes_novos
  FROM public.cliente c
 GROUP BY 1;

COMMENT ON VIEW relatorios.vw_clientes_novos_por_mes IS
  'APD3 | Quantos clientes se cadastraram em cada mês. Nenhum dado de cliente individual.';

-- 6. Agenda do profissional conectado ----------------------------------------
-- O filtro usa seguranca.id_profissional_atual(), que roda com a identidade de
-- quem consulta: cada profissional vê só os próprios atendimentos, e quem não
-- é profissional não vê nada.
CREATE OR REPLACE VIEW agenda.vw_minha_agenda
WITH (security_barrier = true) AS
SELECT a.id_agendamento,
       a.data_agendamento,
       a.hora,
       s.nome AS servico,
       s.duracao_minutos,
       split_part(btrim(c.nome), ' ', 1) AS cliente_primeiro_nome,
       a.status
  FROM public.agendamento a
  JOIN public.servico s ON s.id_servico = a.id_servico
  JOIN public.cliente c ON c.id_cliente = a.id_cliente
 WHERE a.id_profissional = (SELECT seguranca.id_profissional_atual());

COMMENT ON VIEW agenda.vw_minha_agenda IS
  'APD3 | Atendimentos do profissional conectado, com o primeiro nome do cliente. Sem telefone, e-mail ou valores.';

-- Evidência: views criadas ------------------------------------------------------
SELECT schemaname || '.' || viewname AS view,
       obj_description((schemaname || '.' || viewname)::regclass, 'pg_class') AS descricao
FROM pg_views
WHERE schemaname IN ('relatorios', 'agenda')
ORDER BY 1;
