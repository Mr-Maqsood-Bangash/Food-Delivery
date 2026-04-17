import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
<<<<<<< HEAD
    port: 5175
=======
    port: 5173
>>>>>>> 5409204 (files added in dev brach)
  }
})
