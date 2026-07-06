import { useEffect, useState } from 'react';
import { api } from '../api.js';
import Alert from '../components/Alert.jsx';

// Página com as 4 consultas exigidas, cada uma em seu próprio cartão,
// com campo(s) de filtro e botão "Pesquisar".
export default function Consultas() {
  const [erro, setErro] = useState('');
  return (
    <section>
      <h2>Consultas</h2>
      <Alert tipo="erro" onClose={() => setErro('')}>{erro}</Alert>
      <ClientePorNome onErro={setErro} />
      <PorProfissional onErro={setErro} />
      <PorPeriodo onErro={setErro} />
      <SemAgendamento onErro={setErro} />
    </section>
  );
}

// (1) SELECT em uma tabela por parâmetro -----------------------------------
function ClientePorNome({ onErro }) {
  const [nome, setNome] = useState('');
  const [res, setRes] = useState(null);

  async function pesquisar(e) {
    e.preventDefault();
    onErro('');
    try { setRes(await api.clientePorNome(nome)); }
    catch (e) { onErro(e.message); }
  }

  return (
    <div className="card">
      <h3>1 · Cliente por nome <small>(SELECT + WHERE LIKE)</small></h3>
      <form className="linha-filtro" onSubmit={pesquisar}>
        <input placeholder="Parte do nome (ex.: ana)" value={nome} onChange={e => setNome(e.target.value)} />
        <button className="btn primary" type="submit">Pesquisar</button>
      </form>
      {res && (res.length ? (
        <table>
          <thead><tr><th>Nome</th><th>Telefone</th><th>E-mail</th><th>Nascimento</th></tr></thead>
          <tbody>
            {res.map(c => (
              <tr key={c.id_cliente}>
                <td>{c.nome}</td><td>{c.telefone || '—'}</td>
                <td>{c.email || '—'}</td><td>{c.data_nascimento || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <p className="vazio">Nenhum cliente encontrado.</p>)}
    </div>
  );
}

// (2) INNER JOIN — agendamentos por profissional ---------------------------
function PorProfissional({ onErro }) {
  const [profissionais, setProfissionais] = useState([]);
  const [id, setId] = useState('');
  const [res, setRes] = useState(null);

  useEffect(() => {
    api.listProfissionais().then(setProfissionais).catch(e => onErro(e.message));
  }, []);

  async function pesquisar(e) {
    e.preventDefault();
    onErro('');
    if (!id) { onErro('Selecione um profissional.'); return; }
    try { setRes(await api.agPorProfissional(id)); }
    catch (e) { onErro(e.message); }
  }

  return (
    <div className="card">
      <h3>2 · Agendamentos por profissional <small>(INNER JOIN)</small></h3>
      <form className="linha-filtro" onSubmit={pesquisar}>
        <select value={id} onChange={e => setId(e.target.value)}>
          <option value="">Selecione o profissional…</option>
          {profissionais.map(p => <option key={p.id_profissional} value={p.id_profissional}>{p.nome}</option>)}
        </select>
        <button className="btn primary" type="submit">Pesquisar</button>
      </form>
      {res && (res.length ? (
        <table>
          <thead><tr><th>Data</th><th>Hora</th><th>Cliente</th><th>Serviço</th><th>Valor</th><th>Status</th></tr></thead>
          <tbody>
            {res.map((a, i) => (
              <tr key={i}>
                <td>{a.data_agendamento}</td><td>{a.hora || '—'}</td>
                <td>{a.cliente}</td><td>{a.servico}</td>
                <td>R$ {a.valor}</td><td>{a.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <p className="vazio">Nenhum agendamento para este profissional.</p>)}
    </div>
  );
}

// (3) INNER JOIN — agendamentos por período --------------------------------
function PorPeriodo({ onErro }) {
  const [inicio, setInicio] = useState('2026-07-01');
  const [fim, setFim] = useState('2026-07-31');
  const [res, setRes] = useState(null);

  async function pesquisar(e) {
    e.preventDefault();
    onErro('');
    if (!inicio || !fim) { onErro('Informe início e fim.'); return; }
    try { setRes(await api.agPorPeriodo(inicio, fim)); }
    catch (e) { onErro(e.message); }
  }

  return (
    <div className="card">
      <h3>3 · Agendamentos por período <small>(INNER JOIN + BETWEEN)</small></h3>
      <form className="linha-filtro" onSubmit={pesquisar}>
        <label className="inline">De <input type="date" value={inicio} onChange={e => setInicio(e.target.value)} /></label>
        <label className="inline">Até <input type="date" value={fim} onChange={e => setFim(e.target.value)} /></label>
        <button className="btn primary" type="submit">Pesquisar</button>
      </form>
      {res && (res.length ? (
        <table>
          <thead><tr><th>Data</th><th>Hora</th><th>Cliente</th><th>Profissional</th><th>Serviço</th><th>Valor</th></tr></thead>
          <tbody>
            {res.map((a, i) => (
              <tr key={i}>
                <td>{a.data_agendamento}</td><td>{a.hora || '—'}</td>
                <td>{a.cliente}</td><td>{a.profissional}</td>
                <td>{a.servico}</td><td>R$ {a.valor}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <p className="vazio">Nenhum agendamento no período.</p>)}
    </div>
  );
}

// (4) SUBCONSULTA NOT IN — clientes que nunca agendaram --------------------
function SemAgendamento({ onErro }) {
  const [res, setRes] = useState(null);

  async function pesquisar() {
    onErro('');
    try { setRes(await api.clientesSemAgendamento()); }
    catch (e) { onErro(e.message); }
  }

  return (
    <div className="card">
      <h3>4 · Clientes que nunca agendaram <small>(SUBCONSULTA NOT IN)</small></h3>
      <div className="linha-filtro">
        <button className="btn primary" onClick={pesquisar}>Pesquisar</button>
      </div>
      {res && (res.length ? (
        <table>
          <thead><tr><th>Nome</th><th>Telefone</th><th>E-mail</th><th>Cadastro</th></tr></thead>
          <tbody>
            {res.map(c => (
              <tr key={c.id_cliente}>
                <td>{c.nome}</td><td>{c.telefone || '—'}</td>
                <td>{c.email || '—'}</td><td>{c.data_cadastro}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <p className="vazio">Todos os clientes já agendaram.</p>)}
    </div>
  );
}
