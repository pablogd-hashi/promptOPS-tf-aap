# Root Module - GPU Infrastructure Platform
#
# This is the platform entry point.
# All resources are created through opinionated modules.
# The LLM can only set variables that modules expose.
# Terraform enforces all constraints via validations.

# -----------------------------------------------------------------------------
# Encryption Policy
# -----------------------------------------------------------------------------
# Must be created first if KMS key is needed for boot disk

module "encryption" {
  source = "./modules/encryption_policy"

  project_id          = var.project_id
  region              = var.region
  boot_disk_encrypted = var.boot_disk_encrypted
}

# -----------------------------------------------------------------------------
# Compute VM
# -----------------------------------------------------------------------------
# Creates GPU-enabled VM with platform-approved configurations

module "compute" {
  source = "./modules/compute_vm"

  project_id          = var.project_id
  zone                = var.zone
  instance_name       = var.instance_name
  machine_type        = var.machine_type
  gpu_type            = var.gpu_type
  gpu_count           = var.gpu_count
  disk_size_gb        = var.disk_size_gb
  enable_public_ip    = var.enable_public_ip
  boot_disk_kms_key   = module.encryption.kms_key_id
  network             = var.network
  tags                = ["gpu-worker"]
  ssh_user            = var.ssh_user
  vm_count            = var.vm_count
  vault_ca_public_key = local.vault_ca_public_key

  depends_on = [module.encryption]
}

# -----------------------------------------------------------------------------
# Network Policy
# -----------------------------------------------------------------------------
# Controls network access with platform-approved patterns only

module "network" {
  source = "./modules/network_policy"

  project_id      = var.project_id
  network         = var.network
  instance_name   = var.instance_name
  target_tags     = ["gpu-worker"]
  allow_ssh       = var.allow_ssh
  allow_streamlit = var.allow_streamlit

  depends_on = [module.compute]
}

# -----------------------------------------------------------------------------
# AAP Trigger
# -----------------------------------------------------------------------------
# Triggers Ansible configuration after VM and network are ready.
# Using terraform_data resource to bind action_trigger to module completion.

resource "terraform_data" "aap_trigger" {
  # Track VM IPs - if any change, re-trigger configuration
  input = join(",", module.compute.vm_ips)

  depends_on = [module.compute, module.network]

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.aap_job_launch.configure_vm]
    }
  }
}
