# -----------------------------------------------------------------------------
# Terraform Actions
# -----------------------------------------------------------------------------
# Triggers AAP job after target VMs are created or updated.
# Requires Terraform 1.14+ for Actions support.

action "aap_job_launch" "configure_targets" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    extra_vars = jsonencode({
      target_hosts            = join(",", aws_instance.target[*].public_ip)
      ssh_user                = var.ssh_user
      vault_addr              = var.vault_addr
      vault_namespace         = var.vault_namespace
      vault_ssh_role          = local.vault_ssh_role_name
      vault_approle_role_id   = local.vault_approle_role_id
      vault_approle_secret_id = local.vault_approle_secret_id
    })
  }
}

# -----------------------------------------------------------------------------
# Action Trigger Resource
# -----------------------------------------------------------------------------
# Tracks target VM state and triggers AAP configuration on changes.

resource "terraform_data" "aap_trigger" {
  input = join(",", aws_instance.target[*].public_ip)

  depends_on = [aws_instance.target]

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.aap_job_launch.configure_targets]
    }
  }
}
