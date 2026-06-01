/**
 * Hardening configuration tests.
 *
 * Tests for:
 *  - hardening/rubrics.json   — schema structure, required fields, target scores
 *  - hardening/tsconfig.hardening.json — compiler option presence
 *  - hardening/audit.sh       — file metadata, shebang, section coverage
 *  - .github/workflows/hardening.yml — job coverage, key run commands
 *
 * Run: bun test hardening/_test.ts
 */

import { describe, test, expect } from 'bun:test'
import { readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = join(import.meta.dir, '..')

// ── Helpers ─────────────────────────────────────────────────────────────────

function readJson(relPath: string): unknown {
  const raw = readFileSync(join(ROOT, relPath), 'utf8')
  return JSON.parse(raw)
}

function readText(relPath: string): string {
  return readFileSync(join(ROOT, relPath), 'utf8')
}

// ── rubrics.json ─────────────────────────────────────────────────────────────

describe('hardening/rubrics.json', () => {
  const rubrics = readJson('hardening/rubrics.json') as Record<string, unknown>

  test('has version field equal to "1.0"', () => {
    expect(rubrics['version']).toBe('1.0')
  })

  test('has a description field', () => {
    expect(typeof rubrics['description']).toBe('string')
    expect((rubrics['description'] as string).length).toBeGreaterThan(0)
  })

  test('has a rubrics object', () => {
    expect(typeof rubrics['rubrics']).toBe('object')
    expect(rubrics['rubrics']).not.toBeNull()
  })

  const expectedRubrics = [
    'design_system',
    'dry_solid_ssot_kiss',
    'ux_accessibility',
    'performance',
    'bugs_correctness',
    'security',
  ]

  test('contains all 6 rubric categories', () => {
    const keys = Object.keys(rubrics['rubrics'] as object)
    expect(keys).toHaveLength(6)
    for (const key of expectedRubrics) {
      expect(keys).toContain(key)
    }
  })

  describe('each rubric has required structure', () => {
    const rubricsObj = rubrics['rubrics'] as Record<string, unknown>

    for (const name of expectedRubrics) {
      test(`${name} has title and criteria`, () => {
        const rubric = rubricsObj[name] as Record<string, unknown>
        expect(typeof rubric['title']).toBe('string')
        expect(typeof rubric['criteria']).toBe('object')
        expect(rubric['criteria']).not.toBeNull()
      })

      test(`${name} criteria all have target scores between 1 and 5`, () => {
        const rubric = rubricsObj[name] as Record<string, unknown>
        const criteria = rubric['criteria'] as Record<string, Record<string, unknown>>
        for (const [criterionKey, criterion] of Object.entries(criteria)) {
          const target = criterion['target'] as number
          expect(
            typeof target,
            `${name}.${criterionKey}.target should be a number`,
          ).toBe('number')
          expect(target, `${name}.${criterionKey}.target should be >= 1`).toBeGreaterThanOrEqual(1)
          expect(target, `${name}.${criterionKey}.target should be <= 5`).toBeLessThanOrEqual(5)
        }
      })

      test(`${name} criteria all have description and flags`, () => {
        const rubric = rubricsObj[name] as Record<string, unknown>
        const criteria = rubric['criteria'] as Record<string, Record<string, unknown>>
        for (const [criterionKey, criterion] of Object.entries(criteria)) {
          expect(
            typeof criterion['description'],
            `${name}.${criterionKey}.description should be a string`,
          ).toBe('string')
          expect(
            Array.isArray(criterion['flags']),
            `${name}.${criterionKey}.flags should be an array`,
          ).toBe(true)
          expect(
            (criterion['flags'] as unknown[]).length,
            `${name}.${criterionKey}.flags should have at least one flag`,
          ).toBeGreaterThan(0)
        }
      })
    }
  })

  describe('specific rubric criteria exist', () => {
    const rubricsObj = rubrics['rubrics'] as Record<string, Record<string, unknown>>

    test('design_system has design_tokens criterion with target 5', () => {
      const ds = rubricsObj['design_system']!['criteria'] as Record<string, Record<string, unknown>>
      expect(ds['design_tokens']!['target']).toBe(5)
    })

    test('bugs_correctness has type_safety criterion with target 5', () => {
      const bc = rubricsObj['bugs_correctness']!['criteria'] as Record<string, Record<string, unknown>>
      expect(bc['type_safety']!['target']).toBe(5)
    })

    test('performance bundle_size has numeric thresholds', () => {
      const perf = rubricsObj['performance']!['criteria'] as Record<string, Record<string, unknown>>
      const bs = perf['bundle_size'] as Record<string, unknown>
      const thresholds = bs['thresholds'] as Record<string, number>
      expect(thresholds['initial_js_bytes']).toBe(512000)
      expect(thresholds['target_bytes']).toBe(102400)
    })

    test('performance core_web_vitals has LCP/CLS/INP thresholds', () => {
      const perf = rubricsObj['performance']!['criteria'] as Record<string, Record<string, unknown>>
      const cwv = perf['core_web_vitals'] as Record<string, unknown>
      const thresholds = cwv['thresholds'] as Record<string, number>
      expect(thresholds['lcp_ms']).toBe(2500)
      expect(thresholds['cls']).toBe(0.1)
      expect(thresholds['inp_ms']).toBe(200)
    })

    test('security criteria all have auto_check fields', () => {
      const sec = rubricsObj['security']!['criteria'] as Record<string, Record<string, unknown>>
      for (const [key, crit] of Object.entries(sec)) {
        expect(
          'auto_check' in crit,
          `security.${key} should have an auto_check field`,
        ).toBe(true)
      }
    })
  })

  test('no criterion target score is below 4 (project quality floor)', () => {
    const rubricsObj = rubrics['rubrics'] as Record<string, Record<string, unknown>>
    for (const [rubricName, rubric] of Object.entries(rubricsObj)) {
      const criteria = rubric['criteria'] as Record<string, Record<string, unknown>>
      for (const [critKey, crit] of Object.entries(criteria)) {
        const target = crit['target'] as number
        expect(
          target,
          `${rubricName}.${critKey} target ${target} is below the project minimum of 4`,
        ).toBeGreaterThanOrEqual(4)
      }
    }
  })
})

// ── tsconfig.hardening.json ───────────────────────────────────────────────────

describe('hardening/tsconfig.hardening.json', () => {
  const tsconfig = readJson('hardening/tsconfig.hardening.json') as Record<string, unknown>

  test('extends the base tsconfig', () => {
    expect(tsconfig['extends']).toBe('../tsconfig.base.json')
  })

  test('has compilerOptions', () => {
    expect(typeof tsconfig['compilerOptions']).toBe('object')
    expect(tsconfig['compilerOptions']).not.toBeNull()
  })

  const opts = () => tsconfig['compilerOptions'] as Record<string, unknown>

  test('enables exactOptionalPropertyTypes', () => {
    expect(opts()['exactOptionalPropertyTypes']).toBe(true)
  })

  test('enables noPropertyAccessFromIndexSignature', () => {
    expect(opts()['noPropertyAccessFromIndexSignature']).toBe(true)
  })

  test('enables noFallthroughCasesInSwitch', () => {
    expect(opts()['noFallthroughCasesInSwitch']).toBe(true)
  })

  test('enables forceConsistentCasingInFileNames', () => {
    expect(opts()['forceConsistentCasingInFileNames']).toBe(true)
  })

  test('disallows unreachable code (allowUnreachableCode: false)', () => {
    expect(opts()['allowUnreachableCode']).toBe(false)
  })

  test('disallows unused labels (allowUnusedLabels: false)', () => {
    expect(opts()['allowUnusedLabels']).toBe(false)
  })

  test('enables noImplicitReturns', () => {
    expect(opts()['noImplicitReturns']).toBe(true)
  })

  test('does not override strict mode to false', () => {
    // strict should either be absent (inherited from base) or true
    const strict = opts()['strict']
    expect(strict === undefined || strict === true).toBe(true)
  })

  test('has $schema field pointing to schemastore', () => {
    const schema = tsconfig['$schema'] as string
    expect(schema).toContain('tsconfig')
  })
})

// ── hardening/audit.sh ───────────────────────────────────────────────────────

describe('hardening/audit.sh', () => {
  const auditPath = join(ROOT, 'hardening/audit.sh')
  const auditText = readText('hardening/audit.sh')

  test('file exists and is non-empty', () => {
    const stat = statSync(auditPath)
    expect(stat.size).toBeGreaterThan(0)
  })

  test('starts with correct bash shebang', () => {
    expect(auditText.startsWith('#!/usr/bin/env bash')).toBe(true)
  })

  test('uses set -uo pipefail for safety', () => {
    expect(auditText).toContain('set -uo pipefail')
  })

  test('defines FAILED variable initialized to 0', () => {
    expect(auditText).toContain('FAILED=0')
  })

  test('defines WARNED variable initialized to 0', () => {
    expect(auditText).toContain('WARNED=0')
  })

  test('exits with code 1 on failures', () => {
    expect(auditText).toContain('exit 1')
  })

  const expectedSections = [
    'Bugs & Correctness',
    'Security',
    'DRY',
    'Performance',
    'Design System',
    'UX & Accessibility',
    'Build',
  ]

  test.each(expectedSections)('contains section: %s', (section) => {
    expect(auditText).toContain(section)
  })

  test('checks for TypeScript type errors via bun tsc --noEmit', () => {
    expect(auditText).toContain('bun tsc --noEmit')
  })

  test('checks for any type usage with grep', () => {
    expect(auditText).toContain(': any')
    expect(auditText).toContain('as any')
  })

  test('checks for dangerouslySetInnerHTML', () => {
    expect(auditText).toContain('dangerouslySetInnerHTML')
  })

  test('checks for localStorage auth token usage', () => {
    expect(auditText).toContain('localStorage.setItem')
  })

  test('checks for barrel index imports', () => {
    expect(auditText).toContain("from '.*/index'")
  })

  test('checks for raw hex color values', () => {
    expect(auditText).toContain('#[0-9a-fA-F]')
  })

  test('checks for img tags missing alt attributes', () => {
    expect(auditText).toContain('<img')
    expect(auditText).toContain('alt=')
  })

  test('runs dependency audit via bun audit --audit-level high', () => {
    expect(auditText).toContain('bun audit --audit-level high')
  })

  test('runs build as final check', () => {
    expect(auditText).toContain('bun run build')
  })

  test('skips checks gracefully when src/ directory is absent', () => {
    expect(auditText).toContain('[ -d src ]')
    // Multiple guards for the src/ directory
    const srcChecks = (auditText.match(/\[ -d src \]/g) ?? []).length
    expect(srcChecks).toBeGreaterThanOrEqual(5)
  })

  test('filters out env-variable references from secret scan', () => {
    expect(auditText).toContain('process\\.env\\.')
    expect(auditText).toContain('import\\.meta\\.env\\.')
  })

  test('filters out test/spec/mock files from secret scan', () => {
    expect(auditText).toContain('test\\|spec\\|mock\\|fixture')
  })

  test('dangerouslySetInnerHTML check excludes sanitized usages', () => {
    // The grep filters out lines that also contain DOMPurify/sanitize
    expect(auditText).toContain('DOMPurify\\|sanitize\\|sanitizeHtml')
  })

  test('summary exits 0 when only warnings (no failures)', () => {
    // The summary block only exits 1 if FAILED != 0
    expect(auditText).toContain('[ "$FAILED" -eq 0 ]')
  })
})

// ── .github/workflows/hardening.yml ─────────────────────────────────────────

describe('.github/workflows/hardening.yml', () => {
  const workflowText = readText('.github/workflows/hardening.yml')

  test('file is non-empty', () => {
    expect(workflowText.length).toBeGreaterThan(0)
  })

  test('has correct workflow name', () => {
    expect(workflowText).toContain('name: Hardening Checks')
  })

  test('triggers on push to master and main', () => {
    expect(workflowText).toContain('branches: [master, main]')
  })

  test('triggers on pull_request events', () => {
    expect(workflowText).toContain('pull_request:')
  })

  test('uses concurrency group to cancel in-progress runs', () => {
    expect(workflowText).toContain('cancel-in-progress: true')
    expect(workflowText).toContain('hardening-${{ github.ref }}')
  })

  const expectedJobs = ['type-check', 'lint', 'audit', 'secrets', 'bundle']

  test.each(expectedJobs)('defines job: %s', (job) => {
    expect(workflowText).toContain(`${job}:`)
  })

  test('type-check job runs bun tsc --noEmit', () => {
    expect(workflowText).toContain('bun tsc --noEmit')
  })

  test('lint job installs hardening ESLint deps', () => {
    expect(workflowText).toContain('typescript-eslint')
    expect(workflowText).toContain('eslint-plugin-jsx-a11y')
    expect(workflowText).toContain('eslint-plugin-react-hooks')
    expect(workflowText).toContain('eslint-plugin-security')
  })

  test('lint job uses hardening/eslint.config.js config', () => {
    expect(workflowText).toContain('hardening/eslint.config.js')
  })

  test('audit job runs bun audit', () => {
    expect(workflowText).toContain('bun audit')
  })

  test('secrets job uses gitleaks-action@v2', () => {
    expect(workflowText).toContain('gitleaks/gitleaks-action@v2')
  })

  test('secrets job fetches full history (fetch-depth: 0)', () => {
    expect(workflowText).toContain('fetch-depth: 0')
  })

  test('bundle job enforces 512000 byte limit', () => {
    expect(workflowText).toContain('MAX_BYTES=512000')
    expect(workflowText).toContain('512000')
  })

  test('bundle job skips gracefully when dist/ is absent', () => {
    expect(workflowText).toContain('No dist/ directory found')
    expect(workflowText).toContain('exit 0')
  })

  test('bundle job fails on oversized bundle (exit 1)', () => {
    expect(workflowText).toContain('exit 1')
  })

  test('all jobs run on ubuntu-latest', () => {
    const ubuntuCount = (workflowText.match(/ubuntu-latest/g) ?? []).length
    // There are 5 jobs, all should use ubuntu-latest
    expect(ubuntuCount).toBe(expectedJobs.length)
  })

  test('all jobs install dependencies with --frozen-lockfile', () => {
    const frozenCount = (workflowText.match(/--frozen-lockfile/g) ?? []).length
    // All jobs that use bun install should use --frozen-lockfile
    expect(frozenCount).toBeGreaterThanOrEqual(4)
  })

  test('GITHUB_TOKEN is used for secret scanning (not hardcoded)', () => {
    expect(workflowText).toContain('secrets.GITHUB_TOKEN')
  })
})

// ── hardening/eslint.config.js (static content) ──────────────────────────────

describe('hardening/eslint.config.js', () => {
  const configText = readText('hardening/eslint.config.js')

  test('file is non-empty', () => {
    expect(configText.length).toBeGreaterThan(0)
  })

  test('imports typescript-eslint', () => {
    expect(configText).toContain("from 'typescript-eslint'")
  })

  test('imports eslint-plugin-jsx-a11y', () => {
    expect(configText).toContain("from 'eslint-plugin-jsx-a11y'")
  })

  test('imports eslint-plugin-react-hooks', () => {
    expect(configText).toContain("from 'eslint-plugin-react-hooks'")
  })

  test('imports eslint-plugin-security', () => {
    expect(configText).toContain("from 'eslint-plugin-security'")
  })

  test('uses strictTypeChecked from typescript-eslint', () => {
    expect(configText).toContain('tseslint.configs.strictTypeChecked')
  })

  test('forbids explicit any type', () => {
    expect(configText).toContain('@typescript-eslint/no-explicit-any')
    expect(configText).toContain("'error'")
  })

  test('forbids non-null assertions', () => {
    expect(configText).toContain('@typescript-eslint/no-non-null-assertion')
  })

  test('forbids floating promises', () => {
    expect(configText).toContain('@typescript-eslint/no-floating-promises')
  })

  test('forbids misused promises', () => {
    expect(configText).toContain('@typescript-eslint/no-misused-promises')
  })

  test('enforces max file length of 300 lines', () => {
    expect(configText).toContain('max-lines')
    expect(configText).toContain('max: 300')
  })

  test('enforces max cyclomatic complexity of 10', () => {
    expect(configText).toContain('complexity')
    expect(configText).toContain('max: 10')
  })

  test('enforces max function params of 4', () => {
    expect(configText).toContain('max-params')
    expect(configText).toContain('max: 4')
  })

  test('forbids eval', () => {
    expect(configText).toContain("'no-eval'")
  })

  test('forbids new Function()', () => {
    expect(configText).toContain("'no-new-func'")
  })

  test('restricts dangerouslySetInnerHTML with descriptive message', () => {
    expect(configText).toContain('dangerouslySetInnerHTML')
    expect(configText).toContain('DOMPurify')
  })

  test('restricts localStorage with descriptive message', () => {
    expect(configText).toContain('localStorage')
    expect(configText).toContain('HttpOnly cookies')
  })

  test('restricts barrel index imports with descriptive message', () => {
    expect(configText).toContain('/index$')
    expect(configText).toContain('tree-shaking')
  })

  test('includes jsx-a11y alt-text rule as error', () => {
    expect(configText).toContain('jsx-a11y/alt-text')
  })

  test('includes jsx-a11y click-events-have-key-events rule', () => {
    expect(configText).toContain('jsx-a11y/click-events-have-key-events')
  })

  test('includes react-hooks exhaustive-deps as error', () => {
    expect(configText).toContain('react-hooks/exhaustive-deps')
  })

  test('uses export default for the config array', () => {
    expect(configText).toContain('export default hardeningConfig')
  })
})