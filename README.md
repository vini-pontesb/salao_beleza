# Sistema de Agendamento de Salão de Beleza

Trabalho Prático de **Banco de Dados I** — Bacharelado em Engenharia de
Computação, IFRJ Campus Niterói.

**Grupo:** Vinicius Pontes e Jean Macedo.

Aplicação web integrada a um banco de dados relacional (PostgreSQL, no
Supabase) para gerenciar clientes, profissionais, serviços e agendamentos
de um salão de beleza.

## Tecnologias

- **Banco de dados:** PostgreSQL (Supabase), modelo relacional
- **Back-end:** Node.js + Express + `pg` (SQL explícito, sem ORM)
- **Front-end:** React (Vite) + CSS

## Estrutura

```
database/   Script SQL (estrutura + dados de teste), versão PostgreSQL
backend/    API REST em Express
frontend/   Aplicação React
docs/       Requisitos e modelo lógico
CLAUDE.md   Contexto do projeto para o Claude Code
```

## Como rodar

### Banco de dados
O schema já foi criado no Supabase pelo SQL Editor a partir de
`database/schema.sql`. Para recriá-lo do zero (reseta os dados de teste):
```bash
cd backend
npm run db:init
```

### Back-end
Crie `backend/.env` (a partir de `backend/.env.example`) com a
`DATABASE_URL` do seu projeto Supabase antes de instalar/rodar:
```bash
cd backend
npm install
npm start
```

### Front-end
```bash
cd frontend
npm install
npm run dev
```

## Funcionalidades exigidas

- CRUD completo de **clientes** e **agendamentos**
- Consulta de cliente por nome
- Consulta com INNER JOIN (agendamentos por profissional e por período)
- Consulta com subconsulta NOT IN (clientes sem agendamento)
- Tratamento de integridade referencial (FK RESTRICT)

Ver detalhes em [`CLAUDE.md`](./CLAUDE.md) e [`docs/requisitos.md`](./docs/requisitos.md).
