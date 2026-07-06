// =====================================================================
// scripts/demo-consultas.js
// Executa as 4 consultas exigidas pelo trabalho e imprime os resultados,
// para conferência do back-end direto no PostgreSQL (Supabase).
//
// Uso:  npm run db:consultas   (a partir da pasta backend/)
// =====================================================================
const pool = require('../db');

function titulo(t) {
  console.log('\n' + '='.repeat(72));
  console.log(t);
  console.log('='.repeat(72));
}

async function main() {
  // ---------------------------------------------------------------------
  // (1) CONSULTA EM UMA TABELA — cliente por nome (SELECT + WHERE + ILIKE)
  // ---------------------------------------------------------------------
  titulo("(1) Cliente por nome  ->  WHERE nome ILIKE '%ana%'");
  const r1 = await pool.query(
    `SELECT id_cliente, nome, telefone, email
       FROM cliente
      WHERE nome ILIKE $1`,
    ['%ana%']
  );
  console.table(r1.rows);

  // ---------------------------------------------------------------------
  // (2) INNER JOIN — agendamentos de um profissional (id = 1)
  // ---------------------------------------------------------------------
  titulo('(2) INNER JOIN  ->  agendamentos do profissional id=1 (Marina Alves)');
  const r2 = await pool.query(
    `SELECT p.nome AS profissional, c.nome AS cliente, s.nome AS servico,
            a.data_agendamento, a.hora, a.valor, a.status
       FROM agendamento a
       INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
       INNER JOIN profissional p ON p.id_profissional = a.id_profissional
       INNER JOIN servico      s ON s.id_servico      = a.id_servico
      WHERE p.id_profissional = $1`,
    [1]
  );
  console.table(r2.rows);

  // ---------------------------------------------------------------------
  // (3) INNER JOIN — agendamentos em um período de datas (BETWEEN)
  // ---------------------------------------------------------------------
  titulo('(3) INNER JOIN  ->  agendamentos entre 2026-07-01 e 2026-07-31');
  const r3 = await pool.query(
    `SELECT c.nome AS cliente, c.telefone, s.nome AS servico,
            a.data_agendamento, a.valor
       FROM agendamento a
       INNER JOIN cliente c ON c.id_cliente = a.id_cliente
       INNER JOIN servico s ON s.id_servico = a.id_servico
      WHERE a.data_agendamento BETWEEN $1 AND $2
      ORDER BY a.data_agendamento`,
    ['2026-07-01', '2026-07-31']
  );
  console.table(r3.rows);

  // ---------------------------------------------------------------------
  // (4) SUBCONSULTA (NOT IN) — clientes que NUNCA agendaram
  // ---------------------------------------------------------------------
  titulo('(4) Subconsulta NOT IN  ->  clientes que nunca agendaram');
  const r4 = await pool.query(
    `SELECT id_cliente, nome, email
       FROM cliente
      WHERE id_cliente NOT IN (SELECT id_cliente FROM agendamento)`
  );
  console.table(r4.rows);

  await pool.end();
}

main().catch((err) => {
  console.error(err);
  pool.end();
  process.exitCode = 1;
});
