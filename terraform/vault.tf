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

# -----------------------------------------------------------------------------
# SSH Secrets Engine
# -----------------------------------------------------------------------------

resource "vault_mount" "ssh" {
  path        = "ssh"
  type        = "ssh"
  description = "SSH certificate signing for PromptOps"
}

resource "vault_ssh_secret_backend_ca" "ssh_ca" {
  backend              = vault_mount.ssh.path
  generate_signing_key = true
}

# -----------------------------------------------------------------------------
# SSH Role for Certificate Issuance
# -----------------------------------------------------------------------------

resource "vault_ssh_secret_backend_role" "promptops" {
  name                    = "promptops"
  backend                 = vault_mount.ssh.path
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
}

# -----------------------------------------------------------------------------
# AppRole Auth Method
# -----------------------------------------------------------------------------

resource "vault_auth_backend" "approle" {
  type = "approle"
  path = "approle"
}

# Policy allowing SSH certificate issuance via /ssh/issue
resource "vault_policy" "ssh_issue" {
  name = "promptops-ssh-issue"

  policy = <<-EOT
    # Allow issuing SSH certificates (generates key + signs)
    path "${vault_mount.ssh.path}/issue/${vault_ssh_secret_backend_role.promptops.name}" {
      capabilities = ["create", "update"]
    }

    # Allow signing SSH keys (signs existing key)
    path "${vault_mount.ssh.path}/sign/${vault_ssh_secret_backend_role.promptops.name}" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_approle_auth_backend_role" "promptops" {
  backend        = vault_auth_backend.approle.path
  role_name      = "promptops"
  token_policies = [vault_policy.ssh_issue.name]
  token_ttl      = 3600 # 1 hour
  token_max_ttl  = 7200 # 2 hours
}

resource "vault_approle_auth_backend_role_secret_id" "promptops" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.promptops.role_name
}

# -----------------------------------------------------------------------------
# Outputs for other modules
# -----------------------------------------------------------------------------

locals {
  vault_ca_public_key     = vault_ssh_secret_backend_ca.ssh_ca.public_key
  vault_approle_role_id   = vault_approle_auth_backend_role.promptops.role_id
  vault_approle_secret_id = vault_approle_auth_backend_role_secret_id.promptops.secret_id
  vault_ssh_role_name     = vault_ssh_secret_backend_role.promptops.name
}
