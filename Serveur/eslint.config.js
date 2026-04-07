// eslint.config.js — Cartana server
// Node.js ESM + Vitest, adapté aux patterns réels du code

import js from '@eslint/js';
import security from 'eslint-plugin-security';
import sonarjs from 'eslint-plugin-sonarjs';
import vitest from '@vitest/eslint-plugin';

export default [
  // ─────────────────────────────────────────────
  // IGNORES
  // ─────────────────────────────────────────────
  {
    ignores: [
      'node_modules/',
      'coverage/',
      'dist/',
      'build/',
      'app/saves/',
      '*.pck',
      'package-lock.json',
    ],
  },

  // ─────────────────────────────────────────────
  // BASE — tous les fichiers .js
  // ─────────────────────────────────────────────
  {
    files: ['**/*.js'],

    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        // Node.js globals
        console: 'readonly',
        process: 'readonly',
        Buffer: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
        global: 'readonly',
        URL: 'readonly',
        URLSearchParams: 'readonly',
        // Timers
        setImmediate: 'readonly',
        clearImmediate: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
      },
    },

    plugins: { security, sonarjs },

    rules: {
      // ── Base ESLint ──────────────────────────
      ...js.configs.recommended.rules,

      // Erreurs silencieuses à attraper
      'no-unused-vars': [
        'warn',
        {
          vars: 'all',
          args: 'after-used',
          // Paramètres préfixés _ sont intentionnellement ignorés
          // ex: (_ws, req) dans les handlers
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
        },
      ],
      'no-undef': 'error',
      'no-shadow': 'warn',
      'no-param-reassign': 'off', // Le code modifie game.turn, game.slots, etc. intentionnellement
      'no-use-before-define': ['warn', { functions: false, classes: false }],

      // Qualité de code
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'no-implicit-coercion': 'warn',
      'prefer-const': ['warn', { destructuring: 'all' }],
      'no-var': 'error',
      'object-shorthand': 'warn',
      'prefer-template': 'warn',

      // async/await — cohérence avec le style du code
      'require-await': 'warn',
      'no-async-promise-executor': 'error',
      'no-return-await': 'warn',

      // Sécurité des boucles
      'no-await-in-loop': 'warn', // warn car parfois intentionnel (saveLeaderboard)

      // Console — intentionnel côté serveur, autorisé
      'no-console': 'off',

      // Style (Prettier gère le reste, ces règles évitent les bugs logiques)
      'no-lonely-if': 'warn',
      'no-else-return': 'warn',
      'no-useless-return': 'warn',
      'no-empty': ['warn', { allowEmptyCatch: true }],

      // ── Security — seulement les règles pertinentes ──────
      ...security.configs.recommended.rules,

      // Désactivé : false-positifs constants sur accès dict/object légitimes
      // ex: board[username], meta.slot_sig[key], game.cardsById[id]
      'security/detect-object-injection': 'off',

      // Désactivé : les regex du projet sont simples et contrôlées
      'security/detect-unsafe-regex': 'off',

      // Désactivé : les chemins DB/fichiers viennent de config contrôlée
      'security/detect-non-literal-fs-filename': 'off',

      // Gardé : protège contre les injections réelles
      'security/detect-non-literal-regexp': 'warn',
      'security/detect-eval-with-expression': 'error',
      'security/detect-child-process': 'warn',
      'security/detect-new-buffer': 'error',
      'security/detect-possible-timing-attacks': 'warn',

      // ── SonarJS — règles utiles, bruit supprimé ──────────
      ...sonarjs.configs.recommended.rules,

      // Désactivé : fonctions longues légitimes dans ce projet
      // ex: createServerContext(), orchestrateMove(), tryExpireTurn()
      'sonarjs/cognitive-complexity': 'off',
      'sonarjs/max-union-size': 'off',

      // Désactivé : le projet utilise des magic numbers pour des codes
      // réseau, des constantes de jeu, des timings — c'est lisible en contexte
      'sonarjs/no-hardcoded-credentials': 'off', // faux positifs sur "pin", "hash"

      // Gardé mais en warn : logique dupliquée entre notifier.js / emitter.js
      // (intentionnel selon l'architecture layers)
      'sonarjs/no-identical-functions': 'warn',
      'sonarjs/no-duplicate-string': ['warn', { threshold: 6 }],

      // Erreurs logiques réelles à garder en error
      'sonarjs/no-all-duplicated-branches': 'error',
      'sonarjs/no-element-overwrite': 'error',
      'sonarjs/no-unused-collection': 'warn',
      'sonarjs/no-gratuitous-expressions': 'warn',
    },
  },

  // ─────────────────────────────────────────────
  // HANDLERS — règles assouplies pour les fichiers réseau
  // Les handlers reçoivent (ctx, ws, req, data, actor) et retournent true
  // ─────────────────────────────────────────────
  {
    files: ['handlers/**/*.js', 'net/**/*.js', 'app/router.js', 'app/context.js'],
    rules: {
      // Les handlers utilisent early returns + resError(sendRes, ws, req, ...) + return true
      // ce pattern génère du bruit sur no-else-return
      'no-else-return': 'off',
      // Les handlers reçoivent souvent des params nommés mais non utilisés localement
      'no-unused-vars': ['warn', { argsIgnorePattern: '^_|^ctx$|^ws$|^req$' }],
    },
  },

  // ─────────────────────────────────────────────
  // GAME ENGINE — règles assouplies pour la logique de jeu
  // ─────────────────────────────────────────────
  {
    files: ['game/**/*.js'],
    rules: {
      // Les fonctions moteur modifient l'état du jeu in-place (game.slots, game.turn)
      // c'est intentionnel dans cette architecture
      'no-param-reassign': 'off',
      'prefer-const': ['warn', { destructuring: 'all' }],

      // Les fonctions de règles retournent { valid: true } ou userDenied(code)
      // les early returns multiples sont lisibles dans ce contexte
      'sonarjs/prefer-single-boolean-return': 'off',
    },
  },

  // ─────────────────────────────────────────────
  // TESTS — règles Vitest + assouplissements
  // ─────────────────────────────────────────────
  {
    files: ['**/__tests__/**/*.js', '**/*.test.js', '**/*.spec.js'],

    plugins: { vitest },

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
      // Vitest
      'vitest/no-disabled-tests': 'warn',
      'vitest/no-focused-tests': 'error', // interdit it.only() en CI
      'vitest/expect-expect': 'warn',
      'vitest/no-identical-title': 'error',

      // Assouplissements pour les tests
      'no-console': 'off',
      'require-await': 'off',
      'no-await-in-loop': 'off', // loops dans les tests d'intégration
      'sonarjs/no-duplicate-string': 'off', // fixtures répétées dans les tests

      // Magic numbers OK dans les tests (counts, codes, timeouts)
      'sonarjs/no-hardcoded-credentials': 'off',
    },
  },
];
