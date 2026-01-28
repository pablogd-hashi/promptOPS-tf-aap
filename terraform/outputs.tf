# Root Module - Outputs

# -----------------------------------------------------------------------------
# Compute Outputs
# -----------------------------------------------------------------------------

output "vm_ip" {
  description = "External IP address of the VM"
  value       = module.compute.vm_ip
}

output "instance_name" {
  description = "Name of the VM instance"
  value       = module.compute.instance_name
}

output "zone" {
  description = "Zone where the VM is deployed"
  value       = module.compute.zone
}

output "machine_type" {
  description = "Machine type of the VM"
  value       = module.compute.machine_type
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "gcloud compute ssh ${module.compute.instance_name} --zone=${module.compute.zone} --project=${var.project_id}"
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

output "app_url" {
  description = "URL to access the Streamlit demo app (if enabled)"
  value       = module.network.streamlit_enabled ? "http://${module.compute.vm_ip}:8501" : "App port is closed"
}

output "app_status" {
  description = "Human-readable app access status"
  value       = module.network.streamlit_enabled ? "App is accessible at http://${module.compute.vm_ip}:8501" : "App is running but port 8501 is closed. Ask to 'enable streamlit access'."
}

# -----------------------------------------------------------------------------
# Encryption Outputs
# -----------------------------------------------------------------------------

output "encryption_enabled" {
  description = "Whether boot disk encryption is enabled"
  value       = module.encryption.encryption_enabled
}

# -----------------------------------------------------------------------------
# AAP Outputs
# -----------------------------------------------------------------------------
# Actions don't produce state, so there's no job status to output.
# Use `terraform apply -invoke action.aap_job_launch.configure_vm` to re-run.
