-- =====================================================================
-- 03_consultas.sql
-- Projeto Integrador de Banco de Dados II (APD1) - IFRJ Campus Niterói
-- Solução: Sistema de Gestão de Salão de Beleza
-- Equipe: Jean de Pinho Macedo, Vinícius Pontes Braga e Pietro Gomes Borges
-- SGBD: PostgreSQL (Supabase)
--
-- Consultas e subconsultas da APD1. Executar depois de
-- 01_criacao_tabelas.sql e 02_insercao_dados.sql.
--
--   CS01 a CS05 -> consultas simples/qualificadas (uma tabela)
--   CJ01 a CJ05 -> consultas com JOIN (agrupamento, agregação e filtros)
--   SQ01 a SQ05 -> subconsultas (comparação, IN/NOT IN, ALL, ANY, EXISTS)
-- =====================================================================


-- =====================================================================
-- CONSULTAS SIMPLES / QUALIFICADAS
-- =====================================================================

-- CS01 - Buscar clientes pelo nome (busca sem diferenciar maiúsculas).
-- Uso: tela de atendimento, quando a recepção procura um cliente.
SELECT id_cliente, nome, telefone, email
FROM cliente
WHERE nome ILIKE '%ana%'
ORDER BY nome;

-- CS02 - Serviços ativos com preço entre R$ 50 e R$ 150, do mais barato
-- ao mais caro. Uso: montar a tabela de preços para divulgação.
SELECT nome, categoria, preco, duracao_minutos
FROM servico
WHERE ativo = 1
  AND preco BETWEEN 50 AND 150
ORDER BY preco, nome;

-- CS03 - Produtos ativos com estoque igual ou abaixo do mínimo.
-- Uso: lista de reposição para o setor de compras.
SELECT id_produto, nome, marca, qtd_estoque, estoque_minimo
FROM produto
WHERE ativo = TRUE
  AND qtd_estoque <= estoque_minimo
ORDER BY qtd_estoque, nome;

-- CS04 - Clientes que fazem aniversário em dezembro, com a idade que
-- vão completar. Uso: campanha de desconto de aniversário.
SELECT nome,
       telefone,
       data_nascimento,
       EXTRACT(YEAR FROM AGE(DATE '2026-12-31', data_nascimento)) AS idade_em_dezembro
FROM cliente
WHERE EXTRACT(MONTH FROM data_nascimento) = 12
ORDER BY EXTRACT(DAY FROM data_nascimento);

-- CS05 - Profissionais cabeleireiros(as) ou coloristas com comissão
-- acima de 38%, dos mais antigos aos mais novos na casa.
SELECT nome, especialidade, comissao_percentual, data_admissao
FROM profissional
WHERE especialidade IN ('Cabeleireira', 'Cabeleireiro', 'Colorista')
  AND comissao_percentual > 38
ORDER BY data_admissao;


-- =====================================================================
-- CONSULTAS COM JOIN (duas ou mais tabelas, agrupamento e agregação)
-- =====================================================================

-- CJ01 - Faturamento e comissão por profissional (atendimentos
-- concluídos). Mostra só quem faturou mais de R$ 500.
-- WHERE filtra as linhas antes de agrupar; HAVING filtra os grupos.
SELECT p.nome                                                  AS profissional,
       p.especialidade,
       COUNT(*)                                                AS atendimentos,
       SUM(a.valor)                                            AS faturamento,
       ROUND(AVG(a.valor), 2)                                  AS ticket_medio,
       ROUND(SUM(a.valor) * p.comissao_percentual / 100, 2)    AS comissao
FROM agendamento a
INNER JOIN profissional p ON p.id_profissional = a.id_profissional
WHERE a.status = 'concluido'
GROUP BY p.id_profissional, p.nome, p.especialidade, p.comissao_percentual
HAVING SUM(a.valor) > 500
ORDER BY faturamento DESC;

-- CJ02 - Receita por categoria de serviço e por mês (2º semestre de
-- 2026), considerando os pagamentos efetivamente recebidos.
SELECT TO_CHAR(DATE_TRUNC('month', pg.data_hora_pagamento), 'YYYY-MM') AS mes,
       s.categoria,
       COUNT(*)                                                        AS qtd_pagamentos,
       SUM(pg.valor_pago)                                              AS receita
FROM pagamento pg
INNER JOIN agendamento a ON a.id_agendamento = pg.id_agendamento
INNER JOIN servico     s ON s.id_servico     = a.id_servico
WHERE pg.data_hora_pagamento >= '2026-07-01'
GROUP BY DATE_TRUNC('month', pg.data_hora_pagamento), s.categoria
ORDER BY mes, receita DESC;

-- CJ03 - Uso de cada forma de pagamento nos serviços: quantidade,
-- valor recebido, descontos concedidos e média de parcelas.
SELECT pg.forma_pagamento,
       COUNT(*)                     AS qtd,
       SUM(pg.valor_pago)           AS total_recebido,
       SUM(pg.desconto)             AS total_descontos,
       ROUND(AVG(pg.parcelas), 1)   AS media_parcelas
FROM pagamento pg
INNER JOIN agendamento a ON a.id_agendamento = pg.id_agendamento
WHERE a.status = 'concluido'
GROUP BY pg.forma_pagamento
ORDER BY total_recebido DESC;

-- CJ04 - Produtos mais vendidos por categoria: unidades e receita.
-- Lista apenas produtos com pelo menos 3 unidades vendidas.
SELECT pr.categoria,
       pr.nome                                   AS produto,
       pr.marca,
       SUM(v.quantidade)                         AS unidades,
       SUM(v.quantidade * v.valor_unitario)      AS receita
FROM venda_produto v
INNER JOIN produto pr ON pr.id_produto = v.id_produto
GROUP BY pr.categoria, pr.id_produto, pr.nome, pr.marca
HAVING SUM(v.quantidade) >= 3
ORDER BY pr.categoria, unidades DESC;

-- CJ05 - Ranking dos 10 clientes que mais gastaram no salão somando
-- serviços pagos e compras de produtos. LEFT JOIN mantém clientes que
-- só têm um dos dois tipos de gasto.
SELECT c.nome                                             AS cliente,
       COALESCE(sv.total_servicos, 0)                     AS gasto_servicos,
       COALESCE(pd.total_produtos, 0)                     AS gasto_produtos,
       COALESCE(sv.total_servicos, 0)
         + COALESCE(pd.total_produtos, 0)                 AS gasto_total
FROM cliente c
LEFT JOIN (SELECT a.id_cliente, SUM(pg.valor_pago) AS total_servicos
             FROM agendamento a
             INNER JOIN pagamento pg ON pg.id_agendamento = a.id_agendamento
            GROUP BY a.id_cliente) sv ON sv.id_cliente = c.id_cliente
LEFT JOIN (SELECT v.id_cliente, SUM(v.quantidade * v.valor_unitario) AS total_produtos
             FROM venda_produto v
            GROUP BY v.id_cliente) pd ON pd.id_cliente = c.id_cliente
WHERE sv.total_servicos IS NOT NULL OR pd.total_produtos IS NOT NULL
ORDER BY gasto_total DESC
LIMIT 10;


-- =====================================================================
-- SUBCONSULTAS
-- =====================================================================

-- SQ01 (NOT IN) - Clientes que nunca agendaram serviço.
-- Uso: campanha para converter compradores e cadastros parados.
SELECT id_cliente, nome, telefone, data_cadastro
FROM cliente
WHERE id_cliente NOT IN (SELECT id_cliente FROM agendamento)
ORDER BY nome;

-- SQ02 (operador de comparação) - Serviços ativos com preço acima da
-- média de preço dos serviços ativos.
SELECT nome, categoria, preco
FROM servico
WHERE ativo = 1
  AND preco > (SELECT AVG(preco) FROM servico WHERE ativo = 1)
ORDER BY preco DESC;

-- SQ03 (ALL) - Produto(s) com o maior preço de venda dentro da
-- categoria Shampoo: preço maior ou igual ao de TODOS os shampoos.
SELECT nome, marca, preco_venda
FROM produto
WHERE categoria = 'Shampoo'
  AND preco_venda >= ALL (SELECT preco_venda FROM produto WHERE categoria = 'Shampoo');

-- SQ04 (ANY) - Profissionais (exceto barbeiros) cuja comissão é maior
-- que a de pelo menos um barbeiro.
SELECT nome, especialidade, comissao_percentual
FROM profissional
WHERE especialidade <> 'Barbeiro'
  AND comissao_percentual > ANY (SELECT comissao_percentual
                                   FROM profissional
                                  WHERE especialidade = 'Barbeiro')
ORDER BY comissao_percentual DESC, nome;

-- SQ05 (EXISTS) - Clientes que já tiveram serviço concluído E também
-- compraram produto (clientes que aproveitam as duas frentes do salão).
SELECT c.id_cliente, c.nome, c.email
FROM cliente c
WHERE EXISTS (SELECT 1
                FROM agendamento a
               WHERE a.id_cliente = c.id_cliente
                 AND a.status = 'concluido')
  AND EXISTS (SELECT 1
                FROM venda_produto v
               WHERE v.id_cliente = c.id_cliente)
ORDER BY c.nome;
