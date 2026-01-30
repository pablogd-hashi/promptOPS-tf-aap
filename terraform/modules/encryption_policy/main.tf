# Encryption Policy Module - Main
#
# Creates KMS resources for disk encryption when enabled.
# This is a simplified demo - production would have more controls.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# KMS Key Ring (created only if encryption is enabled)
resource "google_kms_key_ring" "keyring" {
  count = var.boot_disk_encrypted ? 1 : 0

  name     = var.key_ring_name
  location = var.region
  project  = var.project_id
}

# KMS Crypto Key for boot disk encryption
resource "google_kms_crypto_key" "boot_disk_key" {
  count = var.boot_disk_encrypted ? 1 : 0

  name     = var.key_name
  key_ring = google_kms_key_ring.keyring[0].id

  lifecycle {
    prevent_destroy = false # Demo only - production should be true
  }
}
