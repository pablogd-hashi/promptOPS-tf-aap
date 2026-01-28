# Encryption Policy Module - Outputs

output "encryption_enabled" {
  description = "Whether boot disk encryption is enabled"
  value       = var.boot_disk_encrypted
}

output "kms_key_id" {
  description = "KMS key ID for boot disk encryption (if enabled)"
  value       = var.boot_disk_encrypted ? google_kms_crypto_key.boot_disk_key[0].id : null
}

output "kms_key_ring_id" {
  description = "KMS key ring ID (if encryption enabled)"
  value       = var.boot_disk_encrypted ? google_kms_key_ring.keyring[0].id : null
}
