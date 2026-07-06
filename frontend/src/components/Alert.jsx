// Alerta simples reutilizável (erro/sucesso). Não renderiza nada se vazio.
export default function Alert({ tipo = 'info', children, onClose }) {
  if (!children) return null;
  return (
    <div className={`alert alert-${tipo}`}>
      <span>{children}</span>
      {onClose && (
        <button className="alert-close" onClick={onClose} aria-label="fechar">×</button>
      )}
    </div>
  );
}
