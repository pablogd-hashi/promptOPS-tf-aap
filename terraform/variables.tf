# Root Module - Variables
#
# These are the ONLY variables the LLM can propose values for.
# All constraints are enforced by the underlying modules.
# PromptOps reads this file to tell the LLM what's allowed.

# -----------------------------------------------------------------------------
# Project Configuration (user must provide)
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

# -----------------------------------------------------------------------------
# Compute Configuration
# -----------------------------------------------------------------------------

variable "vm_count" {
  description = "Number of VMs to create. ALLOWED: 1-10"
  type        = number
  default     = 1
}

variable "instance_name" {
  description = "Base name for VM instances (will be suffixed with index)"
  type        = string
  default     = "gpu-worker"
}

variable "machine_type" {
  description = "VM machine type. ALLOWED: n1-standard-4, n1-standard-8"
  type        = string
  default     = "n1-standard-4"
}

variable "gpu_type" {
  description = "GPU type. ALLOWED: nvidia-tesla-t4"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "Number of GPUs. ALLOWED: 1-2"
  type        = number
  default     = 1
}

variable "disk_size_gb" {
  description = "Boot disk size in GB. ALLOWED: 50-200"
  type        = number
  default     = 100
}

variable "enable_public_ip" {
  description = "Assign public IP address"
  type        = bool
  default     = true
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

# -----------------------------------------------------------------------------
# Network Policy
# -----------------------------------------------------------------------------

variable "allow_ssh" {
  description = "Allow SSH access (port 22)"
  type        = bool
  default     = true
}

variable "allow_streamlit" {
  description = "Allow Streamlit app access (port 8501). This is the ONLY app port available."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Encryption Policy
# -----------------------------------------------------------------------------

variable "boot_disk_encrypted" {
  description = "Enable CMEK encryption for boot disk"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# AAP Configuration (user must provide)
# -----------------------------------------------------------------------------

variable "aap_host" {
  description = "Ansible Automation Platform URL"
  type        = string
}

variable "aap_username" {
  description = "AAP username"
  type        = string
}

variable "aap_password" {
  description = "AAP password"
  type        = string
  sensitive   = true
}

variable "aap_job_template_id" {
  description = "AAP Job Template ID to launch after VM creation"
  type        = number
}

variable "ssh_user" {
  description = "SSH username for Ansible"
  type        = string
  default     = "ubuntu"
}

# -----------------------------------------------------------------------------
# Vault Configuration
# -----------------------------------------------------------------------------

variable "vault_addr" {
  description = "Vault server URL (e.g., https://vault.example.com:8200)"
  type        = string
}

variable "vault_token" {
  description = "Vault admin token (use HCP service principal for long-lived token)"
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "Vault Enterprise namespace (leave empty for OSS Vault)"
  type        = string
  default     = ""
}

variable "vault_ssh_role" {
  description = "Vault SSH role name for certificate issuance"
  type        = string
  default     = "ssh-role"
}
