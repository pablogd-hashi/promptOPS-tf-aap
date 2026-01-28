# Network Policy Module - Main
#
# Creates firewall rules based on platform-approved access patterns.
# No arbitrary ports allowed.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# SSH Access (port 22)
# Required for Ansible to configure the VM
resource "google_compute_firewall" "allow_ssh" {
  count = var.allow_ssh ? 1 : 0

  name    = "${var.instance_name}-allow-ssh"
  network = var.network
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.target_tags

  description = "Allow SSH access (managed by platform)"
}

# Streamlit Access (port 8501)
# The only application port exposed by platform policy
resource "google_compute_firewall" "allow_streamlit" {
  count = var.allow_streamlit ? 1 : 0

  name    = "${var.instance_name}-allow-streamlit"
  network = var.network
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["8501"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.target_tags

  description = "Allow Streamlit app access (managed by platform)"
}
