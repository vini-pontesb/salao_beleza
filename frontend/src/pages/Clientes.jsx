import { useEffect, useState } from 'react';
import { api } from '../api.js';
import Alert from '../components/Alert.jsx';

const vazio = { nome: '', telefone: '', email: '', data_nascimento: '' };

export default function Clientes() {
  const [clientes, setClientes] = useState([]);
  const [form, setForm] = useState(vazio);
  const [editId, setEditId] = useState(null);
  const [erro, setErro] = useState('');
  const [ok, setOk] = useState('');
  const [carregando, setCarregando] = useState(false);

  async function carregar() {
    setCarregando(true);
    try { setClientes(await api.listClientes()); }
    catch (e) { setErro(e.message); }
    finally { setCarregando(false); }
  }
  useEffect(() => { carregar(); }, []);

  function editar(c) {
    setEditId(c.id_cliente);
    setForm({
      nome: c.nome || '',
      telefone: c.telefone || '',
      email: c.email || '',
      data_nascimento: c.data_nascimento || '',
    });
    setErro(''); setOk('');
  }
  function cancelar() { setEditId(null); setForm(vazio); }

  async function salvar(e) {
    e.preventDefault();
    setErro(''); setOk('');
    try {
      if (editId) {
        await api.updateCliente(editId, form);
        setOk('Cliente atualizado com sucesso.');
      } else {
        await api.createCliente(form);
        setOk('Cliente cadastrado com sucesso.');
      }
      cancelar();
      carregar();
    } catch (e) { setErro(e.message); }
  }

  async function excluir(c) {
    if (!confirm(`Excluir o cliente "${c.nome}"?`)) return;
    setErro(''); setOk('');
    try {
      await api.deleteCliente(c.id_cliente);
      setOk('Cliente excluído.');
      carregar();
    } catch (e) {
      // Mostra a mensagem amigável do back-end (ex.: bloqueio por FK RESTRICT).
      setErro(e.message);
    }
  }

  return (
    <section>
      <h2>Clientes</h2>
      <Alert tipo="erro" onClose={() => setErro('')}>{erro}</Alert>
      <Alert tipo="ok" onClose={() => setOk('')}>{ok}</Alert>

      <form className="card form" onSubmit={salvar}>
        <h3>{editId ? 'Editar cliente' : 'Novo cliente'}</h3>
        <div className="grid">
          <label>Nome*
            <input value={form.nome} onChange={e => setForm({ ...form, nome: e.target.value })} required />
          </label>
          <label>Telefone
            <input value={form.telefone} onChange={e => setForm({ ...form, telefone: e.target.value })} />
          </label>
          <label>E-mail
            <input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} />
          </label>
          <label>Nascimento
            <input type="date" value={form.data_nascimento} onChange={e => setForm({ ...form, data_nascimento: e.target.value })} />
          </label>
        </div>
        <div className="acoes">
          <button className="btn primary" type="submit">{editId ? 'Salvar' : 'Cadastrar'}</button>
          {editId && <button className="btn" type="button" onClick={cancelar}>Cancelar</button>}
        </div>
      </form>

      <div className="card">
        <h3>Lista de clientes {carregando && <small>(carregando…)</small>}</h3>
        <table>
          <thead>
            <tr>
              <th>Nome</th><th>Telefone</th><th>E-mail</th>
              <th>Nascimento</th><th>Cadastro</th><th></th>
            </tr>
          </thead>
          <tbody>
            {clientes.map(c => (
              <tr key={c.id_cliente}>
                <td>{c.nome}</td>
                <td>{c.telefone || '—'}</td>
                <td>{c.email || '—'}</td>
                <td>{c.data_nascimento || '—'}</td>
                <td>{c.data_cadastro}</td>
                <td className="linha-acoes">
                  <button className="btn small" onClick={() => editar(c)}>Editar</button>
                  <button className="btn small danger" onClick={() => excluir(c)}>Excluir</button>
                </td>
              </tr>
            ))}
            {clientes.length === 0 && !carregando && (
              <tr><td colSpan="6" className="vazio">Nenhum cliente cadastrado.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
