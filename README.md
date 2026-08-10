# platform-gcp

Per-cloud GCP landing zone for keyless GitHub Actions federation, remote OpenTofu state,
and zero-cost guardrails.

## What this root creates

- A Workload Identity Pool and GitHub Actions OIDC provider. The provider accepts tokens
  only when `assertion.sub` begins with the configured immutable repository identity.
- A service account that only the exact configured repository-and-ref OIDC subject can
  impersonate. No service-account key resource exists.
- A custom read-only role containing only the permissions required to refresh this root
  during a plan.
- A GCS state bucket with object versioning, uniform bucket-level access, public access
  prevention, and destruction protection. CI receives object administration only on this
  bucket so OpenTofu can read, write, and lock state.

GCS encrypts every object at rest with Google-managed server-side encryption. This root
uses that default instead of Cloud KMS because a KMS key has a standing monthly charge.
The configured `gcs` backend provides native locking; no separate lock resource exists.

## Inputs

Copy `config/example/landing-zone.tfvars` to the ignored
`config/local/landing-zone.tfvars` and replace every redacted marker. The repository
identity must come from the immutable GitHub OIDC subject and retain both numeric IDs.
The project number is checked against the project resolved from provider configuration.

The billing account input records the already-linked account identity for apply-time
review; this root does not mutate billing.

## Bootstrap and approval boundary

The GCS backend requires its bucket to exist before backend initialization, and this
stack is what creates it. `tofu init -backend=false` is **not** sufficient: `plan` still
refuses with "Backend initialization required" while a `backend` block is present.

Bootstrap by temporarily removing the backend block, so the first plan and apply run on
local state:

```sh
mv backend.tf backend.tf.bootstrap
tofu init
tofu fmt -check -recursive .
tofu validate
set -o pipefail
tofu plan -json -var-file=../config/local/landing-zone.tfvars \
  | scripts/cost-guard.sh /dev/stdin
```

The guard and denylist are vendored byte-for-byte from `platform-aws`. Vendoring keeps
the check available in this repository and in GitHub Actions without a sibling checkout;
the shared denylist is not weakened.

Stop after the plan. Creating the bucket, workload identity resources, service account,
or IAM bindings requires fresh human approval. After the approved bootstrap apply has
created the bucket, migrate the local state into the configured backend:

```sh
tofu init -migrate-state \
  -backend-config="bucket=$TF_BACKEND_BUCKET"
```

Do not pass credentials in backend arguments. Local users authenticate with Application
Default Credentials; GitHub Actions uses Workload Identity Federation.

After the approved apply, store the sensitive `workload_identity_provider` and
`ci_service_account_email` outputs in repository secrets named
`GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT`. Run the manual identity-check
workflow from the exact configured ref. It compares the active account to the expected
service account without printing either value.

The negative check is also post-approval: attempt the workflow from any other ref or
repository and confirm authentication fails. Changing an IAM binding to perform that
test requires another fresh human approval.
