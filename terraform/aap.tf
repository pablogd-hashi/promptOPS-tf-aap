# Ansible Automation Platform Integration
#
# Terraform Actions trigger AAP job after VM creation.
# AAP configures the instances (Day-2 configuration).
#
# The playbook uses Vault SSH CA for ephemeral credentials:
#   1. Playbook authenticates to Vault via AppRole (credentials passed via extra_vars)
#   2. Vault issues ephemeral SSH private key + signed certificate via /ssh/issue
#   3. Playbook connects to VMs using Vault-signed credentials
#   4. Credentials are shredded after use
#
# No static keys are stored in AAP - everything is generated at runtime.

action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    extra_vars = jsonencode({
      # Target hosts - comma-separated list for multiple VMs
      target_hosts = join(",", module.compute.vm_ips)
      ssh_user     = var.ssh_user

      # Vault configuration for SSH CA
      vault_addr              = var.vault_addr
      vault_namespace         = var.vault_namespace
      vault_ssh_role          = local.vault_ssh_role_name
      vault_approle_role_id   = local.vault_approle_role_id
      vault_approle_secret_id = local.vault_approle_secret_id
    })
  }
}
