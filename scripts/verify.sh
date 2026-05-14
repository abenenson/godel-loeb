#!/usr/bin/env bash
# verify.sh — repository verification checks for Lean files
#
# Usage:
#   scripts/verify.sh [--lean] PATH...
#
# Checks:
#   (mechanical, always run)
#   1. Single copyright header per file, correct format
#   2. No `(show T from x)` coercion pattern
#   3. No broad `import Mathlib` without qualification
#   4. No blank lines inside proof blocks
#   5. Lines ≤ 100 chars
#   6. No automated co-author trailers in git history
#   7. No `by` on its own line
#   8. Module header `/-! ... -/` present
#   9. No `λ` in code
#  10. No ` $ ` for function application
#
#   (lean-required, only with --lean flag)
#  11. `#lint` passes (docBlame, naming, style linters)
#  12. Zero sorries
#
# Exit codes:
#   0  all checks pass
#   1  one or more checks failed (details printed to stderr)
#
# Notes:
#   - Run without --lean for fast pre-commit gating (< 1s per file)
#   - Run with --lean during PR prep (requires lake env lean, ~minutes per file)
#   - The --lean checks require a built Mathlib olean cache in .lake/
#   - Does NOT check proof quality or tactic style

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── argument parsing ──────────────────────────────────────────────────────────
RUN_LEAN=false
PATHS=()
for arg in "$@"; do
  case "$arg" in
    --lean) RUN_LEAN=true ;;
    -h|--help) sed -n '2,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'; exit 0 ;;
    *) PATHS+=("$arg") ;;
  esac
done

if [[ ${#PATHS[@]} -eq 0 ]]; then
  echo "Usage: $0 [--lean] PATH..." >&2
  exit 1
fi

# ── collect .lean files ───────────────────────────────────────────────────────
LEAN_FILES=()
for p in "${PATHS[@]}"; do
  if [[ -f "$p" && "$p" == *.lean ]]; then
    LEAN_FILES+=("$p")
  elif [[ -d "$p" ]]; then
    while IFS= read -r f; do
      LEAN_FILES+=("$f")
    done < <(find "$p" -name "*.lean" -not -path "*/.lake/*" | sort)
  fi
done

if [[ ${#LEAN_FILES[@]} -eq 0 ]]; then
  echo "No .lean files found in: ${PATHS[*]}" >&2
  exit 1
fi

FAILURES=0
WARNINGS=0

fail() { echo "  FAIL: $*" >&2; ((FAILURES++)) || true; }
warn() { echo "  WARN: $*" >&2; ((WARNINGS++)) || true; }
pass() { echo "  ok:   $*"; }

# ── Check 1: single copyright header ─────────────────────────────────────────
check_copyright() {
  local f="$1"
  local count
  count=$(grep -c "^Copyright" "$f" 2>/dev/null || true)
  count="${count:-0}"
  if [[ "$count" -eq 0 ]]; then
    fail "$f: missing copyright header (expected '/-\\nCopyright (c) YYYY Author...')"
  elif [[ "$count" -gt 1 ]]; then
    fail "$f: duplicate copyright headers ($count found)"
  else
    local line
    line=$(grep "^Copyright" "$f" | head -1)
    if ! echo "$line" | grep -qE "^Copyright \(c\) [0-9]{4} .+\. All rights reserved\."; then
      warn "$f: copyright format unexpected: $line"
    fi
  fi
}

# ── Check 2: `(show T from x)` coercion pattern ──────────────────────────────
check_show_coercion() {
  local f="$1"
  local count
  count=$(grep -c "(show .* from " "$f" 2>/dev/null || true); count="${count:-0}"
  if [[ "$count" -gt 0 ]]; then
    fail "$f: $count occurrence(s) of '(show T from x)' — use idiomatic coercion (x : T) instead"
  fi
}

# ── Check 3: broad `import Mathlib` ──────────────────────────────────────────
check_broad_import() {
  local f="$1"
  if grep -qE "^import Mathlib$" "$f" 2>/dev/null; then
    fail "$f: broad 'import Mathlib' — use specific imports (e.g. import Mathlib.Analysis.X)"
  fi
}

# ── Check 4: blank lines inside proof blocks ─────────────────────────────────
# Uses Python for accurate proof-block boundary detection
check_proof_blank_lines() {
  local f="$1"
  local count
  count=$(python3 -c "
import sys, re
with open(sys.argv[1]) as fh:
    lines = fh.readlines()
in_proof = False
violations = 0
for i, line in enumerate(lines):
    s = line.rstrip(); ls = s.lstrip()
    if not ls.startswith('--') and not ls.startswith('/-'):
        if re.search(r':=\s*by\s*$', s) or re.search(r'\bby\s*$', s):
            in_proof = True
    if in_proof and len(s) - len(ls) == 0 and ls and not ls.startswith('--'):
        if re.match(r'^(theorem|lemma|def |noncomputable|private |protected |section|end |namespace|variable|instance|@\[|class |structure |/-)', ls):
            in_proof = False
    if in_proof and s == '':
        # Only flag if the next non-blank line is also indented (truly inside proof body)
        j = i + 1
        while j < len(lines) and lines[j].strip() == '':
            j += 1
        if j < len(lines):
            next_s = lines[j].rstrip(); next_ls = next_s.lstrip()
            next_indent = len(next_s) - len(next_ls)
            if next_indent > 0:
                violations += 1
print(violations)
" "$f" 2>/dev/null || echo 0)
  if [[ "$count" -gt 0 ]]; then
    fail "$f: $count blank line(s) inside proof blocks (Mathlib linter will reject)"
  fi
}

# ── Check 5: line length ─────────────────────────────────────────────────────
check_line_length() {
  local f="$1"
  local violations=0 lineno=0
  while IFS= read -r line; do
    ((lineno++)) || true
    if [[ ${#line} -gt 100 ]]; then
      ((violations++)) || true
      if [[ $violations -le 3 ]]; then
        warn "$f:$lineno: line length ${#line} > 100 chars"
      fi
    fi
  done < "$f"
  if [[ $violations -gt 3 ]]; then
    warn "$f: $violations total lines > 100 chars (showing first 3)"
  fi
}

# ── Check 6: no automated co-author trailers in git history ──────────────────
check_no_ai_coauthor() {
  local f="$1"
  local rel="${f#"$REPO_ROOT/"}"
  if git -C "$REPO_ROOT" log --all --follow --format="%B" -- "$rel" 2>/dev/null \
      | grep -qi "Co-Authored-By.*\(claude\|anthropic\|openai\|codex\|gpt\|gemini\)"; then
    fail "$f: automated co-author trailer found in git history"
  fi
}

# ── Check 7+8: lean linter (--lean only) ─────────────────────────────────────

# ── Check 7: `by` on its own line ────────────────────────────────────────────
check_by_own_line() {
  local f="$1"
  local count
  count=$(grep -cE '^\s*by\s*$' "$f" 2>/dev/null || true)
  count="${count:-0}"
  if [[ "$count" -gt 0 ]]; then
    fail "$f: $count instance(s) of 'by' on its own line — Mathlib style linter rejects this"
  fi
}

# ── Check 8: missing /-! module header ───────────────────────────────────────
check_module_header() {
  local f="$1"
  if ! grep -q "^/-!" "$f" 2>/dev/null; then
    fail "$f: missing '/-! ... -/' module header docstring"
  fi
}

# ── Check 9: λ usage in code (not doc comments) ──────────────────────────────
check_lambda() {
  local f="$1"
  # Find λ outside of block comments (/-...-/) and line comments
  local count
  count=$(grep -vE '^\s*(/-|--|\*)' "$f" | grep -cE '\bλ ' 2>/dev/null || true)
  count="${count:-0}"
  if [[ "$count" -gt 0 ]]; then
    fail "$f: $count occurrence(s) of 'λ' — use 'fun x ↦ ...' instead"
  fi
}

# ── Check 10: $ for function application ─────────────────────────────────────
check_dollar_app() {
  local f="$1"
  # \$ surrounded by spaces, in non-comment lines
  local count
  count=$(grep -vE '^\s*(/-|--|\*)' "$f" | grep -cE ' \$ ' 2>/dev/null || true)
  count="${count:-0}"
  if [[ "$count" -gt 0 ]]; then
    fail "$f: $count occurrence(s) of ' \$ ' for function application — use '<|' instead"
  fi
}

check_lean() {
  local f="$1"
  local proj_dir
  proj_dir="$(cd "$(dirname "$f")" && while [[ ! -f "lakefile.lean" && ! -f "lakefile.toml" && "$PWD" != "/" ]]; do cd ..; done; pwd)"

  if [[ ! -f "$proj_dir/lakefile.lean" && ! -f "$proj_dir/lakefile.toml" ]]; then
    warn "$f: no lakefile found — skipping lean checks"
    return
  fi

  # Append #lint to a temp file and run
  local tmpfile
  tmpfile=$(mktemp --suffix=.lean)
  cat "$f" > "$tmpfile"
  echo "" >> "$tmpfile"
  echo "#lint" >> "$tmpfile"

  local output
  output=$(cd "$proj_dir" && lake env lean "$tmpfile" 2>&1 || true)
  rm -f "$tmpfile"

  # Check for sorry
  if echo "$output" | grep -q "declaration uses 'sorry'"; then
    fail "$f: contains sorry — Mathlib will not accept"
  fi

  # Check for lint errors
  local lint_errors
  lint_errors=$(echo "$output" | grep -c "^error:" || true)
  if [[ $lint_errors -gt 0 ]]; then
    fail "$f: #lint reports $lint_errors error(s)"
    echo "$output" | grep "^error:" | head -5 >&2
  fi
}

# ── Main loop ─────────────────────────────────────────────────────────────────
echo "Checking ${#LEAN_FILES[@]} file(s) against Mathlib quality bar..."
echo ""

for f in "${LEAN_FILES[@]}"; do
  echo "▸ $f"
  check_copyright "$f"
  check_show_coercion "$f"
  check_broad_import "$f"
  check_proof_blank_lines "$f"
  check_line_length "$f"
  check_no_ai_coauthor "$f"
  check_by_own_line "$f"
  check_module_header "$f"
  check_lambda "$f"
  check_dollar_app "$f"
  if $RUN_LEAN; then
    check_lean "$f"
  fi
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo "────────────────────────────────────────"
if [[ $FAILURES -eq 0 && $WARNINGS -eq 0 ]]; then
  echo "✓ All checks passed (${#LEAN_FILES[@]} file(s))"
  exit 0
elif [[ $FAILURES -eq 0 ]]; then
  echo "⚠ $WARNINGS warning(s), 0 failures"
  exit 0
else
  echo "✗ $FAILURES failure(s), $WARNINGS warning(s) — fix before Mathlib PR"
  exit 1
fi
