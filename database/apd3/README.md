# APD3 · Scripts de administração, segurança e integridade

Scripts da APD3, aplicados sobre a base criada na APD1 e nas rotinas da APD2.
A descrição e a justificativa de cada mecanismo estão na seção 4 de
[`docs/Documentacao_Tecnica_BDII.docx`](../../docs/Documentacao_Tecnica_BDII.docx)
e, em detalhe, em
[`docs/apd3_politicas_administracao_seguranca_integridade.md`](../../docs/apd3_politicas_administracao_seguranca_integridade.md).

| Script | O que faz |
|---|---|
| `00_diagnostico.sql` | Diagnóstico de segurança e integridade, antes e depois (não altera nada) |
| `01_perfis_e_usuarios.sql` | Item (i): 6 perfis, 6 usuários e o vínculo usuário → profissional |
| `02_integridade.sql` | 8 restrições `CHECK` novas, validadas contra os dados existentes |
| `03_auditoria.sql` | Trilha de auditoria somente inclusão e inventário de privilégios |
| `04_visoes.sql` | Views de relatório (sem dado pessoal) e da agenda do profissional |
| `05_privilegios.sql` | Item (ii): API do Supabase fechada; privilégios por perfil, tabela, coluna e rotina |
| `06_rls.sql` | Item (ii): políticas de linha (RLS) por perfil |
| `07_administracao.sql` | Limite de conexões, validade e parâmetros de sessão das contas |
| `90_testes_acesso_e_operacao.sql` | Item (iv): 97 testes de acesso e operação por perfil (nada fica gravado) |
| `91_inventario.sql` | Item (iv): inventário da configuração para a revisão de acessos (não altera nada) |
| `99_reverter.sql` | Plano de volta: devolve a base ao estado da APD2 |
| `ambiente-local/` | Reprodução local do Supabase e da base, usada para gerar `evidencias/apd3/local/` |

## Como aplicar no Supabase

1. Abra o projeto `salao-agendamento` no Supabase e vá em **SQL Editor**.
2. Para cada script, na ordem da tabela abaixo: **New query**, cole o conteúdo
   do arquivo e clique em **Run**.
3. Se aparecer a janela **Potential issues detected**, clique em **Run without
   RLS**. Não use "Run and enable RLS": ela acrescenta um comando que esconde o
   resultado e bloqueia a leitura da trilha de auditoria.
4. No resultado, use **Export → Download CSV** e salve o arquivo em
   `evidencias/apd3/supabase/` com o nome indicado.

| Passo | Script | O que esperar | Salvar como |
|---|---|---|---|
| 1 | `00_diagnostico.sql` | Linhas `RISCO`, `ATENÇÃO` e `PENDENTE` (é o "antes") | `01_diagnostico_antes.csv` |
| 2 | `01_perfis_e_usuarios.sql` | 12 linhas: 6 perfis e 6 usuários, sem atributo privilegiado | `02_01_perfis_e_usuarios.csv` |
| 3 | `02_integridade.sql` | 46 restrições; as 8 da APD3 com `validada = true` | `02_02_integridade.csv` |
| 4 | `03_auditoria.sql` | 18 gatilhos de auditoria | `02_03_auditoria.csv` |
| 5 | `04_visoes.sql` | 6 views (5 em `relatorios`, 1 em `agenda`) | `02_04_visoes.csv` |
| 6 | `05_privilegios.sql` | Matriz com 17 linhas, uma por tabela ou view | `02_05_privilegios.csv` |
| 7 | `06_rls.sql` | 34 políticas, `rls_ligado = true` em todas as tabelas | `02_06_rls.csv` |
| 8 | `07_administracao.sql` | 6 contas com limite, validade e parâmetros | `02_07_administracao.csv` |
| 9 | `00_diagnostico.sql` (de novo) | Tudo `OK` ou `INFO` | `03_diagnostico_depois.csv` |
| 10 | `90_testes_acesso_e_operacao.sql` | Última linha: **97 de 97 casos passaram** | `04_testes_acesso_e_operacao.csv` |
| 11 | `91_inventario.sql` | Inventário com cerca de 80 linhas | `05_inventario.csv` |

| Mensagem | O que fazer |
|---|---|
| `Banco errado: ...` | O projeto aberto não é o do salão. Nada foi alterado. |
| `Papel errado: ...` | Escolha o papel `postgres` no SQL Editor. Nada foi alterado. |
| NOTICE `Restrição ... NÃO VALIDADA` | Há linhas antigas fora da regra; a restrição já vale para dados novos e o passo 9 mostra quantas linhas corrigir. |
| Qualquer outro erro | Nada foi aplicado daquele script (ele roda numa transação só). |

Os scripts 01 a 07 são idempotentes: podem ser rodados de novo sem erro.

## Observações

- **Aplicação web:** o back-end (`backend/db.js`) conecta como `postgres`,
  dono das tabelas, então continua funcionando depois da APD3. O passo
  seguinte recomendado é dar a ele uma conta própria com privilégio mínimo.
- **Recriar a base:** o `database/01_criacao_tabelas.sql` (e o
  `npm run db:init`) apaga e recria as tabelas, levando junto gatilhos,
  políticas, views e privilégios da APD3. Depois de recriar a base, rode
  `99_reverter.sql` e, em seguida, de novo os scripts 01 a 07 da APD3.
- **Senhas:** as contas nascem sem senha (ninguém entra com elas). Para usar
  uma conta, o DBA define a senha pelo `psql`, com `\password nome_da_conta`,
  que não deixa a senha no histórico. Nunca grave senhas no repositório.
