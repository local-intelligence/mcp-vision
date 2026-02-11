#!/usr/bin/env bash
set -euo pipefail

# Bootstrap GitHub hygiene for a repo.
# Requirements: gh CLI authenticated, git repo with origin pointing to GitHub.

OWNER_DEFAULT="local-intelligence"
REPO_DEFAULT="$(basename "$(git rev-parse --show-toplevel)")"
OWNER="${OWNER:-$OWNER_DEFAULT}"
REPO="${REPO:-$REPO_DEFAULT}"
FULL="$OWNER/$REPO"

die(){ echo "❌ $*" >&2; exit 1; }
note(){ echo "• $*" >&2; }

command -v gh >/dev/null || die "gh not found"
command -v git >/dev/null || die "git not found"

# Ensure we're in a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not in a git repo"

# Ensure remote exists
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
[[ -n "$REMOTE_URL" ]] || die "No 'origin' remote found"

note "Target: $FULL"

# Ensure main exists locally + remotely
if ! git show-ref --verify --quiet refs/heads/main; then
  note "Local branch 'main' missing; creating from current HEAD"
  git branch main
fi

if ! gh api "repos/$FULL/branches/main" >/dev/null 2>&1; then
  note "Remote branch 'main' missing; pushing it"
  git push -u origin main
fi

# Set default branch to main (idempotent)
note "Setting default branch to 'main'"
gh repo edit "$FULL" --default-branch main >/dev/null

# Add topics (idempotent-ish; gh will merge)
note "Adding topics"
gh repo edit "$FULL" \
  --add-topic mcp \
  --add-topic local-first \
  --add-topic privacy \
  --add-topic computer-vision \
  --add-topic edge-ai >/dev/null || true

# Create standard labels (idempotent)
note "Creating labels (if missing)"
create_label () {
  local name="$1"; local desc="$2"
  gh api -X POST "repos/$FULL/labels" -f name="$name" -f description="$desc" >/dev/null 2>&1 || true
}

create_label "type:spec" "Specification work"
create_label "type:implementation" "Code changes"
create_label "type:docs" "Documentation updates"
create_label "type:chore" "Maintenance / cleanup"
create_label "type:bug" "Bug fixes"

create_label "area:vision" "Camera / snapshots"
create_label "area:audio" "Microphone / transcription"
create_label "area:security" "Safety gates, auth, audit"
create_label "area:tooling" "Scripts, wrappers, devex"

create_label "version:v0.1" "v0.1 milestone"
create_label "version:v0.2" "v0.2 milestone"

# Scaffold minimal GitHub templates if missing
note "Scaffolding .github templates (if missing)"
mkdir -p .github/ISSUE_TEMPLATE

if [[ ! -f .github/pull_request_template.md ]]; then
  cat > .github/pull_request_template.md <<'TPL'
## Summary
- 

## Linked issue
- Closes #

## Safety checklist (camera/mic sensitive)
- [ ] This change respects ARM/DISARM gating
- [ ] This change does not enable access when disarmed
- [ ] Audit log events updated (if relevant)

## Testing
- [ ] `make lint`
- [ ] `make test`
TPL
fi

if [[ ! -f .github/ISSUE_TEMPLATE/feature.yml ]]; then
  cat > .github/ISSUE_TEMPLATE/feature.yml <<'TPL'
name: Feature
description: Propose a feature or enhancement
title: "[v0.x] "
labels: ["type:implementation"]
body:
  - type: textarea
    id: goal
    attributes:
      label: Goal
      description: What do we want to achieve?
    validations:
      required: true
  - type: textarea
    id: acceptance
    attributes:
      label: Acceptance criteria
      description: Bullet list of what "done" means.
    validations:
      required: true
  - type: textarea
    id: notes
    attributes:
      label: Notes / context
      description: Links, constraints, safety implications.
    validations:
      required: false
TPL
fi

if [[ ! -f .github/ISSUE_TEMPLATE/bug.yml ]]; then
  cat > .github/ISSUE_TEMPLATE/bug.yml <<'TPL'
name: Bug report
description: Report a bug
title: "bug: "
labels: ["type:bug"]
body:
  - type: textarea
    id: repro
    attributes:
      label: Repro steps
      description: Steps to reproduce the behavior.
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected behavior
    validations:
      required: true
  - type: textarea
    id: actual
    attributes:
      label: Actual behavior
    validations:
      required: true
  - type: textarea
    id: env
    attributes:
      label: Environment
      description: OS, Python, device, etc.
    validations:
      required: false
TPL
fi

# Commit templates if we created them
if ! git diff --quiet; then
  note "Committing bootstrap templates"
  git add .github
  git commit -m "chore: add GitHub issue/PR templates"
  git push
else
  note "No template changes to commit"
fi

# Branch protection: require PR + 1 review + no force pushes + linear history.
# Note: required_status_checks.contexts can be added later after CI has run once.

note "Applying branch protection to main (1 review required, linear history, conversation resolution)"

gh api -X PUT "repos/$FULL/branches/main/protection" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": [] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON


note "Bootstrap complete for $FULL"
note "Next: run CI once, then set required status checks contexts."
