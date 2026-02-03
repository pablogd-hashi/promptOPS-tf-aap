terraform {
  required_version = ">= 1.14.0"

  # Uncomment for Terraform Cloud
  # cloud {
  #   organization = "your-org"
  #   workspaces {
  #     name = "aws-aap-vault-ssh"
  #   }
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
    # AAP provider for Terraform Actions
    aap = {
      source  = "ansible/aap"
      version = ">= 1.0"
    }
  }
}
