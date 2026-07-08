// =====================================================================
// server.js — API REST do Sistema de Agendamento de Salão de Beleza.
// Express + pg (PostgreSQL/Supabase), com SQL explícito nas rotas.
// =====================================================================
const path = require('path');
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

// Índice da API em /api (útil para conferir se subiu). A raiz "/" agora
// é servida pelo front-end React buildado (ver bloco de estáticos abaixo).
app.get('/api', (req, res) => {
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

// ---------------------------------------------------------------------
// Front-end em produção.
// Servimos o React já buildado (frontend/dist). Como este bloco vem DEPOIS
// das rotas /api, a API sempre tem prioridade sobre os arquivos estáticos.
// ---------------------------------------------------------------------
const frontendDist = path.join(__dirname, '..', 'frontend', 'dist');

// Arquivos estáticos: index.html, assets/*.js, assets/*.css, imagens etc.
app.use(express.static(frontendDist));

// Fallback SPA (compatível com Express 5 — sem app.get('*')): qualquer GET
// que NÃO comece com /api devolve o index.html, para o react-router tratar
// links diretos (ex.: abrir /agendamentos no navegador e dar F5).
app.use((req, res, next) => {
  if (req.method === 'GET' && !req.path.startsWith('/api')) {
    return res.sendFile(path.join(frontendDist, 'index.html'));
  }
  next();
});

// 404 para qualquer outra rota (ex.: /api inexistente ou método não-GET).
app.use((req, res) => {
  res.status(404).json({ erro: 'Rota não encontrada.' });
});

// ---------------------------------------------------------------------
// Tratamento central de erros.
// As rotas são async e encaminham erros com next(err); eles chegam aqui.
// Traduzimos os códigos de restrição do PostgreSQL em mensagens amigáveis
// (lista completa em: https://www.postgresql.org/docs/current/errcodes-appendix.html).
// ---------------------------------------------------------------------
app.use((err, req, res, next) => {
  console.error('[ERRO]', err.code || '', err.message);

  switch (err.code) {
    // 23503 = foreign_key_violation. Ex.: ON DELETE RESTRICT bloqueou a
    // exclusão de um cliente/profissional/serviço com agendamento vinculado.
    case '23503':
      return res.status(409).json({
        erro: 'Não é possível excluir: existe(m) agendamento(s) vinculado(s) ' +
              'a este registro. Exclua os agendamentos primeiro (o histórico ' +
              'é preservado por integridade referencial).'
      });
    // 23505 = unique_violation. Ex.: e-mail de cliente repetido.
    case '23505':
      return res.status(409).json({
        erro: 'Já existe um cadastro com esse valor único (ex.: e-mail já usado).'
      });
    // 23502 = not_null_violation.
    case '23502':
      return res.status(400).json({ erro: 'Dados inválidos: campo obrigatório em branco.' });
  }

  res.status(500).json({ erro: 'Erro interno do servidor.' });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`API do salão rodando em http://localhost:${PORT}`);
});
