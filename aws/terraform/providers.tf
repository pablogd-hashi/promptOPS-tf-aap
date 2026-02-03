# AWS Provider
provider "aws" {
  region = var.aws_region
}

# Vault Provider
provider "vault" {
  address   = var.vault_addr
  token     = var.vault_token
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

# ACME Provider for Let's Encrypt certificates
provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

# AAP Provider for Terraform Actions
#
# IMPORTANT: When creating new AAP (create_aap = true):
#   - Set aap_host to a placeholder on first run (AAP doesn't exist yet)
#   - After AAP is created, update aap_host with the actual URL
#   - Run `terraform apply` again to trigger the AAP action
#
# When using existing AAP (create_aap = false):
#   - Set aap_host to your existing AAP URL
#   - Actions will trigger automatically
#
provider "aap" {
  host     = var.aap_host
  username = var.aap_username
  password = var.aap_password

  # Skip TLS verification for self-signed certs (common in demos)
  insecure_skip_verify = true
}
