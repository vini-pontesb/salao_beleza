# Ambiente local de teste

Reproduz, num PostgreSQL local e descartável, o ponto de partida do banco do
Supabase, para testar os scripts da APD3 sem tocar no banco real. Foi com ele
que as evidências de [`evidencias/apd3/local/`](../../../evidencias/apd3/local/) foram
geradas.

| Arquivo | O que faz |
|---|---|
| `simular_supabase.sql` | Cria as roles do Supabase (`postgres` sem superusuário, `anon`, `authenticated`, `service_role`, `authenticator`), o banco `salao` e os privilégios padrão que abrem tabelas novas para a API |
| `estrutura_apd1.sql` | Estrutura exata da APD1, extraída do catálogo do Supabase: 7 tabelas, restrições, índice, 3 funções, 3 procedimentos, 3 gatilhos e RLS ligado sem políticas |
| `dados_ficticios.sql` | Dados inventados (20 clientes, 8 profissionais, 10 serviços, 20 agendamentos, 8 pagamentos, 10 produtos, 15 vendas) |
| `executar_local.sh` | Roda tudo e grava as evidências: diagnóstico antes, scripts 01 a 07, diagnóstico depois, testes, inventário, testes de login, backup e restauração, idempotência e reversão |

## Como rodar

Requisitos: PostgreSQL 15 ou mais novo (servidor e cliente), num cluster que
possa ser apagado, e Python 3 (só para gerar senhas temporárias).

No `pg_hba.conf` do cluster de teste, o superusuário, o `postgres` e o
`authenticator` entram sem senha; os demais usuários, por TCP, com senha:

```text
local   all   all                              trust
host    all   pgsuper,postgres,authenticator   127.0.0.1/32   trust
host    all   all                              127.0.0.1/32   scram-sha-256
```

```bash
SUPERUSUARIO=pgsuper PGHOST_SOCKET=/caminho/do/socket PGPORT=5432 ./executar_local.sh
```

As senhas dos testes de login são geradas na hora e não são gravadas.
