// =====================================================================
// routes/profissionais.js — leitura de profissionais.
// Usado para preencher o dropdown do formulário de agendamento.
// =====================================================================
const express = require('express');
const pool = require('../db');
const router = express.Router();

// GET /api/profissionais — LISTAR (SELECT)
router.get('/', async (req, res, next) => {
  try {
    const result = await pool.query(
      `SELECT id_profissional, nome, especialidade, telefone,
              comissao_percentual, data_admissao
         FROM profissional
        ORDER BY nome`
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// GET /api/profissionais/:id — um por id
router.get('/:id', async (req, res, next) => {
  try {
    const result = await pool.query(
      'SELECT * FROM profissional WHERE id_profissional = $1',
      [req.params.id]
    );
    const p = result.rows[0];
    if (!p) return res.status(404).json({ erro: 'Profissional não encontrado.' });
    res.json(p);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
