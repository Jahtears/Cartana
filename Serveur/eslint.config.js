import js from '@eslint/js';
import security from 'eslint-plugin-security';
import sonarjs from 'eslint-plugin-sonarjs';
import vitest from '@vitest/eslint-plugin';

export default [
  // ───────────────────────────────────────────────
  // IGNORE
  // ───────────────────────────────────────────────
  {
    ignores: ['node_modules/', 'coverage/', 'dist/', 'build/', '*.pck'],
  },

  // ───────────────────────────────────────────────
  // GLOBAL JS RULESET
  // ───────────────────────────────────────────────
  {
    files: ['**/*.js'],

    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        console: 'readonly',
        process: 'readonly',
        Buffer: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
        global: 'readonly',
        setImmediate: 'readonly',
        clearImmediate: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
      },
    },

    plugins: {
      security,
      sonarjs,
      vitest,
    },

    rules: {
      // Base ESLint
      ...js.configs.recommended.rules,

      // Security (désactivation du bruit)
      ...security.configs.recommended.rules,


      // SonarJS (réglages réalistes)
      ...sonarjs.configs.recommended.rules,

   },
  },

  // ───────────────────────────────────────────────
  // TEST FILES
  // ───────────────────────────────────────────────
  {
    files: ['**/__tests__/**/*.js', '**/*.test.js', '**/*.spec.js'],

    languageOptions: {
      globals: {
        describe: 'readonly',
        it: 'readonly',
        test: 'readonly',
        expect: 'readonly',
        beforeEach: 'readonly',
        afterEach: 'readonly',
        beforeAll: 'readonly',
        afterAll: 'readonly',
        vi: 'readonly',
      },
    },

    rules: {
      'no-console': 'off',
      'require-await': 'off',
      'vitest/no-disabled-tests': 'warn',
      'vitest/no-focused-tests': 'error',
    },
  },
];
