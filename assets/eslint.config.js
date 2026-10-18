// eslint.config.js - ESLint v9 flat config
import js from '@eslint/js';
import typescript from '@typescript-eslint/eslint-plugin';
import typescriptParser from '@typescript-eslint/parser';

export default [
  js.configs.recommended,
  {
    files: ['js/**/*.ts', 'js/**/*.tsx'],
    languageOptions: {
      parser: typescriptParser,
      parserOptions: {
        ecmaVersion: 2020,
        sourceType: 'module',
        project: './tsconfig.json'
      },
      globals: {
        window: 'readonly',
        document: 'readonly',
        console: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        requestAnimationFrame: 'readonly',
        cancelAnimationFrame: 'readonly',
        fetch: 'readonly',
        localStorage: 'readonly',
        HTMLElement: 'readonly',
        HTMLInputElement: 'readonly',
        HTMLTextAreaElement: 'readonly',
        HTMLFormElement: 'readonly',
        HTMLButtonElement: 'readonly',
        HTMLCanvasElement: 'readonly',
        Event: 'readonly',
        MouseEvent: 'readonly',
        KeyboardEvent: 'readonly',
        EventListener: 'readonly',
        FrameRequestCallback: 'readonly',
        FormData: 'readonly',
        Element: 'readonly',
        Node: 'readonly',
        NodeListOf: 'readonly',
        navigator: 'readonly',
        performance: 'readonly',
        crypto: 'readonly',
        alert: 'readonly',
        prompt: 'readonly',
        screen: 'readonly',
        NodeJS: 'readonly'
      }
    },
    plugins: {
      '@typescript-eslint': typescript
    },
    rules: {
      ...typescript.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      '@typescript-eslint/no-non-null-assertion': 'warn',
      'prefer-const': 'error',
      'no-var': 'error',
      'no-console': 'off'
      ,
      // disallow importing CSS directly in JS/TS to avoid bundling issues with esbuild
      'no-restricted-imports': ['error', { 'patterns': ['*.css', '**/*.css'] }]
    }
  },
  {
    ignores: [
      'node_modules/',
      '../priv/static/assets/',
      '*.js',
      'tailwind.config.js'
    ]
  }
];