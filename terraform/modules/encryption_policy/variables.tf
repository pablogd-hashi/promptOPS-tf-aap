# Encryption Policy Module - Variables
#
# This module defines the platform's encryption requirements.

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for KMS resources"
  type        = string
  default     = "us-central1"
}

variable "boot_disk_encrypted" {
  description = "Whether to enable CMEK encryption for boot disk. When true, creates a KMS key."
  type        = bool
  default     = false
}

variable "key_ring_name" {
  description = "Name for the KMS key ring (if encryption enabled)"
  type        = string
  default     = "promptops-keyring"
}

variable "key_name" {
  description = "Name for the KMS crypto key (if encryption enabled)"
  type        = string
  default     = "boot-disk-key"
}
