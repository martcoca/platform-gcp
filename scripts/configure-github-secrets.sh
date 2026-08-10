#!/usr/bin/env bash
# Transfer sensitive OpenTofu outputs to GitHub without exposing their values.

set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  printf '%s\n' 'configure-github-secrets requires gh.' >&2
  exit 2
fi

if ! command -v tofu >/dev/null 2>&1; then
  printf '%s\n' 'configure-github-secrets requires tofu.' >&2
  exit 2
fi

set_secret() {
  local output_name=$1
  local secret_name=$2

  tofu output -raw "$output_name" | gh secret set "$secret_name"
  printf '%s\n' "$secret_name"
}

set_secret gcp_project_id GCP_PROJECT_ID
set_secret gcp_project_number GCP_PROJECT_NUMBER
set_secret state_bucket_name GCP_STATE_BUCKET
set_secret github_repository GITHUB_REPOSITORY_IDENTITY
set_secret workload_identity_provider GCP_WORKLOAD_IDENTITY_PROVIDER
set_secret ci_service_account_email GCP_SERVICE_ACCOUNT
