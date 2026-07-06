-- =====================================================================
-- Sistema de Agendamento de Salão de Beleza
-- Trabalho Prático de Banco de Dados I - IFRJ Campus Niterói
-- Grupo: Vinicius Pontes e Jean Macedo
-- SGBD: PostgreSQL (Supabase)
-- =====================================================================

-- No PostgreSQL as chaves estrangeiras são SEMPRE validadas — não existe
-- o PRAGMA foreign_keys do SQLite.

-- ---------------------------------------------------------------------
-- Remoção (ordem importa por causa das FKs: filhos antes dos pais)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS agendamento;
DROP TABLE IF EXISTS servico;
DROP TABLE IF EXISTS profissional;
DROP TABLE IF EXISTS cliente;

-- ---------------------------------------------------------------------
-- Tabela: cliente  (campos textuais, numéricos e de data)
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente       SERIAL PRIMARY KEY,
    nome             TEXT NOT NULL,
    telefone         TEXT,
    email            TEXT UNIQUE,
    data_nascimento  DATE,
    data_cadastro    DATE NOT NULL DEFAULT CURRENT_DATE
);

-- ---------------------------------------------------------------------
-- Tabela: profissional
-- ---------------------------------------------------------------------
CREATE TABLE profissional (
    id_profissional      SERIAL PRIMARY KEY,
    nome                 TEXT NOT NULL,
    especialidade        TEXT,
    telefone             TEXT,
    comissao_percentual  NUMERIC(5,2) NOT NULL DEFAULT 0,
    data_admissao        DATE
);

-- ---------------------------------------------------------------------
-- Tabela: servico
-- ---------------------------------------------------------------------
CREATE TABLE servico (
    id_servico       SERIAL PRIMARY KEY,
    nome             TEXT NOT NULL,
    descricao        TEXT,
    preco            NUMERIC(10,2) NOT NULL,
    duracao_minutos  INTEGER,
    ativo            SMALLINT NOT NULL DEFAULT 1   -- 1 = ativo, 0 = inativo
);

-- ---------------------------------------------------------------------
-- Tabela: agendamento  (possui as 3 chaves estrangeiras)
--
-- Regras de integridade referencial escolhidas:
--   ON DELETE RESTRICT  -> não permite excluir cliente/profissional/
--                          serviço que já tenha agendamento vinculado,
--                          preservando o histórico do salão.
--   ON UPDATE CASCADE   -> se um id de referência mudar, propaga.
-- ---------------------------------------------------------------------
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
-- DADOS DE TESTE
-- =====================================================================

INSERT INTO cliente (nome, telefone, email, data_nascimento, data_cadastro) VALUES
    ('Ana Souza',        '21988880001', 'ana.souza@email.com',    '1995-03-12', '2026-01-10'),
    ('Bruno Lima',       '21988880002', 'bruno.lima@email.com',   '1988-07-25', '2026-02-05'),
    ('Carla Mendes',     '21988880003', 'carla.mendes@email.com', '2000-11-30', '2026-02-20'),
    ('Diego Rocha',      '21988880004', 'diego.rocha@email.com',  '1992-05-08', '2026-03-01'),
    ('Elaine Ferreira',  '21988880005', 'elaine.f@email.com',     '1998-09-14', '2026-03-15'),
    ('Fabio Nogueira',   '21988880006', 'fabio.n@email.com',      '1985-01-22', '2026-04-02'); -- nunca agendou

INSERT INTO profissional (nome, especialidade, telefone, comissao_percentual, data_admissao) VALUES
    ('Marina Alves',   'Cabeleireira', '21977770001', 40.0, '2024-06-01'),
    ('Rafael Dias',    'Barbeiro',     '21977770002', 35.0, '2025-01-15'),
    ('Sofia Ramos',    'Manicure',     '21977770003', 30.0, '2025-03-10');

INSERT INTO servico (nome, descricao, preco, duracao_minutos, ativo) VALUES
    ('Corte Feminino',   'Corte e finalização',        80.0,  60, 1),
    ('Corte Masculino',  'Corte na tesoura/máquina',   50.0,  40, 1),
    ('Manicure',         'Cutilagem e esmaltação',     45.0,  50, 1),
    ('Coloração',        'Tintura completa',          180.0, 120, 1),
    ('Hidratação',       'Tratamento capilar',         90.0,  45, 0); -- inativo, nunca agendado

INSERT INTO agendamento (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status) VALUES
    (1, 1, 1, '2026-06-10', '09:00', 80.0,  'concluido'),
    (1, 3, 3, '2026-06-18', '14:00', 45.0,  'concluido'),
    (2, 2, 2, '2026-06-12', '10:30', 50.0,  'concluido'),
    (3, 1, 4, '2026-06-20', '11:00', 180.0, 'agendado'),
    (4, 2, 2, '2026-07-01', '16:00', 50.0,  'agendado'),
    (5, 1, 1, '2026-07-02', '15:30', 80.0,  'agendado'),
    (2, 3, 3, '2026-07-05', '13:00', 45.0,  'agendado');

-- =====================================================================
-- CONSULTAS EXIGIDAS PELO TRABALHO (testar todas antes do front-end)
-- =====================================================================

-- (1) CONSULTA EM UMA TABELA — cliente por nome (parâmetro de filtro)
--     Ex.: buscar "ana". ILIKE é a busca "case-insensitive" do PostgreSQL
--     (o LIKE puro diferencia maiúsculas/minúsculas, ao contrário do SQLite).
SELECT *
FROM cliente
WHERE nome ILIKE '%ana%';

-- (2) CONSULTA COM INNER JOIN — agendamentos de um profissional
--     Retorna cliente, serviço, data e valor dos agendamentos de um profissional
SELECT p.nome  AS profissional,
       c.nome  AS cliente,
       s.nome  AS servico,
       a.data_agendamento,
       a.hora,
       a.valor,
       a.status
FROM agendamento a
INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
INNER JOIN profissional p ON p.id_profissional = a.id_profissional
INNER JOIN servico      s ON s.id_servico      = a.id_servico
WHERE p.id_profissional = 1;

-- (3) CONSULTA COM INNER JOIN — agendamentos em um período de datas
SELECT c.nome  AS cliente,
       c.telefone,
       s.nome  AS servico,
       a.data_agendamento,
       a.valor
FROM agendamento a
INNER JOIN cliente c ON c.id_cliente = a.id_cliente
INNER JOIN servico s ON s.id_servico = a.id_servico
WHERE a.data_agendamento BETWEEN '2026-07-01' AND '2026-07-31'
ORDER BY a.data_agendamento;

-- (4) CONSULTA COM SUBCONSULTA (NOT IN) — clientes que NUNCA agendaram
SELECT *
FROM cliente
WHERE id_cliente NOT IN (
    SELECT id_cliente FROM agendamento
);

-- (4-bis, opcional) SERVIÇOS que nunca foram agendados (outra subconsulta NOT IN)
SELECT *
FROM servico
WHERE id_servico NOT IN (
    SELECT id_servico FROM agendamento
);
