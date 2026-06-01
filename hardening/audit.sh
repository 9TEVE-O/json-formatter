#!/usr/bin/env bash
# Run all 6 rubric checks locally before pushing.
# Usage: bash hardening/audit.sh
#
# Requires: bun, tsc (via bun tsc), optionally jscpd (npm i -g jscpd)

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

FAILED=0
WARNED=0

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; FAILED=1; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; WARNED=1; }
section() { echo -e "\n${BOLD}[ $1 ]${NC}"; }

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Project Hardening Audit (6-Rubric Check)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ── Bugs & Correctness: TypeScript ─────────────────────────────────────────
section "Bugs & Correctness — TypeScript"
if bun tsc --noEmit 2>&1; then
  pass "tsc: no type errors"
else
  fail "tsc: type errors found"
fi

# ── Bugs & Correctness: no `any` type ──────────────────────────────────────
section "Bugs & Correctness — Type safety"
if [ -d src ]; then
  ANY_COUNT=$(grep -rn ': any\b\|as any\b\|<any>' src --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$ANY_COUNT" -eq 0 ]; then
    pass "No 'any' type usage in src/"
  else
    fail "$ANY_COUNT 'any' occurrence(s) — use 'unknown' + narrowing"
    grep -rn ': any\b\|as any\b\|<any>' src --include='*.ts' --include='*.tsx' 2>/dev/null | head -5
  fi
else
  warn "No src/ directory found — skipping any-type scan"
fi

# ── Security: no hardcoded secrets ─────────────────────────────────────────
section "Security — Hardcoded secrets"
SECRET_PATTERN="(api[_-]?key|secret|password|token|private[_-]?key)\\s*[:=]\\s*[\"'][^\"']{8,}"
if [ -d src ]; then
  SECRET_HITS=$(grep -rniE "$SECRET_PATTERN" src --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
    | grep -v 'process\.env\.' \
    | grep -v 'import\.meta\.env\.' \
    | grep -v '\.env\.' \
    | grep -v 'test\|spec\|mock\|fixture' \
    | wc -l | tr -d ' ')
  if [ "$SECRET_HITS" -eq 0 ]; then
    pass "No hardcoded secrets detected"
  else
    fail "$SECRET_HITS possible hardcoded secret(s) detected"
    grep -rniE "$SECRET_PATTERN" src --include='*.ts' --include='*.tsx' 2>/dev/null \
      | grep -v 'process\.env\.' | grep -v 'import\.meta\.env\.' | head -5
  fi
else
  warn "No src/ directory — skipping secret scan"
fi

# ── Security: dangerouslySetInnerHTML ──────────────────────────────────────
section "Security — dangerouslySetInnerHTML"
if [ -d src ]; then
  DANGEROUS=$(grep -rn 'dangerouslySetInnerHTML' src --include='*.tsx' --include='*.jsx' 2>/dev/null \
    | grep -v 'DOMPurify\|sanitize\|sanitizeHtml' | wc -l | tr -d ' ')
  if [ "$DANGEROUS" -eq 0 ]; then
    pass "No unsanitized dangerouslySetInnerHTML"
  else
    fail "$DANGEROUS unsanitized dangerouslySetInnerHTML usage(s) — wrap with sanitizeHtml()"
  fi
else
  warn "No src/ directory — skipping innerHTML scan"
fi

# ── Security: localStorage auth tokens ─────────────────────────────────────
section "Security — Auth token storage"
if [ -d src ]; then
  LS_AUTH=$(grep -rn 'localStorage\.setItem' src --include='*.ts' --include='*.tsx' 2>/dev/null \
    | grep -iE 'token|auth|session|jwt|key' | wc -l | tr -d ' ')
  if [ "$LS_AUTH" -eq 0 ]; then
    pass "No auth tokens in localStorage"
  else
    warn "$LS_AUTH possible auth token(s) stored in localStorage — use HttpOnly cookies"
  fi
else
  warn "No src/ directory — skipping localStorage scan"
fi

# ── Security: dependency audit ─────────────────────────────────────────────
section "Security — Dependency audit"
if command -v bun &>/dev/null; then
  if bun audit --audit-level high 2>&1; then
    pass "bun audit: no high/critical CVEs"
  else
    fail "bun audit: high/critical vulnerabilities found — run 'bun audit' for details"
  fi
elif command -v npm &>/dev/null; then
  if npm audit --audit-level high 2>&1; then
    pass "npm audit: no high/critical CVEs"
  else
    fail "npm audit: high/critical vulnerabilities found"
  fi
else
  warn "No package manager found — skipping dependency audit"
fi

# ── DRY: duplicate code detection ─────────────────────────────────────────
section "DRY / SSOT — Duplicate code blocks"
if command -v jscpd &>/dev/null && [ -d src ]; then
  CLONE_OUTPUT=$(jscpd src --min-lines 10 --min-tokens 100 --reporters console \
    --ignore '**/*.test.*,**/*.spec.*' 2>&1)
  if echo "$CLONE_OUTPUT" | grep -q '0 clones found'; then
    pass "jscpd: no duplicate blocks detected"
  else
    warn "jscpd: duplicate code blocks found — consider extraction"
    echo "$CLONE_OUTPUT" | tail -5
  fi
else
  warn "jscpd not installed (npm i -g jscpd) or no src/ — skipping clone detection"
fi

# ── Performance: barrel index imports ─────────────────────────────────────
section "Performance — Barrel index imports"
if [ -d src ]; then
  BARREL=$(grep -rn "from '.*/index'" src --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BARREL" -eq 0 ]; then
    pass "No barrel index imports detected"
  else
    warn "$BARREL barrel index import(s) — may defeat tree-shaking"
  fi
else
  warn "No src/ directory — skipping barrel scan"
fi

# ── Design System: raw hex values ─────────────────────────────────────────
section "Design System — Raw hex colors"
HEX_DIRS="src"
[ -d lib ] && HEX_DIRS="$HEX_DIRS lib"
HEX_COUNT=0
for dir in $HEX_DIRS; do
  if [ -d "$dir" ]; then
    C=$(grep -rn '#[0-9a-fA-F]\{3,8\}' "$dir" \
      --include='*.ts' --include='*.tsx' --include='*.css' 2>/dev/null \
      | grep -v 'tokens\|token\|theme\|colors\.\|palette\.\|\.test\.' \
      | wc -l | tr -d ' ')
    HEX_COUNT=$((HEX_COUNT + C))
  fi
done
if [ "$HEX_COUNT" -eq 0 ]; then
  pass "No raw hex values in source (move to design tokens)"
else
  warn "$HEX_COUNT raw hex value(s) — move to design tokens"
fi

# ── UX/Accessibility: img without alt ────────────────────────────────────
section "UX & Accessibility — img alt attributes"
if [ -d src ]; then
  ALT_MISSING=$(grep -rn '<img\b' src --include='*.tsx' --include='*.jsx' 2>/dev/null \
    | grep -v 'alt=' | wc -l | tr -d ' ')
  if [ "$ALT_MISSING" -eq 0 ]; then
    pass "All img tags have alt attributes"
  else
    fail "$ALT_MISSING img tag(s) missing alt attribute"
    grep -rn '<img\b' src --include='*.tsx' --include='*.jsx' 2>/dev/null | grep -v 'alt=' | head -5
  fi
else
  warn "No src/ directory — skipping alt-text scan"
fi

# ── Build ─────────────────────────────────────────────────────────────────
section "Build"
if bun run build 2>&1; then
  pass "Build succeeded"
else
  fail "Build failed"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$FAILED" -eq 0 ] && [ "$WARNED" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All hardening checks passed.${NC}"
elif [ "$FAILED" -eq 0 ]; then
  echo -e "${YELLOW}${BOLD}Passed with warnings — review above before merging.${NC}"
else
  echo -e "${RED}${BOLD}Hardening audit FAILED — fix issues above before pushing.${NC}"
  echo ""
  exit 1
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
