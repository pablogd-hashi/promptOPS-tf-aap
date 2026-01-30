# Terraform Providers
#
# Required providers for GCP infrastructure, AAP integration, and Vault SSH CA.

terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aap = {
      source = "ansible/aap"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

# GCP Provider - uses Application Default Credentials
provider "google" {
  project = var.project_id
  region  = var.region
}

# AAP Provider - connects to Ansible Automation Platform
provider "aap" {
  host     = var.aap_host
  username = var.aap_username
  password = var.aap_password

  # Skip TLS verification for demo (use proper certs in production)
  insecure_skip_verify = true
}

# Vault Provider - manages SSH CA and AppRole
provider "vault" {
  address   = var.vault_addr
  token     = var.vault_token
  namespace = var.vault_namespace != "" ? var.vault_namespace : null

  # Skip TLS verification for demo (use proper certs in production)
  skip_tls_verify = true
}
