// =====================================================================
// routes/agendamentos.js — CRUD completo de agendamento.
// Tabela com as 3 chaves estrangeiras (cliente, profissional, servico).
// =====================================================================
const express = require('express');
const db = require('../db');
const router = express.Router();

// Helper: existe uma linha com este id na tabela?
function existe(tabela, coluna, id) {
  return db.prepare(`SELECT 1 FROM ${tabela} WHERE ${coluna} = ?`).get(id);
}

// ---------------------------------------------------------------------
// GET /api/agendamentos — LISTAR agendamentos com os nomes das FKs.
// Usa INNER JOIN nas 3 tabelas referenciadas.
// ---------------------------------------------------------------------
router.get('/', (req, res) => {
  const lista = db.prepare(
    `SELECT a.id_agendamento,
            a.id_cliente, a.id_profissional, a.id_servico,
            c.nome AS cliente,
            p.nome AS profissional,
            s.nome AS servico,
            a.data_agendamento, a.hora, a.valor, a.status
       FROM agendamento a
       INNER JOIN cliente      c ON c.id_cliente      = a.id_cliente
       INNER JOIN profissional p ON p.id_profissional = a.id_profissional
       INNER JOIN servico      s ON s.id_servico      = a.id_servico
      ORDER BY a.data_agendamento DESC, a.hora DESC`
  ).all();
  res.json(lista);
});

// ---------------------------------------------------------------------
// GET /api/agendamentos/:id — um agendamento por id (ids crus p/ editar).
// ---------------------------------------------------------------------
router.get('/:id', (req, res) => {
  const ag = db.prepare('SELECT * FROM agendamento WHERE id_agendamento = ?')
    .get(req.params.id);
  if (!ag) return res.status(404).json({ erro: 'Agendamento não encontrado.' });
  res.json(ag);
});

// Validação compartilhada por POST e PUT. Devolve string de erro ou null.
function validar(body) {
  const { id_cliente, id_profissional, id_servico, data_agendamento } = body;
  if (!id_cliente || !id_profissional || !id_servico || !data_agendamento) {
    return 'Cliente, profissional, serviço e data são obrigatórios.';
  }
  // Integridade referencial checada de forma amigável ANTES do INSERT/UPDATE.
  if (!existe('cliente', 'id_cliente', id_cliente)) return 'Cliente informado não existe.';
  if (!existe('profissional', 'id_profissional', id_profissional)) return 'Profissional informado não existe.';
  if (!existe('servico', 'id_servico', id_servico)) return 'Serviço informado não existe.';
  return null;
}

// Se o valor não vier preenchido, usa o preço do serviço escolhido.
function resolverValor(valor, id_servico) {
  if (valor === undefined || valor === null || valor === '') {
    return db.prepare('SELECT preco FROM servico WHERE id_servico = ?').get(id_servico).preco;
  }
  return valor;
}

// ---------------------------------------------------------------------
// POST /api/agendamentos — CADASTRAR (INSERT)
// ---------------------------------------------------------------------
router.post('/', (req, res) => {
  const erro = validar(req.body);
  if (erro) return res.status(400).json({ erro });

  const { id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status } = req.body;
  const valorFinal = resolverValor(valor, id_servico);

  // INSERT explícito.
  const info = db.prepare(
    `INSERT INTO agendamento
        (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(id_cliente, id_profissional, id_servico, data_agendamento,
        hora || null, valorFinal, status || 'agendado');

  const novo = db.prepare('SELECT * FROM agendamento WHERE id_agendamento = ?')
    .get(info.lastInsertRowid);
  res.status(201).json(novo);
});

// ---------------------------------------------------------------------
// PUT /api/agendamentos/:id — ALTERAR (UPDATE)
// ---------------------------------------------------------------------
router.put('/:id', (req, res) => {
  if (!existe('agendamento', 'id_agendamento', req.params.id)) {
    return res.status(404).json({ erro: 'Agendamento não encontrado.' });
  }
  const erro = validar(req.body);
  if (erro) return res.status(400).json({ erro });

  const { id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status } = req.body;
  const valorFinal = resolverValor(valor, id_servico);

  // UPDATE explícito.
  db.prepare(
    `UPDATE agendamento
        SET id_cliente = ?, id_profissional = ?, id_servico = ?,
            data_agendamento = ?, hora = ?, valor = ?, status = ?
      WHERE id_agendamento = ?`
  ).run(id_cliente, id_profissional, id_servico, data_agendamento,
        hora || null, valorFinal, status || 'agendado', req.params.id);

  const atualizado = db.prepare('SELECT * FROM agendamento WHERE id_agendamento = ?')
    .get(req.params.id);
  res.json(atualizado);
});

// ---------------------------------------------------------------------
// DELETE /api/agendamentos/:id — EXCLUIR (DELETE)
// agendamento é a ponta "filha"; não tem restrição de FK que o impeça.
// ---------------------------------------------------------------------
router.delete('/:id', (req, res) => {
  if (!existe('agendamento', 'id_agendamento', req.params.id)) {
    return res.status(404).json({ erro: 'Agendamento não encontrado.' });
  }
  db.prepare('DELETE FROM agendamento WHERE id_agendamento = ?').run(req.params.id);
  res.json({ mensagem: 'Agendamento excluído com sucesso.' });
});

module.exports = router;
