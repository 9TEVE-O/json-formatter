/**
 * Hardening ESLint rules derived from 6 project quality rubrics.
 *
 * Usage — spread into your project's eslint.config.js:
 *   import hardening from './hardening/eslint.config.js'
 *   export default [...hardening, ...yourProjectRules]
 *
 * Required dev deps:
 *   bun add -d eslint typescript-eslint eslint-plugin-jsx-a11y \
 *             eslint-plugin-react-hooks eslint-plugin-security
 */

import tseslint from 'typescript-eslint'
import jsxA11y from 'eslint-plugin-jsx-a11y'
import reactHooks from 'eslint-plugin-react-hooks'
import security from 'eslint-plugin-security'

/** @type {import('eslint').Linter.Config[]} */
const hardeningConfig = [
  // ── Bugs & Correctness: TypeScript strict layer ───────────────────────
  ...tseslint.configs.strictTypeChecked,
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-non-null-assertion': 'error',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/await-thenable': 'error',
      '@typescript-eslint/restrict-template-expressions': ['error', { allowNumber: true }],
      '@typescript-eslint/no-unnecessary-type-assertion': 'error',
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
      'no-param-reassign': 'error',
      'prefer-const': 'error',
      'no-var': 'error',
    },
  },

  // ── DRY / SOLID / KISS: structural complexity ─────────────────────────
  {
    rules: {
      'max-lines': ['warn', { max: 300, skipBlankLines: true, skipComments: true }],
      complexity: ['warn', { max: 10 }],
      'max-depth': ['warn', { max: 4 }],
      'max-params': ['warn', { max: 4 }],
      'no-duplicate-imports': 'error',
    },
  },

  // ── Security: injection, secrets, auth ────────────────────────────────
  security.configs.recommended,
  {
    rules: {
      'no-eval': 'error',
      'no-implied-eval': 'error',
      'no-new-func': 'error',
      'security/detect-non-literal-regexp': 'error',
      'security/detect-unsafe-regex': 'error',
      // dangerouslySetInnerHTML, localStorage tokens, raw hex, barrel imports
      'no-restricted-syntax': [
        'error',
        {
          selector: 'JSXAttribute[name.name="dangerouslySetInnerHTML"]',
          message:
            'dangerouslySetInnerHTML requires DOMPurify sanitization. Wrap with sanitizeHtml().',
        },
        {
          selector:
            "AssignmentExpression[left.type='MemberExpression'][left.object.name='localStorage']",
          message:
            'localStorage must not store auth tokens. Use HttpOnly cookies set by the server.',
        },
        {
          selector:
            "ImportDeclaration[source.value=/\\/index$/] ImportNamespaceSpecifier",
          message:
            'Namespace imports from barrel index files defeat tree-shaking. Import directly.',
        },
      ],
    },
  },

  // ── UX & Accessibility ────────────────────────────────────────────────
  {
    plugins: { 'jsx-a11y': jsxA11y },
    rules: {
      ...jsxA11y.configs.strict.rules,
      'jsx-a11y/alt-text': 'error',
      'jsx-a11y/aria-props': 'error',
      'jsx-a11y/aria-role': 'error',
      'jsx-a11y/click-events-have-key-events': 'error',
      'jsx-a11y/interactive-supports-focus': 'error',
      'jsx-a11y/label-has-associated-control': 'error',
      'jsx-a11y/tab-index-no-positive': 'error',
      'jsx-a11y/no-autofocus': 'warn',
    },
  },

  // ── Performance: React hooks correctness ──────────────────────────────
  {
    plugins: { 'react-hooks': reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-hooks/exhaustive-deps': 'error',
    },
  },
]

export default hardeningConfig
