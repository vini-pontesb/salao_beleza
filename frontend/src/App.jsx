import { NavLink, Routes, Route, Navigate } from 'react-router-dom';
import Clientes from './pages/Clientes.jsx';
import Agendamentos from './pages/Agendamentos.jsx';
import Consultas from './pages/Consultas.jsx';

export default function App() {
  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="brand-icon">💇‍♀️</span>
          <div>
            <h1>Salão Beleza &amp; Cia</h1>
            <p>Sistema de Agendamento</p>
          </div>
        </div>
        <nav className="menu">
          <NavLink to="/clientes">Clientes</NavLink>
          <NavLink to="/agendamentos">Agendamentos</NavLink>
          <NavLink to="/consultas">Consultas</NavLink>
        </nav>
      </header>

      <main className="content">
        <Routes>
          <Route path="/" element={<Navigate to="/clientes" replace />} />
          <Route path="/clientes" element={<Clientes />} />
          <Route path="/agendamentos" element={<Agendamentos />} />
          <Route path="/consultas" element={<Consultas />} />
          <Route path="*" element={<p>Página não encontrada.</p>} />
        </Routes>
      </main>

      <footer className="rodape">
        Trabalho de Banco de Dados I — IFRJ Niterói · Vinicius Pontes &amp; Jean Macedo
      </footer>
    </div>
  );
}
