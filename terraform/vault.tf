# Vault SSH CA Configuration
#
# Automatically provisions Vault SSH CA infrastructure:
#   - SSH secrets engine
#   - SSH CA signing key
#   - SSH role for certificate issuance
#   - AppRole auth method
#   - Policy for SSH certificate issuance
#
# The playbook uses /ssh/issue/:role to generate ephemeral keys + certs.
# No static keys are stored anywhere.
#
# Note: Uses data sources to check for existing resources and only creates
# what doesn't already exist. Safe to run against a pre-configured Vault.

# -----------------------------------------------------------------------------
# SSH Secrets Engine
# -----------------------------------------------------------------------------

# Try to read existing SSH mount - will fail silently if not exists
data "http" "ssh_mount_check" {
  url = "${var.vault_addr}/v1/sys/mounts/ssh"

  request_headers = merge(
    { "X-Vault-Token" = var.vault_token },
    var.vault_namespace != "" ? { "X-Vault-Namespace" = var.vault_namespace } : {}
  )
}

locals {
  ssh_mount_exists = data.http.ssh_mount_check.status_code == 200
}

resource "vault_mount" "ssh" {
  count = local.ssh_mount_exists ? 0 : 1

  path        = "ssh"
  type        = "ssh"
  description = "SSH certificate signing for PromptOps"
}

# Check if CA already exists
data "http" "vault_ca_check" {
  url = "${var.vault_addr}/v1/ssh/public_key"

  request_headers = var.vault_namespace != "" ? {
    "X-Vault-Namespace" = var.vault_namespace
  } : {}

  depends_on = [vault_mount.ssh]
}

locals {
  ca_exists = data.http.vault_ca_check.status_code == 200
}

resource "vault_ssh_secret_backend_ca" "ssh_ca" {
  count = local.ca_exists ? 0 : 1

  backend              = "ssh"
  generate_signing_key = true

  depends_on = [vault_mount.ssh]
}

# Get the CA public key (works whether we created it or it existed)
data "http" "vault_ca_public_key" {
  url = "${var.vault_addr}/v1/ssh/public_key"

  request_headers = var.vault_namespace != "" ? {
    "X-Vault-Namespace" = var.vault_namespace
  } : {}

  depends_on = [vault_ssh_secret_backend_ca.ssh_ca]
}

# -----------------------------------------------------------------------------
# SSH Role for Certificate Issuance
# -----------------------------------------------------------------------------

resource "vault_ssh_secret_backend_role" "promptops" {
  name                    = "promptops"
  backend                 = "ssh"
  key_type                = "ca"
  algorithm_signer        = "rsa-sha2-256"
  allow_user_certificates = true
  allowed_users           = var.ssh_user
  default_user            = var.ssh_user
  ttl                     = "1800" # 30 minutes

  # CRITICAL: permit-pty is required for SSH sessions to work
  allowed_extensions = "permit-pty,permit-user-rc,permit-port-forwarding"
  default_extensions = {
    "permit-pty"     = ""
    "permit-user-rc" = ""
  }

  depends_on = [vault_mount.ssh, vault_ssh_secret_backend_ca.ssh_ca]
}

# -----------------------------------------------------------------------------
# AppRole Auth Method
# -----------------------------------------------------------------------------

# Check if AppRole auth is already enabled
data "http" "approle_check" {
  url = "${var.vault_addr}/v1/sys/auth"

  request_headers = merge(
    { "X-Vault-Token" = var.vault_token },
    var.vault_namespace != "" ? { "X-Vault-Namespace" = var.vault_namespace } : {}
  )
}

locals {
  # Check if approle/ exists in the auth backends response
  approle_exists = can(jsondecode(data.http.approle_check.response_body)["approle/"])
}

resource "vault_auth_backend" "approle" {
  count = local.approle_exists ? 0 : 1

  type = "approle"
  path = "approle"
}

# Policy allowing SSH certificate issuance via /ssh/issue
resource "vault_policy" "ssh_issue" {
  name = "promptops-ssh-issue"

  policy = <<-EOT
    # Allow issuing SSH certificates (generates key + signs)
    path "ssh/issue/promptops" {
      capabilities = ["create", "update"]
    }

    # Allow signing SSH keys (signs existing key)
    path "ssh/sign/promptops" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_approle_auth_backend_role" "promptops" {
  backend        = "approle"
  role_name      = "promptops"
  token_policies = [vault_policy.ssh_issue.name]
  token_ttl      = 3600 # 1 hour
  token_max_ttl  = 7200 # 2 hours

  depends_on = [vault_auth_backend.approle]
}

resource "vault_approle_auth_backend_role_secret_id" "promptops" {
  backend   = "approle"
  role_name = vault_approle_auth_backend_role.promptops.role_name
}

# -----------------------------------------------------------------------------
# Outputs for other modules
# -----------------------------------------------------------------------------

locals {
  vault_ca_public_key     = trimspace(data.http.vault_ca_public_key.response_body)
  vault_approle_role_id   = vault_approle_auth_backend_role.promptops.role_id
  vault_approle_secret_id = vault_approle_auth_backend_role_secret_id.promptops.secret_id
  vault_ssh_role_name     = vault_ssh_secret_backend_role.promptops.name
}
