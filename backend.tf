terraform {
  backend "gcs" {
    prefix = "platform-gcp/landing-zone"
  }
}

