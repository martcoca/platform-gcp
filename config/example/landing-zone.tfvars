gcp_project_id     = "<project-id>"
gcp_project_number = "<project-number>"
github_repository  = "<owner@id/repository@id>"
github_ref         = "<exact-ref>"
state_bucket_name  = "<globally-unique-state-bucket>"

# The second tenant this landing zone serves. Immutable identity only: the mutable
# owner/name form is rejected by variable validation.
work_tracker_repository = "<owner@id/work-tracker@id>"
work_tracker_ref        = "refs/heads/main"
