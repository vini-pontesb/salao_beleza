import { useEffect, useState } from 'react';
import { api } from '../api.js';
import Alert from '../components/Alert.jsx';

const vazio = {
  id_cliente: '', id_profissional: '', id_servico: '',
  data_agendamento: '', hora: '', valor: '', status: 'agendado',
};

export default function Agendamentos() {
  const [lista, setLista] = useState([]);
  const [clientes, setClientes] = useState([]);
  const [profissionais, setProfissionais] = useState([]);
  const [servicos, setServicos] = useState([]);
  const [form, setForm] = useState(vazio);
  const [editId, setEditId] = useState(null);
  const [erro, setErro] = useState('');
  const [ok, setOk] = useState('');

  async function carregar() {
    try {
      // carrega em paralelo a agenda e os dados dos dropdowns
      const [ag, cl, pr, sv] = await Promise.all([
        api.listAgendamentos(), api.listClientes(),
        api.listProfissionais(), api.listServicos(true),
      ]);
      setLista(ag); setClientes(cl); setProfissionais(pr); setServicos(sv);
    } catch (e) { setErro(e.message); }
  }
  useEffect(() => { carregar(); }, []);

  function editar(a) {
    setEditId(a.id_agendamento);
    setForm({
      id_cliente: a.id_cliente, id_profissional: a.id_profissional,
      id_servico: a.id_servico, data_agendamento: a.data_agendamento,
      hora: a.hora || '', valor: a.valor ?? '', status: a.status || 'agendado',
    });
    setErro(''); setOk('');
  }
  function cancelar() { setEditId(null); setForm(vazio); }

  // Ao escolher o serviço, sugere o preço dele como valor do agendamento.
  function trocarServico(id) {
    const s = servicos.find(x => String(x.id_servico) === String(id));
    setForm(f => ({ ...f, id_servico: id, valor: s ? s.preco : f.valor }));
  }

  async function salvar(e) {
    e.preventDefault();
    setErro(''); setOk('');
    try {
      if (editId) {
        await api.updateAgendamento(editId, form);
        setOk('Agendamento atualizado.');
      } else {
        await api.createAgendamento(form);
        setOk('Agendamento cadastrado.');
      }
      cancelar();
      carregar();
    } catch (e) { setErro(e.message); }
  }

  async function excluir(a) {
    if (!confirm('Excluir este agendamento?')) return;
    setErro(''); setOk('');
    try {
      await api.deleteAgendamento(a.id_agendamento);
      setOk('Agendamento excluído.');
      carregar();
    } catch (e) { setErro(e.message); }
  }

  return (
    <section>
      <h2>Agendamentos</h2>
      <Alert tipo="erro" onClose={() => setErro('')}>{erro}</Alert>
      <Alert tipo="ok" onClose={() => setOk('')}>{ok}</Alert>

      <form className="card form" onSubmit={salvar}>
        <h3>{editId ? 'Editar agendamento' : 'Novo agendamento'}</h3>
        <div className="grid">
          <label>Cliente*
            <select value={form.id_cliente} onChange={e => setForm({ ...form, id_cliente: e.target.value })} required>
              <option value="">Selecione…</option>
              {clientes.map(c => <option key={c.id_cliente} value={c.id_cliente}>{c.nome}</option>)}
            </select>
          </label>
          <label>Profissional*
            <select value={form.id_profissional} onChange={e => setForm({ ...form, id_profissional: e.target.value })} required>
              <option value="">Selecione…</option>
              {profissionais.map(p => (
                <option key={p.id_profissional} value={p.id_profissional}>{p.nome} — {p.especialidade}</option>
              ))}
            </select>
          </label>
          <label>Serviço*
            <select value={form.id_servico} onChange={e => trocarServico(e.target.value)} required>
              <option value="">Selecione…</option>
              {servicos.map(s => (
                <option key={s.id_servico} value={s.id_servico}>{s.nome} (R$ {s.preco})</option>
              ))}
            </select>
          </label>
          <label>Data*
            <input type="date" value={form.data_agendamento} onChange={e => setForm({ ...form, data_agendamento: e.target.value })} required />
          </label>
          <label>Hora
            <input type="time" value={form.hora} onChange={e => setForm({ ...form, hora: e.target.value })} />
          </label>
          <label>Valor (R$)
            <input type="number" step="0.01" min="0" value={form.valor} onChange={e => setForm({ ...form, valor: e.target.value })} />
          </label>
          <label>Status
            <select value={form.status} onChange={e => setForm({ ...form, status: e.target.value })}>
              <option value="agendado">agendado</option>
              <option value="concluido">concluido</option>
              <option value="cancelado">cancelado</option>
            </select>
          </label>
        </div>
        <div className="acoes">
          <button className="btn primary" type="submit">{editId ? 'Salvar' : 'Cadastrar'}</button>
          {editId && <button className="btn" type="button" onClick={cancelar}>Cancelar</button>}
        </div>
      </form>

      <div className="card">
        <h3>Agenda</h3>
        <table>
          <thead>
            <tr>
              <th>Data</th><th>Hora</th><th>Cliente</th><th>Profissional</th>
              <th>Serviço</th><th>Valor</th><th>Status</th><th></th>
            </tr>
          </thead>
          <tbody>
            {lista.map(a => (
              <tr key={a.id_agendamento}>
                <td>{a.data_agendamento}</td>
                <td>{a.hora || '—'}</td>
                <td>{a.cliente}</td>
                <td>{a.profissional}</td>
                <td>{a.servico}</td>
                <td>R$ {a.valor}</td>
                <td><span className={`tag ${a.status}`}>{a.status}</span></td>
                <td className="linha-acoes">
                  <button className="btn small" onClick={() => editar(a)}>Editar</button>
                  <button className="btn small danger" onClick={() => excluir(a)}>Excluir</button>
                </td>
              </tr>
            ))}
            {lista.length === 0 && (
              <tr><td colSpan="8" className="vazio">Nenhum agendamento.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
