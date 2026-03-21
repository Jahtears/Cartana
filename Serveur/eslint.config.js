import js from '@eslint/js';
import security from 'eslint-plugin-security';
import sonarjs from 'eslint-plugin-sonarjs';
import vitest from '@vitest/eslint-plugin';

export default [
  {
    ignores: ['node_modules/', 'coverage/', 'dist/', 'build/', '*.pck'],
  },
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
        // Node.js globals
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
      ...js.configs.recommended.rules,
      ...security.configs.recommended.rules,
      ...sonarjs.configs.recommended.rules,

      // Variables
      'no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],
      'no-var': 'error',
      'prefer-const': 'error',
      'prefer-rest-params': 'error',
      'prefer-spread': 'error',

      // Code Quality
      'no-console': [
        'warn',
        {
          allow: ['warn', 'error'],
        },
      ],
      'no-debugger': 'error',
      'no-empty': 'error',
      'no-eval': 'error',
      'no-implicit-coercion': 'error',
      'no-implied-eval': 'error',
      'no-new-func': 'error',
      'no-throw-literal': 'error',
      eqeqeq: ['error', 'always'],
      curly: ['error', 'all'],

      // Documentation
      'no-warning-comments': ['warn', { terms: ['todo', 'fixme'] }],

      // Async/Await
      'require-await': 'error',
      'no-async-promise-executor': 'error',

      // Security - Additional
      'sonarjs/cognitive-complexity': ['warn', 15],
      'sonarjs/no-ignored-return': 'warn',
      'sonarjs/no-duplicate-string': ['warn', { threshold: 5 }],
    },
  },
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
