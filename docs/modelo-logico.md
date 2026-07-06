# Modelo Lógico

**SGBD:** PostgreSQL (Supabase). Estrutura completa em [`database/schema.sql`](../database/schema.sql).

Legenda: **PK** chave primária · **FK** chave estrangeira · **NN** not null
· **U** unique.

### cliente
| Campo | Tipo | Restrições |
|---|---|---|
| id_cliente | SERIAL | PK |
| nome | TEXT | NN |
| telefone | TEXT | |
| email | TEXT | U |
| data_nascimento | DATE | |
| data_cadastro | DATE | NN, default `CURRENT_DATE` |

### profissional
| Campo | Tipo | Restrições |
|---|---|---|
| id_profissional | SERIAL | PK |
| nome | TEXT | NN |
| especialidade | TEXT | |
| telefone | TEXT | |
| comissao_percentual | NUMERIC(5,2) | NN, default 0 |
| data_admissao | DATE | |

### servico
| Campo | Tipo | Restrições |
|---|---|---|
| id_servico | SERIAL | PK |
| nome | TEXT | NN |
| descricao | TEXT | |
| preco | NUMERIC(10,2) | NN |
| duracao_minutos | INTEGER | |
| ativo | SMALLINT | NN, default 1 (1 = ativo, 0 = inativo) |

### agendamento
| Campo | Tipo | Restrições |
|---|---|---|
| id_agendamento | SERIAL | PK |
| id_cliente | INTEGER | FK → cliente, NN |
| id_profissional | INTEGER | FK → profissional, NN |
| id_servico | INTEGER | FK → servico, NN |
| data_agendamento | DATE | NN |
| hora | TEXT | |
| valor | NUMERIC(10,2) | |
| status | TEXT | NN, default 'agendado' |

## Relacionamentos
- cliente **1 : N** agendamento
- profissional **1 : N** agendamento
- servico **1 : N** agendamento

## Regras de integridade referencial (FKs de agendamento)
- `ON DELETE RESTRICT` — impede excluir cliente/profissional/serviço que
  ainda possua agendamentos, preservando o histórico do salão. No
  PostgreSQL essa validação é sempre ativa (não depende de PRAGMA, como
  no SQLite).
- `ON UPDATE CASCADE` — propaga alteração de id referenciado.

## Notas de tipos (adaptação SQLite → PostgreSQL)
- `INTEGER PRIMARY KEY AUTOINCREMENT` → `SERIAL PRIMARY KEY` (gera a
  sequência de ids automaticamente).
- `REAL` em campos monetários (`preco`, `valor`) → `NUMERIC(10,2)`, que
  evita erro de arredondamento de ponto flutuante em valores em reais.
- `REAL` em `comissao_percentual` → `NUMERIC(5,2)`.
- `INTEGER` (0/1) em `ativo` → `SMALLINT`, mantendo a mesma convenção
  1 = ativo / 0 = inativo.
- `date('now')` (default do SQLite) → `CURRENT_DATE` (padrão SQL/PostgreSQL).
