// =====================================================================
// routes/consultas.js — as 4 consultas exigidas pelo trabalho.
//   (1) SELECT em uma tabela por parâmetro  -> cliente por nome
//   (2) INNER JOIN                          -> agendamentos por profissional
//   (3) INNER JOIN                          -> agendamentos por período
//   (4) SUBCONSULTA NOT IN                  -> clientes que nunca agendaram
// =====================================================================
const express = require('express');
const db = require('../db');
const router = express.Router();

// ---------------------------------------------------------------------
// (1) CONSULTA EM UMA TABELA — cliente por nome (parâmetro de filtro)
// GET /api/consultas/clientes?nome=ana
// ---------------------------------------------------------------------
router.get('/clientes', (req, res) => {
  const nome = req.query.nome || '';
  const clientes = db.prepare(
    `SELECT id_cliente, nome, telefone, email, data_nascimento, data_cadastro
       FROM cliente
      WHERE nome LIKE ?
      ORDER BY nome`
  ).all(`%${nome}%`);
  res.json(clientes);
});

// ---------------------------------------------------------------------
// (2) INNER JOIN — agendamentos de um profissional
// GET /api/consultas/agendamentos-por-profissional?id_profissional=1
// ---------------------------------------------------------------------
router.get('/agendamentos-por-profissional', (req, res) => {
  const id = req.query.id_profissional;
  if (!id) return res.status(400).json({ erro: 'Informe o id_profissional.' });

  const lista = db.prepare(
    `SELECT p.nome AS profissional,
            c.nome AS cliente,
            s.nome AS servico,
            a.data_agendamento, a.hora, a.valor, a.status
       FROM agendamento a
       INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
       INNER JOIN profissional p ON p.id_profissional = a.id_profissional
       INNER JOIN servico      s ON s.id_servico      = a.id_servico
      WHERE p.id_profissional = ?
      ORDER BY a.data_agendamento, a.hora`
  ).all(id);
  res.json(lista);
});

// ---------------------------------------------------------------------
// (3) INNER JOIN — agendamentos em um período de datas
// GET /api/consultas/agendamentos-por-periodo?inicio=2026-07-01&fim=2026-07-31
// ---------------------------------------------------------------------
router.get('/agendamentos-por-periodo', (req, res) => {
  const { inicio, fim } = req.query;
  if (!inicio || !fim) {
    return res.status(400).json({ erro: 'Informe início e fim no formato YYYY-MM-DD.' });
  }

  const lista = db.prepare(
    `SELECT c.nome AS cliente, c.telefone,
            p.nome AS profissional,
            s.nome AS servico,
            a.data_agendamento, a.hora, a.valor, a.status
       FROM agendamento a
       INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
       INNER JOIN profissional p ON p.id_profissional = a.id_profissional
       INNER JOIN servico      s ON s.id_servico      = a.id_servico
      WHERE a.data_agendamento BETWEEN ? AND ?
      ORDER BY a.data_agendamento, a.hora`
  ).all(inicio, fim);
  res.json(lista);
});

// ---------------------------------------------------------------------
// (4) SUBCONSULTA NOT IN — clientes que NUNCA agendaram
// GET /api/consultas/clientes-sem-agendamento
// ---------------------------------------------------------------------
router.get('/clientes-sem-agendamento', (req, res) => {
  const lista = db.prepare(
    `SELECT id_cliente, nome, telefone, email, data_cadastro
       FROM cliente
      WHERE id_cliente NOT IN (SELECT id_cliente FROM agendamento)
      ORDER BY nome`
  ).all();
  res.json(lista);
});

module.exports = router;
