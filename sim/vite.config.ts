import { resolve } from "node:path"
import { defineConfig } from "vite"

// Two HTML entries: the main app and the sensor sandbox (/sandbox.html).
export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, "index.html"),
        sandbox: resolve(import.meta.dirname, "sandbox.html"),
      },
    },
  },
})
