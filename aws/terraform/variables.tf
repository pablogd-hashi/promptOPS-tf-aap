# -----------------------------------------------------------------------------
# AWS Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS region format (e.g., us-east-1, eu-west-2)."
  }
}

# -----------------------------------------------------------------------------
# AAP Configuration (Existing Controller)
# -----------------------------------------------------------------------------
# This module assumes AAP already exists. AAP is a licensed Red Hat product
# and is not provisioned by this repository.

variable "aap_host" {
  description = "URL of existing AAP controller (e.g., https://aap.example.com)"
  type        = string

  validation {
    condition     = can(regex("^https://", var.aap_host))
    error_message = "AAP host must be a valid HTTPS URL."
  }
}

variable "aap_username" {
  description = "AAP admin username"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.aap_username) > 0
    error_message = "AAP username cannot be empty."
  }
}

variable "aap_password" {
  description = "AAP admin password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.aap_password) >= 8
    error_message = "AAP password must be at least 8 characters."
  }
}

variable "aap_job_template_id" {
  description = "AAP job template ID to trigger for VM configuration"
  type        = number

  validation {
    condition     = var.aap_job_template_id > 0
    error_message = "Job template ID must be a positive integer."
  }
}

variable "aap_insecure_skip_verify" {
  description = "Skip TLS certificate verification for AAP (use only for self-signed certs)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Target VM Configuration
# -----------------------------------------------------------------------------

variable "target_vm_count" {
  description = "Number of target VMs to create"
  type        = number
  default     = 1

  validation {
    condition     = var.target_vm_count >= 1 && var.target_vm_count <= 10
    error_message = "VM count must be between 1 and 10."
  }
}

variable "target_instance_type" {
  description = "EC2 instance type for target VMs"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.target_instance_type))
    error_message = "Must be a valid EC2 instance type."
  }
}

variable "target_ami_id" {
  description = "AMI ID for target VMs (leave empty to use latest Amazon Linux 2023)"
  type        = string
  default     = ""

  validation {
    condition     = var.target_ami_id == "" || can(regex("^ami-[a-f0-9]{8,17}$", var.target_ami_id))
    error_message = "Must be a valid AMI ID or empty string."
  }
}

variable "ssh_user" {
  description = "SSH username for target VMs"
  type        = string
  default     = "ec2-user"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.ssh_user))
    error_message = "Must be a valid Unix username."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB for target VMs"
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 500
    error_message = "Root volume size must be between 8 and 500 GB."
  }
}

# -----------------------------------------------------------------------------
# Vault Configuration
# -----------------------------------------------------------------------------

variable "vault_addr" {
  description = "Vault server URL"
  type        = string

  validation {
    condition     = can(regex("^https?://", var.vault_addr))
    error_message = "Vault address must be a valid HTTP(S) URL."
  }
}

variable "vault_token" {
  description = "Vault token with permissions to configure SSH secrets engine"
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "Vault Enterprise namespace (leave empty for OSS Vault)"
  type        = string
  default     = ""
}

variable "vault_ssh_role" {
  description = "Name of the Vault SSH role for certificate issuance"
  type        = string
  default     = "target"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.vault_ssh_role))
    error_message = "SSH role name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to target VMs"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All entries must be valid IPv4 CIDR blocks."
  }
}

variable "aap_cidr" {
  description = "CIDR block of the AAP controller for SSH access to targets"
  type        = string
  default     = ""

  validation {
    condition     = var.aap_cidr == "" || can(cidrhost(var.aap_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block or empty string."
  }
}

# -----------------------------------------------------------------------------
# Naming and Tags
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "vault-ssh-demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.name_prefix))
    error_message = "Name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and be at most 31 characters."
  }
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
