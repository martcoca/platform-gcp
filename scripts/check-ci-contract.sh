#!/usr/bin/env bash

set -euo pipefail

cost_workflow=.github/workflows/cost-guard.yml
plan_workflow=.github/workflows/guarded-plan.yml
helper=scripts/configure-github-secrets.sh

require() {
  local pattern=$1
  local file=$2
  if ! rg -q --fixed-strings "$pattern" "$file"; then
    printf 'Missing required contract %s in %s.\n' "$pattern" "$file" >&2
    exit 1
  fi
}

reject() {
  local pattern=$1
  local file=$2
  if rg -q --fixed-strings "$pattern" "$file"; then
    printf 'Forbidden contract %s found in %s.\n' "$pattern" "$file" >&2
    exit 1
  fi
}

require 'pull_request:' "$cost_workflow"
require 'push:' "$cost_workflow"
require 'scripts/test-cost-guard.sh' "$cost_workflow"
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
require 'tofu plan -input=false -json' "$plan_workflow"
require 'scripts/cost-guard.sh /dev/stdin' "$plan_workflow"
require 'statuses=("${PIPESTATUS[@]}")' "$plan_workflow"
require 'plan_status=${statuses[0]}' "$plan_workflow"
require 'guard_status=${statuses[1]}' "$plan_workflow"
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
for secret in GCP_PROJECT_ID GCP_PROJECT_NUMBER GCP_STATE_BUCKET GITHUB_REPOSITORY_IDENTITY GCP_WORKLOAD_IDENTITY_PROVIDER GCP_SERVICE_ACCOUNT; do
  require "$secret" "$plan_workflow"
  require "$secret" "$helper"
done
require 'tofu output -raw "$output_name" | gh secret set "$secret_name"' "$helper"
reject 'echo "$output' "$helper"
reject 'mktemp' "$helper"

printf '%s\n' 'CI contract passed'
