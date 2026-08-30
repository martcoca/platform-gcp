#!/usr/bin/env bash
# Mechanically hold the CI safety contract: the public inputs and secret handoff stay
# aligned, and the cost guard is consumed rather than carried while still being a gate.
#
# Most of what is asserted here is invisible from a diff of any single file. A guard step
# can be deleted, excused, unpinned to a branch, moved after an apply, or quietly replaced
# by a re-vendored local copy — each of those leaves a workflow that still reads as
# guarded. Pull requests here merge without a human reading the diff, so these have to be
# checks rather than review habits.
#
# grep, not ripgrep. A `if rg ...` test fails *open* where ripgrep is absent: the shell
# returns 127, the branch is not taken, and a forbidden pattern is reported as clean. That
# is exactly backwards for a check whose job is to refuse.

set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

cost_workflow=.github/workflows/cost-guard.yml
plan_workflow=.github/workflows/guarded-plan.yml
contract_workflow=.github/workflows/guard.yml
helper=scripts/configure-github-secrets.sh

require() {
  local needle=$1 file=$2
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'Missing required contract %s in %s.\n' "$needle" "$file" >&2
    exit 1
  fi
}

reject() {
  local needle=$1 file=$2
  if grep -Fq -- "$needle" "$file"; then
    printf 'Forbidden contract %s found in %s.\n' "$needle" "$file" >&2
    exit 1
  fi
}

# A fixed-string match is satisfied by a *comment*. Deleting the guard step but leaving a
# line of prose that names it passes `require` and leaves the workflow unguarded — the
# compromised file the obvious check waves through. Structural facts are therefore matched
# as whole YAML lines: a comment begins with `#` after its indent and cannot match.
require_line() {
  local regex=$1 file=$2
  if ! grep -Eq -- "^[[:space:]]*${regex}[[:space:]]*\$" "$file"; then
    printf 'Missing required contract line /%s/ in %s.\n' "$regex" "$file" >&2
    printf 'It must be a real YAML line, not a mention of one in a comment.\n' >&2
    exit 1
  fi
}

# --- the guard and its denylist are not in this repository ----------------------------
#
# Absent from the working tree *and* untracked. A file that is only deleted on disk but
# still tracked comes back on the next checkout.

for gone in scripts/cost-guard.sh config/cost-guard-denylist.json; do
  if [[ -e "$gone" ]] || git ls-files --error-unmatch "$gone" >/dev/null 2>&1; then
    printf '%s is back. The guard travels with the action; a local copy is the\n' "$gone" >&2
    printf 'duplication that extracting it removed.\n' >&2
    exit 1
  fi
done

# --- the pin has exactly one source ---------------------------------------------------

pin_file=config/cost-guard-action.txt
[[ -f "$pin_file" ]] || {
  printf 'Missing %s: the cost-guard release pin has no single source.\n' "$pin_file" >&2
  exit 1
}
pin=$(tr -d '[:space:]' < "$pin_file")
if [[ ! "$pin" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+@v[0-9]+(\.[0-9]+\.[0-9]+)?$ ]]; then
  printf 'The cost-guard pin must be owner/repo@vN or owner/repo@vN.N.N, not: %s\n' "$pin" >&2
  exit 1
fi

# Every use of the action, in every workflow, must be that exact pin. A branch ref would
# let what is denied change with no commit in this repository.
guard_uses=0
while IFS= read -r used; do
  [[ -n "$used" ]] || continue
  guard_uses=$((guard_uses + 1))
  if [[ "$used" != "$pin" ]]; then
    printf 'Workflow uses %s but the pin in %s is %s.\n' "$used" "$pin_file" "$pin" >&2
    exit 1
  fi
done < <(grep -hE '^[[:space:]]*uses:[[:space:]]*[A-Za-z0-9._-]+/cost-guard@[^[:space:]]+[[:space:]]*$' \
  .github/workflows/*.yml | sed 's/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]*$//')
if [[ "$guard_uses" -eq 0 ]]; then
  printf 'No workflow uses the cost-guard action.\n' >&2
  exit 1
fi

# --- the guarded plan hands the guard a file, and the guard still gates ----------------

require 'push:' "$plan_workflow"
require 'branches: [main]' "$plan_workflow"
require 'workflow_dispatch:' "$plan_workflow"
reject 'pull_request:' "$plan_workflow"
require 'contents: read' "$plan_workflow"
require 'id-token: write' "$plan_workflow"
require 'google-github-actions/auth@v3' "$plan_workflow"
require 'workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}' "$plan_workflow"
require 'service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}' "$plan_workflow"
require 'tofu init -input=false -backend-config="bucket=${{ secrets.GCP_STATE_BUCKET }}"' "$plan_workflow"
require '>/dev/null 2>&1' "$plan_workflow"
require 'tofu_version: 1.12.5' "$plan_workflow"
require 'tofu_wrapper: false' "$plan_workflow"

require 'tofu plan -input=false -no-color -json' "$plan_workflow"
require '>"$RUNNER_TEMP/tofu-plan.json" 2>"$RUNNER_TEMP/tofu-plan.err"' "$plan_workflow"
require_line "uses: ${pin//./\\.}" "$plan_workflow"
require_line 'plan: \$\{\{ runner\.temp \}\}/tofu-plan\.json' "$plan_workflow"
require_line 'id: cost-guard' "$plan_workflow"
require 'GUARD_OUTCOME: ${{ steps.cost-guard.outcome }}' "$plan_workflow"
require 'GUARD_VERDICT: ${{ steps.cost-guard.outputs.verdict }}' "$plan_workflow"
require '[[ "$GUARD_OUTCOME" == "success" ]] || exit 1' "$plan_workflow"
require 'Guarded plan result: allow.' "$plan_workflow"
require 'Guarded plan result: deny.' "$plan_workflow"
require 'Guarded plan result: plan failure.' "$plan_workflow"
require 'Guarded plan result: undecidable.' "$plan_workflow"
require 'TF_VAR_gcp_project_id: ${{ secrets.GCP_PROJECT_ID }}' "$plan_workflow"
require 'TF_VAR_gcp_project_number: ${{ secrets.GCP_PROJECT_NUMBER }}' "$plan_workflow"
require 'TF_VAR_state_bucket_name: ${{ secrets.GCP_STATE_BUCKET }}' "$plan_workflow"
require 'TF_VAR_github_repository: ${{ secrets.GITHUB_REPOSITORY_IDENTITY }}' "$plan_workflow"
require 'TF_VAR_github_ref: refs/heads/main' "$plan_workflow"
reject ' -var=' "$plan_workflow"
reject 'tofu apply' "$plan_workflow"

# The verdict must come from the guard step itself. Feeding the plan to the guard through
# another process reports that process's status, and a plan that never ran then reads as a
# clean plan. The three spellings below are the ways this repository has previously done
# it; none may return. (They are named as data, not in prose, so this comment cannot
# satisfy the assertion it explains.)
for laundered in 'scripts/cost-guard.sh' '/dev/stdin' 'PIPESTATUS'; do
  reject "$laundered" "$plan_workflow"
done
# And the gate must not be excused: a step allowed to fail is a workflow that looks
# guarded and is not. Forbidden anywhere in this file — it has one guard step and nothing
# else here has any business carrying one.
reject 'continue-on-error' "$plan_workflow"

# Ordering: a step that changes infrastructure must not be insertable between the plan and
# the guard. Nothing here applies today and the assertions below keep it that way; this one
# additionally pins the sequence.
plan_line=$(grep -nE '^[[:space:]]*tofu plan -input=false -no-color -json' "$plan_workflow" | head -n 1 | cut -d: -f1)
guard_line=$(grep -nE "^[[:space:]]*uses:[[:space:]]*${pin//./\\.}[[:space:]]*\$" "$plan_workflow" | head -n 1 | cut -d: -f1)
if [[ -z "$plan_line" || -z "$guard_line" || "$guard_line" -le "$plan_line" ]]; then
  printf 'The guard step must follow the plan step in %s.\n' "$plan_workflow" >&2
  exit 1
fi
if grep -nEi 'tofu[[:space:]]+(apply|destroy|import|taint|state[[:space:]]+(rm|mv|push))' "$plan_workflow" >/dev/null; then
  printf 'The guarded plan workflow must not change infrastructure.\n' >&2
  exit 1
fi
if grep -Eqi 'tofu[[:space:]]+apply|terraform[[:space:]]+apply' .github/workflows/*.yml; then
  printf 'Workflows must not apply infrastructure.\n' >&2
  exit 1
fi

# --- freshness: this repository cannot be silently behind ------------------------------
#
# A separate signal from the verdict, and it must stay separate. The guard decides with no
# network; freshness can only be known by asking. What is asserted here is that the asking
# happens, that it happens on a clock as well as on a push, and that it cannot quietly be
# deleted.

pin_ref="${pin##*@}"
freshness_workflow=.github/workflows/cost-guard-freshness.yml

[[ -f "$freshness_workflow" ]] || {
  printf 'Missing %s: nothing asks whether the pin is current when nobody pushes.\n' \
    "$freshness_workflow" >&2
  exit 1
}

# Every use of the freshness sub-action must sit at the same release as the guard itself.
# They ship from one repository; letting them drift apart would mean asking one version
# whether a different version is current.
freshness_uses=0
while IFS= read -r used; do
  [[ -n "$used" ]] || continue
  freshness_uses=$((freshness_uses + 1))
  used_ref="${used##*@}"
  if [[ "$used_ref" != "$pin_ref" ]]; then
    printf 'Workflow uses the freshness action at %s but the pin in %s is %s.\n' \
      "$used_ref" "$pin_file" "$pin_ref" >&2
    exit 1
  fi
done < <(grep -hE '^[[:space:]]*uses:[[:space:]]*[A-Za-z0-9._-]+/cost-guard/freshness@[^[:space:]]+[[:space:]]*$' \
  .github/workflows/*.yml | sed 's/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]*$//')
if [[ "$freshness_uses" -lt 3 ]]; then
  printf 'The freshness action must run beside the guard, on pull requests, and on a\n' >&2
  printf 'schedule. Found %s use(s); expected at least 3.\n' "$freshness_uses" >&2
  exit 1
fi

# Beside the guard, and running even when the guard failed — a denial is exactly when it
# matters whether the denylist in force is the current one.
require_line 'id: freshness' "$plan_workflow"
require_line 'if: always\(\)' "$plan_workflow"
require_line 'pin: \$\{\{ steps\.pin\.outputs\.pin \}\}' "$plan_workflow"
require_line 'fail-on-stale: false' "$plan_workflow"
# The pin reaches the action from the pin file, not from a literal that could drift.
require_line 'printf .pin=%s\\n. "\$\(tr -d .\[:space:\]. < config/cost-guard-action\.txt\)" >> "\$GITHUB_OUTPUT"' "$plan_workflow"

# Freshness must not be able to decide the plan. It runs after the gate, and it is the
# scheduled run — never this one — that is allowed to fail on a stale pin.
freshness_line=$(grep -nE '^[[:space:]]*id: freshness[[:space:]]*$' "$plan_workflow" | head -n 1 | cut -d: -f1)
if [[ -z "$freshness_line" || "$freshness_line" -le "$guard_line" ]]; then
  printf 'The freshness step must follow the guard step in %s.\n' "$plan_workflow" >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*fail-on-stale: true[[:space:]]*$' "$plan_workflow"; then
  printf 'The guarded plan must not fail on a stale pin: a pin that has fallen behind is\n' >&2
  printf 'not a reason to fail a plan that is otherwise fine.\n' >&2
  exit 1
fi

# On pull requests: reported, never blocking.
require_line 'fail-on-stale: false' "$cost_workflow"

# On a clock: reported, and not ignorable.
require_line 'fail-on-stale: true' "$freshness_workflow"
require 'schedule:' "$freshness_workflow"
require_line "- cron: '[0-9*/, -]+'" "$freshness_workflow"
require_line 'workflow_dispatch:' "$freshness_workflow"
require_line 'contents: read' "$freshness_workflow"
# A scheduled run that only ever reports `current` would be indistinguishable from one
# that never ran. The action never fails on `unknown`, so `true` here is the only place
# staleness is allowed to turn something red.

# --- the demonstration that the consumed action behaves like the deleted local one -----

require 'pull_request:' "$cost_workflow"
require 'push:' "$cost_workflow"
require 'workflow_dispatch:' "$cost_workflow"
require 'contents: read' "$cost_workflow"
require_line "uses: ${pin//./\\.}" "$cost_workflow"
# The three exit outcomes, asserted through the action. `undecidable` failing is the one
# most easily lost when moving to a wrapper, so it is named here rather than implied.
require "assert 'clean plan'          'success/allow/0'" "$cost_workflow"
require "assert 'denied create'       'failure/deny/1'" "$cost_workflow"
require "assert 'errored plan'        'failure/undecidable/2'" "$cost_workflow"
require "assert 'unrecognizable'      'failure/undecidable/2'" "$cost_workflow"
require "assert 'empty plan'          'failure/undecidable/2'" "$cost_workflow"
for fixture in clean-plan.json denied-plan.json denied-plan.jsonl \
               errored-plan.jsonl unrecognizable.json empty.json; do
  [[ -f "scripts/fixtures/cost-guard/$fixture" ]] || {
    printf 'Missing fixture scripts/fixtures/cost-guard/%s.\n' "$fixture" >&2
    exit 1
  }
  require_line "plan: scripts/fixtures/cost-guard/${fixture//./\\.}" "$cost_workflow"
done

# --- this check must actually run --------------------------------------------------
#
# A contract check nobody invokes is a comment. It was one here until this packet.

require_line 'run: scripts/check-ci-contract\.sh' "$contract_workflow"

# --- the public inputs and the secret handoff ------------------------------------------

for secret in GCP_PROJECT_ID GCP_PROJECT_NUMBER GCP_STATE_BUCKET GITHUB_REPOSITORY_IDENTITY GCP_WORKLOAD_IDENTITY_PROVIDER GCP_SERVICE_ACCOUNT; do
  require "$secret" "$plan_workflow"
  require "$secret" "$helper"
done
require 'tofu output -raw "$output_name" | gh secret set "$secret_name"' "$helper"
reject 'echo "$output' "$helper"
reject 'mktemp' "$helper"

printf '%s\n' 'CI contract passed'
