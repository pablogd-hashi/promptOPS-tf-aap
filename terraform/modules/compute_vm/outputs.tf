# Compute VM Module - Outputs

output "vm_ip" {
  description = "External IP address of the VM (if public IP enabled)"
  value       = var.enable_public_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : null
}

output "vm_internal_ip" {
  description = "Internal IP address of the VM"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "instance_name" {
  description = "Name of the VM instance"
  value       = google_compute_instance.vm.name
}

output "zone" {
  description = "Zone where the VM is deployed"
  value       = google_compute_instance.vm.zone
}

output "machine_type" {
  description = "Machine type of the VM"
  value       = google_compute_instance.vm.machine_type
}

output "self_link" {
  description = "Self-link of the VM instance"
  value       = google_compute_instance.vm.self_link
}
