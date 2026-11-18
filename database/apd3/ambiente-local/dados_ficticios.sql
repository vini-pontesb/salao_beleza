-- =============================================================================
-- dados_ficticios.sql
-- Dados inventados para o banco LOCAL de teste (nenhum dado real do salão).
-- Nomes, telefones e e-mails seguem o padrão "Cliente Fictício 01",
-- "(21) 90000-0001" e "cliente01@exemplo.com", para não haver dúvida de que
-- não são pessoas reais (LGPD).
--
-- Rodar como postgres, depois de estrutura_apd1.sql:
--   psql "$URL" -v ON_ERROR_STOP=1 -1 -f dados_ficticios.sql
--
-- Os gatilhos da APD1 trabalham normalmente aqui: o valor do agendamento vem
-- do preço do serviço, o pagamento é criado por sp_concluir_atendimento e a
-- venda dá baixa no estoque.
-- =============================================================================

INSERT INTO public.cliente (nome, telefone, email, data_nascimento, data_cadastro)
SELECT format('Cliente Fictício %s', lpad(n::text, 2, '0')),
       format('(21) 90000-%s', lpad(n::text, 4, '0')),
       format('cliente%s@exemplo.com', lpad(n::text, 2, '0')),
       date '1985-01-15' + n * 200,
       current_date - 120 + n
  FROM generate_series(1, 20) AS n;

INSERT INTO public.profissional (nome, especialidade, telefone, comissao_percentual, data_admissao)
SELECT format('Profissional Fictício %s', n),
       (ARRAY['Cabeleireira', 'Barbeiro', 'Manicure', 'Esteticista',
              'Maquiadora', 'Depiladora', 'Colorista', 'Cabeleireiro'])[n],
       format('(21) 98000-%s', lpad(n::text, 4, '0')),
       10 + n * 3,
       date '2023-03-01' + n * 30
  FROM generate_series(1, 8) AS n;

INSERT INTO public.servico (nome, descricao, categoria, preco, duracao_minutos, ativo) VALUES
  ('Corte feminino',      'Corte e finalização',          'Cabelo',    80.00, 60, 1),
  ('Corte masculino',     'Corte com máquina e tesoura',  'Cabelo',    45.00, 30, 1),
  ('Barba completa',      'Barba com toalha quente',      'Barba',     35.00, 30, 1),
  ('Manicure',            'Cutilagem e esmaltação',       'Unhas',     30.00, 45, 1),
  ('Pedicure',            'Cutilagem e esmaltação',       'Unhas',     35.00, 45, 1),
  ('Limpeza de pele',     'Limpeza profunda',             'Estética', 120.00, 90, 1),
  ('Maquiagem social',    'Maquiagem para eventos',       'Maquiagem', 150.00, 60, 1),
  ('Depilação de pernas', 'Cera quente',                  'Depilação', 70.00, 45, 1),
  ('Coloração',           'Coloração completa',           'Cabelo',   180.00, 90, 1),
  ('Escova progressiva',  'Serviço descontinuado',        'Cabelo',   250.00, 120, 0);

INSERT INTO public.produto (nome, marca, categoria, preco_venda, qtd_estoque, estoque_minimo, codigo_barras, ativo)
SELECT format('Produto Fictício %s', n),
       format('Marca %s', chr(64 + n)),
       (ARRAY['Shampoo', 'Condicionador', 'Tratamento', 'Finalizador', 'Coloração',
              'Unhas', 'Pele', 'Barba', 'Shampoo', 'Tratamento'])[n],
       19.90 + n * 5,
       30,
       5,
       '7890000000' || lpad(n::text, 3, '0'),
       n <> 10
  FROM generate_series(1, 10) AS n;

-- 20 agendamentos em dias diferentes (sem conflito de horário): 10 no passado e
-- 10 no futuro, todos com serviços ativos (1 a 9).
INSERT INTO public.agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora)
SELECT n,
       1 + (n % 8),
       1 + (n % 9),
       current_date - 11 + n,
       lpad((8 + n % 10)::text, 2, '0') || ':00'
  FROM generate_series(1, 20) AS n;

-- Os 8 primeiros (passados) foram atendidos e pagos; o 9º foi cancelado.
CALL public.sp_concluir_atendimento(1, 'pix');
CALL public.sp_concluir_atendimento(2, 'dinheiro');
CALL public.sp_concluir_atendimento(3, 'debito');
CALL public.sp_concluir_atendimento(4, 'credito', 0, 2);
CALL public.sp_concluir_atendimento(5, 'pix', 5);
CALL public.sp_concluir_atendimento(6, 'pix');
CALL public.sp_concluir_atendimento(7, 'credito', 10, 3);
CALL public.sp_concluir_atendimento(8, 'dinheiro');
UPDATE public.agendamento SET status = 'cancelado' WHERE id_agendamento = 9;

-- 15 vendas de produtos ativos (1 a 9); o valor unitário vem do preço do produto.
INSERT INTO public.venda_produto (id_cliente, id_produto, id_profissional, quantidade, forma_pagamento)
SELECT 1 + (n % 20),
       1 + (n % 9),
       CASE WHEN n % 3 = 0 THEN NULL ELSE 1 + (n % 8) END,
       1 + (n % 2),
       (ARRAY['dinheiro', 'pix', 'debito', 'credito'])[1 + n % 4]
  FROM generate_series(1, 15) AS n;
