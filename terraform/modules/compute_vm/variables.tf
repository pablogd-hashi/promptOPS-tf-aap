# Compute VM Module - Variables
#
# This module defines the platform's compute capabilities.
# The LLM can only propose values that pass these validations.

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "zone" {
  description = "GCP zone for the VM"
  type        = string
  default     = "us-central1-a"
}

variable "instance_name" {
  description = "Name for the VM instance"
  type        = string
  default     = "gpu-worker-01"
}

variable "machine_type" {
  description = "VM machine type. Platform allows only: n1-standard-4, n1-standard-8"
  type        = string
  default     = "n1-standard-4"

  validation {
    condition     = contains(["n1-standard-4", "n1-standard-8"], var.machine_type)
    error_message = "Machine type must be n1-standard-4 or n1-standard-8. Other types are not approved by platform policy."
  }
}

variable "gpu_type" {
  description = "GPU accelerator type. Platform allows only: nvidia-tesla-t4"
  type        = string
  default     = "nvidia-tesla-t4"

  validation {
    condition     = var.gpu_type == "nvidia-tesla-t4"
    error_message = "GPU type must be nvidia-tesla-t4. Other GPU types are not approved by platform policy."
  }
}

variable "gpu_count" {
  description = "Number of GPUs to attach"
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_count >= 1 && var.gpu_count <= 2
    error_message = "GPU count must be 1 or 2. Platform policy limits GPU allocation."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size in GB. Platform allows: 50-200 GB"
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 50 && var.disk_size_gb <= 200
    error_message = "Disk size must be between 50 and 200 GB. Platform policy restricts disk allocation."
  }
}

variable "enable_public_ip" {
  description = "Whether to assign a public IP address"
  type        = bool
  default     = true
}

variable "boot_disk_kms_key" {
  description = "KMS key for boot disk encryption (optional)"
  type        = string
  default     = ""
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Network tags for the instance"
  type        = list(string)
  default     = ["gpu-worker"]
}

variable "ssh_user" {
  description = "SSH username for key-based access"
  type        = string
  default     = "ubuntu"
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1

  validation {
    condition     = var.vm_count >= 1 && var.vm_count <= 10
    error_message = "VM count must be between 1 and 10. Platform policy limits instance allocation."
  }
}

variable "vault_ca_public_key" {
  description = "Vault SSH CA public key for trusted certificate authentication"
  type        = string
}
