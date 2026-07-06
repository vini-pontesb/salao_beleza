// =====================================================================
// routes/servicos.js — leitura de serviços.
// Usado para preencher o dropdown do formulário de agendamento.
// =====================================================================
const express = require('express');
const db = require('../db');
const router = express.Router();

// GET /api/servicos           — todos os serviços
// GET /api/servicos?ativos=1  — apenas os serviços ativos (para novo agendamento)
router.get('/', (req, res) => {
  const somenteAtivos = req.query.ativos === '1' || req.query.ativos === 'true';
  const sql = somenteAtivos
    ? `SELECT id_servico, nome, descricao, preco, duracao_minutos, ativo
         FROM servico
        WHERE ativo = 1
        ORDER BY nome`
    : `SELECT id_servico, nome, descricao, preco, duracao_minutos, ativo
         FROM servico
        ORDER BY nome`;
  res.json(db.prepare(sql).all());
});

// GET /api/servicos/:id — um por id
router.get('/:id', (req, res) => {
  const s = db.prepare('SELECT * FROM servico WHERE id_servico = ?')
    .get(req.params.id);
  if (!s) return res.status(404).json({ erro: 'Serviço não encontrado.' });
  res.json(s);
});

module.exports = router;
