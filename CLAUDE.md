# Project Hardening Standards

Every code change must be evaluated against the six quality rubrics below.
Before marking any task complete, check the relevant criteria and raise
issues if any criterion falls below level 3. Target is level 4–5 across
all areas.

Run `bash hardening/audit.sh` before every push. The CI workflow at
`.github/workflows/hardening.yml` enforces these checks automatically.

---

## 1. Design System

**Atoms / molecules / organisms layer boundaries must be respected.**

- All colors, spacing, typography, and radius values come from design tokens — no raw hex values, no magic pixel numbers
- Component variants are expressed via props, never by copy-pasting a near-identical component
- Spacing comes from the token scale; layout uses Stack/Grid primitives, not arbitrary margins
- Type scale defined (xs–5xl); no raw `font-size` values in component code
- Storybook stories exist at each atomic layer (or equivalent visual test)

**Block merge if:**
- Raw hex color appears in any component file (e.g. `#3b82f6`, `rgba(0,0,0,0.5)`)
- `style={{ margin: '12px' }}` or similar magic-number inline style
- A new component is a copy-paste of an existing one instead of a shared abstraction

---

## 2. DRY / SOLID / SSOT / KISS

**No logic should exist in two places; no file should have two reasons to change.**

- Any logic appearing in 2+ files must be extracted to a shared hook or utility
- UI components hold no business logic — hooks own state, effects, and validation
- Every constant, config value, and type has exactly one canonical source
- Abstractions must be justified by actual reuse — no speculative layers
- Circular imports are forbidden
- Max file length: 300 lines. Max cyclomatic complexity: 10. Max function params: 4.

**Block merge if:**
- Same logic block appears in 2+ places
- Business logic (API calls, validation, calculations) lives inside a React component body
- The same constant is defined in more than one file

---

## 3. UX & Accessibility

**Every interaction must work without a mouse; every piece of content must be perceivable.**

- All interactive elements are keyboard operable with visible focus styling
- `skip-to-content` link present on all pages; modals trap and restore focus
- All images have descriptive `alt` text; all form fields have associated `<label>` elements
- WCAG AA contrast minimum (4.5:1 text, 3:1 UI) on all visible elements
- 44px minimum touch target size
- All animations respect `prefers-reduced-motion`
- Custom widgets carry correct ARIA roles and live-region announcements
- Loading states: skeleton screens not spinners; errors are contextual with a retry action

**Block merge if:**
- `onClick` handler on a non-interactive element without `role` and `tabIndex`
- `<img>` without `alt` attribute
- Error state that only shows "Something went wrong" with no retry
- Animation added with no `prefers-reduced-motion` media query guard

---

## 4. Performance

**Measure first; optimize second. Every budget must be tracked in CI.**

- Heavy dependencies imported with dynamic `import()`, never at module top-level
- No barrel-file (`index.ts`) re-exports on large modules — they defeat tree-shaking
- `useMemo` / `useCallback` only where render profiling proves a win
- Lists of 50+ items must be virtualized
- All `<img>` tags carry explicit `width` and `height`; use WebP/AVIF formats
- Data fetching uses SWR or React Query (stale-while-revalidate); no waterfall `useEffect` chains
- Target: LCP < 2.5 s, CLS < 0.1, INP < 200 ms, initial JS ≤ 500 KB (target ≤ 100 KB)

**Block merge if:**
- New barrel index import that pulls in an entire module tree
- Un-keyed list render
- New waterfall fetch chain (effect that triggers another effect via state)

---

## 5. Bugs & Correctness

**TypeScript strict mode is non-negotiable. Every async path must be handled.**

- No `any` type — use `unknown` + narrowing or proper generics
- No `as` casts to escape the type system; use discriminated unions and type guards
- Every async operation handles rejection; no floating unhandled promises
- State mutations are forbidden — always return new references
- Every component that receives array or nullable data must render an empty/null state
- Race conditions addressed with AbortController or query deduplication
- Error boundaries wrap each major feature; structured logging on every caught error

**Block merge if:**
- `any` type — use `unknown` + narrowing
- Floating promise (unawaited async call / `.then()` with no `.catch()`)
- Component receiving a nullable prop with no null-state render path

---

## 6. Security

**No secret ever touches source control. No user input ever reaches the DOM unencoded.**

- `dangerouslySetInnerHTML` is forbidden without DOMPurify sanitization — use `sanitizeHtml()` wrapper
- API keys and secrets live in environment variables only; never in source files
- All external input validated with a schema — arktype is available in this project
- Auth tokens stored in HttpOnly cookies only; never localStorage or sessionStorage
- `bun audit` must pass at `--audit-level high` before merge
- CSP headers set on all server responses

**Block merge if:**
- Any hardcoded credential, token, or API key
- `dangerouslySetInnerHTML` without a DOMPurify call on the same value
- User-controlled data interpolated into a URL or HTML string without encoding
- `bun audit` returns a high or critical CVE

---

## Automated Enforcement

| Check | Tool | Config |
|---|---|---|
| Type safety | `tsc --noEmit` | `tsconfig.base.json` |
| ESLint hardening | `eslint` | `hardening/eslint.config.js` |
| Dependency CVEs | `bun audit` | — |
| Secret scanning | `gitleaks` | CI only |
| Bundle size | custom script | `.github/workflows/hardening.yml` |
| Local all-in-one | `bash hardening/audit.sh` | — |
