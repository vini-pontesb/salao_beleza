# Evidências geradas no Supabase

Saídas dos scripts rodados no banco real (projeto `salao-agendamento`), pelo
SQL Editor do Supabase, seguindo a Parte 2 do
[`database/apd3/README.md`](../../../database/apd3/README.md).

| Arquivo | Script | O que mostra |
|---|---|---|
| `01_diagnostico_antes.csv` | `00_diagnostico.sql` | Estado da base como ficou na APD1 |
| `02_01_perfis_e_usuarios.csv` | `01_perfis_e_usuarios.sql` | Perfis e usuários criados |
| `02_02_integridade.csv` | `02_integridade.sql` | Restrições da APD1 e da APD3 |
| `02_03_auditoria.csv` | `03_auditoria.sql` | Gatilhos de auditoria instalados |
| `02_04_visoes.csv` | `04_visoes.sql` | Views de relatório e de agenda |
| `02_05_privilegios.csv` | `05_privilegios.sql` | Matriz de privilégios por perfil |
| `02_06_rls.csv` | `06_rls.sql` | Políticas de linha por tabela |
| `02_07_administracao.csv` | `07_administracao.sql` | Limites e parâmetros de cada conta |
| `03_diagnostico_depois.csv` | `00_diagnostico.sql` | Mesmo diagnóstico, depois da APD3 |
| `04_testes_acesso_e_operacao.csv` | `90_testes_acesso_e_operacao.sql` | Testes de acesso e operação por perfil |
| `05_inventario.csv` | `91_inventario.sql` | Configuração completa lida do catálogo |
| `print_diagnostico_depois.png` | `00_diagnostico.sql` | Tela do diagnóstico depois |
| `print_testes_resumo.png` | `90_testes_acesso_e_operacao.sql` | Linha de resumo dos testes |
| `print_security_advisor.png` | painel do Supabase | Security Advisor depois dos scripts |

Os prints não mostram o endereço do projeto, chaves da API nem senhas.
