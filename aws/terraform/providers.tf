# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Terraform = "true"
      Project   = var.name_prefix
    }
  }
}

provider "vault" {
  address   = var.vault_addr
  token     = var.vault_token
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

provider "aap" {
  host                 = var.aap_host
  username             = var.aap_username
  password             = var.aap_password
  insecure_skip_verify = var.aap_insecure_skip_verify
}
