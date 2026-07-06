// =====================================================================
// scripts/init-db.js
// Gera (ou regenera) o arquivo SQLite database/salao.db a partir do
// script oficial database/schema.sql — a fonte da verdade do banco.
//
// Uso:  npm run db:init   (a partir da pasta backend/)
// =====================================================================
const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');

// backend/scripts -> backend -> raiz do projeto -> database/
const SCHEMA_PATH = path.join(__dirname, '..', '..', 'database', 'schema.sql');
const DB_PATH = path.join(__dirname, '..', '..', 'database', 'salao.db');

// Reconstrução limpa: remove o banco anterior, se existir.
if (fs.existsSync(DB_PATH)) {
  fs.unlinkSync(DB_PATH);
  console.log('Banco anterior removido.');
}

const db = new Database(DB_PATH);

// SQLite só valida as chaves estrangeiras com este PRAGMA ligado.
db.pragma('foreign_keys = ON');

// Executa todo o DDL + INSERTs de teste do schema.sql de uma vez.
const schema = fs.readFileSync(SCHEMA_PATH, 'utf8');
db.exec(schema);

// Conferência: conta os registros carregados em cada tabela.
const tabelas = ['cliente', 'profissional', 'servico', 'agendamento'];
console.log('\nBanco gerado em:', DB_PATH);
for (const t of tabelas) {
  const { n } = db.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get();
  console.log(`  ${t.padEnd(13)} -> ${n} registro(s)`);
}

db.close();
console.log('\nOK: banco pronto para uso.');
