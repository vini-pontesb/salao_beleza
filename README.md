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

## Pré-requisitos

- Node.js 18 ou superior e npm.
- Um projeto no [Supabase](https://supabase.com) com o schema de
  `database/schema.sql` já aplicado (SQL Editor).
- A *connection string* do banco (**Project Settings → Database →
  Connection pooling**), no formato:
  `postgresql://postgres.<ref>:<senha>@aws-<n>-<regiao>.pooler.supabase.com:5432/postgres`

## Como instalar e rodar

### 1. Banco de dados
Se o schema ainda não existir no projeto Supabase, rode o conteúdo de
`database/schema.sql` no SQL Editor (cria as 4 tabelas e insere os dados
de teste).

### 2. Back-end
```bash
cd backend
npm install
cp .env.example .env      # depois edite com a sua DATABASE_URL e a porta
npm start                 # ou: npm run dev (reinicia sozinho ao salvar)
```
A API sobe em `http://localhost:3001`. Para conferir a conexão e as 4
consultas exigidas direto no terminal, sem precisar do front-end:
```bash
npm run db:consultas
```
Para resetar os dados de teste no Supabase a partir do zero (**atenção:
apaga e recria as 4 tabelas**):
```bash
npm run db:init
```

### 3. Front-end
```bash
cd frontend
npm install
npm run dev
```
Acesse o endereço mostrado pelo Vite (normalmente `http://localhost:5173`).
As chamadas para `/api/...` são encaminhadas para o back-end (ver
`frontend/vite.config.js`).

## Telas da aplicação

A navegação tem três seções, acessíveis pelo menu no topo:

- **Clientes** — formulário de cadastro/edição (nome, telefone, e-mail,
  data de nascimento) e a lista de clientes com ações de **Editar** e
  **Excluir**. Exclusão bloqueada com aviso amigável quando o cliente tem
  agendamento vinculado (integridade referencial).
- **Agendamentos** — formulário com seleção de cliente, profissional e
  serviço (o valor é preenchido automaticamente com o preço do serviço
  escolhido, mas pode ser ajustado), data, hora e status; abaixo, a agenda
  completa com nomes já resolvidos via `INNER JOIN` e uma etiqueta colorida
  por status (agendado / concluído / cancelado).
- **Consultas** — as 4 consultas exigidas pelo trabalho, cada uma em seu
  próprio cartão com filtro e botão "Pesquisar": cliente por nome, agenda
  por profissional, agenda por período de datas e clientes que nunca
  agendaram (subconsulta `NOT IN`).

## Funcionalidades exigidas

- CRUD completo de **clientes** e **agendamentos**
- Consulta de cliente por nome
- Consulta com INNER JOIN (agendamentos por profissional e por período)
- Consulta com subconsulta NOT IN (clientes sem agendamento)
- Tratamento de integridade referencial (FK RESTRICT)

Ver detalhes em [`CLAUDE.md`](./CLAUDE.md), [`docs/requisitos.md`](./docs/requisitos.md)
e o modelo lógico das tabelas em [`docs/modelo-logico.md`](./docs/modelo-logico.md).
