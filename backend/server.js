// =====================================================================
// server.js — API REST do Sistema de Agendamento de Salão de Beleza.
// Express + better-sqlite3, com SQL explícito nas rotas.
// =====================================================================
const express = require('express');
const cors = require('cors');

const clientesRouter = require('./routes/clientes');
const agendamentosRouter = require('./routes/agendamentos');
const profissionaisRouter = require('./routes/profissionais');
const servicosRouter = require('./routes/servicos');
const consultasRouter = require('./routes/consultas');

const app = express();

app.use(cors());            // libera o front-end (Vite) a consumir a API
app.use(express.json());    // faz o parse de corpo JSON nas requisições

// Rota raiz: pequeno "índice" da API (útil para conferir se subiu).
app.get('/', (req, res) => {
  res.json({
    api: 'Salão de Beleza - Agendamento',
    rotas: {
      clientes: '/api/clientes',
      agendamentos: '/api/agendamentos',
      profissionais: '/api/profissionais',
      servicos: '/api/servicos',
      consultas: {
        clientePorNome: '/api/consultas/clientes?nome=ana',
        porProfissional: '/api/consultas/agendamentos-por-profissional?id_profissional=1',
        porPeriodo: '/api/consultas/agendamentos-por-periodo?inicio=2026-07-01&fim=2026-07-31',
        semAgendamento: '/api/consultas/clientes-sem-agendamento'
      }
    }
  });
});

app.use('/api/clientes', clientesRouter);
app.use('/api/agendamentos', agendamentosRouter);
app.use('/api/profissionais', profissionaisRouter);
app.use('/api/servicos', servicosRouter);
app.use('/api/consultas', consultasRouter);

// 404 para qualquer outra rota.
app.use((req, res) => {
  res.status(404).json({ erro: 'Rota não encontrada.' });
});

// ---------------------------------------------------------------------
// Tratamento central de erros.
// better-sqlite3 é síncrono, então erros lançados nas rotas chegam aqui.
// Traduzimos os erros de restrição do SQLite em mensagens amigáveis.
// ---------------------------------------------------------------------
app.use((err, req, res, next) => {
  console.error('[ERRO]', err.code || '', err.message);

  const msg = err.message || '';
  if (err.code && err.code.startsWith('SQLITE_CONSTRAINT')) {
    // ON DELETE RESTRICT: tentou excluir um registro que tem filhos.
    // Obs.: no SQLite o RESTRICT chega aqui com código
    // SQLITE_CONSTRAINT_TRIGGER (e não _FOREIGNKEY), então detectamos
    // pela mensagem "FOREIGN KEY constraint failed".
    if (msg.includes('FOREIGN KEY')) {
      return res.status(409).json({
        erro: 'Não é possível excluir: existe(m) agendamento(s) vinculado(s) ' +
              'a este registro. Exclua os agendamentos primeiro (o histórico ' +
              'é preservado por integridade referencial).'
      });
    }
    // UNIQUE: e-mail de cliente repetido, por exemplo.
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE' || msg.includes('UNIQUE')) {
      return res.status(409).json({
        erro: 'Já existe um cadastro com esse valor único (ex.: e-mail já usado).'
      });
    }
    // Demais restrições (NOT NULL, CHECK...).
    return res.status(400).json({ erro: 'Dados inválidos: ' + msg });
  }

  res.status(500).json({ erro: 'Erro interno do servidor.' });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`API do salão rodando em http://localhost:${PORT}`);
});
