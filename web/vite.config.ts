import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// @powersync/web ships a wasm SQLite + web workers; exclude from dep pre-bundling
// and serve workers as ES modules.
export default defineConfig({
  plugins: [react()],
  optimizeDeps: {
    exclude: ['@powersync/web', '@journeyapps/wa-sqlite']
  },
  worker: {
    format: 'es'
  },
  server: {
    port: 3030,
    host: true
  }
});
