# Root Module - Outputs

# -----------------------------------------------------------------------------
# Compute Outputs
# -----------------------------------------------------------------------------

output "vm_ips" {
  description = "External IP addresses of the VMs"
  value       = module.compute.vm_ips
}

output "instance_names" {
  description = "Names of the VM instances"
  value       = module.compute.instance_names
}

output "vm_count" {
  description = "Number of VMs created"
  value       = var.vm_count
}

output "zone" {
  description = "Zone where the VMs are deployed"
  value       = module.compute.zone
}

output "machine_type" {
  description = "Machine type of the VMs"
  value       = module.compute.machine_type
}

output "ssh_commands" {
  description = "SSH commands to connect to the instances"
  value       = [for name in module.compute.instance_names : "gcloud compute ssh ${name} --zone=${module.compute.zone} --project=${var.project_id}"]
}

# -----------------------------------------------------------------------------
# Network Policy Outputs
# -----------------------------------------------------------------------------

output "ssh_enabled" {
  description = "Whether SSH access is enabled"
  value       = module.network.ssh_enabled
}

output "streamlit_enabled" {
  description = "Whether Streamlit app access is enabled"
  value       = module.network.streamlit_enabled
}

output "app_urls" {
  description = "URLs to access the Streamlit demo app on each VM (if enabled)"
  value       = module.network.streamlit_enabled ? [for ip in module.compute.vm_ips : "http://${ip}:8501"] : []
}

output "app_status" {
  description = "Human-readable app access status"
  value       = module.network.streamlit_enabled ? "Apps are accessible at port 8501 on each VM" : "Apps are running but port 8501 is closed. Ask to 'enable streamlit access'."
}

# -----------------------------------------------------------------------------
# Encryption Outputs
# -----------------------------------------------------------------------------

output "encryption_enabled" {
  description = "Whether boot disk encryption is enabled"
  value       = module.encryption.encryption_enabled
}

# -----------------------------------------------------------------------------
# Vault SSH CA Outputs
# -----------------------------------------------------------------------------

output "vault_ssh_ca_configured" {
  description = "Whether Vault SSH CA trust is configured on VMs"
  value       = true
}

# -----------------------------------------------------------------------------
# Vault AppRole Outputs (for AAP Credential Configuration)
# -----------------------------------------------------------------------------

output "vault_approle_role_id" {
  description = "Vault AppRole role_id - use this in AAP Vault Secret Lookup credential"
  value       = local.vault_approle_role_id
}

output "vault_approle_secret_id" {
  description = "Vault AppRole secret_id - use this in AAP Vault Secret Lookup credential"
  value       = local.vault_approle_secret_id
  sensitive   = true
}

output "vault_ssh_role_name" {
  description = "Vault SSH role name for certificate issuance"
  value       = local.vault_ssh_role_name
}

# -----------------------------------------------------------------------------
# AAP Outputs
# -----------------------------------------------------------------------------
# Actions don't produce state, so there's no job status to output.
# Use `terraform apply -invoke action.aap_job_launch.configure_vm` to re-run.
