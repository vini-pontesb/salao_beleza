// =====================================================================
// db.js — Conexão com o PostgreSQL (Supabase) via node-postgres (pg).
// A URL de conexão vem do .env (nunca versionada).
// =====================================================================
const { Pool, types } = require('pg');
require('dotenv').config();

// O pg, por padrão, converte DATE (OID 1082) para objeto Date do JS, o que
// pode deslocar o dia por fuso ao virar JSON. Mantemos a string 'YYYY-MM-DD'
// crua, igual ao comportamento antigo do SQLite (evita bug na tela).
types.setTypeParser(1082, (v) => v);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }, // o Supabase exige SSL
});

// No PostgreSQL as FKs são SEMPRE validadas — não existe o PRAGMA do SQLite.
module.exports = pool;
