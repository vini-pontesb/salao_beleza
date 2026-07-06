import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// O proxy encaminha as chamadas /api do front-end (porta 5173) para o
// back-end Express (porta 3001), evitando qualquer questão de CORS em dev.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174,
    proxy: {
      '/api': 'http://localhost:3001'
    }
  }
});
