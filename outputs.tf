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

