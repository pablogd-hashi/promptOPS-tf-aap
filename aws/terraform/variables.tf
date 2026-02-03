# -----------------------------------------------------------------------------
# AWS Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2", "eu-central-1", "eu-west-1", "ap-southeast-1", "ap-south-1"], var.aws_region)
    error_message = "Region must be one of the supported regions."
  }
}

# -----------------------------------------------------------------------------
# AAP Configuration
# -----------------------------------------------------------------------------

variable "create_aap" {
  description = "Whether to create AAP infrastructure (set false to use existing AAP)"
  type        = bool
  default     = true
}

variable "aap_instance_type" {
  description = "Instance type for AAP controller"
  type        = string
  default     = "m6a.xlarge"
}

variable "aap_ami_id" {
  description = "AMI ID for AAP (leave empty to use default from rts-aap-demo)"
  type        = string
  default     = ""
}

variable "create_alb" {
  description = "Whether to create ALB with HTTPS for AAP"
  type        = bool
  default     = true
}

variable "aap_host" {
  description = <<-EOT
    AAP server URL for the provider.

    Two-stage deployment (when create_aap = true):
      1. First apply: Leave as placeholder - creates AAP infrastructure
      2. After AAP is created: Update to the actual URL from `terraform output aap_url`
      3. Second apply: Terraform Actions will trigger the AAP job

    Single-stage (when create_aap = false):
      Set to your existing AAP URL (e.g., "https://aap.example.com")
  EOT
  type        = string
  default     = "https://placeholder.local"
}

variable "aap_username" {
  description = "AAP admin username"
  type        = string
  default     = "admin"
}

variable "aap_password" {
  description = "AAP admin password"
  type        = string
  sensitive   = true
}

variable "aap_job_template_id" {
  description = "AAP job template ID to trigger"
  type        = number
}

# -----------------------------------------------------------------------------
# Target VM Configuration
# -----------------------------------------------------------------------------

variable "target_vm_count" {
  description = "Number of target VMs to create"
  type        = number
  default     = 1

  validation {
    condition     = var.target_vm_count >= 0 && var.target_vm_count <= 10
    error_message = "VM count must be between 0 and 10."
  }
}

variable "target_instance_type" {
  description = "Instance type for target VMs"
  type        = string
  default     = "t3.medium"
}

variable "target_ami_id" {
  description = "AMI ID for target VMs (leave empty to use Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "SSH username for target VMs"
  type        = string
  default     = "ec2-user"
}

# -----------------------------------------------------------------------------
# Vault Configuration
# -----------------------------------------------------------------------------

variable "vault_addr" {
  description = "Vault server URL"
  type        = string
}

variable "vault_token" {
  description = "Vault token with admin permissions"
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "Vault Enterprise namespace (leave empty for OSS)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "tf-actions-demo"
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
