#!/usr/bin/env bash
# =============================================================================
# executar_local.sh
# Reproduz, num PostgreSQL local, TODAS as evidências de evidencias/apd3/local/:
# simula o Supabase, cria a base da APD1 (estrutura_apd1.sql) com dados
# fictícios, aplica os scripts da APD3, roda diagnóstico, testes, inventário,
# testes de login, backup e restauração, idempotência e reversão.
#
# Requisitos
#   * PostgreSQL 15 ou mais novo (servidor e cliente: psql, pg_dump, pg_restore)
#     num cluster DESCARTÁVEL. O script apaga e recria o banco salao e as roles
#     postgres, anon, authenticated, service_role e authenticator.
#   * pg_hba.conf: postgres, authenticator e o superusuário entram sem senha
#     (trust); os demais usuários, por TCP, com scram-sha-256. Exemplo no
#     README desta pasta.
#
# Uso
#   SUPERUSUARIO=pgsuper PGHOST_SOCKET=/caminho/do/socket PGPORT=5432 ./executar_local.sh
#
# Nenhuma senha é gravada em arquivo: as senhas dos testes de login são
# geradas na hora e morrem com o processo.
# =============================================================================
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$AQUI/.."
EVID="$AQUI/../../../evidencias/apd3/local"
: "${SUPERUSUARIO:?defina SUPERUSUARIO (superusuário do cluster de teste)}"
: "${PGHOST_SOCKET:?defina PGHOST_SOCKET (diretório do socket do PostgreSQL)}"
: "${PGPORT:=5432}"
TCP=127.0.0.1
BANCO=salao
export PGPORT

mkdir -p "$EVID"

SCRIPTS_APD3="01_perfis_e_usuarios 02_integridade 03_auditoria 04_visoes 05_privilegios 06_rls 07_administracao"

su_sql()   { psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST_SOCKET" -U "$SUPERUSUARIO" -d "${2:-postgres}" -c "$1"; }
# Roda a partir de database/apd3/, para as mensagens do psql citarem só o nome do arquivo.
dba()      { (cd "$SCRIPTS" && psql -X -v ON_ERROR_STOP=1 -P pager=off -h "$PGHOST_SOCKET" -U postgres -d "$1" "${@:2}"); }
senha()    { python3 -c 'import secrets; print(secrets.token_urlsafe(24))'; }
cabecalho() {
  printf '%s\n' "==============================================================================="
  printf 'APD3 · Base de dados do salão de beleza · %s\n' "$1"
  printf 'Gerado em: %s (Brasília)\n' "$(TZ=America/Sao_Paulo date '+%d/%m/%Y %H:%M:%S')"
  printf 'Banco: PostgreSQL local que reproduz o Supabase (ver database/apd3/ambiente-local/README.md)\n'
  printf '%s\n' "==============================================================================="
  printf '%s\n\n' "$2"
}

echo "1/9 Limpando o cluster de teste e simulando o Supabase"
for db in "$BANCO" salao_restaurado ecosol test_ecosol ecosol_restaurado ecosol_rascunho; do
  su_sql "DROP DATABASE IF EXISTS $db WITH (FORCE);"
done
for papel in gerente_salao recepcao_salao profissional_salao analista_salao auditor_salao backup_salao apd3_expirada \
             perfil_gerente perfil_recepcao perfil_profissional perfil_relatorios perfil_auditoria perfil_backup \
             ecosol_api ecosol_relatorios ecosol_auditor ecosol_backup perfil_aplicacao perfil_leitura \
             authenticator anon authenticated service_role postgres; do
  su_sql "DROP ROLE IF EXISTS $papel;"
done
psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST_SOCKET" -U "$SUPERUSUARIO" -d postgres -f "$AQUI/simular_supabase.sql" > /dev/null

echo "2/9 Criando a base da APD1 e carregando dados fictícios"
dba "$BANCO" -q -1 -f "$AQUI/estrutura_apd1.sql" > /dev/null
dba "$BANCO" -q -1 -f "$AQUI/dados_ficticios.sql" > /dev/null 2>&1

{
  cabecalho "00 · Ambiente da execução local" \
"Versões usadas para gerar as evidências desta pasta."
  echo "Servidor:      $(dba "$BANCO" -Atc 'select version()')"
  echo "Cliente psql:  $(psql --version)"
  echo
  echo "Base da APD1 reproduzida por database/apd3/ambiente-local/estrutura_apd1.sql (tabelas do schema public):"
  dba "$BANCO" -Atc "select ' - ' || tablename from pg_tables where schemaname = 'public' order by 1"
  echo
  echo "Dados fictícios carregados (database/apd3/ambiente-local/dados_ficticios.sql):"
  dba "$BANCO" -c "select 'cliente' as tabela, count(*) as linhas from cliente union all select 'profissional', count(*) from profissional union all select 'servico', count(*) from servico union all select 'agendamento', count(*) from agendamento union all select 'pagamento', count(*) from pagamento union all select 'produto', count(*) from produto union all select 'venda_produto', count(*) from venda_produto"
} > "$EVID/00_ambiente.txt"

echo "3/9 Diagnóstico ANTES"
{ cabecalho "01 · Diagnóstico ANTES dos scripts (database/apd3/00_diagnostico.sql)" \
"Estado da base como ficou na APD1, com os privilégios padrão do Supabase reproduzidos localmente."
  dba "$BANCO" -f "00_diagnostico.sql" 2>&1; } > "$EVID/01_diagnostico_antes.txt"

echo "4/9 Aplicando os scripts 01 a 07"
{ cabecalho "02 · Aplicação dos scripts 01 a 07" \
"Cada script roda numa transação (psql -1): ou aplica tudo, ou nada. A tabela no fim de cada um é a evidência do que ele configurou."
  for f in $SCRIPTS_APD3; do
    echo; echo "########## database/apd3/$f.sql"; dba "$BANCO" -1 -f "$f.sql" 2>&1
  done; } > "$EVID/02_aplicacao_scripts_01_a_07.txt"

echo "5/9 Diagnóstico DEPOIS, testes e inventário"
{ cabecalho "03 · Diagnóstico DEPOIS dos scripts (database/apd3/00_diagnostico.sql)" \
"Mesmo diagnóstico do arquivo 01, depois dos scripts 01 a 07."
  dba "$BANCO" -f "00_diagnostico.sql" 2>&1; } > "$EVID/03_diagnostico_depois.txt"
{ cabecalho "04 · Testes de acesso e operação (database/apd3/90_testes_acesso_e_operacao.sql)" \
"Cada caso assume um papel, tenta a operação e compara com o esperado. Nada fica gravado."
  dba "$BANCO" -f "90_testes_acesso_e_operacao.sql" 2>&1; } > "$EVID/04_testes_acesso_e_operacao.txt"
{ cabecalho "05 · Inventário da configuração (database/apd3/91_inventario.sql)" \
"Usuários, perfis, privilégios, políticas, restrições, gatilhos e rotinas, lidos do catálogo."
  dba "$BANCO" -f "91_inventario.sql" 2>&1; } > "$EVID/05_inventario.txt"

echo "6/9 Testes com login de verdade"
S_REC="$(senha)"; S_PRO="$(senha)"; S_ANA="$(senha)"; S_BKP="$(senha)"; S_EXP="$(senha)"
dba "$BANCO" -q -c "ALTER ROLE recepcao_salao PASSWORD '$S_REC'" -c "ALTER ROLE profissional_salao PASSWORD '$S_PRO'" \
  -c "ALTER ROLE analista_salao PASSWORD '$S_ANA'" -c "ALTER ROLE backup_salao PASSWORD '$S_BKP'" \
  -c "CREATE ROLE apd3_expirada LOGIN PASSWORD '$S_EXP' VALID UNTIL '2020-01-01'" > /dev/null
como() { local u="$1" s="$2"; shift 2; PGPASSWORD="$s" psql -X -P pager=off -h "$TCP" -U "$u" -d "$BANCO" "$@" 2>&1 || true; }
# Um agendamento futuro do profissional da conta de exemplo e um de outro profissional.
ID_PROPRIO=$(dba "$BANCO" -Atc "select min(a.id_agendamento) from agendamento a join seguranca.usuario_profissional up on up.id_profissional = a.id_profissional where up.usuario = 'profissional_salao' and a.status = 'agendado'")
ID_OUTRO=$(dba "$BANCO" -Atc "select min(a.id_agendamento) from agendamento a where a.status = 'agendado' and a.data_agendamento >= current_date and a.id_profissional <> (select id_profissional from seguranca.usuario_profissional where usuario = 'profissional_salao')")
{
  cabecalho "06 · Testes com login de verdade (usuário e senha, por TCP)" \
"Parte dos mecanismos só vale no login (parâmetros de sessão, senha, validade, limite de conexões, SET ROLE). As senhas foram geradas na hora e não estão gravadas em lugar nenhum. Alterações feitas aqui rodam entre BEGIN e ROLLBACK."
  echo "--- 6.1 auditor_salao ainda não recebeu senha: o login é recusado"
  PGPASSWORD="qualquer-coisa" psql -X -h "$TCP" -U auditor_salao -d "$BANCO" -c "select 1" 2>&1 || true
  echo
  echo "--- 6.2 Conta expirada (VALID UNTIL no passado) não entra, mesmo com a senha certa"
  como apd3_expirada "$S_EXP" -c "select 1"
  echo
  echo "--- 6.3 recepcao_salao entra e recebe os parâmetros do script 07"
  como recepcao_salao "$S_REC" -c "select current_user, session_user" -c "show search_path" -c "show statement_timeout" -c "show idle_in_transaction_session_timeout"
  echo "--- 6.4 recepcao_salao não consegue virar o DBA nem a gerência (SET ROLE)"
  como recepcao_salao "$S_REC" -c "set role postgres" -c "set role gerente_salao"
  echo
  echo "--- 6.5 recepcao_salao conclui um atendimento pelo procedimento (o pagamento sai com o valor do agendamento)"
  como recepcao_salao "$S_REC" -c "begin" -c "call sp_concluir_atendimento($ID_OUTRO, 'pix')" \
    -c "select a.id_agendamento, a.status, p.valor_pago, p.forma_pagamento from agendamento a join pagamento p using (id_agendamento) where a.id_agendamento = $ID_OUTRO" \
    -c "rollback"
  echo "--- 6.6 recepcao_salao tenta ver a comissão dos profissionais"
  como recepcao_salao "$S_REC" -c "select nome, comissao_percentual from profissional limit 1"
  echo
  echo "--- 6.7 profissional_salao vê a própria agenda (view pelo search_path) e só os próprios agendamentos (RLS)"
  como profissional_salao "$S_PRO" -c "show search_path" -c "select * from vw_minha_agenda order by data_agendamento, hora" \
    -c "select count(*) as agendamentos_visiveis from agendamento"
  echo "--- 6.8 profissional_salao conclui o próprio atendimento, mas não alcança o de outro profissional"
  como profissional_salao "$S_PRO" -c "begin" \
    -c "update agendamento set status = 'concluido' where id_agendamento = $ID_PROPRIO" \
    -c "update agendamento set status = 'concluido' where id_agendamento = $ID_OUTRO" \
    -c "rollback"
  echo
  echo "--- 6.9 analista_salao entra em modo somente leitura e usa as views pelo search_path"
  como analista_salao "$S_ANA" -c "show default_transaction_read_only" -c "show search_path" \
    -c "select * from vw_faturamento_mensal order by mes" -c "create temp table rascunho (x int)"
  echo "--- 6.10 analista_salao tenta ler clientes"
  como analista_salao "$S_ANA" -c "select count(*) from public.cliente"
  echo
  echo "--- 6.11 Limite de conexões: backup_salao aceita no máximo 2 sessões simultâneas"
  PGPASSWORD="$S_BKP" psql -X -h "$TCP" -U backup_salao -d "$BANCO" -qc "select pg_sleep(4)" > /dev/null 2>&1 &
  PGPASSWORD="$S_BKP" psql -X -h "$TCP" -U backup_salao -d "$BANCO" -qc "select pg_sleep(4)" > /dev/null 2>&1 &
  sleep 1.5
  echo "(duas sessões abertas; abrindo a terceira)"
  como backup_salao "$S_BKP" -c "select 'terceira sessão'"
  wait
  echo
  echo "--- 6.12 O que a API automática do Supabase faz: entra como authenticator e assume anon"
  psql -X -P pager=off -h "$TCP" -U authenticator -d "$BANCO" -c "set role anon" -c "select count(*) from public.cliente" 2>&1 || true
} > "$EVID/06_testes_de_login.txt"
dba "$BANCO" -q -c "DROP ROLE apd3_expirada" > /dev/null

echo "7/9 Backup com backup_salao e restauração"
{
  cabecalho "07 · Cópia de segurança (pg_dump com backup_salao) e teste de restauração" \
"A conta de backup só lê. Com RLS ligado, o pg_dump precisa de --enable-row-security; sem a opção, ele se recusa a gerar uma cópia que poderia sair incompleta."
  echo "--- 7.1 pg_dump SEM --enable-row-security (recusado de propósito pelo pg_dump)"
  PGPASSWORD="$S_BKP" pg_dump -h "$TCP" -U backup_salao -d "$BANCO" -Fc -f /tmp/apd3_sem_rls.dump 2>&1 || true
  echo
  echo "--- 7.2 pg_dump COM --enable-row-security"
  PGPASSWORD="$S_BKP" pg_dump -h "$TCP" -U backup_salao -d "$BANCO" --enable-row-security -Fc -f /tmp/apd3_backup.dump 2>&1 && \
    echo "OK: cópia gerada ($(du -h /tmp/apd3_backup.dump | cut -f1))"
  echo
  echo "--- 7.3 Restauração num banco novo e conferência das contagens"
  su_sql "CREATE DATABASE salao_restaurado OWNER postgres;"
  pg_restore -h "$PGHOST_SOCKET" -U postgres -d salao_restaurado --no-owner --no-privileges /tmp/apd3_backup.dump 2>&1 | grep -v "^$" || true
  for t in public.cliente public.profissional public.servico public.agendamento public.pagamento public.produto \
           public.venda_produto seguranca.usuario_profissional auditoria.registro_alteracao; do
    a=$(dba "$BANCO" -Atc "select count(*) from $t"); b=$(dba salao_restaurado -Atc "select count(*) from $t")
    printf '%-32s original=%-4s restaurado=%-4s %s\n' "$t" "$a" "$b" "$([ "$a" = "$b" ] && echo OK || echo DIFERENTE)"
  done
  echo
  echo "--- 7.4 backup_salao não consegue alterar nada (sessão somente leitura + sem privilégio)"
  como backup_salao "$S_BKP" -c "delete from public.pagamento"
  rm -f /tmp/apd3_backup.dump /tmp/apd3_sem_rls.dump
} > "$EVID/07_backup_e_restauracao.txt"
su_sql "DROP DATABASE IF EXISTS salao_restaurado WITH (FORCE);"

echo "8/9 Idempotência"
{
  cabecalho "08 · Idempotência e reversão" \
"Os scripts podem ser rodados de novo sem erro; o 99 desfaz tudo; reaplicar volta ao mesmo estado."
  echo "--- 8.1 Segunda aplicação dos scripts 01 a 07 sobre o banco já configurado (nenhum erro esperado)"
  for f in $SCRIPTS_APD3; do
    if dba "$BANCO" -q -1 -f "$f.sql" > /dev/null 2>/tmp/apd3_err.txt; then echo "OK   $f.sql"; else echo "ERRO $f.sql"; cat /tmp/apd3_err.txt; fi
  done
} > "$EVID/08_idempotencia_e_reversao.txt" 2>&1

echo "9/9 Reversão e reaplicação"
{
  echo
  echo "--- 8.2 Reversão (database/apd3/99_reverter.sql): o que sobra da APD3 depois dela (deve vir vazio)"
  dba "$BANCO" -1 -f "99_reverter.sql" 2>&1 | grep -v -E "NOTICE|DETAIL|^drop cascades|^(and|cascade)" || true
  echo
  echo "--- 8.3 Diagnóstico depois da reversão: de volta ao estado da APD1 (resumo por situação)"
  dba "$BANCO" -q -f "00_diagnostico.sql" | grep -E "^ (Funções|RLS|Auditoria|Views) " || true
  echo
  echo "--- 8.4 Reaplicação dos scripts 01 a 07 depois da reversão, e os testes de novo"
  for f in $SCRIPTS_APD3; do
    if dba "$BANCO" -q -1 -f "$f.sql" > /dev/null 2>/tmp/apd3_err.txt; then echo "OK   $f.sql"; else echo "ERRO $f.sql"; cat /tmp/apd3_err.txt; fi
  done
  dba "$BANCO" -q -f "90_testes_acesso_e_operacao.sql" | grep "RESUMO"
  echo
  echo "As contas recriadas nascem sem senha, como manda o script 01: as senhas temporárias dos testes de login deixaram de existir com a reversão."
} >> "$EVID/08_idempotencia_e_reversao.txt" 2>&1
rm -f /tmp/apd3_err.txt

echo "Pronto. Evidências em $EVID"
