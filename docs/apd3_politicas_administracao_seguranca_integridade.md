# Políticas de Administração, Segurança e Integridade da Base de Dados

Base de dados do salão de beleza (APD1) · PostgreSQL 17 no Supabase · APD3

Este documento detalha a seção 4 (APD3) da documentação técnica da base
(`docs/Documentacao_Tecnica_BDII.docx`). Ele descreve cada mecanismo de
administração, segurança e integridade adotado, explica por que ele é
necessário e aponta o script que o implementa e a evidência de que funciona.

## 1. Contexto

A base da APD1 guarda a operação de um salão de beleza em 7 tabelas do schema
`public`: `cliente`, `profissional`, `servico`, `agendamento`, `pagamento`,
`produto` e `venda_produto`, com cerca de 50 linhas cada. As regras de negócio
já estão no banco: chaves e restrições `CHECK`, um índice que impede dois
atendimentos do mesmo profissional no mesmo horário, três gatilhos (agenda,
pagamento e estoque), três funções e três procedimentos.

A base está no Supabase (projeto `salao-agendamento`, PostgreSQL 17.6). O
diagnóstico feito antes da APD3 (`database/apd3/00_diagnostico.sql`) encontrou:

| Situação encontrada | Risco |
|---|---|
| As roles da API automática do Supabase (`anon`, `authenticated`, `service_role`) tinham `ALL` nas 7 tabelas | A chave `anon` é pública por definição. Só o RLS impedia a leitura de nome, telefone, e-mail e data de nascimento dos clientes; a `service_role` ignora o RLS |
| Tabelas novas criadas no `public` nasciam abertas para a API (privilégios padrão do Supabase) | Qualquer tabela futura ficaria exposta até alguém lembrar de fechá-la |
| RLS ligado nas 7 tabelas, mas nenhuma política | Ninguém além do dono (`postgres`) via linha alguma: não havia como dar acesso controlado a outra pessoa |
| As 9 rotinas executáveis por qualquer usuário (`PUBLIC`) e sem `search_path` fixo | Qualquer conta chamaria `fn_comissao_profissional` ou `sp_cancelar_agendamentos_expirados`; sem `search_path` fixo, uma rotina pode ser desviada para um objeto falso (aviso do Security Advisor do Supabase) |
| Um único usuário, `postgres`, dono de tudo | Sem separação de funções e sem como saber quem fez o quê |
| Nenhuma trilha de auditoria | Impossível responder "quem deu esse desconto?" ou "quem cancelou esse horário?" |
| Nomes em branco, telefone e código de barras sem formato | Dados inválidos entrariam sem aviso |

Princípios que orientam as políticas:

- **Privilégio mínimo:** cada conta recebe só o que a sua função no salão exige.
- **Defesa em profundidade:** o mesmo dado é protegido por mais de uma camada
  (privilégio de tabela e de coluna, RLS, views, sessão somente leitura).
- **Separação de funções:** quem opera não audita; quem audita não opera; quem
  faz backup só lê.
- **Minimização (LGPD, art. 6º, III):** cada perfil vê só o dado pessoal de que
  precisa; a trilha de auditoria não copia valores.
- **Rastreabilidade:** toda alteração nas tabelas fica registrada.
- **Tudo como código:** cada mecanismo é um script versionado, idempotente e
  reversível.

## 2. Visão geral dos mecanismos

| # | Mecanismo | Tipo | Script |
|---|---|---|---|
| 1 | 6 perfis (papéis de grupo) e 6 usuários, um perfil por usuário | Segurança / administração | `01_perfis_e_usuarios.sql` |
| 2 | Vínculo usuário do banco → profissional do salão | Segurança | `01_perfis_e_usuarios.sql` |
| 3 | 8 restrições `CHECK` novas, validadas contra os dados existentes | Integridade | `02_integridade.sql` |
| 4 | Trilha de auditoria somente inclusão, com retenção de 12 meses | Segurança / administração | `03_auditoria.sql` |
| 5 | Inventário de privilégios para revisão periódica | Administração | `03_auditoria.sql`, `91_inventario.sql` |
| 6 | Views de relatório sem dado pessoal e view da agenda do profissional | Segurança | `04_visoes.sql` |
| 7 | API automática do Supabase fechada | Segurança | `05_privilegios.sql` |
| 8 | Privilégios por perfil, por tabela e por coluna | Segurança | `05_privilegios.sql` |
| 9 | Rotinas: `EXECUTE` só para quem usa, `search_path` fixo, `SECURITY DEFINER` só onde é preciso | Segurança / integridade | `05_privilegios.sql` |
| 10 | Privilégios padrão para objetos futuros | Administração | `05_privilegios.sql` |
| 11 | Políticas de linha (RLS) por perfil | Segurança / integridade | `06_rls.sql` |
| 12 | Parâmetros de sessão, limite de conexões e validade das contas | Administração | `07_administracao.sql` |
| 13 | Diagnóstico antes/depois, testes de acesso e operação, inventário | Evidência | `00`, `90`, `91` |
| 14 | Plano de volta | Administração | `99_reverter.sql` |
| 15 | Trava contra aplicação no banco errado ou com o papel errado | Administração | `01` a `07` e `99` |
| 16 | Backup lógico com conta própria e teste de restauração | Administração | seção 6.4 |

## 3. Usuários, perfis e privilégios

### 3.1 Modelo adotado

O PostgreSQL não distingue usuário de grupo: os dois são "roles". A política é:

- **Perfil** = role `NOLOGIN`. Agrupa os privilégios de uma função do salão.
  Ninguém conecta com ele.
- **Usuário** = role `LOGIN INHERIT`, membro de **um** perfil, de quem herda os
  privilégios. Nenhum privilégio é concedido direto a um usuário.
- Nenhum perfil ou usuário tem `SUPERUSER`, `CREATEROLE`, `CREATEDB`,
  `REPLICATION` ou `BYPASSRLS`.
- As contas nascem **sem senha** (`PASSWORD NULL`), o que impede o login. O
  DBA define a senha fora do repositório, só quando a conta for usada.

Justificativa: conceder ao perfil e não à pessoa torna a gestão simples e
auditável. Para dar acesso a uma recepcionista nova basta
`GRANT perfil_recepcao TO ...`; para tirar, `REVOKE` ou `DROP ROLE`, sem
caçar privilégios espalhados. Com uma conta por pessoa, a trilha de auditoria
diz quem fez cada alteração.

### 3.2 Perfis e usuários

| Perfil | Usuário de exemplo | Quem usa | Pode | Não pode |
|---|---|---|---|---|
| `perfil_gerente` | `gerente_salao` | Gerência do salão | Ler e alterar todos os dados de negócio; definir preços e comissões; rodar todas as funções e procedimentos; ler relatórios | DDL (`CREATE`, `ALTER`, `DROP`), `TRUNCATE`, criar usuários, ler ou alterar a trilha de auditoria |
| `perfil_recepcao` | `recepcao_salao` | Balcão | Cadastrar e corrigir clientes; marcar, remarcar e cancelar agendamentos; registrar pagamentos e vendas; concluir atendimentos por `sp_concluir_atendimento`; consultar horário livre | Excluir qualquer coisa; ver comissão e admissão dos profissionais; digitar valor de agendamento, valor pago ou preço de venda; alterar preços; concluir atendimento sem registrar o pagamento |
| `perfil_profissional` | `profissional_salao` | Cada profissional | Ver só a própria agenda (RLS e `agenda.vw_minha_agenda`); concluir só os próprios atendimentos; ver serviços e produtos ativos | Ver agenda de outro profissional, dados de contato de cliente, valores, pagamentos; cancelar ou remarcar |
| `perfil_relatorios` | `analista_salao` | Relatórios gerenciais | Ler as 5 views do schema `relatorios` | Ler qualquer tabela; alterar qualquer coisa |
| `perfil_auditoria` | `auditor_salao` | Auditoria | Ler a trilha de alterações e o inventário de privilégios | Ler ou alterar dados do negócio; apagar ou alterar a trilha |
| `perfil_backup` | `backup_salao` | Rotina de cópia de segurança | Ler todas as tabelas (inclusive a trilha) para o `pg_dump` | Qualquer escrita |

O dono das tabelas, `postgres`, continua sendo a conta do DBA: aplica os
scripts e faz manutenção. Ele não é usado no dia a dia.

### 3.3 Matriz de privilégios

Resumo do que o script 05 concede (a matriz completa, lida do catálogo, está
em `evidencias/apd3/local/02_aplicacao_scripts_01_a_07.txt` e no inventário).
`S` = `SELECT`, `I` = `INSERT`, `U` = `UPDATE`, `D` = `DELETE`; colunas entre
parênteses quando o privilégio é só em parte da tabela.

| Objeto | Gerente | Recepção | Profissional | Relatórios | Auditoria | Backup |
|---|---|---|---|---|---|---|
| `cliente` | S I U D | S I U | - | - | - | S |
| `profissional` | S I U D | S (id, nome, especialidade, telefone) | - | - | - | S |
| `servico` | S I U D | S | S (RLS: ativos) | - | - | S |
| `produto` | S I U D | S | S (RLS: ativos) | - | - | S |
| `agendamento` | S I U D | S; I e U (todas menos `valor`) | S (todas menos `valor`; RLS: os seus); U (`status`; RLS: os seus, só para concluir) | - | - | S |
| `pagamento` | S I U D | S; I (todas menos `valor_pago`) | - | - | - | S |
| `venda_produto` | S I U D | S; I (todas menos `valor_unitario`) | - | - | - | S |
| `relatorios.*` (5 views) | S | - | - | S | - | - |
| `agenda.vw_minha_agenda` | - | - | S | - | - | - |
| `auditoria.*` (trilha e 2 views) | - | - | - | - | S | S |
| `seguranca.usuario_profissional` | S I U D | - | S (RLS: a sua linha) | - | - | S |

Nenhum perfil tem `TRUNCATE`, `REFERENCES`, `TRIGGER` ou `CREATE` em schema.

Os privilégios por **coluna** são o que garante, por exemplo, que a recepção
nunca veja a comissão de um profissional e que nenhum valor em dinheiro seja
digitado por ela: o valor do agendamento vem do preço do serviço, o valor pago
é calculado como valor do atendimento menos desconto e o preço da venda vem do
cadastro do produto, tudo pelos gatilhos da APD1.

### 3.4 Funções e procedimentos

| Rotina | Quem executa | Modo | Por quê |
|---|---|---|---|
| `fn_horario_disponivel` | gerente, recepção | invoker | Consulta da agenda no balcão |
| `sp_concluir_atendimento` | gerente, recepção | **definer** | Conclui e registra o pagamento numa só operação; a recepção não pode marcar `concluido` direto |
| `fn_total_gasto_cliente` | gerente | invoker | Informação financeira do cliente |
| `fn_comissao_profissional` | gerente | invoker | Remuneração |
| `sp_repor_estoque` | gerente | invoker | Movimenta estoque |
| `sp_cancelar_agendamentos_expirados` | gerente | invoker | Altera muitos agendamentos de uma vez |
| `fn_trg_agendamento_regras`, `fn_trg_pagamento_valida`, `fn_trg_venda_estoque` | ninguém (são gatilhos) | **definer** | A regra precisa valer para qualquer perfil sem dar a ele acesso direto às tabelas que ela mexe (ex.: a venda baixa o estoque em `produto`, onde a recepção não tem `UPDATE`) |
| `seguranca.id_profissional_atual` | profissional | invoker | Base do RLS da agenda |

Todas as rotinas ganharam `search_path` fixo (`public, pg_temp`). Sem isso, uma
rotina `SECURITY DEFINER` pode ser enganada por quem crie um objeto com o mesmo
nome de uma tabela num schema que venha antes no caminho; `pg_temp` por último
fecha também a área temporária. É a recomendação da documentação do PostgreSQL
para funções `SECURITY DEFINER` e o aviso "Function Search Path Mutable" do
Security Advisor do Supabase.

## 4. Segurança

### 4.1 API automática do Supabase fechada

O Supabase publica as tabelas do schema `public` por uma API REST e GraphQL. As
requisições anônimas rodam como `anon`, as autenticadas como `authenticated` e
as feitas com a chave secreta como `service_role`, que ignora o RLS. Por padrão
o Supabase concede `ALL` a essas três roles em toda tabela que o `postgres`
cria no `public`.

O script 05 revoga esses privilégios nas tabelas, sequências e rotinas
existentes e nos privilégios padrão (objetos futuros). Justificativa: o projeto
não usa essa API, e a chave `anon` fica dentro de qualquer aplicação que a use.
Nenhuma funcionalidade é perdida: com RLS ligado e sem políticas, a API já
devolvia zero linhas. O que muda é que a proteção deixa de depender de uma
única camada. Os schemas criados na APD3 (`relatorios`, `agenda`, `auditoria`,
`seguranca`) não são publicados pela API.

### 4.2 Row Level Security (RLS)

O RLS decide **quais linhas** cada perfil alcança, depois que o `GRANT` decidiu
**quais tabelas e colunas**. As políticas do script 06:

| Tabela | Perfil | Comando | Regra |
|---|---|---|---|
| todas as 7 e o vínculo | gerente | todos | todas as linhas |
| todas as 7 e o vínculo | backup | `SELECT` | todas as linhas |
| `cliente` | recepção | `SELECT`, `INSERT`, `UPDATE` | todas as linhas |
| `profissional`, `servico`, `produto`, `pagamento`, `venda_produto` | recepção | `SELECT` | todas as linhas |
| `agendamento` | recepção | `SELECT` | todas as linhas |
| `agendamento` | recepção | `INSERT` | só com `status = 'agendado'` |
| `agendamento` | recepção | `UPDATE` | só linhas `agendado`, e o resultado só pode ser `agendado` (remarcar) ou `cancelado` |
| `pagamento`, `venda_produto` | recepção | `INSERT` | o gatilho da APD1 valida |
| `agendamento` | profissional | `SELECT` | `id_profissional` = o profissional do usuário conectado |
| `agendamento` | profissional | `UPDATE` | só os seus, só de `agendado` para `concluido` |
| `servico` | profissional | `SELECT` | `ativo = 1` |
| `produto` | profissional | `SELECT` | `ativo` |
| `seguranca.usuario_profissional` | profissional | `SELECT` | só a própria linha |

Como o RLS sabe quem é o profissional: a tabela `seguranca.usuario_profissional`
liga cada usuário do banco a um `id_profissional`, e a função
`seguranca.id_profissional_atual()` devolve o profissional do usuário
conectado. A política usa `(SELECT seguranca.id_profissional_atual())`, para a
função rodar uma vez por consulta e não uma vez por linha.

O dono das tabelas fica fora do RLS (não se usa `FORCE ROW LEVEL SECURITY`):
é com os privilégios dele que rodam as views e as rotinas `SECURITY DEFINER`,
e é ele que aplica os scripts.

Justificativa: sem o RLS, a única forma de impedir que um profissional veja a
agenda dos colegas seria criar uma view por profissional. O RLS aplica a regra
em qualquer consulta, inclusive nas escritas: a recepção não consegue gravar um
agendamento já "concluído" para fugir do registro de pagamento, e o
profissional não consegue cancelar um atendimento.

### 4.3 Views como camada de acesso

| View | Para quem | O que mostra | O que esconde |
|---|---|---|---|
| `relatorios.vw_faturamento_mensal` | gerente, relatórios | Receita de serviços e produtos e descontos por mês | Clientes e pagamentos individuais |
| `relatorios.vw_servicos_mais_realizados` | gerente, relatórios | Atendimentos concluídos, cancelamentos e receita por serviço | Clientes |
| `relatorios.vw_ocupacao_profissionais` | gerente, relatórios | Atendimentos por profissional e mês | Comissão (dado de remuneração) |
| `relatorios.vw_produtos_estoque_baixo` | gerente, relatórios | Produtos ativos no estoque mínimo ou abaixo | - |
| `relatorios.vw_clientes_novos_por_mes` | gerente, relatórios | Quantidade de clientes novos por mês | Qualquer dado individual |
| `agenda.vw_minha_agenda` | profissional | Os próprios atendimentos, com o **primeiro nome** do cliente | Telefone, e-mail, nascimento, valores e a agenda dos colegas |

As views pertencem ao `postgres` e leem as tabelas com os privilégios dele; o
perfil precisa apenas de `SELECT` na view. Todas são `security_barrier`, o que
impede que uma função escrita por quem consulta rode antes do filtro da view e
vaze linhas.

Justificativa: relatório gerencial não precisa de dado pessoal. Dar ao analista
uma view agregada, em vez das tabelas, cumpre a minimização da LGPD e reduz o
estrago de uma senha vazada.

### 4.4 Rotinas sob controle

- `EXECUTE` revogado de `PUBLIC` em todas as rotinas do `public` e dos schemas
  novos; cada perfil recebe só as que usa (seção 3.4). As rotinas criadas
  depois pelo `postgres` também nascem sem `EXECUTE` para `PUBLIC`.
- `search_path` fixo em todas as rotinas.
- `SECURITY DEFINER` só em quatro rotinas da APD1 (os três gatilhos e
  `sp_concluir_atendimento`) e na função da trilha de auditoria. As demais
  rodam com o privilégio de quem chama.

### 4.5 Trilha de auditoria

O schema `auditoria` guarda, em `auditoria.registro_alteracao`, uma linha para
cada inclusão, alteração ou exclusão nas 7 tabelas e no vínculo usuário →
profissional. Cada linha registra:

- **quem:** usuário da sessão (`session_user`) e papel em vigor (`SET ROLE`);
- **quando:** momento exato (`clock_timestamp()`) e número da transação;
- **de onde:** aplicação (`application_name`) e IP do cliente;
- **o quê:** tabela, operação, chave da linha e, em alterações, os **nomes**
  das colunas que mudaram.

Os **valores** não são gravados. Uma trilha com valores seria uma segunda
cópia do telefone, do e-mail e da data de nascimento dos clientes, sem
controle de acesso próprio e guardada por mais tempo. Os nomes das colunas
bastam para a investigação; o valor atual está na tabela.

A trilha é somente inclusão: um gatilho recusa `UPDATE`, `DELETE` e `TRUNCATE`
até para o dono da tabela. A função de gravação é `SECURITY DEFINER`, porque
nenhum perfil tem `INSERT` na trilha, e assim ninguém consegue forjar um
registro. A retenção é de 12 meses; só `auditoria.expurgar_registros_antigos()`,
executável apenas pelo DBA, apaga registros mais antigos que isso.

Justificativa: a trilha responde perguntas que o salão terá (quem deu um
desconto, quem cancelou um horário, quem mudou um preço ou uma comissão), cobre
o que foi feito por qualquer caminho (SQL Editor, scripts, conexões diretas) e
é exigência de rastreabilidade para dados pessoais.

### 4.6 Autenticação e senhas

- `password_encryption = scram-sha-256` (padrão do Supabase), conferido pelo
  diagnóstico.
- Nenhuma senha no repositório: as contas nascem sem senha.
- A senha é definida pelo DBA no `psql`, com `\password nome_da_conta`, que não
  deixa a senha no histórico. No SQL Editor do Supabase, o comando
  `ALTER ROLE ... PASSWORD` ficaria salvo no histórico de consultas.
- Contas de pessoas expiram (`VALID UNTIL`, fim do semestre) e são revistas
  antes de renovar.

### 4.7 Trava contra aplicação no lugar errado

Os scripts 01 a 07 e o 99 começam conferindo se o banco tem as tabelas do salão
e se a sessão é do dono delas. Se não, param com uma mensagem clara antes de
alterar qualquer coisa. Como o SQL Editor roda o texto inteiro numa só
transação, nada fica aplicado pela metade.

## 5. Integridade

### 5.1 Mecanismos que vêm da APD1

| Mecanismo | Onde | O que garante |
|---|---|---|
| 7 chaves primárias | todas as tabelas | Cada linha é única e endereçável |
| 7 chaves estrangeiras | `agendamento`, `pagamento`, `venda_produto` | Não existe agendamento de cliente, profissional ou serviço inexistente. `ON DELETE RESTRICT` impede apagar quem tem histórico; `ON DELETE SET NULL` em `venda_produto.id_profissional` preserva a venda se o profissional sair |
| 5 `UNIQUE` | e-mail do cliente, nome do serviço, código de barras, nome e marca do produto, um pagamento por agendamento | Sem cadastro duplicado e sem pagamento em dobro |
| 19 `CHECK` | todas as tabelas | Domínios válidos: status, categorias, formas de pagamento, valores positivos, hora `HH:MM`, comissão entre 0 e 100, parcelas só no crédito |
| Índice único parcial `uq_agendamento_horario_profissional` | `agendamento` | Um profissional não tem dois atendimentos ativos no mesmo horário |
| Gatilho `trg_agendamento_regras` | `agendamento` | Valor vem do preço do serviço; serviço inativo não é agendado; horário não se sobrepõe a outro (considerando a duração); atendimento pago não volta atrás |
| Gatilho `trg_pagamento_valida` | `pagamento` | Só se paga atendimento concluído; valor pago = valor - desconto; desconto não passa do valor |
| Gatilho `trg_venda_estoque` | `venda_produto` | Estoque nunca fica negativo; produto inativo não é vendido; estorno devolve ao estoque |
| `SELECT ... FOR UPDATE` nas rotinas | gatilhos e procedimentos | Duas operações simultâneas não usam o mesmo horário nem a mesma unidade do estoque |

### 5.2 Restrições novas da APD3

| Restrição | Regra | Justificativa |
|---|---|---|
| `ck_cliente_nome_preenchido`, `ck_profissional_nome_preenchido`, `ck_servico_nome_preenchido` | `btrim(nome) <> ''` | O `NOT NULL` da APD1 aceita `'   '`: um cliente ou serviço "sem nome" aparece em branco na agenda e nos relatórios |
| `ck_produto_nome_preenchido` | nome e marca não vazios | Nome e marca formam a chave natural do produto (`uq_produto_nome_marca`) |
| `ck_cliente_telefone_formato`, `ck_profissional_telefone_formato` | só dígitos, espaço, `( ) + -`, de 8 a 20 caracteres | O telefone é o principal meio de confirmar horário; texto livre como "ligar depois" não serve para contato |
| `ck_produto_codigo_barras` | exatamente 13 dígitos (EAN-13) | `char(13)` completa com espaços, então um código curto entraria sem erro |
| `ck_agendamento_concluido_com_valor` | `status <> 'concluido' OR valor IS NOT NULL` | O valor do atendimento concluído é a base do pagamento e da comissão. O gatilho da APD1 já preenche o valor; a restrição garante a regra mesmo quando o gatilho é desligado numa carga de dados |

Cada restrição é criada `NOT VALID` (rápido, sem travar a tabela enquanto lê
tudo) e depois validada contra as linhas existentes. Se alguma linha antiga
estiver fora da regra, a restrição continua valendo para os dados novos, o
script avisa e o diagnóstico mostra quantas linhas corrigir. Nenhum dado é
alterado automaticamente.

### 5.3 Integridade garantida pelo controle de acesso

Parte da integridade vem da combinação de privilégio por coluna, RLS e
gatilhos:

- Nenhum valor em dinheiro é digitado pela recepção: o privilégio por coluna
  deixa de fora `agendamento.valor`, `pagamento.valor_pago` e
  `venda_produto.valor_unitario`, e os gatilhos da APD1 preenchem esses valores
  a partir do cadastro.
- A recepção não marca um atendimento como concluído sem registrar o pagamento
  (RLS); o caminho é `sp_concluir_atendimento`, que faz as duas coisas na mesma
  transação.
- O profissional só conclui o que é dele e só de `agendado` para `concluido`.
- Nada é excluído por quem atende: exclusões ficam com a gerência e passam pela
  trilha de auditoria.

## 6. Administração

### 6.1 Parâmetros de cada conta

| Usuário | Conexões | Validade | `statement_timeout` | Ociosa em transação | Somente leitura | `search_path` |
|---|---|---|---|---|---|---|
| `gerente_salao` | 3 | 31/03/2027 | 60 s | 5 min | não | `public` |
| `recepcao_salao` | 5 | 31/03/2027 | 30 s | 2 min | não | `public` |
| `profissional_salao` | 2 | 31/03/2027 | 30 s | 2 min | não | `agenda, public` |
| `analista_salao` | 2 | 31/03/2027 | 60 s | 5 min | **sim** | `relatorios` |
| `auditor_salao` | 2 | 31/03/2027 | 60 s | 5 min | **sim** | `auditoria` |
| `backup_salao` | 2 | sem expiração | sem limite | 10 min | **sim** | `public` |

Justificativas:

- O **limite de conexões** impede que uma conta comprometida ou um programa com
  defeito esgote as conexões do plano gratuito do Supabase.
- O **tempo máximo por consulta** derruba consultas descontroladas antes que
  pesem para todos. A conta de backup não tem limite porque o `pg_dump` lê
  tabelas inteiras.
- O **tempo máximo ocioso em transação** derruba sessões esquecidas no meio de
  uma transação, que seguram travas de linha (por exemplo, a trava de
  `FOR UPDATE` do profissional durante um agendamento).
- **Somente leitura** nas contas que só leem é uma segunda barreira: mesmo que
  um privilégio de escrita sobre por engano, a escrita é recusada.
- A **validade** força a revisão semestral das contas de pessoas.

### 6.2 Ciclo de vida das contas

1. **Criação:** pelo script 01 (ou pelo modelo comentado nele), sempre como
   membro de um único perfil, sem senha. Se for profissional, uma linha em
   `seguranca.usuario_profissional`.
2. **Ativação:** o DBA define a senha com `\password` e a entrega à pessoa por
   um canal seguro.
3. **Revisão semestral:** antes de `VALID UNTIL`, o DBA roda o script 91,
   confere cada conta com a gerência e renova ou remove.
4. **Desligamento:** no mesmo dia, `ALTER ROLE nome NOLOGIN` (ou `DROP ROLE`) e
   remoção do vínculo. A trilha de auditoria guarda o histórico.
5. Contas nunca são compartilhadas: cada pessoa tem a sua.

### 6.3 Revisão de acessos

O script `91_inventario.sql` lista, direto do catálogo, usuários, perfis,
privilégios em schemas, tabelas, colunas e sequências, privilégios padrão,
políticas de RLS, restrições, gatilhos e rotinas. As views
`auditoria.vw_privilegios` e `auditoria.vw_usuarios_e_perfis` dão o mesmo
retrato ao auditor, que não tem acesso aos dados. A revisão é semestral e
também depois de qualquer mudança de estrutura.

### 6.4 Backup e recuperação

O plano gratuito do Supabase não inclui backups automáticos, e a documentação
do Supabase recomenda exportar o banco regularmente e guardar a cópia fora da
plataforma. A política adotada:

- **Como:** `pg_dump` lógico com a conta `backup_salao`, que só lê. Como as
  tabelas têm RLS, o `pg_dump` exige `--enable-row-security`; a política
  `pol_backup_leitura_total` faz a cópia sair completa.
- **Quando:** semanal e antes de qualquer mudança de estrutura.
- **Onde:** fora do Supabase, em pelo menos dois lugares (regra 3-2-1).
  Arquivos de backup nunca vão para o repositório: contêm dados pessoais.
- **Retenção:** 4 cópias semanais e 3 mensais.
- **Teste:** restauração mensal num banco de teste, conferindo a contagem de
  linhas de cada tabela.

```bash
pg_dump "postgresql://backup_salao@HOST:5432/postgres" \
  --enable-row-security --schema=public --schema=auditoria --schema=seguranca \
  -Fc -f salao_$(date +%Y%m%d).dump
```

### 6.5 Gestão de mudanças

- Toda mudança de segurança é um script versionado no GitHub, revisado antes
  de aplicar.
- Os scripts são **idempotentes**: rodar de novo não duplica nada nem dá erro
  (evidência `08_idempotencia_e_reversao.txt`).
- Cada script roda numa única transação: ou aplica tudo, ou nada.
- O script `99_reverter.sql` desfaz a APD3 e devolve a base ao estado da APD1,
  sem reabrir a API do Supabase.
- Ordem de aplicação: 00 (antes), 01 a 07, 00 (depois), 90, 91.

### 6.6 Monitoramento

- `database/apd3/00_diagnostico.sql`, rodado depois de cada mudança, aponta `RISCO`,
  `ATENÇÃO` ou `PENDENTE` em qualquer regressão (tabela nova sem RLS, rotina
  aberta, privilégio da API devolvido).
- O **Security Advisor** do painel do Supabase (Advisors → Security Advisor)
  é conferido depois de cada mudança.
- A trilha de auditoria é revista pelo auditor no fechamento de cada mês.

## 7. Evidências

| Arquivo | Prova |
|---|---|
| `evidencias/apd3/local/00_ambiente.txt` | Versões e dados usados nos testes locais |
| `evidencias/apd3/local/01_diagnostico_antes.txt` | Estado da base como ficou na APD1 |
| `evidencias/apd3/local/02_aplicacao_scripts_01_a_07.txt` | Saída de cada script: usuários e perfis criados, restrições, gatilhos, views, matriz de privilégios, políticas e parâmetros |
| `evidencias/apd3/local/03_diagnostico_depois.txt` | Mesmo diagnóstico depois da APD3: tudo `OK` |
| `evidencias/apd3/local/04_testes_acesso_e_operacao.txt` | 97 testes de acesso e operação, por perfil, todos aprovados |
| `evidencias/apd3/local/05_inventario.txt` | Configuração completa lida do catálogo |
| `evidencias/apd3/local/06_testes_de_login.txt` | Login real: conta sem senha e conta expirada recusadas, parâmetros de sessão, `SET ROLE` negado, RLS do profissional, sessão somente leitura, limite de conexões |
| `evidencias/apd3/local/07_backup_e_restauracao.txt` | `pg_dump` com `backup_salao` e restauração conferida tabela a tabela |
| `evidencias/apd3/local/08_idempotencia_e_reversao.txt` | Reaplicação sem erro, reversão completa e reaplicação |
| `evidencias/apd3/supabase/` | As mesmas saídas, geradas no banco real do Supabase |

As evidências locais foram geradas por `database/apd3/ambiente-local/executar_local.sh` num
PostgreSQL que reproduz as roles e os privilégios padrão do Supabase, com a
estrutura exata da APD1 (`database/apd3/ambiente-local/estrutura_apd1.sql`) e dados
fictícios. As do Supabase seguem o `database/apd3/README.md`.

## 8. Limitações e próximos passos

- `profissional_salao` é uma conta de exemplo ligada a um profissional. Em uso
  real, cada profissional terá a sua conta (modelo comentado no script 01).
- Se o salão passar a usar a API do Supabase (um aplicativo de agendamento
  online, por exemplo), será preciso conceder privilégios específicos a
  `authenticated` e escrever políticas de RLS com `auth.uid()`; o script 05 não
  deve ser simplesmente desfeito.
- A trilha registra o que muda, não o que é lido. Registrar leituras exigiria
  a extensão `pgaudit`, com custo de armazenamento.
- O backup depende de alguém rodá-lo. Um plano pago do Supabase traria backup
  diário automático e recuperação pontual (PITR).
- Tabelas criadas por outra role que não o `postgres` não recebem os
  privilégios padrão do script 05: depois de mudanças de estrutura, rodar 05 e
  06 de novo e conferir com o 00.

## 9. Referências

- PostgreSQL 17. "Database Roles" e "Role Membership":
  <https://www.postgresql.org/docs/17/user-manag.html>
- PostgreSQL 17. "Privileges" e `GRANT`:
  <https://www.postgresql.org/docs/17/ddl-priv.html>
- PostgreSQL 17. "Row Security Policies":
  <https://www.postgresql.org/docs/17/ddl-rowsecurity.html>
- PostgreSQL 17. `CREATE FUNCTION`, seção *Writing SECURITY DEFINER Functions
  Safely*: <https://www.postgresql.org/docs/17/sql-createfunction.html>
- PostgreSQL 17. `ALTER DEFAULT PRIVILEGES`:
  <https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html>
- PostgreSQL 17. `pg_dump`: <https://www.postgresql.org/docs/17/app-pgdump.html>
- Supabase. "Postgres Roles":
  <https://supabase.com/docs/guides/database/postgres/roles>
- Supabase. "Row Level Security":
  <https://supabase.com/docs/guides/database/postgres/row-level-security>
- Supabase. "Database Backups":
  <https://supabase.com/docs/guides/platform/backups>
- Supabase. "Database Advisors":
  <https://supabase.com/docs/guides/database/database-advisors>
- Brasil. Lei nº 13.709/2018 (LGPD):
  <https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm>
