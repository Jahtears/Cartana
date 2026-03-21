import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,          // describe, it, expect disponibles sans import
    environment: "node",    // parfait pour un serveur Node.js
    coverage: {
      provider: "v8",       // rapide et natif
      reporter: ["text", "html"],
    },
    include: ["__tests__/**/*.test.js"], 
    watch: false,
  },
});
