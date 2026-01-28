# Compute VM Module - Main
#
# Creates a GPU-enabled VM with platform-approved configurations.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

resource "google_compute_instance" "vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  allow_stopping_for_update = true

  tags = var.tags

  labels = {
    managed_by = "terraform"
    platform   = "promptops"
  }

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }

    # CMEK encryption (if enabled)
    kms_key_self_link = var.boot_disk_kms_key != "" ? var.boot_disk_kms_key : null
  }

  # GPU configuration
  guest_accelerator {
    type  = "projects/${var.project_id}/zones/${var.zone}/acceleratorTypes/${var.gpu_type}"
    count = var.gpu_count
  }

  # GPU instances require TERMINATE on maintenance
  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
  }

  network_interface {
    network = var.network

    dynamic "access_config" {
      for_each = var.enable_public_ip ? [1] : []
      content {
        # Ephemeral public IP
      }
    }
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    ssh-keys = var.ssh_public_key != "" ? "${var.ssh_user}:${var.ssh_public_key}" : null
  }
}
