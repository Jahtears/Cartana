module.exports = {
  env: {
    node: true,
    es2022: true,
    "vitest/globals": true,
  },

  extends: [
    'eslint:recommended',
    'plugin:security/recommended',
    'plugin:sonarjs/recommended',
    'prettier',
  ],

  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
  },

  plugins: ['security', 'sonarjs', 'vitest'],

  rules: {
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
    'eqeqeq': ['error', 'always'],
    'curly': ['error', 'all'],

    // Documentation
    'no-warning-comments': ['warn', { terms: ['todo', 'fixme'] }],

    // Async/Await
    'require-await': 'error',
    'no-async-promise-executor': 'error',

    // Security - Additional
    'sonarjs/cognitive-complexity': ['warn', 15],
    'sonarjs/no-ignored-return': 'warn',
    'sonarjs/no-duplicate-string': ['warn', { threshold: 5 }],

    // Vitest
    'vitest/no-disabled-tests': 'warn',
    'vitest/no-focused-tests': 'error',
  },

  overrides: [
    {
      files: ['**/__tests__/**/*.js', '**/*.test.js', '**/*.spec.js'],
      env: {
        vitest: true,
      },
      rules: {
        'no-console': 'off',
      },
    },
  ],
};
