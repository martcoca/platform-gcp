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
