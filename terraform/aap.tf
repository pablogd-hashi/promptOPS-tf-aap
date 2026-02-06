# Ansible Automation Platform Integration
#
# Terraform Actions trigger AAP job after VM creation.
# AAP configures the instances (Day-2 configuration).
#
# Credential Flow (Wrapped Secret ID):
#   1. Terraform generates a WRAPPED secret_id from Vault (single-use, 3h TTL)
#   2. Wrapped token is passed to AAP via extra_vars
#   3. Playbook UNWRAPS the token to get the real secret_id
#   4. Playbook authenticates to Vault with role_id + unwrapped secret_id
#   5. Playbook gets ephemeral SSH keys, connects to VMs
#   6. Credentials are shredded after use
#
# Security benefits:
#   - Wrapped token is single-use (useless after unwrap, even if logged)
#   - Wrapped token has 3h TTL (expires if not used)
#   - Real secret_id never appears in logs or extra_vars
#   - No static secrets stored in AAP
#
# No AAP credential setup required - everything flows through Terraform.

action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = false

    extra_vars = jsonencode({
      # Target hosts - comma-separated list for multiple VMs
      target_hosts = join(",", module.compute.vm_ips)
      ssh_user     = var.ssh_user

      # Vault configuration
      vault_addr              = var.vault_addr
      vault_namespace         = var.vault_namespace
      vault_ssh_role          = local.vault_ssh_role_name
      vault_approle_role_id   = local.vault_approle_role_id
      vault_wrapped_secret_id = local.vault_wrapped_secret_id  # Single-use wrapped token
    })
  }
}
