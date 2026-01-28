# Ansible Automation Platform Integration
#
# Terraform Actions trigger AAP job after VM creation.
# AAP configures the instance (Day-2 configuration).
#
# Using Terraform Actions (1.14+) instead of aap_job resource ensures
# the job runs as a lifecycle event, not a managed resource.

action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    extra_vars = jsonencode({
      target_host = module.compute.vm_ip
      ssh_user    = var.ssh_user
    })
  }
}
