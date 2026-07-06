// =====================================================================
// routes/clientes.js — CRUD completo de cliente.
// Demonstra INSERT / UPDATE / DELETE / SELECT com SQL explícito.
// =====================================================================
const express = require('express');
const db = require('../db');
const router = express.Router();

// ---------------------------------------------------------------------
// GET /api/clientes — LISTAR todos os clientes (SELECT)
// ---------------------------------------------------------------------
router.get('/', (req, res) => {
  const clientes = db.prepare(
    `SELECT id_cliente, nome, telefone, email, data_nascimento, data_cadastro
       FROM cliente
      ORDER BY nome`
  ).all();
  res.json(clientes);
});

// ---------------------------------------------------------------------
// GET /api/clientes/:id — um cliente por id (SELECT + WHERE)
// ---------------------------------------------------------------------
router.get('/:id', (req, res) => {
  const cliente = db.prepare(
    `SELECT id_cliente, nome, telefone, email, data_nascimento, data_cadastro
       FROM cliente
      WHERE id_cliente = ?`
  ).get(req.params.id);

  if (!cliente) return res.status(404).json({ erro: 'Cliente não encontrado.' });
  res.json(cliente);
});

// ---------------------------------------------------------------------
// POST /api/clientes — CADASTRAR novo cliente (INSERT)
// ---------------------------------------------------------------------
router.post('/', (req, res) => {
  const { nome, telefone, email, data_nascimento } = req.body;

  if (!nome || !nome.trim()) {
    return res.status(400).json({ erro: 'O nome é obrigatório.' });
  }

  // INSERT explícito. data_cadastro tem DEFAULT date('now') no schema.
  const info = db.prepare(
    `INSERT INTO cliente (nome, telefone, email, data_nascimento)
     VALUES (?, ?, ?, ?)`
  ).run(nome.trim(), telefone || null, email || null, data_nascimento || null);

  // Devolve o registro recém-criado (com o id gerado).
  const novo = db.prepare('SELECT * FROM cliente WHERE id_cliente = ?')
    .get(info.lastInsertRowid);
  res.status(201).json(novo);
});

// ---------------------------------------------------------------------
// PUT /api/clientes/:id — ALTERAR cliente (UPDATE)
// ---------------------------------------------------------------------
router.put('/:id', (req, res) => {
  const { nome, telefone, email, data_nascimento } = req.body;

  if (!nome || !nome.trim()) {
    return res.status(400).json({ erro: 'O nome é obrigatório.' });
  }

  const existe = db.prepare('SELECT 1 FROM cliente WHERE id_cliente = ?')
    .get(req.params.id);
  if (!existe) return res.status(404).json({ erro: 'Cliente não encontrado.' });

  // UPDATE explícito.
  db.prepare(
    `UPDATE cliente
        SET nome = ?, telefone = ?, email = ?, data_nascimento = ?
      WHERE id_cliente = ?`
  ).run(nome.trim(), telefone || null, email || null, data_nascimento || null, req.params.id);

  const atualizado = db.prepare('SELECT * FROM cliente WHERE id_cliente = ?')
    .get(req.params.id);
  res.json(atualizado);
});

// ---------------------------------------------------------------------
// DELETE /api/clientes/:id — EXCLUIR cliente (DELETE)
// Se houver agendamento vinculado, o ON DELETE RESTRICT do schema
// dispara SQLITE_CONSTRAINT_FOREIGNKEY, tratado no server.js com
// mensagem amigável (HTTP 409).
// ---------------------------------------------------------------------
router.delete('/:id', (req, res) => {
  const existe = db.prepare('SELECT 1 FROM cliente WHERE id_cliente = ?')
    .get(req.params.id);
  if (!existe) return res.status(404).json({ erro: 'Cliente não encontrado.' });

  db.prepare('DELETE FROM cliente WHERE id_cliente = ?').run(req.params.id);
  res.json({ mensagem: 'Cliente excluído com sucesso.' });
});

module.exports = router;
