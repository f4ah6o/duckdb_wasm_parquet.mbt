import { defineConfig } from 'vite';
import path from 'node:path';

export default defineConfig({
  resolve: {
    alias: {
      // Browser builds should never use the Node backend; stub it to avoid resolution errors.
      '@duckdb/node-api': path.resolve('src/shims/duckdb-node-api.js')
    }
  },
  // Development server settings
  server: {
    // port: 3000,
    // Required headers for SharedArrayBuffer (used by DuckDB-WASM)
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp'
    },
  },

  // Build settings
  build: {
    outDir: 'dist',
    // Optimize for modern browsers
    target: 'esnext',
    // Copy WASM files
    assetsInlineLimit: 0
  },

  // Preview server settings (for production build testing)
  preview: {
    port: 3000,
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp'
    }
  },

  // Optimize dependencies
  optimizeDeps: {
    exclude: ['@duckdb/duckdb-wasm', '@duckdb/node-api']
  }
});
