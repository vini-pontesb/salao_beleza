// =====================================================================
// scripts/init-db.js
// (Re)cria o schema no Supabase a partir do script oficial
// database/schema.sql — a fonte da verdade do banco — e recarrega os
// dados de teste.
//
// Decisão de migração: mantivemos este script (em vez de removê-lo do
// fluxo) porque ele é útil para resetar os dados de teste antes da
// apresentação. Ele é DESTRUTIVO (dá DROP TABLE nas 4 tabelas), então só
// rode de propósito — o schema em si já existe no Supabase, criado antes
// pelo SQL Editor.
//
// Uso:  npm run db:init   (a partir da pasta backend/)
// =====================================================================
const path = require('path');
const fs = require('fs');
const pool = require('../db');

// backend/scripts -> backend -> raiz do projeto -> database/
const SCHEMA_PATH = path.join(__dirname, '..', '..', 'database', 'schema.sql');

async function main() {
  // O protocolo "simple query" do pg aceita múltiplos comandos separados
  // por ';' em uma única chamada — executa todo o DDL + INSERTs de uma vez,
  // igual ao db.exec(schema) do better-sqlite3.
  const schema = fs.readFileSync(SCHEMA_PATH, 'utf8');
  await pool.query(schema);

  // Conferência: conta os registros carregados em cada tabela.
  const tabelas = ['cliente', 'profissional', 'servico', 'agendamento'];
  console.log('\nSchema recriado no Supabase a partir de:', SCHEMA_PATH);
  for (const t of tabelas) {
    const { rows } = await pool.query(`SELECT COUNT(*) AS n FROM ${t}`);
    console.log(`  ${t.padEnd(13)} -> ${rows[0].n} registro(s)`);
  }

  await pool.end();
  console.log('\nOK: banco pronto para uso.');
}

main().catch((err) => {
  console.error(err);
  pool.end();
  process.exitCode = 1;
});
