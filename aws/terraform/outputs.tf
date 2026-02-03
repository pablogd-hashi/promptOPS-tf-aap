# Outputs

# -----------------------------------------------------------------------------
# AAP Outputs
# -----------------------------------------------------------------------------

output "aap_url" {
  description = "URL to access AAP"
  value       = local.aap_url
}

output "aap_public_ip" {
  description = "Public IP of AAP instance"
  value       = var.create_aap ? aws_instance.aap[0].public_ip : null
}

output "aap_instance_id" {
  description = "Instance ID of AAP"
  value       = var.create_aap ? aws_instance.aap[0].id : null
}

output "aap_private_key" {
  description = "Private key to SSH to AAP (for debugging)"
  value       = var.create_aap ? module.key_pair[0].private_key_pem : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Target VM Outputs
# -----------------------------------------------------------------------------

output "target_vm_ips" {
  description = "Public IPs of target VMs"
  value       = aws_instance.target[*].public_ip
}

output "target_vm_ids" {
  description = "Instance IDs of target VMs"
  value       = aws_instance.target[*].id
}

output "target_vm_count" {
  description = "Number of target VMs created"
  value       = var.target_vm_count
}

output "ssh_commands" {
  description = "SSH commands to connect to target VMs (using standard key)"
  value = var.create_aap ? [
    for ip in aws_instance.target[*].public_ip :
    "ssh -i <private-key> ${var.ssh_user}@${ip}"
  ] : []
}

# -----------------------------------------------------------------------------
# Vault Outputs
# -----------------------------------------------------------------------------

output "vault_ssh_ca_configured" {
  description = "Whether Vault SSH CA is configured"
  value       = true
}

output "vault_ssh_role" {
  description = "Vault SSH role name"
  value       = local.vault_ssh_role_name
}

output "vault_approle_role_id" {
  description = "Vault AppRole role ID"
  value       = local.vault_approle_role_id
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Network Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public_az1.id
}

output "target_security_group_id" {
  description = "Security group ID for target VMs"
  value       = aws_security_group.target.id
}

# -----------------------------------------------------------------------------
# Summary & Next Steps
# -----------------------------------------------------------------------------

output "summary" {
  description = "Deployment summary"
  value       = <<-EOT

    ============================================
    Terraform Actions + Vault SSH CA Demo (AWS)
    ============================================

    AAP URL: ${local.aap_url}
    AAP Username: ${var.aap_username}

    Target VMs: ${var.target_vm_count}
    Target IPs: ${join(", ", aws_instance.target[*].public_ip)}

    Vault Address: ${var.vault_addr}
    Vault SSH Role: ${local.vault_ssh_role_name}

  EOT
}

locals {
  next_steps_two_stage = <<-EOT

    ============================================
    NEXT STEPS (Two-Stage Deployment)
    ============================================

    You created AAP but haven't triggered the action yet.

    1. Update terraform.tfvars with the actual AAP URL:
       aap_host = "${local.aap_url}"

    2. Run terraform apply again to trigger the AAP action:
       terraform apply

    Or manually trigger:
       terraform apply -invoke "action.aap_job_launch.configure_targets"

  EOT

  next_steps_complete = <<-EOT

    ============================================
    DEPLOYMENT COMPLETE
    ============================================

    Terraform Actions triggered AAP to configure target VMs.
    Check AAP for job status.

    To re-trigger AAP:
      terraform apply -invoke "action.aap_job_launch.configure_targets"

  EOT
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = var.aap_host == "https://placeholder.local" ? local.next_steps_two_stage : local.next_steps_complete
}
