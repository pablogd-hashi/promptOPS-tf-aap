# Network Policy Module - Variables
#
# This module defines the platform's network access policies.
# Only approved access patterns are allowed. No arbitrary ports.

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "instance_name" {
  description = "Instance name (used for firewall rule naming)"
  type        = string
}

variable "target_tags" {
  description = "Network tags to apply firewall rules to"
  type        = list(string)
  default     = ["gpu-worker"]
}

variable "allow_ssh" {
  description = "Allow SSH access (port 22). Required for Ansible configuration."
  type        = bool
  default     = true
}

variable "allow_streamlit" {
  description = "Allow Streamlit app access (port 8501). The only application port exposed by platform."
  type        = bool
  default     = false
}

# Note: No arbitrary port variable. Platform policy restricts to SSH (22) and Streamlit (8501) only.
