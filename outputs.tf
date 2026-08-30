output "gcp_project_id" {
  description = "Project identity used by this landing zone."
  value       = var.gcp_project_id
  sensitive   = true
}

output "gcp_project_number" {
  description = "Numeric project identity used by this landing zone."
  value       = var.gcp_project_number
  sensitive   = true
}

output "state_bucket_name" {
  description = "GCS backend bucket identity."
  value       = google_storage_bucket.state.name
  sensitive   = true
}

output "github_repository" {
  description = "Immutable GitHub repository identity authorized by federation."
  value       = var.github_repository
  sensitive   = true
}

output "workload_identity_provider" {
  description = "Canonical provider name for keyless GitHub Actions authentication."
  value       = google_iam_workload_identity_pool_provider.github_actions.name
  sensitive   = true
}

output "ci_service_account_email" {
  description = "Service account GitHub Actions impersonates after federation."
  value       = google_service_account.github_actions.email
  sensitive   = true
}

# --- the consumer contract ---------------------------------------------------------------
#
# work-tracker's session stopped because no registry host, project, repository or image path
# was tracked or configured anywhere it could read. These four outputs are that contract, so
# a consumer can obtain it without asking a person.

output "artifact_registry_host" {
  description = "Artifact Registry Docker host for this landing zone's region. Not sensitive: it is derived from the region alone and identifies no account."
  value       = local.artifact_registry_host
}

output "product_image_repository" {
  description = "Full repository path to push product images to, as `HOST/PROJECT/REPOSITORY`. Append `/<image>:<tag>`."
  value       = local.product_image_repository_path
  sensitive   = true
}

output "work_tracker_workload_identity_provider" {
  description = "Canonical provider name work-tracker presents its GitHub OIDC token to."
  value       = google_iam_workload_identity_pool_provider.work_tracker.name
  sensitive   = true
}

output "work_tracker_publisher_service_account_email" {
  description = "Service account work-tracker impersonates after federation to push images."
  value       = google_service_account.work_tracker_publisher.email
  sensitive   = true
}
