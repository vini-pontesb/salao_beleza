# Sistema de Agendamento de Salão de Beleza

Trabalho Prático de **Banco de Dados I** — Bacharelado em Engenharia de
Computação, IFRJ Campus Niterói.

**Grupo:** Vinicius Pontes e Jean Macedo.

Aplicação web integrada a um banco de dados relacional (SQLite) para
gerenciar clientes, profissionais, serviços e agendamentos de um salão de
beleza.

## Tecnologias

- **Banco de dados:** SQLite (modelo relacional)
- **Back-end:** Node.js + Express + `better-sqlite3` (SQL explícito)
- **Front-end:** React (Vite) + CSS

## Estrutura

```
database/   Script SQL (estrutura + dados de teste) e o banco gerado
backend/    API REST em Express (a ser criada com o Claude Code)
frontend/   Aplicação React (a ser criada com o Claude Code)
docs/       Requisitos e modelo lógico
CLAUDE.md   Contexto do projeto para o Claude Code
```

## Como rodar (será preenchido conforme o projeto for construído)

### Banco de dados
```bash
# Gera o banco a partir do script
sqlite3 database/salao.db < database/schema.sql
```

### Back-end
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
