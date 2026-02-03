# Packer template for target VMs with Vault SSH CA trust
#
# This creates an AMI for target VMs that:
#   - Trust Vault SSH CA for certificate-based authentication
#   - Can be configured by AAP using Vault-issued credentials
#
# The resulting AMI accepts SSH connections from certificates signed by Vault.

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

variable "base_ami_owner" {
  type        = string
  default     = "amazon"
  description = "Owner of the base AMI (amazon for Amazon Linux, 099720109477 for Ubuntu)"
}

variable "base_ami_filter" {
  type        = string
  default     = "al2023-ami-*-x86_64"
  description = "Filter for the base AMI name"
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
  description = "Vault SSH CA public key"
}

variable "ssh_user" {
  type        = string
  default     = "ec2-user"
  description = "SSH user for the target VMs"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Instance type for building the AMI"
}

variable "ami_name_prefix" {
  type        = string
  default     = "target-vault-ssh"
  description = "Prefix for the AMI name"
}

# Local variables
locals {
  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
}

# Data source to find the latest base AMI
source "amazon-ebs" "target-vault-ssh" {
  ami_name        = "${var.ami_name_prefix}-${local.timestamp}"
  ami_description = "Target VM with Vault SSH CA trust for AAP configuration"
  instance_type   = var.instance_type
  region          = var.aws_region

  source_ami_filter {
    filters = {
      name                = var.base_ami_filter
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = [var.base_ami_owner]
    most_recent = true
  }

  ssh_username = var.ssh_user

  # Tags
  tags = {
    Name          = "${var.ami_name_prefix}-${local.timestamp}"
    Vault_Addr    = var.vault_addr
    Built_By      = "Packer"
    Purpose       = "Target VM with Vault SSH CA"
  }

  # Launch block device mappings
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

# Build block
build {
  name    = "target-vault-ssh"
  sources = ["source.amazon-ebs.target-vault-ssh"]

  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Cloud-init complete.'"
    ]
  }

  # Configure Vault SSH CA trust
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

  # Create systemd service to update CA key on boot (optional)
  provisioner "shell" {
    inline = [
      "echo 'Creating CA update service...'",

      # Create the update script
      "sudo tee /usr/local/bin/vault-ca-update.sh <<'SCRIPT'\n#!/bin/bash\n# Update Vault SSH CA key on boot\n# This script runs at startup to ensure the CA key is current\n\nVAULT_ADDR=\"${var.vault_addr}\"\nVAULT_NAMESPACE=\"${var.vault_namespace}\"\nCA_FILE=\"/etc/ssh/vault-ca/trusted-user-ca-keys.pem\"\n\n# Only update if Vault is reachable\nif curl -s --connect-timeout 5 \"$VAULT_ADDR/v1/sys/health\" > /dev/null 2>&1; then\n  NEW_CA=$(curl -s \\\n    $${VAULT_NAMESPACE:+-H \"X-Vault-Namespace: $VAULT_NAMESPACE\"} \\\n    \"$VAULT_ADDR/v1/ssh/public_key\")\n  \n  if echo \"$NEW_CA\" | grep -q \"ssh-rsa\\|ssh-ed25519\"; then\n    echo \"$NEW_CA\" > \"$CA_FILE\"\n    chmod 644 \"$CA_FILE\"\n    systemctl reload sshd 2>/dev/null || true\n    echo \"Vault CA key updated successfully\"\n  fi\nelse\n  echo \"Vault not reachable, keeping existing CA key\"\nfi\nSCRIPT",
      "sudo chmod +x /usr/local/bin/vault-ca-update.sh",

      # Create systemd service (disabled by default)
      "sudo tee /etc/systemd/system/vault-ca-update.service <<'SERVICE'\n[Unit]\nDescription=Update Vault SSH CA key\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/vault-ca-update.sh\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\nSERVICE",

      # Create timer for periodic updates (disabled by default)
      "sudo tee /etc/systemd/system/vault-ca-update.timer <<'TIMER'\n[Unit]\nDescription=Periodically update Vault SSH CA key\n\n[Timer]\nOnBootSec=1min\nOnUnitActiveSec=1h\n\n[Install]\nWantedBy=timers.target\nTIMER",

      "sudo systemctl daemon-reload",
      "echo 'CA update service created (disabled by default).'",
      "echo 'Enable with: systemctl enable --now vault-ca-update.timer'"
    ]
  }

  # Install useful packages
  provisioner "shell" {
    inline = [
      "echo 'Installing packages...'",
      "sudo yum update -y || sudo dnf update -y",
      "sudo yum install -y python3 python3-pip || sudo dnf install -y python3 python3-pip",
      "echo 'Packages installed.'"
    ]
  }

  # Final cleanup
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "sudo yum clean all 2>/dev/null || sudo dnf clean all 2>/dev/null || true",
      "sudo rm -rf /var/cache/yum /var/cache/dnf 2>/dev/null || true",
      "echo 'AMI build complete!'"
    ]
  }

  # Post-processor to output AMI info
  post-processor "manifest" {
    output     = "manifest-target.json"
    strip_path = true
  }
}
