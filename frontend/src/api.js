// =====================================================================
// api.js — camada de acesso ao back-end (fetch). As chamadas usam o
// caminho relativo /api, que o Vite encaminha para http://localhost:3001.
// =====================================================================
const BASE = '/api';

async function req(path, options = {}) {
  const res = await fetch(BASE + path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  // tenta ler o corpo JSON (mesmo em erro, para pegar a mensagem amigável)
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.erro || `Erro ${res.status} na requisição.`);
  }
  return data;
}

export const api = {
  // ---- clientes (CRUD) ----
  listClientes: () => req('/clientes'),
  getCliente: (id) => req(`/clientes/${id}`),
  createCliente: (b) => req('/clientes', { method: 'POST', body: JSON.stringify(b) }),
  updateCliente: (id, b) => req(`/clientes/${id}`, { method: 'PUT', body: JSON.stringify(b) }),
  deleteCliente: (id) => req(`/clientes/${id}`, { method: 'DELETE' }),

  // ---- agendamentos (CRUD) ----
  listAgendamentos: () => req('/agendamentos'),
  createAgendamento: (b) => req('/agendamentos', { method: 'POST', body: JSON.stringify(b) }),
  updateAgendamento: (id, b) => req(`/agendamentos/${id}`, { method: 'PUT', body: JSON.stringify(b) }),
  deleteAgendamento: (id) => req(`/agendamentos/${id}`, { method: 'DELETE' }),

  // ---- apoio para formulários ----
  listProfissionais: () => req('/profissionais'),
  listServicos: (ativos) => req('/servicos' + (ativos ? '?ativos=1' : '')),

  // ---- 4 consultas exigidas ----
  clientePorNome: (nome) => req('/consultas/clientes?nome=' + encodeURIComponent(nome)),
  agPorProfissional: (id) => req('/consultas/agendamentos-por-profissional?id_profissional=' + id),
  agPorPeriodo: (i, f) => req(`/consultas/agendamentos-por-periodo?inicio=${i}&fim=${f}`),
  clientesSemAgendamento: () => req('/consultas/clientes-sem-agendamento'),
};
