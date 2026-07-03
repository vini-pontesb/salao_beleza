# Prompt inicial para o Claude Code

> Cole o bloco abaixo na primeira conversa com o Claude Code (dentro desta
> pasta). O `CLAUDE.md` já dá todo o contexto; este prompt orienta a
> sequência de construção. Depois disso, vá pedindo uma etapa por vez.

---

Você está me ajudando a construir o trabalho de Banco de Dados I descrito
no `CLAUDE.md` deste repositório (Sistema de Agendamento de Salão de Beleza).
Leia o `CLAUDE.md` e o `database/schema.sql` antes de começar — eles são a
fonte da verdade sobre requisitos, modelo de dados e stack.

Quero construir em etapas, uma de cada vez, esperando eu confirmar antes de
seguir para a próxima. Não pule etapas nem gere tudo de uma vez.

**Etapa 1 — Banco de dados.**
Crie o script para gerar o arquivo SQLite `database/salao.db` a partir de
`database/schema.sql`. Depois execute as 4 consultas exigidas (busca de
cliente por nome; INNER JOIN por profissional; INNER JOIN por período;
subconsulta NOT IN de clientes sem agendamento) e me mostre os resultados,
pra eu confirmar que o banco está correto antes de irmos ao back-end.

**Etapa 2 — Back-end (Express + better-sqlite3).**
Crie o servidor Express com:
- `db.js`: conexão ao SQLite com `PRAGMA foreign_keys = ON`.
- Rotas CRUD completas para **cliente** e **agendamento** (GET listar,
  GET por id, POST inserir, PUT atualizar, DELETE excluir) usando SQL
  explícito (INSERT/UPDATE/SELECT/DELETE). Comente cada query.
- Rotas de leitura para **profissional** e **servico** (para preencher os
  formulários de agendamento).
- Rotas de consulta: (a) cliente por nome; (b) agendamentos por
  profissional; (c) agendamentos por período; (d) clientes sem agendamento.
- Tratar o erro de FK RESTRICT (ex.: tentar excluir cliente com
  agendamento) devolvendo mensagem amigável em vez de erro 500 cru.
Ao final, me mostre como testar as rotas (ex.: curl) e aguarde confirmação.

**Etapa 3 — Front-end (React + Vite).**
Interface com tema de salão de beleza, com páginas/telas para:
- CRUD de clientes (listar, cadastrar, editar, excluir).
- CRUD de agendamentos (com dropdowns de cliente/profissional/serviço
  vindos do banco).
- Telas de consulta cobrindo as 4 consultas exigidas, cada uma com seu
  campo de filtro e botão "Pesquisar".
Cuide da navegação e de uma UX simples e limpa. Mostre mensagens de erro
amigáveis (ex.: exclusão bloqueada por integridade referencial).

**Etapa 4 — Documentação e fechamento.**
- Atualize o `README.md` com instruções de instalação e execução
  (backend e frontend) e print/descrição das telas.
- Preencha o `docs/modelo-logico.md` com o modelo lógico final das tabelas.
- Faça uma revisão final contra o checklist de requisitos do `CLAUDE.md`.

Regras gerais durante todo o trabalho:
- SQL sempre explícito e comentado (a disciplina exige demonstrar as
  queries rodando no banco).
- Commits pequenos, em português, ao final de cada etapa concluída.
- Se algo do schema precisar mudar, atualize `database/schema.sql` junto.
- Sempre que terminar uma etapa, faça um resumo do que foi feito e do que
  falta, e espere minha confirmação.

Comece pela Etapa 1.
