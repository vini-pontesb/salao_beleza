-- =====================================================================
-- scripts-admin.sql
-- Scripts SQL para o ADMINISTRADOR rodar direto no SQL Editor do Supabase
-- (não fazem parte do fluxo do back-end/front-end da aplicação).
--
-- Sistema de Agendamento de Salão de Beleza
-- Trabalho Prático de Banco de Dados I — IFRJ Campus Niterói
-- Grupo: Vinicius Pontes e Jean Macedo
-- SGBD: PostgreSQL (Supabase)
--
-- Cada bloco é numerado conforme a lista de exigências da reunião.
-- Rodar os blocos em ordem (1) -> (3) -> (2) -> (4) -> (5) -> (6).
-- =====================================================================


-- =====================================================================
-- (1) CRIAÇÃO DO BANCO E TABELAS
-- ---------------------------------------------------------------------
-- A criação oficial das 4 tabelas está em database/schema.sql (fonte da
-- verdade). Reproduzida aqui, com a mesma estrutura, para o administrador
-- poder recriar o banco do zero direto pelo SQL Editor. Ordem dos DROPs:
-- filhos antes dos pais, por causa das FKs.
-- =====================================================================
DROP TABLE IF EXISTS agendamento;
DROP TABLE IF EXISTS servico;
DROP TABLE IF EXISTS profissional;
DROP TABLE IF EXISTS cliente;

CREATE TABLE cliente (
    id_cliente       SERIAL PRIMARY KEY,
    nome             TEXT NOT NULL,
    telefone         TEXT,
    email            TEXT UNIQUE,
    data_nascimento  DATE,
    data_cadastro    DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE profissional (
    id_profissional      SERIAL PRIMARY KEY,
    nome                 TEXT NOT NULL,
    especialidade        TEXT,
    telefone             TEXT,
    comissao_percentual  NUMERIC(5,2) NOT NULL DEFAULT 0,
    data_admissao        DATE
);

CREATE TABLE servico (
    id_servico       SERIAL PRIMARY KEY,
    nome             TEXT NOT NULL,
    descricao        TEXT,
    preco            NUMERIC(10,2) NOT NULL,
    duracao_minutos  INTEGER,
    ativo            SMALLINT NOT NULL DEFAULT 1   -- 1 = ativo, 0 = inativo
);

CREATE TABLE agendamento (
    id_agendamento    SERIAL PRIMARY KEY,
    id_cliente        INTEGER NOT NULL,
    id_profissional   INTEGER NOT NULL,
    id_servico        INTEGER NOT NULL,
    data_agendamento  DATE NOT NULL,
    hora              TEXT,
    valor             NUMERIC(10,2),
    status            TEXT NOT NULL DEFAULT 'agendado',  -- agendado | concluido | cancelado
    FOREIGN KEY (id_cliente)      REFERENCES cliente(id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_profissional) REFERENCES profissional(id_profissional)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_servico)      REFERENCES servico(id_servico)
        ON DELETE RESTRICT ON UPDATE CASCADE
);


-- =====================================================================
-- (3) APAGAR OS DADOS DE TODAS AS TABELAS
-- ---------------------------------------------------------------------
-- Vem ANTES do bloco (2) de propósito: assim os ids reiniciam em 1 e o
-- INSERT seguinte pode referenciar ids 1..5 com segurança.
--
-- Como agendamento tem FK com ON DELETE RESTRICT para as outras 3
-- tabelas, não seria possível apagar cliente/profissional/servico
-- diretamente enquanto existirem agendamentos vinculados. O TRUNCATE com
-- CASCADE resolve isso apagando também as linhas dependentes de
-- agendamento, e RESTART IDENTITY zera a numeração dos ids (SERIAL).
-- =====================================================================
TRUNCATE TABLE agendamento, servico, profissional, cliente
    RESTART IDENTITY CASCADE;


-- =====================================================================
-- (2) INSERIR 5 REGISTROS EM TODAS AS TABELAS (GARANTINDO A INTEGRIDADE)
-- ---------------------------------------------------------------------
-- As tabelas-pai (cliente, profissional, servico) são preenchidas ANTES
-- de agendamento, e cada agendamento referencia ids que já existem
-- (1..5), respeitando as chaves estrangeiras. Rodar logo após o bloco
-- (3), com os ids reiniciados.
-- =====================================================================
INSERT INTO cliente (nome, telefone, email, data_nascimento) VALUES
    ('Ana Souza',       '21988880001', 'ana.souza@email.com',    '1995-03-12'),
    ('Bruno Lima',      '21988880002', 'bruno.lima@email.com',   '1988-07-25'),
    ('Carla Mendes',    '21988880003', 'carla.mendes@email.com', '2000-11-30'),
    ('Diego Rocha',     '21988880004', 'diego.rocha@email.com',  '1992-05-08'),
    ('Elaine Ferreira', '21988880005', 'elaine.f@email.com',     '1998-09-14');

INSERT INTO profissional (nome, especialidade, telefone, comissao_percentual, data_admissao) VALUES
    ('Marina Alves', 'Cabeleireira',  '21977770001', 40.0, '2024-06-01'),
    ('Rafael Dias',  'Barbeiro',      '21977770002', 35.0, '2025-01-15'),
    ('Sofia Ramos',  'Manicure',      '21977770003', 30.0, '2025-03-10'),
    ('Tiago Nunes',  'Cabeleireiro',  '21977770004', 38.0, '2025-04-20'),
    ('Vera Lopes',   'Esteticista',   '21977770005', 33.0, '2025-05-05');

INSERT INTO servico (nome, descricao, preco, duracao_minutos, ativo) VALUES
    ('Corte Feminino',  'Corte e finalização',      80.0,  60, 1),
    ('Corte Masculino', 'Corte na tesoura/máquina', 50.0,  40, 1),
    ('Manicure',        'Cutilagem e esmaltação',   45.0,  50, 1),
    ('Coloração',       'Tintura completa',        180.0, 120, 1),
    ('Hidratação',      'Tratamento capilar',       90.0,  45, 1);

-- agendamento referencia os ids 1..5 criados acima (tabelas zeradas).
-- Vera Lopes (profissional 5) é deixada sem agendamento de propósito,
-- para o bloco (6) (EXISTS) ter algo a filtrar.
INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status) VALUES
    (1, 1, 1, '2026-06-10', '09:00',  80.0, 'concluido'),
    (2, 2, 2, '2026-06-12', '10:30',  50.0, 'concluido'),
    (3, 3, 3, '2026-06-18', '14:00',  45.0, 'concluido'),
    (4, 1, 4, '2026-06-20', '11:00', 180.0, 'concluido'),
    (5, 4, 5, '2026-07-02', '15:30',  90.0, 'agendado');


-- =====================================================================
-- (4) CONSULTA MULTI-TABELA COM DADOS AGREGADOS, AGRUPADOS E FILTRADOS
-- ---------------------------------------------------------------------
-- Contexto: faturamento por profissional. Junta agendamento + profissional,
-- agrega com COUNT/SUM/AVG, agrupa por profissional e filtra os grupos.
--   WHERE    -> filtra as LINHAS antes de agrupar (só atendimentos concluídos)
--   GROUP BY -> agrupa por profissional
--   HAVING   -> filtra os GRUPOS depois de agregar (faturamento > 100)
-- Com os dados do bloco (2), só Marina Alves (profissional 1) passa do
-- HAVING, pois soma 80 + 180 = 260 em atendimentos concluídos.
-- =====================================================================
SELECT p.nome                          AS profissional,
       COUNT(*)                        AS qtd_atendimentos,
       SUM(a.valor)                    AS total_faturado,
       ROUND(AVG(a.valor)::numeric, 2) AS ticket_medio
FROM agendamento a
INNER JOIN profissional p ON p.id_profissional = a.id_profissional
WHERE a.status = 'concluido'
GROUP BY p.id_profissional, p.nome
HAVING SUM(a.valor) > 10
ORDER BY total_faturado DESC;


-- =====================================================================
-- (5) SUBCONSULTA COM OPERADOR DE COMPARAÇÃO ANY / ALL
-- ---------------------------------------------------------------------
-- Contexto: profissional(is) com a MAIOR comissão do salão. O ">= ALL"
-- exige que a comissão seja maior ou igual a TODAS as comissões da tabela
-- (inclusive a própria linha). Com os dados do bloco (2), retorna Marina
-- Alves (40.0%).
-- =====================================================================
SELECT nome, especialidade, comissao_percentual
FROM profissional
WHERE comissao_percentual >= ALL (SELECT comissao_percentual FROM profissional);

-- Variante com ANY (opcional): serviços que NÃO são o mais barato, ou
-- seja, com preço maior que ALGUM outro serviço.
-- SELECT nome, preco
-- FROM servico
-- WHERE preco > ANY (SELECT preco FROM servico);


-- =====================================================================
-- (6) SUBCONSULTA COM EXISTS
-- ---------------------------------------------------------------------
-- Contexto: profissionais que JÁ possuem pelo menos um agendamento.
-- O EXISTS é uma subconsulta CORRELACIONADA: para cada profissional,
-- verifica se existe algum agendamento com o mesmo id_profissional.
-- Com os dados do bloco (2), fica de fora só Vera Lopes (profissional 5).
-- =====================================================================
SELECT p.id_profissional, p.nome, p.especialidade
FROM profissional p
WHERE EXISTS (
    SELECT 1
    FROM agendamento a
    WHERE a.id_profissional = p.id_profissional
);

-- Variante com NOT EXISTS (opcional): serviços que NUNCA foram agendados.
-- SELECT s.id_servico, s.nome
-- FROM servico s
-- WHERE NOT EXISTS (
--     SELECT 1 FROM agendamento a WHERE a.id_servico = s.id_servico
-- );
