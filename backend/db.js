// =====================================================================
// db.js — Conexão única com o banco SQLite (better-sqlite3).
//
// better-sqlite3 é SÍNCRONO: cada prepare/run/get/all executa a query
// na hora e devolve o resultado, o que deixa o SQL bem explícito.
// =====================================================================
const path = require('path');
const Database = require('better-sqlite3');

const DB_PATH = path.join(__dirname, '..', 'database', 'salao.db');

const db = new Database(DB_PATH);

// IMPRESCINDÍVEL no SQLite: sem este PRAGMA as chaves estrangeiras (e as
// regras ON DELETE RESTRICT / ON UPDATE CASCADE) são ignoradas.
db.pragma('foreign_keys = ON');

module.exports = db;
