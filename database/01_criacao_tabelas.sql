-- =====================================================================
-- 01_criacao_tabelas.sql
-- Projeto Integrador de Banco de Dados II (APD1) - IFRJ Campus Niterói
-- Solução: Sistema de Gestão de Salão de Beleza
-- Equipe: Jean de Pinho Macedo, Vinícius Pontes Braga e Pietro Gomes Borges
-- SGBD: PostgreSQL (Supabase)
--
-- Cria as 7 tabelas da base relacional com suas restrições
-- (PK, FK, NOT NULL, UNIQUE, CHECK e DEFAULT).
--
-- Ordem de execução dos scripts:
--   1) 01_criacao_tabelas.sql   (este arquivo)
--   2) 02_insercao_dados.sql
--   3) 03_consultas.sql
--
-- ATENÇÃO: o script é destrutivo. Os DROPs apagam as tabelas e os dados
-- existentes para recriar a base do zero.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Remoção das tabelas (tabelas filhas antes das tabelas pai)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS venda_produto CASCADE;
DROP TABLE IF EXISTS pagamento     CASCADE;
DROP TABLE IF EXISTS agendamento   CASCADE;
DROP TABLE IF EXISTS produto       CASCADE;
DROP TABLE IF EXISTS servico       CASCADE;
DROP TABLE IF EXISTS profissional  CASCADE;
DROP TABLE IF EXISTS cliente       CASCADE;

-- ---------------------------------------------------------------------
-- Tabela: cliente
-- Pessoas atendidas pelo salão (serviços e/ou compra de produtos).
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente       SERIAL       PRIMARY KEY,
    nome             TEXT         NOT NULL,
    telefone         TEXT,
    email            TEXT         UNIQUE,
    data_nascimento  DATE,
    data_cadastro    DATE         NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT ck_cliente_email      CHECK (email IS NULL OR email LIKE '%_@_%._%'),
    CONSTRAINT ck_cliente_nascimento CHECK (data_nascimento IS NULL OR data_nascimento < data_cadastro)
);

-- ---------------------------------------------------------------------
-- Tabela: profissional
-- Funcionários que executam os serviços e recebem comissão.
-- ---------------------------------------------------------------------
CREATE TABLE profissional (
    id_profissional      SERIAL        PRIMARY KEY,
    nome                 TEXT          NOT NULL,
    especialidade        TEXT,
    telefone             TEXT,
    comissao_percentual  NUMERIC(5,2)  NOT NULL DEFAULT 0,
    data_admissao        DATE,
    CONSTRAINT ck_profissional_comissao CHECK (comissao_percentual BETWEEN 0 AND 100)
);

-- ---------------------------------------------------------------------
-- Tabela: servico
-- Catálogo de serviços oferecidos pelo salão.
-- ativo: 1 = disponível para agendamento, 0 = fora do catálogo.
-- ---------------------------------------------------------------------
CREATE TABLE servico (
    id_servico       SERIAL         PRIMARY KEY,
    nome             TEXT           NOT NULL UNIQUE,
    descricao        TEXT,
    categoria        VARCHAR(30)    NOT NULL DEFAULT 'Cabelo',
    preco            NUMERIC(10,2)  NOT NULL,
    duracao_minutos  INTEGER,
    ativo            SMALLINT       NOT NULL DEFAULT 1,
    CONSTRAINT ck_servico_categoria CHECK (categoria IN ('Cabelo','Barba','Unhas','Estética','Maquiagem','Depilação')),
    CONSTRAINT ck_servico_preco     CHECK (preco > 0),
    CONSTRAINT ck_servico_duracao   CHECK (duracao_minutos IS NULL OR duracao_minutos > 0),
    CONSTRAINT ck_servico_ativo     CHECK (ativo IN (0, 1))
);

-- ---------------------------------------------------------------------
-- Tabela: produto
-- Produtos de beleza vendidos aos clientes no balcão do salão.
-- ---------------------------------------------------------------------
CREATE TABLE produto (
    id_produto      SERIAL         PRIMARY KEY,
    nome            VARCHAR(100)   NOT NULL,
    marca           VARCHAR(60)    NOT NULL,
    categoria       VARCHAR(30)    NOT NULL,
    preco_venda     NUMERIC(10,2)  NOT NULL,
    qtd_estoque     INTEGER        NOT NULL DEFAULT 0,
    estoque_minimo  INTEGER        NOT NULL DEFAULT 5,
    codigo_barras   CHAR(13)       UNIQUE,
    ativo           BOOLEAN        NOT NULL DEFAULT TRUE,
    -- um mesmo produto (nome) não se repete para a mesma marca
    CONSTRAINT uq_produto_nome_marca UNIQUE (nome, marca),
    CONSTRAINT ck_produto_categoria  CHECK (categoria IN ('Shampoo','Condicionador','Tratamento','Finalizador','Coloração','Unhas','Pele','Barba')),
    CONSTRAINT ck_produto_preco      CHECK (preco_venda > 0),
    CONSTRAINT ck_produto_estoque    CHECK (qtd_estoque >= 0 AND estoque_minimo >= 0)
);

-- ---------------------------------------------------------------------
-- Tabela: agendamento
-- Liga cliente, profissional e serviço em uma data e hora.
--
-- Regras de integridade referencial:
--   ON DELETE RESTRICT -> não permite excluir cliente, profissional ou
--                         serviço que já tenha agendamento (preserva o
--                         histórico do salão).
--   ON UPDATE CASCADE  -> se a chave referenciada mudar, a mudança é
--                         propagada para os agendamentos.
-- ---------------------------------------------------------------------
CREATE TABLE agendamento (
    id_agendamento    SERIAL         PRIMARY KEY,
    id_cliente        INTEGER        NOT NULL,
    id_profissional   INTEGER        NOT NULL,
    id_servico        INTEGER        NOT NULL,
    data_agendamento  DATE           NOT NULL,
    hora              TEXT,
    valor             NUMERIC(10,2),
    status            TEXT           NOT NULL DEFAULT 'agendado',
    CONSTRAINT fk_agendamento_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_agendamento_profissional FOREIGN KEY (id_profissional)
        REFERENCES profissional (id_profissional) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_agendamento_servico FOREIGN KEY (id_servico)
        REFERENCES servico (id_servico) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_agendamento_status CHECK (status IN ('agendado','concluido','cancelado')),
    CONSTRAINT ck_agendamento_valor  CHECK (valor IS NULL OR valor >= 0),
    CONSTRAINT ck_agendamento_hora   CHECK (hora IS NULL OR hora ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
);

-- Um profissional não pode ter dois agendamentos ativos no mesmo horário.
-- Agendamentos cancelados não ocupam o horário (índice único parcial).
CREATE UNIQUE INDEX uq_agendamento_horario_profissional
    ON agendamento (id_profissional, data_agendamento, hora)
    WHERE status <> 'cancelado';

-- ---------------------------------------------------------------------
-- Tabela: pagamento
-- Pagamento de um agendamento concluído (relação 1:1 com agendamento).
--
-- Regras de integridade referencial:
--   ON DELETE RESTRICT -> um agendamento já pago não pode ser excluído.
--   ON UPDATE CASCADE  -> propaga alteração da chave do agendamento.
-- ---------------------------------------------------------------------
CREATE TABLE pagamento (
    id_pagamento         SERIAL         PRIMARY KEY,
    id_agendamento       INTEGER        NOT NULL UNIQUE,
    forma_pagamento      VARCHAR(20)    NOT NULL,
    valor_pago           NUMERIC(10,2)  NOT NULL,
    desconto             NUMERIC(10,2)  NOT NULL DEFAULT 0,
    parcelas             SMALLINT       NOT NULL DEFAULT 1,
    data_hora_pagamento  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pagamento_agendamento FOREIGN KEY (id_agendamento)
        REFERENCES agendamento (id_agendamento) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_pagamento_forma    CHECK (forma_pagamento IN ('dinheiro','pix','debito','credito')),
    CONSTRAINT ck_pagamento_valor    CHECK (valor_pago > 0 AND desconto >= 0),
    CONSTRAINT ck_pagamento_parcelas CHECK (parcelas BETWEEN 1 AND 6
                                            AND (forma_pagamento = 'credito' OR parcelas = 1))
);

-- ---------------------------------------------------------------------
-- Tabela: venda_produto
-- Venda de produto do salão para um cliente. O profissional que indicou
-- o produto é opcional.
--
-- Regras de integridade referencial:
--   id_cliente, id_produto -> ON DELETE RESTRICT (preserva o histórico
--                             de vendas) e ON UPDATE CASCADE.
--   id_profissional        -> ON DELETE SET NULL (se o profissional sair
--                             do cadastro, a venda continua registrada,
--                             apenas sem a indicação).
-- ---------------------------------------------------------------------
CREATE TABLE venda_produto (
    id_venda         SERIAL         PRIMARY KEY,
    id_cliente       INTEGER        NOT NULL,
    id_produto       INTEGER        NOT NULL,
    id_profissional  INTEGER,
    quantidade       SMALLINT       NOT NULL DEFAULT 1,
    valor_unitario   NUMERIC(10,2)  NOT NULL,
    forma_pagamento  VARCHAR(20)    NOT NULL,
    data_venda       TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_venda_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_venda_produto FOREIGN KEY (id_produto)
        REFERENCES produto (id_produto) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_venda_profissional FOREIGN KEY (id_profissional)
        REFERENCES profissional (id_profissional) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT ck_venda_quantidade CHECK (quantidade > 0),
    CONSTRAINT ck_venda_valor      CHECK (valor_unitario > 0),
    CONSTRAINT ck_venda_forma      CHECK (forma_pagamento IN ('dinheiro','pix','debito','credito'))
);
