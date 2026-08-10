variable "gcp_project_id" {
  description = "Existing GCP project that owns the landing zone."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp_project_id))
    error_message = "gcp_project_id must be a valid GCP project ID."
  }
}

variable "gcp_project_number" {
  description = "Numeric identifier expected for gcp_project_id; checked against the provider-resolved project."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.gcp_project_number))
    error_message = "gcp_project_number must contain only digits."
  }
}

variable "gcp_billing_account_id" {
  description = "Billing account already linked to the project; retained as an explicit apply-time identity input."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.gcp_billing_account_id))
    error_message = "gcp_billing_account_id must use the canonical six-six-six uppercase format."
  }
}

variable "gcp_region" {
  description = "GCP region used by the landing zone."
  type        = string
  default     = "us-central1"

  validation {
    condition     = var.gcp_region == "us-central1"
    error_message = "This platform is fixed to us-central1."
  }
}

variable "github_repository" {
  description = "Immutable repository identity exactly as issued inside the GitHub OIDC subject."
  type        = string

  validation {
    condition     = can(regex("^[^/@[:space:]]+@[0-9]+/[^/@[:space:]]+@[0-9]+$", var.github_repository))
    error_message = "github_repository must be the immutable owner@id/name@id identity from the OIDC subject."
  }
}

variable "github_ref" {
  description = "One exact Git ref allowed to impersonate the CI service account."
  type        = string

  validation {
    condition     = can(regex("^refs/(heads|tags)/[^[:space:]*?]+$", var.github_ref))
    error_message = "github_ref must be one exact branch or tag ref without wildcards."
  }
}

variable "state_bucket_name" {
  description = "Globally unique name of the GCS bucket that stores OpenTofu state."
  type        = string

  validation {
    condition = (
      length(var.state_bucket_name) >= 3 &&
      length(var.state_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9._-]*[a-z0-9]$", var.state_bucket_name))
    )
    error_message = "state_bucket_name must be a valid 3-63 character GCS bucket name."
  }
}

variable "workload_identity_pool_id" {
  description = "ID of the GitHub Actions workload identity pool."
  type        = string
  default     = "github-actions"

  validation {
    condition = (
      can(regex("^[a-z0-9-]{4,32}$", var.workload_identity_pool_id)) &&
      !startswith(var.workload_identity_pool_id, "gcp-")
    )
    error_message = "workload_identity_pool_id must be 4-32 lowercase letters, digits, or hyphens and cannot start with gcp-."
  }
}

variable "workload_identity_provider_id" {
  description = "ID of the GitHub Actions OIDC provider."
  type        = string
  default     = "github-actions"

  validation {
    condition = (
      can(regex("^[a-z0-9-]{4,32}$", var.workload_identity_provider_id)) &&
      !startswith(var.workload_identity_provider_id, "gcp-")
    )
    error_message = "workload_identity_provider_id must be 4-32 lowercase letters, digits, or hyphens and cannot start with gcp-."
  }
}

variable "ci_service_account_id" {
  description = "Account ID of the keyless GitHub Actions planning service account."
  type        = string
  default     = "github-actions-plan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.ci_service_account_id))
    error_message = "ci_service_account_id must be a valid 6-30 character service-account ID."
  }
}

variable "ci_plan_role_id" {
  description = "ID of the custom read-only role used by CI to refresh this stack during plans."
  type        = string
  default     = "landingZonePlanViewer"

  validation {
    condition     = can(regex("^[A-Za-z0-9._]{3,64}$", var.ci_plan_role_id))
    error_message = "ci_plan_role_id must be a valid custom role ID without hyphens."
  }
}

