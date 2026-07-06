// =====================================================================
// routes/profissionais.js — leitura de profissionais.
// Usado para preencher o dropdown do formulário de agendamento.
// =====================================================================
const express = require('express');
const db = require('../db');
const router = express.Router();

// GET /api/profissionais — LISTAR (SELECT)
router.get('/', (req, res) => {
  const lista = db.prepare(
    `SELECT id_profissional, nome, especialidade, telefone,
            comissao_percentual, data_admissao
       FROM profissional
      ORDER BY nome`
  ).all();
  res.json(lista);
});

// GET /api/profissionais/:id — um por id
router.get('/:id', (req, res) => {
  const p = db.prepare('SELECT * FROM profissional WHERE id_profissional = ?')
    .get(req.params.id);
  if (!p) return res.status(404).json({ erro: 'Profissional não encontrado.' });
  res.json(p);
});

module.exports = router;
