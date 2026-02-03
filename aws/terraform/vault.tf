# Vault SSH CA Configuration
#
# Provisions Vault SSH CA infrastructure:
#   - SSH secrets engine
#   - SSH CA signing key
#   - SSH role for certificate issuance
#   - AppRole auth method
#   - Policy for SSH certificate issuance
#
# Uses data sources to check for existing resources - safe to run against
# a pre-configured Vault.

# -----------------------------------------------------------------------------
# SSH Secrets Engine
# -----------------------------------------------------------------------------

# Check if SSH mount exists
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
  description = "SSH certificate signing"
}

# Check if CA exists
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

# Get the CA public key
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

resource "vault_ssh_secret_backend_role" "target" {
  name                    = "target"
  backend                 = "ssh"
  key_type                = "ca"
  algorithm_signer        = "rsa-sha2-256"
  allow_user_certificates = true
  allowed_users           = "*"
  default_user            = var.ssh_user
  ttl                     = "1800" # 30 minutes

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

# Check if AppRole auth is enabled
data "http" "approle_check" {
  url = "${var.vault_addr}/v1/sys/auth"

  request_headers = merge(
    { "X-Vault-Token" = var.vault_token },
    var.vault_namespace != "" ? { "X-Vault-Namespace" = var.vault_namespace } : {}
  )
}

locals {
  approle_exists = can(jsondecode(data.http.approle_check.response_body).data["approle/"])
}

resource "vault_auth_backend" "approle" {
  count = local.approle_exists ? 0 : 1

  type = "approle"
  path = "approle"
}

# Policy for SSH certificate issuance
resource "vault_policy" "ssh_issue" {
  name = "${var.name_prefix}-ssh-issue"

  policy = <<-EOT
    # Allow issuing SSH certificates
    path "ssh/issue/target" {
      capabilities = ["create", "update"]
    }

    # Allow signing SSH keys
    path "ssh/sign/target" {
      capabilities = ["create", "update"]
    }
  EOT
}

# AppRole for AAP
resource "vault_approle_auth_backend_role" "aap" {
  backend        = "approle"
  role_name      = "${var.name_prefix}-aap"
  token_policies = [vault_policy.ssh_issue.name]
  token_ttl      = 3600
  token_max_ttl  = 7200

  depends_on = [vault_auth_backend.approle]
}

resource "vault_approle_auth_backend_role_secret_id" "aap" {
  backend   = "approle"
  role_name = vault_approle_auth_backend_role.aap.role_name
}

# -----------------------------------------------------------------------------
# Outputs for other modules
# -----------------------------------------------------------------------------

locals {
  vault_ca_public_key     = trimspace(data.http.vault_ca_public_key.response_body)
  vault_approle_role_id   = vault_approle_auth_backend_role.aap.role_id
  vault_approle_secret_id = vault_approle_auth_backend_role_secret_id.aap.secret_id
  vault_ssh_role_name     = vault_ssh_secret_backend_role.target.name
}
