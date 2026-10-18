import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { defineConfig, type Plugin } from "vite"

// Inlines public/brand SVGs where HTML has <!--archy:logo--> or <!--archy:mark-->, so the
// wordmark (fill: currentColor) takes the page ink color and there is no image flash.
const inlineBrand = (): Plugin => ({
  name: "inline-brand",
  transformIndexHtml: (html) =>
    html.replace(/<!--archy:(logo|mark)-->/g, (_, name: string) =>
      readFileSync(resolve(import.meta.dirname, `public/brand/archy_${name}.svg`), "utf8")
        .replace(/<title>.*?<\/title>/, "")
        .replace("<svg ", '<svg aria-hidden="true" focusable="false" ')
        .trim(),
    ),
})

// Two HTML entries: the main app and the sensor sandbox (/sandbox.html).
export default defineConfig({
  plugins: [inlineBrand()],
  build: {
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, "index.html"),
        sandbox: resolve(import.meta.dirname, "sandbox.html"),
      },
    },
  },
})
