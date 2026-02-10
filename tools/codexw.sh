#!/usr/bin/env bash
set -euo pipefail

# codexw.sh — run Codex CLI as a disciplined worker:
#   - require a non-main branch
#   - run a task prompt (optionally from a card file)
#   - apply the patch
#   - run checks
#   - emit a receipt
#
# Usage:
#   codexw.sh --branch <branch> --prompt-file <file> [--root <dir>] [--receipt <file>]
#   codexw.sh --branch <branch> --prompt "<text>"     [--root <dir>] [--receipt <file>]
#
# Optional:
#   --allow-path <path>    (repeatable) file fence hint (included in prompt)
#   --check "<cmd>"        (repeatable) commands to run after apply (default: make lint test)
#
# Examples:
#   ./tools/codexw.sh --root ~/git/labs/mcp-vision \
#     --branch codex/v0-1-spec \
#     --prompt-file .adl/cards/issue-0001__input__v0.1.md \
#     --receipt .adl/cards/issue-0001__output__v0.1.md \
#     --allow-path docs/V0_1_SPEC.md

die(){ echo "❌ $*" >&2; exit 1; }
note(){ echo "• $*" >&2; }

ROOT=""
BRANCH=""
PROMPT=""
PROMPT_FILE=""
RECEIPT=""
ALLOW_PATHS=()
CHECKS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --receipt) RECEIPT="$2"; shift 2 ;;
    --allow-path) ALLOW_PATHS+=("$2"); shift 2 ;;
    --check) CHECKS+=("$2"); shift 2 ;;
    -h|--help)
      sed -n '1,140p' "$0"; exit 0 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "$BRANCH" ]] || die "Missing --branch"
if [[ -z "$ROOT" ]]; then ROOT="$(pwd)"; fi
[[ -d "$ROOT" ]] || die "Root dir not found: $ROOT"

if [[ -n "$PROMPT" && -n "$PROMPT_FILE" ]]; then
  die "Use either --prompt or --prompt-file, not both"
fi
if [[ -z "$PROMPT" && -z "$PROMPT_FILE" ]]; then
  die "Missing --prompt or --prompt-file"
fi

cd "$ROOT"

# Ensure git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repo: $ROOT"

# Enforce branch discipline
current="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current" == "main" || "$current" == "master" ]]; then
  note "On $current; switching to $BRANCH"
fi

# Create/switch branch
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH" >/dev/null
else
  git switch -c "$BRANCH" >/dev/null
fi

# Hard guard: refuse if still on main/master
current="$(git rev-parse --abbrev-ref HEAD)"
[[ "$current" != "main" && "$current" != "master" ]] || die "Refusing to run on $current"

# Read prompt
if [[ -n "$PROMPT_FILE" ]]; then
  [[ -f "$PROMPT_FILE" ]] || die "Prompt file not found: $PROMPT_FILE"
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# Default checks
if [[ ${#CHECKS[@]} -eq 0 ]]; then
  CHECKS=("make lint test")
fi

# Build fencing hint (Codex cannot be forced perfectly, but strong instructions help)
FENCE=""
if [[ ${#ALLOW_PATHS[@]} -gt 0 ]]; then
  FENCE=$'\n\n'\
"FILE FENCE (hard requirement):\n"\
"- You may only modify these paths:\n"
  for p in "${ALLOW_PATHS[@]}"; do
    FENCE+="- ${p}"$'\n'
  done
  FENCE+=$'\n'"- If you think you need other files, STOP and explain why."
fi

# Capture baseline for receipt
start_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
base_sha="$(git rev-parse HEAD 2>/dev/null || true)"

note "Running Codex (non-interactive)…"
# Use workspace-write sandbox and on-request approvals; adjust if you prefer.
codex exec \
  --full-auto \
  -C "$ROOT" \
  --prompt "$PROMPT"$'\n'"$FENCE"

note "Applying patch (codex apply)…"
codex apply

note "Running checks…"
check_log="$(mktemp)"
set +e
for cmd in "${CHECKS[@]}"; do
  echo "\$ $cmd" | tee -a "$check_log"
  bash -lc "$cmd" 2>&1 | tee -a "$check_log"
  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    note "Check failed: $cmd (rc=$rc)"
    break
  fi
done
set -e

end_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
head_sha="$(git rev-parse HEAD 2>/dev/null || true)"

# Write receipt
if [[ -n "$RECEIPT" ]]; then
  mkdir -p "$(dirname "$RECEIPT")"
  {
    echo "Issue: (fill in)"
    echo "Version: v0.1"
    echo "Status: IN_PROGRESS"
    echo "Branch: $BRANCH"
    echo "Started: $start_ts"
    echo "Finished: $end_ts"
    echo ""
    echo "Base SHA: ${base_sha}"
    echo "Head SHA: ${head_sha}"
    echo ""
    echo "Files changed:"
    git diff --name-status "${base_sha:-HEAD~0}"..HEAD 2>/dev/null || true
    echo ""
    echo "Diff summary:"
    git diff --stat "${base_sha:-HEAD~0}"..HEAD 2>/dev/null || true
    echo ""
    echo "Checks:"
    cat "$check_log"
  } > "$RECEIPT"
  note "Wrote receipt: $RECEIPT"
else
  note "No --receipt specified; skipping receipt write"
fi

note "Done on branch: $BRANCH"
