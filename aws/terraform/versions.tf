# -----------------------------------------------------------------------------
# Terraform Version and Provider Requirements
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.0, < 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0, < 4.0"
    }
    aap = {
      source  = "ansible/aap"
      version = ">= 1.0, < 2.0"
    }
  }
}
