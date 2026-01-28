# Network Policy Module - Outputs

output "ssh_enabled" {
  description = "Whether SSH access is enabled"
  value       = var.allow_ssh
}

output "streamlit_enabled" {
  description = "Whether Streamlit app access is enabled"
  value       = var.allow_streamlit
}

output "ssh_firewall_name" {
  description = "Name of SSH firewall rule (if created)"
  value       = var.allow_ssh ? google_compute_firewall.allow_ssh[0].name : null
}

output "streamlit_firewall_name" {
  description = "Name of Streamlit firewall rule (if created)"
  value       = var.allow_streamlit ? google_compute_firewall.allow_streamlit[0].name : null
}
