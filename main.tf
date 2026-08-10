data "google_project" "current" {}

locals {
  github_subject            = "repo:${var.github_repository}:ref:${var.github_ref}"
  repository_subject_prefix = "repo:${var.github_repository}:"
  workload_identity_member = join("", [
    "principal://iam.googleapis.com/projects/",
    data.google_project.current.number,
    "/locations/global/workloadIdentityPools/",
    google_iam_workload_identity_pool.github_actions.workload_identity_pool_id,
    "/subject/",
    local.github_subject,
  ])
}

check "project_number_matches" {
  assert {
    condition     = tostring(data.google_project.current.number) == var.gcp_project_number
    error_message = "gcp_project_number does not match the project resolved from provider configuration."
  }
}

check "github_subject_length" {
  assert {
    condition     = length(local.github_subject) <= 127
    error_message = "The exact GitHub OIDC subject exceeds GCP's 127-character google.subject limit."
  }
}

resource "google_storage_bucket" "state" {
  name                        = var.state_bucket_name
  location                    = var.gcp_region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "github_actions" {
  account_id   = var.ci_service_account_id
  display_name = "GitHub Actions landing-zone planner"
  description  = "Keyless CI identity with read-only planning and state-object access"
}

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "GitHub Actions"
  description               = "Federated identities for one immutable GitHub repository"
  disabled                  = false
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "GitHub Actions OIDC"
  description                        = "OIDC trust restricted to one immutable repository identity"
  disabled                           = false

  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }

  attribute_condition = format(
    "assertion.sub.startsWith(%s)",
    jsonencode(local.repository_subject_prefix),
  )

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_actions_exact_ref" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.workload_identity_member

  depends_on = [google_iam_workload_identity_pool_provider.github_actions]
}

resource "google_project_iam_custom_role" "ci_plan_viewer" {
  role_id     = var.ci_plan_role_id
  title       = "Landing Zone Plan Viewer"
  description = "Read-only permissions required to refresh the landing-zone resources"
  permissions = [
    "iam.roles.get",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.workloadIdentityPoolProviders.get",
    "iam.workloadIdentityPools.get",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
  ]
}

resource "google_project_iam_member" "ci_plan_viewer" {
  project = data.google_project.current.project_id
  role    = google_project_iam_custom_role.ci_plan_viewer.name
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_storage_bucket_iam_member" "ci_state_object_admin" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_actions.email}"
}

