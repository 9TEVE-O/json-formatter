#!/usr/bin/env bash
# Unit tests for the grep patterns used in hardening/audit.sh.
# Each test creates a temporary directory with controlled fixture content,
# runs the exact same pattern the script uses, and asserts the expected count.
#
# Usage: bash hardening/audit_patterns_test.sh
# Exit: 0 if all pass, 1 if any fail.

set -uo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo -e "  ${GREEN}✓${NC} $description"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $description  (expected $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# Create a fresh src/ directory for each test group
setup_src() {
  FIXTURE_DIR="$(mktemp -d -p "$TMPDIR_ROOT")"
  mkdir -p "$FIXTURE_DIR/src"
  echo "$FIXTURE_DIR"
}

# ── Pattern: any-type detection ───────────────────────────────────────────────
# Source pattern:
#   grep -rn ': any\b\|as any\b\|<any>' src --include='*.ts' --include='*.tsx'

echo ""
echo -e "${BOLD}[ any-type detection pattern ]${NC}"

DIR=$(setup_src)
# Should detect: ': any', 'as any', '<any>'
cat > "$DIR/src/foo.ts" <<'EOF'
const x: any = 5
const y = bar as any
function baz<any>() {}
// should NOT match: 'notany' or 'someanyvalue'
const notany = 'hello'
EOF

COUNT=$(grep -rn ': any\b\|as any\b\|<any>' "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "detects ': any', 'as any', '<any>' in .ts file" 3 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/clean.ts" <<'EOF'
const x: unknown = 5
function identity<T>(val: T): T { return val }
EOF
COUNT=$(grep -rn ': any\b\|as any\b\|<any>' "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "returns 0 for clean TypeScript file" 0 "$COUNT"

DIR=$(setup_src)
# tsx file should also be scanned
cat > "$DIR/src/component.tsx" <<'EOF'
const data: any = fetchData()
EOF
COUNT=$(grep -rn ': any\b\|as any\b\|<any>' "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "detects 'any' in .tsx files" 1 "$COUNT"

DIR=$(setup_src)
# partial word 'company' or 'antany' should NOT match
cat > "$DIR/src/words.ts" <<'EOF'
const company = 'Acme'
const botany = 'study of plants'
const fantasy = 'dream'
EOF
COUNT=$(grep -rn ': any\b\|as any\b\|<any>' "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "does not match partial word 'any' (company, botany, fantasy)" 0 "$COUNT"

# ── Pattern: secret detection ─────────────────────────────────────────────────
# Source pattern:
#   grep -rniE "(api[_-]?key|secret|password|token|private[_-]?key)\s*[:=]\s*[\"'][^\"']{8,}" src
#   | grep -v 'process\.env\.' | grep -v 'import\.meta\.env\.' | grep -v '\.env\.'
#   | grep -v 'test\|spec\|mock\|fixture'

echo ""
echo -e "${BOLD}[ secret detection pattern ]${NC}"

SECRET_PATTERN="(api[_-]?key|secret|password|token|private[_-]?key)\\s*[:=]\\s*[\"'][^\"']{8,}"

DIR=$(setup_src)
cat > "$DIR/src/config.ts" <<'EOF'
const apiKey = 'sk-abcdefghijklmnop'
const secret = "supersecretvalue123"
const password = 'p@ssw0rdX9'
const token = 'ghp_ABCDEFGHIJKLMNOPQRST'
const private_key = 'MIIEvQIBADANBgkq'
EOF
COUNT=$(grep -rniE "$SECRET_PATTERN" "$DIR/src" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
  | grep -v 'process\.env\.' \
  | grep -v 'import\.meta\.env\.' \
  | grep -v '\.env\.' \
  | grep -v 'test\|spec\|mock\|fixture' \
  | wc -l | tr -d ' ')
assert_eq "detects hardcoded api_key, secret, password, token, private_key" 5 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/env-usage.ts" <<'EOF'
const apiKey = process.env.API_KEY
const secret = import.meta.env.SECRET
const password = someObj.env.PASSWORD
EOF
COUNT=$(grep -rniE "$SECRET_PATTERN" "$DIR/src" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
  | grep -v 'process\.env\.' \
  | grep -v 'import\.meta\.env\.' \
  | grep -v '\.env\.' \
  | grep -v 'test\|spec\|mock\|fixture' \
  | wc -l | tr -d ' ')
assert_eq "env variable references are not flagged as secrets" 0 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/fixtures.spec.ts" <<'EOF'
const token = 'fixture_token_value_here'
const password = 'mock_password_12345'
EOF
COUNT=$(grep -rniE "$SECRET_PATTERN" "$DIR/src" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
  | grep -v 'process\.env\.' \
  | grep -v 'import\.meta\.env\.' \
  | grep -v '\.env\.' \
  | grep -v 'test\|spec\|mock\|fixture' \
  | wc -l | tr -d ' ')
assert_eq "test/spec/mock/fixture files are excluded from secret scan" 0 "$COUNT"

DIR=$(setup_src)
# Short values (< 8 chars) should NOT match
cat > "$DIR/src/short.ts" <<'EOF'
const token = 'abc'
const password = '1234567'
EOF
COUNT=$(grep -rniE "$SECRET_PATTERN" "$DIR/src" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
  | grep -v 'process\.env\.' | grep -v 'import\.meta\.env\.' | grep -v '\.env\.' \
  | grep -v 'test\|spec\|mock\|fixture' \
  | wc -l | tr -d ' ')
assert_eq "short credential values (< 8 chars) are not flagged" 0 "$COUNT"

DIR=$(setup_src)
# api-key variant (with dash)
cat > "$DIR/src/dash.ts" <<'EOF'
const api-key = 'longapivalue1234'
EOF
COUNT=$(grep -rniE "$SECRET_PATTERN" "$DIR/src" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
  | grep -v 'process\.env\.' | grep -v 'import\.meta\.env\.' | grep -v '\.env\.' \
  | grep -v 'test\|spec\|mock\|fixture' \
  | wc -l | tr -d ' ')
assert_eq "api-key (dash variant) is detected" 1 "$COUNT"

# ── Pattern: dangerouslySetInnerHTML without sanitizer ────────────────────────
# Source pattern:
#   grep -rn 'dangerouslySetInnerHTML' src --include='*.tsx' --include='*.jsx'
#   | grep -v 'DOMPurify\|sanitize\|sanitizeHtml'

echo ""
echo -e "${BOLD}[ dangerouslySetInnerHTML pattern ]${NC}"

DIR=$(setup_src)
cat > "$DIR/src/unsafe.tsx" <<'EOF'
function Comp({ html }: { html: string }) {
  return <div dangerouslySetInnerHTML={{ __html: html }} />
}
EOF
COUNT=$(grep -rn 'dangerouslySetInnerHTML' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'DOMPurify\|sanitize\|sanitizeHtml' | wc -l | tr -d ' ')
assert_eq "detects unsanitized dangerouslySetInnerHTML" 1 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/safe.tsx" <<'EOF'
import DOMPurify from 'dompurify'
function Comp({ html }: { html: string }) {
  // dangerouslySetInnerHTML wrapped with DOMPurify.sanitize
  return <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }} />
}
EOF
COUNT=$(grep -rn 'dangerouslySetInnerHTML' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'DOMPurify\|sanitize\|sanitizeHtml' | wc -l | tr -d ' ')
assert_eq "sanitized dangerouslySetInnerHTML (DOMPurify) is not flagged" 0 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/safe2.tsx" <<'EOF'
function Comp({ html }: { html: string }) {
  return <div dangerouslySetInnerHTML={{ __html: sanitizeHtml(html) }} />
}
EOF
COUNT=$(grep -rn 'dangerouslySetInnerHTML' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'DOMPurify\|sanitize\|sanitizeHtml' | wc -l | tr -d ' ')
assert_eq "dangerouslySetInnerHTML wrapped with sanitizeHtml() is not flagged" 0 "$COUNT"

DIR=$(setup_src)
# .ts files should NOT be scanned (only .tsx/.jsx)
cat > "$DIR/src/notJSX.ts" <<'EOF'
const dangerous = 'dangerouslySetInnerHTML'
EOF
COUNT=$(grep -rn 'dangerouslySetInnerHTML' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'DOMPurify\|sanitize\|sanitizeHtml' | wc -l | tr -d ' ')
assert_eq "dangerouslySetInnerHTML in .ts files is not scanned" 0 "$COUNT"

# ── Pattern: localStorage auth token ─────────────────────────────────────────
# Source pattern:
#   grep -rn 'localStorage.setItem' src --include='*.ts' --include='*.tsx'
#   | grep -iE 'token|auth|session|jwt|key'

echo ""
echo -e "${BOLD}[ localStorage auth token pattern ]${NC}"

DIR=$(setup_src)
cat > "$DIR/src/auth.ts" <<'EOF'
localStorage.setItem('authToken', token)
localStorage.setItem('jwt', jwtValue)
localStorage.setItem('session_id', sid)
localStorage.setItem('user_key', key)
localStorage.setItem('ACCESS_AUTH', val)
EOF
COUNT=$(grep -rn 'localStorage\.setItem' "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null \
  | grep -iE 'token|auth|session|jwt|key' | wc -l | tr -d ' ')
assert_eq "detects localStorage.setItem with auth-related keys" 5 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/safe-storage.ts" <<'EOF'
localStorage.setItem('theme', 'dark')
localStorage.setItem('language', 'en')
localStorage.setItem('preferredCurrency', 'USD')
EOF
COUNT=$(grep -rn 'localStorage\.setItem' "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null \
  | grep -iE 'token|auth|session|jwt|key' | wc -l | tr -d ' ')
assert_eq "localStorage.setItem with non-auth keys is not flagged" 0 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/cookies.ts" <<'EOF'
// Using HttpOnly cookies instead — no localStorage here
document.cookie = 'session=abc; HttpOnly; Secure'
EOF
COUNT=$(grep -rn 'localStorage\.setItem' "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null \
  | grep -iE 'token|auth|session|jwt|key' | wc -l | tr -d ' ')
assert_eq "HttpOnly cookie usage is not flagged" 0 "$COUNT"

# ── Pattern: barrel index imports ─────────────────────────────────────────────
# Source pattern:
#   grep -rn "from '.*/index'" src --include='*.ts' --include='*.tsx'

echo ""
echo -e "${BOLD}[ barrel index import pattern ]${NC}"

DIR=$(setup_src)
cat > "$DIR/src/barrel-user.ts" <<'EOF'
import { foo } from './components/index'
import { bar } from '../utils/index'
import { baz } from '../../lib/index'
EOF
COUNT=$(grep -rn "from '.*/index'" "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "detects barrel index imports" 3 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/direct-imports.ts" <<'EOF'
import { foo } from './components/Foo'
import { bar } from '../utils/formatDate'
import type { Baz } from '../../lib/types'
EOF
COUNT=$(grep -rn "from '.*/index'" "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "direct non-barrel imports are not flagged" 0 "$COUNT"

DIR=$(setup_src)
# 'index' appearing in the middle of a path should NOT match
cat > "$DIR/src/index-in-middle.ts" <<'EOF'
import { thing } from './index-helpers/someFile'
import { other } from '../reindex/module'
EOF
COUNT=$(grep -rn "from '.*/index'" "$DIR/src" --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "'index' in middle of path is not flagged as barrel import" 0 "$COUNT"

# ── Pattern: raw hex colors ───────────────────────────────────────────────────
# Source pattern:
#   grep -rn '#[0-9a-fA-F]\{3,8\}' dir --include='*.ts' --include='*.tsx' --include='*.css'
#   | grep -v 'tokens\|token\|theme\|colors\.\|palette\.\|\.test\.'

echo ""
echo -e "${BOLD}[ raw hex color pattern ]${NC}"

DIR=$(setup_src)
cat > "$DIR/src/button.tsx" <<'EOF'
const style = { color: '#ff0000', background: '#3b82f6' }
const border = '#fff'
const shadow = '#00000080'
EOF
COUNT=$(grep -rn '#[0-9a-fA-F]\{3,8\}' "$DIR/src" \
  --include='*.ts' --include='*.tsx' --include='*.css' 2>/dev/null \
  | grep -v 'tokens\|token\|theme\|colors\.\|palette\.\|\.test\.' \
  | wc -l | tr -d ' ')
assert_eq "detects raw hex colors in .tsx files" 3 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/tokens.ts" <<'EOF'
// design tokens file
export const colors = {
  primary: '#3b82f6',
  danger: '#ef4444',
}
export const palette = {
  white: '#ffffff',
}
EOF
COUNT=$(grep -rn '#[0-9a-fA-F]\{3,8\}' "$DIR/src" \
  --include='*.ts' --include='*.tsx' --include='*.css' 2>/dev/null \
  | grep -v 'tokens\|token\|theme\|colors\.\|palette\.\|\.test\.' \
  | wc -l | tr -d ' ')
assert_eq "hex values in design token files are excluded" 0 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/styles.css" <<'EOF'
.button {
  color: #ff0000;
  border: 2px solid #cccccc;
}
EOF
COUNT=$(grep -rn '#[0-9a-fA-F]\{3,8\}' "$DIR/src" \
  --include='*.ts' --include='*.tsx' --include='*.css' 2>/dev/null \
  | grep -v 'tokens\|token\|theme\|colors\.\|palette\.\|\.test\.' \
  | wc -l | tr -d ' ')
assert_eq "detects raw hex colors in .css files" 2 "$COUNT"

DIR=$(setup_src)
# 2-char hex (too short) should not match
cat > "$DIR/src/short-hex.ts" <<'EOF'
const x = '#ff'
const y = '#a'
EOF
COUNT=$(grep -rn '#[0-9a-fA-F]\{3,8\}' "$DIR/src" \
  --include='*.ts' --include='*.tsx' --include='*.css' 2>/dev/null \
  | grep -v 'tokens\|token\|theme\|colors\.\|palette\.\|\.test\.' \
  | wc -l | tr -d ' ')
assert_eq "2-char hex values are not flagged (minimum is 3 hex chars)" 0 "$COUNT"

# ── Pattern: img without alt ──────────────────────────────────────────────────
# Source pattern:
#   grep -rn '<img\b' src --include='*.tsx' --include='*.jsx'
#   | grep -v 'alt='

echo ""
echo -e "${BOLD}[ img alt-text pattern ]${NC}"

DIR=$(setup_src)
cat > "$DIR/src/page.tsx" <<'EOF'
function Page() {
  return (
    <div>
      <img src="logo.png" />
      <img src="banner.jpg" width={800} height={200} />
    </div>
  )
}
EOF
COUNT=$(grep -rn '<img\b' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'alt=' | wc -l | tr -d ' ')
assert_eq "detects img tags missing alt attribute" 2 "$COUNT"

DIR=$(setup_src)
cat > "$DIR/src/accessible.tsx" <<'EOF'
function Page() {
  return (
    <div>
      <img src="logo.png" alt="Company Logo" />
      <img src="banner.jpg" alt="" aria-hidden="true" />
    </div>
  )
}
EOF
COUNT=$(grep -rn '<img\b' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'alt=' | wc -l | tr -d ' ')
assert_eq "img tags with alt attributes are not flagged" 0 "$COUNT"

DIR=$(setup_src)
# .ts files should NOT be scanned for img tags
cat > "$DIR/src/helper.ts" <<'EOF'
const imgTag = '<img src="x.png">'
EOF
COUNT=$(grep -rn '<img\b' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'alt=' | wc -l | tr -d ' ')
assert_eq "img strings in .ts files are not scanned for alt" 0 "$COUNT"

DIR=$(setup_src)
# 'img' should not trigger on partial words like 'image' or 'imaging'
cat > "$DIR/src/partials.tsx" <<'EOF'
function Comp() {
  return <image src="x.png" />
}
const imaging = true
EOF
COUNT=$(grep -rn '<img\b' "$DIR/src" --include='*.tsx' --include='*.jsx' 2>/dev/null \
  | grep -v 'alt=' | wc -l | tr -d ' ')
assert_eq "<image> does not match <img> pattern" 0 "$COUNT"

# ── Pattern: bundle size gate (hardening.yml logic) ───────────────────────────
# Test the arithmetic logic: bundle exceeds limit when BUNDLE_BYTES > MAX_BYTES

echo ""
echo -e "${BOLD}[ bundle size gate logic ]${NC}"

MAX_BYTES=512000

# Simulate checking a bundle within limit
BUNDLE_BYTES=400000
if [ "${BUNDLE_BYTES}" -gt "${MAX_BYTES}" ]; then
  RESULT="exceeded"
else
  RESULT="within"
fi
if [ "$RESULT" = "within" ]; then
  echo -e "  ${GREEN}✓${NC} bundle within limit passes (400000 < 512000)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} bundle within limit should pass"
  FAIL=$((FAIL + 1))
fi

# Simulate a bundle exactly at the limit (should pass)
BUNDLE_BYTES=512000
if [ "${BUNDLE_BYTES}" -gt "${MAX_BYTES}" ]; then
  RESULT="exceeded"
else
  RESULT="within"
fi
if [ "$RESULT" = "within" ]; then
  echo -e "  ${GREEN}✓${NC} bundle exactly at limit (512000 == 512000) passes"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} bundle exactly at limit should pass (not strictly greater)"
  FAIL=$((FAIL + 1))
fi

# Simulate a bundle over the limit
BUNDLE_BYTES=512001
if [ "${BUNDLE_BYTES}" -gt "${MAX_BYTES}" ]; then
  RESULT="exceeded"
else
  RESULT="within"
fi
if [ "$RESULT" = "exceeded" ]; then
  echo -e "  ${GREEN}✓${NC} bundle over limit fails (512001 > 512000)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} bundle over limit should fail"
  FAIL=$((FAIL + 1))
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
TOTAL=$((PASS + FAIL))
echo -e "${BOLD}Results: ${PASS}/${TOTAL} tests passed${NC}"
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All pattern tests passed.${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}${FAIL} test(s) failed.${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  exit 1
fi
