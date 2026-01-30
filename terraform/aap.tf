# Ansible Automation Platform Integration
#
# Terraform Actions trigger AAP job after VM creation.
# AAP configures the instance (Day-2 configuration).
#
# Using Terraform Actions (1.14+) instead of aap_job resource ensures
# the job runs as a lifecycle event, not a managed resource.
#
# The playbook uses Vault SSH CA for ephemeral credentials:
#   1. AAP authenticates to Vault via AppRole (credentials injected by Job Template)
#   2. Vault issues ephemeral SSH private key + signed certificate
#   3. AAP connects to VMs using Vault-signed credentials
#   4. Credentials are shredded after use

action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    extra_vars = jsonencode({
      # Target hosts - comma-separated list for multiple VMs
      target_hosts = join(",", module.compute.vm_ips)
      ssh_user     = var.ssh_user

      # Vault configuration for SSH CA
      vault_addr      = var.vault_addr
      vault_namespace = var.vault_namespace
      vault_ssh_role  = var.vault_ssh_role
    })
  }
}
