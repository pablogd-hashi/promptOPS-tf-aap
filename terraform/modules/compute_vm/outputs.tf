# Compute VM Module - Outputs

output "vm_ips" {
  description = "External IP addresses of the VMs (if public IP enabled)"
  value       = var.enable_public_ip ? [for vm in google_compute_instance.vm : vm.network_interface[0].access_config[0].nat_ip] : []
}

output "vm_internal_ips" {
  description = "Internal IP addresses of the VMs"
  value       = [for vm in google_compute_instance.vm : vm.network_interface[0].network_ip]
}

output "instance_names" {
  description = "Names of the VM instances"
  value       = [for vm in google_compute_instance.vm : vm.name]
}

output "zones" {
  description = "Zones where the VMs are deployed"
  value       = [for vm in google_compute_instance.vm : vm.zone]
}

output "machine_type" {
  description = "Machine type of the VMs"
  value       = var.machine_type
}

output "self_links" {
  description = "Self-links of the VM instances"
  value       = [for vm in google_compute_instance.vm : vm.self_link]
}

# Convenience outputs for single-VM backwards compatibility
output "vm_ip" {
  description = "External IP of first VM (backwards compatible)"
  value       = var.enable_public_ip && length(google_compute_instance.vm) > 0 ? google_compute_instance.vm[0].network_interface[0].access_config[0].nat_ip : null
}

output "instance_name" {
  description = "Name of first VM (backwards compatible)"
  value       = length(google_compute_instance.vm) > 0 ? google_compute_instance.vm[0].name : null
}

output "zone" {
  description = "Zone of first VM (backwards compatible)"
  value       = length(google_compute_instance.vm) > 0 ? google_compute_instance.vm[0].zone : null
}
