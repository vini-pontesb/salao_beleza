// =====================================================================
// routes/clientes.js — CRUD completo de cliente.
// Demonstra INSERT / UPDATE / DELETE / SELECT com SQL explícito.
// =====================================================================
const express = require('express');
const pool = require('../db');
const router = express.Router();

// ---------------------------------------------------------------------
// GET /api/clientes — LISTAR todos os clientes (SELECT)
// ---------------------------------------------------------------------
router.get('/', async (req, res, next) => {
  try {
    const result = await pool.query(
      `SELECT id_cliente, nome, telefone, email, data_nascimento, data_cadastro
         FROM cliente
        ORDER BY nome`
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// GET /api/clientes/:id — um cliente por id (SELECT + WHERE)
// ---------------------------------------------------------------------
router.get('/:id', async (req, res, next) => {
  try {
    const result = await pool.query(
      `SELECT id_cliente, nome, telefone, email, data_nascimento, data_cadastro
         FROM cliente
        WHERE id_cliente = $1`,
      [req.params.id]
    );

    const cliente = result.rows[0];
    if (!cliente) return res.status(404).json({ erro: 'Cliente não encontrado.' });
    res.json(cliente);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// POST /api/clientes — CADASTRAR novo cliente (INSERT)
// ---------------------------------------------------------------------
router.post('/', async (req, res, next) => {
  try {
    const { nome, telefone, email, data_nascimento } = req.body;

    if (!nome || !nome.trim()) {
      return res.status(400).json({ erro: 'O nome é obrigatório.' });
    }

    // INSERT explícito. data_cadastro tem DEFAULT CURRENT_DATE no schema.
    // RETURNING * já devolve o registro recém-criado (com o id gerado).
    const result = await pool.query(
      `INSERT INTO cliente (nome, telefone, email, data_nascimento)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [nome.trim(), telefone || null, email || null, data_nascimento || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// PUT /api/clientes/:id — ALTERAR cliente (UPDATE)
// ---------------------------------------------------------------------
router.put('/:id', async (req, res, next) => {
  try {
    const { nome, telefone, email, data_nascimento } = req.body;

    if (!nome || !nome.trim()) {
      return res.status(400).json({ erro: 'O nome é obrigatório.' });
    }

    const existe = await pool.query('SELECT 1 FROM cliente WHERE id_cliente = $1', [req.params.id]);
    if (existe.rows.length === 0) return res.status(404).json({ erro: 'Cliente não encontrado.' });

    // UPDATE explícito, devolvendo a linha atualizada.
    const result = await pool.query(
      `UPDATE cliente
          SET nome = $1, telefone = $2, email = $3, data_nascimento = $4
        WHERE id_cliente = $5
        RETURNING *`,
      [nome.trim(), telefone || null, email || null, data_nascimento || null, req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// DELETE /api/clientes/:id — EXCLUIR cliente (DELETE)
// Se houver agendamento vinculado, o ON DELETE RESTRICT do schema
// dispara o erro 23503, tratado no server.js com mensagem amigável (HTTP 409).
// ---------------------------------------------------------------------
router.delete('/:id', async (req, res, next) => {
  try {
    const existe = await pool.query('SELECT 1 FROM cliente WHERE id_cliente = $1', [req.params.id]);
    if (existe.rows.length === 0) return res.status(404).json({ erro: 'Cliente não encontrado.' });

    await pool.query('DELETE FROM cliente WHERE id_cliente = $1', [req.params.id]);
    res.json({ mensagem: 'Cliente excluído com sucesso.' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
