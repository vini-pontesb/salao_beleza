// =====================================================================
// scripts/demo-consultas.js
// Executa as 4 consultas exigidas pelo trabalho e imprime os resultados,
// para conferência antes de construir o back-end/front-end.
//
// Uso:  npm run db:consultas   (a partir da pasta backend/)
// =====================================================================
const path = require('path');
const Database = require('better-sqlite3');

const DB_PATH = path.join(__dirname, '..', '..', 'database', 'salao.db');
const db = new Database(DB_PATH, { readonly: true });
db.pragma('foreign_keys = ON');

function titulo(t) {
  console.log('\n' + '='.repeat(72));
  console.log(t);
  console.log('='.repeat(72));
}

// ---------------------------------------------------------------------
// (1) CONSULTA EM UMA TABELA — cliente por nome (SELECT + WHERE + LIKE)
// ---------------------------------------------------------------------
titulo("(1) Cliente por nome  ->  WHERE nome LIKE '%ana%'");
console.table(
  db.prepare(
    `SELECT id_cliente, nome, telefone, email
       FROM cliente
      WHERE nome LIKE ?`
  ).all('%ana%')
);

// ---------------------------------------------------------------------
// (2) INNER JOIN — agendamentos de um profissional (id = 1)
// ---------------------------------------------------------------------
titulo('(2) INNER JOIN  ->  agendamentos do profissional id=1 (Marina Alves)');
console.table(
  db.prepare(
    `SELECT p.nome AS profissional, c.nome AS cliente, s.nome AS servico,
            a.data_agendamento, a.hora, a.valor, a.status
       FROM agendamento a
       INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
       INNER JOIN profissional p ON p.id_profissional = a.id_profissional
       INNER JOIN servico      s ON s.id_servico      = a.id_servico
      WHERE p.id_profissional = ?`
  ).all(1)
);

// ---------------------------------------------------------------------
// (3) INNER JOIN — agendamentos em um período de datas (BETWEEN)
// ---------------------------------------------------------------------
titulo('(3) INNER JOIN  ->  agendamentos entre 2026-07-01 e 2026-07-31');
console.table(
  db.prepare(
    `SELECT c.nome AS cliente, c.telefone, s.nome AS servico,
            a.data_agendamento, a.valor
       FROM agendamento a
       INNER JOIN cliente c ON c.id_cliente = a.id_cliente
       INNER JOIN servico s ON s.id_servico = a.id_servico
      WHERE a.data_agendamento BETWEEN ? AND ?
      ORDER BY a.data_agendamento`
  ).all('2026-07-01', '2026-07-31')
);

// ---------------------------------------------------------------------
// (4) SUBCONSULTA (NOT IN) — clientes que NUNCA agendaram
// ---------------------------------------------------------------------
titulo('(4) Subconsulta NOT IN  ->  clientes que nunca agendaram');
console.table(
  db.prepare(
    `SELECT id_cliente, nome, email
       FROM cliente
      WHERE id_cliente NOT IN (SELECT id_cliente FROM agendamento)`
  ).all()
);

db.close();
