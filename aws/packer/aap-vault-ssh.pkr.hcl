# Packer template for AAP with Vault SSH CA trust pre-configured
#
# This builds on the existing AAP AMI from rts-aap-demo and adds:
#   - Vault SSH CA public key trust
#   - sshd configuration for certificate authentication
#
# The resulting AMI can SSH to any target VM that trusts the same Vault CA.

packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# Variables
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to build the AMI"
}

variable "source_ami" {
  type        = string
  description = "Source AMI ID (the existing AAP AMI from rts-aap-demo)"
  # Default AMIs from rts-aap-demo by region
  default     = ""
}

variable "vault_addr" {
  type        = string
  description = "Vault server URL"
}

variable "vault_namespace" {
  type        = string
  default     = ""
  description = "Vault Enterprise namespace (leave empty for OSS)"
}

variable "vault_ca_public_key" {
  type        = string
  description = "Vault SSH CA public key (fetched from Vault)"
  default     = ""
}

variable "instance_type" {
  type        = string
  default     = "m6a.xlarge"
  description = "Instance type for building the AMI"
}

variable "ami_name_prefix" {
  type        = string
  default     = "aap-vault-ssh"
  description = "Prefix for the AMI name"
}

# Local variables
locals {
  # Map of AAP AMI IDs from rts-aap-demo
  source_amis = {
    "us-east-1"      = "ami-09758fd69558336ec"
    "eu-central-1"   = "ami-0f6536ad0b5a0a6a9"
    "ap-southeast-1" = "ami-0efd6a38242c8917e"
    "ap-south-1"     = "ami-076833edc1679a270"
  }

  # Use provided AMI or lookup from map
  ami_id = var.source_ami != "" ? var.source_ami : local.source_amis[var.aws_region]

  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
}

# Data source to get VPC info
data "amazon-ami" "source" {
  filters = {
    image-id = local.ami_id
  }
  owners      = ["self", "309956199498", "amazon"]
  most_recent = true
  region      = var.aws_region
}

# Source block - Amazon EBS
source "amazon-ebs" "aap-vault-ssh" {
  ami_name        = "${var.ami_name_prefix}-${local.timestamp}"
  ami_description = "AAP with Vault SSH CA trust pre-configured"
  instance_type   = var.instance_type
  region          = var.aws_region
  source_ami      = local.ami_id

  ssh_username = "ec2-user"

  # Tags
  tags = {
    Name          = "${var.ami_name_prefix}-${local.timestamp}"
    Base_AMI      = local.ami_id
    Vault_Addr    = var.vault_addr
    Built_By      = "Packer"
    Purpose       = "AAP with Vault SSH CA"
  }

  # Launch block device mappings
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

# Build block
build {
  name    = "aap-vault-ssh"
  sources = ["source.amazon-ebs.aap-vault-ssh"]

  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Cloud-init complete.'"
    ]
  }

  # Configure Vault SSH CA trust on AAP host
  # This allows AAP to accept SSH connections using Vault-signed certificates
  provisioner "shell" {
    inline = [
      "echo 'Configuring Vault SSH CA trust...'",

      # Create directory for CA keys
      "sudo mkdir -p /etc/ssh/vault-ca",

      # Write the Vault CA public key
      "echo '${var.vault_ca_public_key}' | sudo tee /etc/ssh/vault-ca/trusted-user-ca-keys.pem",
      "sudo chmod 644 /etc/ssh/vault-ca/trusted-user-ca-keys.pem",

      # Configure sshd to trust Vault CA
      "if ! grep -q 'TrustedUserCAKeys' /etc/ssh/sshd_config; then",
      "  echo '' | sudo tee -a /etc/ssh/sshd_config",
      "  echo '# Vault SSH CA - Trust certificates signed by Vault' | sudo tee -a /etc/ssh/sshd_config",
      "  echo 'TrustedUserCAKeys /etc/ssh/vault-ca/trusted-user-ca-keys.pem' | sudo tee -a /etc/ssh/sshd_config",
      "fi",

      # Validate sshd config
      "sudo sshd -t",

      "echo 'Vault SSH CA trust configured successfully.'"
    ]
  }

  # Install Vault CLI (useful for debugging and manual operations)
  provisioner "shell" {
    inline = [
      "echo 'Installing Vault CLI...'",

      # Add HashiCorp repo
      "sudo yum install -y yum-utils || sudo dnf install -y dnf-plugins-core",
      "sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo || sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo",

      # Install Vault
      "sudo yum install -y vault || sudo dnf install -y vault",

      # Verify installation
      "vault version",

      "echo 'Vault CLI installed successfully.'"
    ]
  }

  # Create helper scripts for Vault SSH operations
  provisioner "shell" {
    inline = [
      "echo 'Creating Vault SSH helper scripts...'",

      # Create script to fetch SSH credentials from Vault
      "sudo tee /usr/local/bin/vault-ssh-issue <<'SCRIPT'\n#!/bin/bash\n# Issue SSH credentials from Vault\n# Usage: vault-ssh-issue <role> [username]\n\nROLE=\"$${1:-promptops}\"\nUSERNAME=\"$${2:-ec2-user}\"\n\nif [ -z \"$VAULT_ADDR\" ]; then\n  echo \"Error: VAULT_ADDR not set\"\n  exit 1\nfi\n\nif [ -z \"$VAULT_TOKEN\" ]; then\n  echo \"Error: VAULT_TOKEN not set (use vault login or set directly)\"\n  exit 1\nfi\n\n# Issue credentials\ncurl -s \\\n  -H \"X-Vault-Token: $VAULT_TOKEN\" \\\n  $${VAULT_NAMESPACE:+-H \"X-Vault-Namespace: $VAULT_NAMESPACE\"} \\\n  -X POST \\\n  -d \"{\\\"key_type\\\":\\\"rsa\\\",\\\"key_bits\\\":4096}\" \\\n  \"$VAULT_ADDR/v1/ssh/issue/$ROLE\"\nSCRIPT",
      "sudo chmod +x /usr/local/bin/vault-ssh-issue",

      # Create script to update CA key from Vault
      "sudo tee /usr/local/bin/vault-ssh-update-ca <<'SCRIPT'\n#!/bin/bash\n# Update Vault SSH CA public key\n# Usage: vault-ssh-update-ca\n\nif [ -z \"$VAULT_ADDR\" ]; then\n  echo \"Error: VAULT_ADDR not set\"\n  exit 1\nfi\n\necho \"Fetching CA public key from $VAULT_ADDR...\"\n\nCA_KEY=$(curl -s \\\n  $${VAULT_NAMESPACE:+-H \"X-Vault-Namespace: $VAULT_NAMESPACE\"} \\\n  \"$VAULT_ADDR/v1/ssh/public_key\")\n\nif echo \"$CA_KEY\" | grep -q \"ssh-rsa\"; then\n  echo \"$CA_KEY\" | sudo tee /etc/ssh/vault-ca/trusted-user-ca-keys.pem\n  sudo systemctl reload sshd\n  echo \"CA key updated and sshd reloaded.\"\nelse\n  echo \"Error: Failed to fetch CA key\"\n  echo \"$CA_KEY\"\n  exit 1\nfi\nSCRIPT",
      "sudo chmod +x /usr/local/bin/vault-ssh-update-ca",

      "echo 'Helper scripts created.'"
    ]
  }

  # Create Vault environment file template
  provisioner "shell" {
    inline = [
      "echo 'Creating Vault environment template...'",

      "sudo tee /etc/profile.d/vault.sh <<'SCRIPT'\n# Vault environment variables\n# Uncomment and set these for your environment\n#export VAULT_ADDR=\"${var.vault_addr}\"\n#export VAULT_NAMESPACE=\"${var.vault_namespace}\"\n#export VAULT_TOKEN=\"\"\nSCRIPT",
      "sudo chmod 644 /etc/profile.d/vault.sh",

      "echo 'Vault environment template created at /etc/profile.d/vault.sh'"
    ]
  }

  # Final cleanup
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "sudo yum clean all || sudo dnf clean all",
      "sudo rm -rf /var/cache/yum /var/cache/dnf",
      "echo 'AMI build complete!'"
    ]
  }

  # Post-processor to output AMI info
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
