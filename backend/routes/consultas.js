// =====================================================================
// routes/consultas.js — as 4 consultas exigidas pelo trabalho.
//   (1) SELECT em uma tabela por parâmetro  -> cliente por nome
//   (2) INNER JOIN                          -> agendamentos por profissional
//   (3) INNER JOIN                          -> agendamentos por período
//   (4) SUBCONSULTA NOT IN                  -> clientes que nunca agendaram
// =====================================================================
const express = require('express');
const pool = require('../db');
const router = express.Router();

// ---------------------------------------------------------------------
// (1) CONSULTA EM UMA TABELA — cliente por nome (parâmetro de filtro)
// GET /api/consultas/clientes?nome=ana
// ---------------------------------------------------------------------
router.get('/clientes', async (req, res, next) => {
  try {
    const nome = req.query.nome || '';
    const result = await pool.query(
      `SELECT id_cliente, nome, telefone, email, data_nascimento, data_cadastro
         FROM cliente
        WHERE nome ILIKE $1
        ORDER BY nome`,
      [`%${nome}%`]
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// (2) INNER JOIN — agendamentos de um profissional
// GET /api/consultas/agendamentos-por-profissional?id_profissional=1
// ---------------------------------------------------------------------
router.get('/agendamentos-por-profissional', async (req, res, next) => {
  try {
    const id = req.query.id_profissional;
    if (!id) return res.status(400).json({ erro: 'Informe o id_profissional.' });

    const result = await pool.query(
      `SELECT p.nome AS profissional,
              c.nome AS cliente,
              s.nome AS servico,
              a.data_agendamento, a.hora, a.valor, a.status
         FROM agendamento a
         INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
         INNER JOIN profissional p ON p.id_profissional = a.id_profissional
         INNER JOIN servico      s ON s.id_servico      = a.id_servico
        WHERE p.id_profissional = $1
        ORDER BY a.data_agendamento, a.hora`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// (3) INNER JOIN — agendamentos em um período de datas
// GET /api/consultas/agendamentos-por-periodo?inicio=2026-07-01&fim=2026-07-31
// ---------------------------------------------------------------------
router.get('/agendamentos-por-periodo', async (req, res, next) => {
  try {
    const { inicio, fim } = req.query;
    if (!inicio || !fim) {
      return res.status(400).json({ erro: 'Informe início e fim no formato YYYY-MM-DD.' });
    }

    const result = await pool.query(
      `SELECT c.nome AS cliente, c.telefone,
              p.nome AS profissional,
              s.nome AS servico,
              a.data_agendamento, a.hora, a.valor, a.status
         FROM agendamento a
         INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
         INNER JOIN profissional p ON p.id_profissional = a.id_profissional
         INNER JOIN servico      s ON s.id_servico      = a.id_servico
        WHERE a.data_agendamento BETWEEN $1 AND $2
        ORDER BY a.data_agendamento, a.hora`,
      [inicio, fim]
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// (4) SUBCONSULTA NOT IN — clientes que NUNCA agendaram
// GET /api/consultas/clientes-sem-agendamento
// ---------------------------------------------------------------------
router.get('/clientes-sem-agendamento', async (req, res, next) => {
  try {
    const result = await pool.query(
      `SELECT id_cliente, nome, telefone, email, data_cadastro
         FROM cliente
        WHERE id_cliente NOT IN (SELECT id_cliente FROM agendamento)
        ORDER BY nome`
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
