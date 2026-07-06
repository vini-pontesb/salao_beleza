// =====================================================================
// routes/servicos.js — leitura de serviços.
// Usado para preencher o dropdown do formulário de agendamento.
// =====================================================================
const express = require('express');
const pool = require('../db');
const router = express.Router();

// GET /api/servicos           — todos os serviços
// GET /api/servicos?ativos=1  — apenas os serviços ativos (para novo agendamento)
router.get('/', async (req, res, next) => {
  try {
    const somenteAtivos = req.query.ativos === '1' || req.query.ativos === 'true';
    const sql = somenteAtivos
      ? `SELECT id_servico, nome, descricao, preco, duracao_minutos, ativo
           FROM servico
          WHERE ativo = 1
          ORDER BY nome`
      : `SELECT id_servico, nome, descricao, preco, duracao_minutos, ativo
           FROM servico
          ORDER BY nome`;
    const result = await pool.query(sql);
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// GET /api/servicos/:id — um por id
router.get('/:id', async (req, res, next) => {
  try {
    const result = await pool.query(
      'SELECT * FROM servico WHERE id_servico = $1',
      [req.params.id]
    );
    const s = result.rows[0];
    if (!s) return res.status(404).json({ erro: 'Serviço não encontrado.' });
    res.json(s);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
