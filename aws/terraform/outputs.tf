# -----------------------------------------------------------------------------
# Target VM Outputs
# -----------------------------------------------------------------------------

output "target_vm_ips" {
  description = "Public IP addresses of target VMs"
  value       = aws_instance.target[*].public_ip
}

output "target_vm_private_ips" {
  description = "Private IP addresses of target VMs"
  value       = aws_instance.target[*].private_ip
}

output "target_vm_ids" {
  description = "Instance IDs of target VMs"
  value       = aws_instance.target[*].id
}

output "target_vm_count" {
  description = "Number of target VMs created"
  value       = var.target_vm_count
}

# -----------------------------------------------------------------------------
# Vault Outputs
# -----------------------------------------------------------------------------

output "vault_ssh_role" {
  description = "Name of the Vault SSH role for certificate issuance"
  value       = local.vault_ssh_role_name
}

output "vault_approle_role_id" {
  description = "Vault AppRole role ID for AAP authentication"
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
  value       = aws_subnet.public.id
}

output "target_security_group_id" {
  description = "Security group ID for target VMs"
  value       = aws_security_group.target.id
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

output "summary" {
  description = "Deployment summary"
  value       = <<-EOT

    ============================================
    Vault SSH CA Demo - AWS
    ============================================

    AAP Controller: ${var.aap_host}
    AAP Username:   ${var.aap_username}

    Target VMs:     ${var.target_vm_count}
    Target IPs:     ${join(", ", aws_instance.target[*].public_ip)}
    SSH User:       ${var.ssh_user}

    Vault Address:  ${var.vault_addr}
    Vault SSH Role: ${local.vault_ssh_role_name}

    ============================================
    Re-trigger AAP Job
    ============================================

    terraform apply -invoke "action.aap_job_launch.configure_targets"

  EOT
}
