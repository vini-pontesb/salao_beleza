# CLAUDE.md — Contexto do Projeto

> Este arquivo é lido automaticamente pelo Claude Code. Ele define o
> contexto, as regras e o padrão de qualidade esperados para todo o
> desenvolvimento deste trabalho.

## Sobre o trabalho

Trabalho Prático de **Banco de Dados I** — Bacharelado em Engenharia de
Computação, IFRJ Campus Niterói. Peso 4.0 na AV2.

**Grupo:** Vinicius Pontes e Jean Macedo.
**Sistema:** Sistema de Agendamento de Salão de Beleza.
**Objetivo:** aplicação web integrada a um SGBD relacional, demonstrando
modelagem, implementação e manipulação de banco de dados relacional.

**Prazo:** apresentação em 06/07/2026 (aula extra/remota, turno da noite).
Priorize atender 100% dos requisitos obrigatórios antes de qualquer extra.

## Stack definida

- **Banco:** SQLite (arquivo local `database/salao.db`), modelo relacional.
  - Sempre executar `PRAGMA foreign_keys = ON;` a cada conexão — sem isso
    o SQLite ignora as chaves estrangeiras.
  - O schema oficial está em `database/schema.sql`. Não divergir dele sem
    atualizar o arquivo.
- **Back-end:** Node.js + Express, usando **SQL explícito** (biblioteca
  `better-sqlite3`). Nada de ORM — as queries SQL devem ficar visíveis no
  código, pois a disciplina exige demonstrar INSERT/UPDATE/DELETE/SELECT,
  INNER JOIN e subconsultas rodando no banco.
- **Front-end:** React (Vite) + CSS. Interface adequada ao contexto de um
  salão de beleza, com boa navegabilidade.

> Se em algum momento fizer sentido trocar por PostgreSQL/Supabase, avise
> antes e ajuste o `schema.sql` correspondente.

## Modelo de dados (4 tabelas)

- **cliente** (id_cliente PK, nome, telefone, email UNIQUE, data_nascimento, data_cadastro)
- **profissional** (id_profissional PK, nome, especialidade, telefone, comissao_percentual, data_admissao)
- **servico** (id_servico PK, nome, descricao, preco, duracao_minutos, ativo)
- **agendamento** (id_agendamento PK, id_cliente FK, id_profissional FK, id_servico FK, data_agendamento, hora, valor, status)

`agendamento` é a tabela com as 3 chaves estrangeiras. Regras adotadas:
`ON DELETE RESTRICT` (preserva histórico — não deixa apagar cliente/
profissional/serviço com agendamento) e `ON UPDATE CASCADE`.

## Requisitos OBRIGATÓRIOS (checklist de correção)

Banco de dados:
- [ ] 4 tabelas relacionadas, cada uma com 5+ campos.
- [ ] Tipos textuais, numéricos e de data presentes.
- [ ] Restrições: PRIMARY KEY, FOREIGN KEY, NOT NULL, UNIQUE.
- [ ] Regras de exclusão/atualização definidas nas FKs (RESTRICT/CASCADE).
- [ ] Script SQL com estrutura + dados de teste (`database/schema.sql`).

Aplicação:
- [ ] **CRUD completo** (cadastrar, alterar, excluir, listar) para as
      tabelas **cliente** e **agendamento** — usando INSERT/UPDATE/DELETE/SELECT.
- [ ] Consulta em **uma tabela** por parâmetro: buscar cliente por nome
      (SELECT + WHERE).
- [ ] Consulta com **INNER JOIN** (duas variantes): agendamentos por
      profissional; agendamentos por período de datas.
- [ ] Consulta com **subconsulta IN / NOT IN**: clientes que nunca fizeram
      agendamento (`NOT IN`).
- [ ] Tratamento de integridade referencial no back-end (ex.: mensagem
      amigável quando `RESTRICT` bloqueia uma exclusão, em vez de erro cru).
- [ ] Interface web adequada ao contexto e com boa UX.

> A tabela de controle da turma dizia "listar agendamentos do salão inteiro"
> como consulta de subconsulta, mas isso NÃO exige IN/NOT IN. Por isso foi
> substituída por "clientes que nunca agendaram" (NOT IN), que atende o
> requisito de verdade.

## Entregáveis

1. Repositório Git com código versionado e **commits dos dois integrantes**
   (a nota individual depende da contribuição versionada de cada um).
2. Script SQL da base (estrutura + dados de teste).
3. Documento de especificação técnica (template do professor) com o
   modelo lógico das tabelas — ver `docs/modelo-logico.md`.
4. Apresentação prática (máx. 10 min, sem .ppt): objetivo, tecnologias,
   demonstração funcional e explicação técnica (conexão com o BD, CRUD e
   consultas rodando no banco). **Cada integrante deve falar.**

## Convenções de código

- Comentar as queries SQL para facilitar a explicação na apresentação.
- Nomes de tabelas/campos em português (como no schema).
- Commits pequenos e descritivos, em português. Alternar autoria entre
  os dois integrantes ao longo do projeto (usar `git config user.name`
  correto de quem estiver na máquina, ou co-author nos commits).
- Não commitar `node_modules/` nem o arquivo `.db` gerado (ver `.gitignore`).

## Estrutura de pastas alvo

```
salao-agendamento/
├── database/
│   ├── schema.sql        # estrutura + dados de teste (fonte da verdade)
│   └── salao.db          # gerado (NÃO versionar)
├── backend/              # Express + better-sqlite3 (a criar)
│   ├── server.js
│   ├── db.js             # conexão + PRAGMA foreign_keys
│   └── routes/           # cliente, profissional, servico, agendamento, consultas
├── frontend/             # React (Vite) (a criar)
│   └── src/
├── docs/
│   ├── requisitos.md
│   └── modelo-logico.md
├── CLAUDE.md
└── README.md
```
