# Modelo Lógico

Legenda: **PK** chave primária · **FK** chave estrangeira · **NN** not null
· **U** unique.

### cliente
| Campo | Tipo | Restrições |
|---|---|---|
| id_cliente | INTEGER | PK, autoincremento |
| nome | TEXT | NN |
| telefone | TEXT | |
| email | TEXT | U |
| data_nascimento | DATE | |
| data_cadastro | DATE | NN, default data atual |

### profissional
| Campo | Tipo | Restrições |
|---|---|---|
| id_profissional | INTEGER | PK, autoincremento |
| nome | TEXT | NN |
| especialidade | TEXT | |
| telefone | TEXT | |
| comissao_percentual | REAL | NN, default 0 |
| data_admissao | DATE | |

### servico
| Campo | Tipo | Restrições |
|---|---|---|
| id_servico | INTEGER | PK, autoincremento |
| nome | TEXT | NN |
| descricao | TEXT | |
| preco | REAL | NN |
| duracao_minutos | INTEGER | |
| ativo | INTEGER | NN, default 1 |

### agendamento
| Campo | Tipo | Restrições |
|---|---|---|
| id_agendamento | INTEGER | PK, autoincremento |
| id_cliente | INTEGER | FK → cliente, NN |
| id_profissional | INTEGER | FK → profissional, NN |
| id_servico | INTEGER | FK → servico, NN |
| data_agendamento | DATE | NN |
| hora | TEXT | |
| valor | REAL | |
| status | TEXT | NN, default 'agendado' |

## Relacionamentos
- cliente **1 : N** agendamento
- profissional **1 : N** agendamento
- servico **1 : N** agendamento

## Regras de integridade referencial (FKs de agendamento)
- `ON DELETE RESTRICT` — impede excluir cliente/profissional/serviço que
  ainda possua agendamentos, preservando o histórico do salão.
- `ON UPDATE CASCADE` — propaga alteração de id referenciado.
