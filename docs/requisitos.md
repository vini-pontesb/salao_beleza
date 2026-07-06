# Requisitos do Trabalho (destilados da especificação)

## Banco de dados
- Estrutura relacional para a aplicação.
- Modelo lógico apresentado no relatório técnico (campos, tipos, PK, FK).
- Mínimo de 2 tabelas relacionadas (este projeto usa 4).
- Cada tabela com no mínimo 5 campos.
- Tipos presentes: textuais, numéricos e de data.
- Restrições de integridade: PRIMARY KEY, FOREIGN KEY, NOT NULL, UNIQUE.
- Regras de atualização/exclusão nas FKs: CASCADE, RESTRICT, SET NULL ou
  NO ACTION, conforme a lógica do contexto.
- Tecnologia de BD de livre escolha (relacional). Aqui: PostgreSQL (Supabase).

## Aplicação (front-end + back-end)
- CRUD completo por interface gráfica (INSERT, UPDATE, DELETE, SELECT).
- Consulta baseada em UMA tabela, com parâmetro/filtro (SELECT + WHERE).
- Consulta com dados de DUAS OU MAIS tabelas relacionadas (INNER JOIN).
- Consulta com subconsulta usando IN / NOT IN.
- Lógica de negócio tratando integridade referencial.
- Interface adequada ao contexto e boa UX.
- Tecnologias web de livre escolha.

## Entregáveis
- Link do repositório (código versionado com contribuição de cada membro;
  configurações técnicas se necessário; script SQL com estrutura + dados).
- Documento de especificação técnica (template do professor).
- Apresentação técnica prática (máx. 10 min, sem .ppt).

## Apresentação
- Objetivo da aplicação.
- Tecnologias (front, back, BD).
- Demonstração funcional.
- Explicação técnica: conexão com o BD, CRUD e consultas rodando no banco.
- Cada integrante deve demonstrar conhecimento técnico (fala individual).

## Datas
- 01/07/2026 (após a prova prática) — já passou.
- 06/07/2026 (aula extra/remota noturna) — data alvo.
- Presença obrigatória em todas as apresentações.

## Mapeamento grupo → requisitos (linha 12 da tabela da turma)
| Requisito | Definição do grupo |
|---|---|
| Contexto | Sistema de Agendamento de Salão de Beleza |
| Tabelas | Profissional, Cliente, Agendamento, Serviço |
| CRUD (2 tabelas) | Cliente e Agendamento |
| Consulta 1 tabela | Cliente por nome |
| Consulta INNER JOIN | Agendamentos por profissional; por período de datas |
| Consulta subconsulta | Clientes que nunca agendaram (NOT IN)* |

\* Ajuste do item original "listar agendamentos do salão inteiro", que não
exigia IN/NOT IN.
