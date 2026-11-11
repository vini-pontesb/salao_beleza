// =====================================================================
// scripts/init-db.js
// (Re)cria o schema no Supabase a partir dos scripts oficiais
// database/01_criacao_tabelas.sql e database/02_insercao_dados.sql
// (fonte da verdade do banco) e recarrega os dados de teste.
//
// Decisão de migração: mantivemos este script (em vez de removê-lo do
// fluxo) porque ele é útil para resetar os dados de teste antes da
// apresentação. Ele é DESTRUTIVO (dá DROP TABLE nas 7 tabelas), então só
// rode de propósito — o schema em si já existe no Supabase, criado antes
// pelo SQL Editor.
//
// Uso:  npm run db:init   (a partir da pasta backend/)
// =====================================================================
const path = require('path');
const fs = require('fs');
const pool = require('../db');

// backend/scripts -> backend -> raiz do projeto -> database/
const DB_DIR = path.join(__dirname, '..', '..', 'database');
const SCRIPTS = ['01_criacao_tabelas.sql', '02_insercao_dados.sql'];

async function main() {
  // O protocolo "simple query" do pg aceita múltiplos comandos separados
  // por ';' em uma única chamada — executa todo o DDL + INSERTs de uma vez,
  // igual ao db.exec(schema) do better-sqlite3.
  for (const arquivo of SCRIPTS) {
    const sql = fs.readFileSync(path.join(DB_DIR, arquivo), 'utf8');
    await pool.query(sql);
    console.log('Executado:', arquivo);
  }

  // Conferência: conta os registros carregados em cada tabela.
  const tabelas = ['cliente', 'profissional', 'servico', 'produto',
                   'agendamento', 'pagamento', 'venda_produto'];
  console.log('\nSchema recriado no Supabase a partir de:', DB_DIR);
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
