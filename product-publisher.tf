# A second tenant: work-tracker publishes container images, and does nothing else.
#
# Deliberately a separate file from main.tf. main.tf is the landing zone's own identity —
# the CI account that plans this stack — and nothing here touches it. A second identity is
# a second identity.
#
# THE SHAPE, AND WHY IT IS NOT A WIDER PREFIX
#
# The landing zone's provider trusts `assertion.sub.startsWith("repo:<this repo>:")`. The
# cheap way to admit work-tracker is to loosen that condition to match both repositories.
# That is the wrong change: it makes one trust boundary serve two tenants, so any future
# mistake in the condition is a mistake in *both* products' security, and revoking one
# tenant means editing a string that the other depends on.
#
# work-tracker therefore gets its own pool, its own provider, its own condition and its own
# service account. The separate *pool* is the part worth arguing for: a principal is named
# `principal://…/workloadIdentityPools/<pool>/subject/<subject>`, which is pool-scoped and
# does not name the provider. Two providers in one pool mint principals into one namespace,
# so the landing zone's isolation would depend on every provider in that pool staying tight
# forever — including ones nobody has added yet. With separate pools, work-tracker's
# provider cannot name a principal in the landing zone's pool at all. The isolation is
# structural rather than maintained.

locals {
  work_tracker_subject          = "repo:${var.work_tracker_repository}:ref:${var.work_tracker_ref}"
  work_tracker_subject_prefix   = "repo:${var.work_tracker_repository}:"
  artifact_registry_host        = "${var.gcp_region}-docker.pkg.dev"
  product_image_repository_path = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.artifact_registry_repository_id}"

  # The project number comes from the validated variable rather than from
  # data.google_project.current, which main.tf already asserts they agree on. Reading the
  # data source would make every resource below unplannable without live access to the
  # project, and the Founder approves this from a plan.
  work_tracker_principal = join("", [
    "principal://iam.googleapis.com/projects/",
    var.gcp_project_number,
    "/locations/global/workloadIdentityPools/",
    google_iam_workload_identity_pool.work_tracker.workload_identity_pool_id,
    "/subject/",
    local.work_tracker_subject,
  ])
}

check "work_tracker_subject_length" {
  assert {
    condition     = length(local.work_tracker_subject) <= 127
    error_message = "The work-tracker OIDC subject exceeds GCP's 127-character google.subject limit."
  }
}

# --- the registry -----------------------------------------------------------------------

resource "google_artifact_registry_repository" "product_images" {
  repository_id = var.artifact_registry_repository_id
  location      = var.gcp_region
  format        = "DOCKER"
  description   = "Container images published by products this landing zone serves"

  # Retention posture: report, do not delete. The policies below are authored and inert —
  # `cleanup_policy_dry_run` makes Artifact Registry log what it *would* remove without
  # removing anything. Deleting a published image is destructive and irreversible, so
  # enabling it is a deliberate second decision, not a side effect of the first apply.
  # To enable: set cleanup_policy_dry_run = false, which is a one-line change and its own
  # plan.
  cleanup_policy_dry_run = true

  cleanup_policies {
    id     = "keep-ten-most-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-untagged-after-30-days"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s"
    }
  }
}

# --- the publishing identity --------------------------------------------------------------

resource "google_service_account" "work_tracker_publisher" {
  account_id   = var.work_tracker_publisher_account_id
  display_name = "work-tracker image publisher"
  description  = "Keyless identity that may push container images and do nothing else"
}

resource "google_iam_workload_identity_pool" "work_tracker" {
  workload_identity_pool_id = var.work_tracker_pool_id
  display_name              = "work-tracker"
  description               = "Federated identity for one immutable GitHub repository: work-tracker"
  disabled                  = false
}

resource "google_iam_workload_identity_pool_provider" "work_tracker" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.work_tracker.workload_identity_pool_id
  workload_identity_pool_provider_id = var.work_tracker_provider_id
  display_name                       = "work-tracker OIDC"
  description                        = "OIDC trust restricted to work-tracker's immutable repository identity"
  disabled                           = false

  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }

  # Scoped to work-tracker's immutable identity only. The variable's own validation
  # rejects the mutable `owner/name` form, so this condition cannot be written against a
  # repository name that could be deleted and recreated by someone else.
  attribute_condition = format(
    "assertion.sub.startsWith(%s)",
    jsonencode(local.work_tracker_subject_prefix),
  )

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# The provider admits the repository; this binding admits one exact ref within it. Two
# layers, the same shape main.tf uses for the landing zone's own CI identity.
resource "google_service_account_iam_member" "work_tracker_publisher_exact_ref" {
  service_account_id = google_service_account.work_tracker_publisher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.work_tracker_principal

  depends_on = [google_iam_workload_identity_pool_provider.work_tracker]
}

# --- what the publisher may do, exhaustively ---------------------------------------------

# Push, and read what push needs to read. Not delete: a publisher that can remove images
# can erase what it published, and nothing in this product needs that. Not create, update
# or delete repositories. No setIamPolicy, so it cannot grant itself anything further.
resource "google_project_iam_custom_role" "product_image_publisher" {
  role_id     = var.product_image_publisher_role_id
  title       = "Product Image Publisher"
  description = "Push container images to one Artifact Registry repository; no delete, no IAM, no deploy"
  permissions = [
    "artifactregistry.files.get",
    "artifactregistry.files.list",
    "artifactregistry.packages.get",
    "artifactregistry.packages.list",
    "artifactregistry.repositories.downloadArtifacts",
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.uploadArtifacts",
    "artifactregistry.tags.create",
    "artifactregistry.tags.get",
    "artifactregistry.tags.list",
    "artifactregistry.tags.update",
    "artifactregistry.versions.get",
    "artifactregistry.versions.list",
  ]
}

# Bound on the repository, not on the project. The role is defined project-wide because
# custom roles must be; this binding is what limits where it applies. A second registry
# repository added later is not reachable by this identity without a second binding.
resource "google_artifact_registry_repository_iam_member" "work_tracker_publisher" {
  project    = var.gcp_project_id
  location   = google_artifact_registry_repository.product_images.location
  repository = google_artifact_registry_repository.product_images.name
  role       = google_project_iam_custom_role.product_image_publisher.name
  member     = "serviceAccount:${google_service_account.work_tracker_publisher.email}"
}
