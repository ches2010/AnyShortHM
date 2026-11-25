import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// Tauri 需要相对路径产物 + 固定端口
export default defineConfig({
  plugins: [vue()],
  base: './',
  build: {
    target: 'es2020',
    outDir: 'dist',
    emptyOutDir: true
  },
  server: {
    port: 1420,
    strictPort: true
  }
});
