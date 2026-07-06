// =====================================================================
// routes/agendamentos.js — CRUD completo de agendamento.
// Tabela com as 3 chaves estrangeiras (cliente, profissional, servico).
// =====================================================================
const express = require('express');
const pool = require('../db');
const router = express.Router();

// Helper: existe uma linha com este id na tabela?
// tabela/coluna são sempre constantes fixas no código (nunca vêm do
// req.body/req.params), então a interpolação aqui não abre brecha para
// SQL injection.
async function existe(tabela, coluna, id) {
  const result = await pool.query(`SELECT 1 FROM ${tabela} WHERE ${coluna} = $1`, [id]);
  return result.rows.length > 0;
}

// ---------------------------------------------------------------------
// GET /api/agendamentos — LISTAR agendamentos com os nomes das FKs.
// Usa INNER JOIN nas 3 tabelas referenciadas.
// ---------------------------------------------------------------------
router.get('/', async (req, res, next) => {
  try {
    const result = await pool.query(
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
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// GET /api/agendamentos/:id — um agendamento por id (ids crus p/ editar).
// ---------------------------------------------------------------------
router.get('/:id', async (req, res, next) => {
  try {
    const result = await pool.query(
      'SELECT * FROM agendamento WHERE id_agendamento = $1',
      [req.params.id]
    );
    const ag = result.rows[0];
    if (!ag) return res.status(404).json({ erro: 'Agendamento não encontrado.' });
    res.json(ag);
  } catch (err) {
    next(err);
  }
});

// Validação compartilhada por POST e PUT. Devolve string de erro ou null.
async function validar(body) {
  const { id_cliente, id_profissional, id_servico, data_agendamento } = body;
  if (!id_cliente || !id_profissional || !id_servico || !data_agendamento) {
    return 'Cliente, profissional, serviço e data são obrigatórios.';
  }
  // Integridade referencial checada de forma amigável ANTES do INSERT/UPDATE.
  if (!(await existe('cliente', 'id_cliente', id_cliente))) return 'Cliente informado não existe.';
  if (!(await existe('profissional', 'id_profissional', id_profissional))) return 'Profissional informado não existe.';
  if (!(await existe('servico', 'id_servico', id_servico))) return 'Serviço informado não existe.';
  return null;
}

// Se o valor não vier preenchido, usa o preço do serviço escolhido.
async function resolverValor(valor, id_servico) {
  if (valor === undefined || valor === null || valor === '') {
    const result = await pool.query('SELECT preco FROM servico WHERE id_servico = $1', [id_servico]);
    return result.rows[0].preco;
  }
  return valor;
}

// ---------------------------------------------------------------------
// POST /api/agendamentos — CADASTRAR (INSERT)
// ---------------------------------------------------------------------
router.post('/', async (req, res, next) => {
  try {
    const erro = await validar(req.body);
    if (erro) return res.status(400).json({ erro });

    const { id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status } = req.body;
    const valorFinal = await resolverValor(valor, id_servico);

    // INSERT explícito, devolvendo o registro recém-criado.
    const result = await pool.query(
      `INSERT INTO agendamento
          (id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [id_cliente, id_profissional, id_servico, data_agendamento,
        hora || null, valorFinal, status || 'agendado']
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// PUT /api/agendamentos/:id — ALTERAR (UPDATE)
// ---------------------------------------------------------------------
router.put('/:id', async (req, res, next) => {
  try {
    if (!(await existe('agendamento', 'id_agendamento', req.params.id))) {
      return res.status(404).json({ erro: 'Agendamento não encontrado.' });
    }
    const erro = await validar(req.body);
    if (erro) return res.status(400).json({ erro });

    const { id_cliente, id_profissional, id_servico, data_agendamento, hora, valor, status } = req.body;
    const valorFinal = await resolverValor(valor, id_servico);

    // UPDATE explícito, devolvendo a linha atualizada.
    const result = await pool.query(
      `UPDATE agendamento
          SET id_cliente = $1, id_profissional = $2, id_servico = $3,
              data_agendamento = $4, hora = $5, valor = $6, status = $7
        WHERE id_agendamento = $8
        RETURNING *`,
      [id_cliente, id_profissional, id_servico, data_agendamento,
        hora || null, valorFinal, status || 'agendado', req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// DELETE /api/agendamentos/:id — EXCLUIR (DELETE)
// agendamento é a ponta "filha"; não tem restrição de FK que o impeça.
// ---------------------------------------------------------------------
router.delete('/:id', async (req, res, next) => {
  try {
    if (!(await existe('agendamento', 'id_agendamento', req.params.id))) {
      return res.status(404).json({ erro: 'Agendamento não encontrado.' });
    }
    await pool.query('DELETE FROM agendamento WHERE id_agendamento = $1', [req.params.id]);
    res.json({ mensagem: 'Agendamento excluído com sucesso.' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
