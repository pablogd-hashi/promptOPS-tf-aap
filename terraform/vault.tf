# Vault SSH CA Integration
#
# Fetches the Vault SSH CA public key dynamically.
# This key is used to configure sshd on VMs to trust Vault-signed certificates.
# The /v1/ssh/public_key endpoint is unauthenticated (public key is not secret).

# -----------------------------------------------------------------------------
# Fetch Vault SSH CA Public Key
# -----------------------------------------------------------------------------

data "http" "vault_ssh_ca_public_key" {
  url = "${var.vault_addr}/v1/ssh/public_key"

  request_headers = var.vault_namespace != "" ? {
    "X-Vault-Namespace" = var.vault_namespace
  } : {}
}

locals {
  # The response body is the raw public key (no JSON wrapper)
  vault_ca_public_key = trimspace(data.http.vault_ssh_ca_public_key.response_body)
}
