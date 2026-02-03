# Target VMs
#
# Creates target VMs with Vault SSH CA trust pre-configured.
# These VMs can be configured by AAP using Vault-issued SSH credentials.

# -----------------------------------------------------------------------------
# Target VM Instances
# -----------------------------------------------------------------------------

resource "aws_instance" "target" {
  count = var.target_vm_count

  ami                         = var.target_ami_id != "" ? var.target_ami_id : data.aws_ami.amazon_linux.id
  instance_type               = var.target_instance_type
  key_name                    = var.create_aap ? module.key_pair[0].key_pair_name : null
  subnet_id                   = aws_subnet.public_az1.id
  vpc_security_group_ids      = [aws_security_group.target.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # Configure Vault SSH CA trust via user_data
  user_data = <<-EOF
    #!/bin/bash
    set -e

    echo "Configuring Vault SSH CA trust..."

    # Create directory for CA keys
    mkdir -p /etc/ssh/vault-ca

    # Write Vault CA public key
    cat > /etc/ssh/vault-ca/trusted-user-ca-keys.pem <<'CAKEY'
    ${local.vault_ca_public_key}
    CAKEY

    chmod 644 /etc/ssh/vault-ca/trusted-user-ca-keys.pem

    # Configure sshd to trust Vault CA
    if ! grep -q "TrustedUserCAKeys" /etc/ssh/sshd_config; then
      echo "" >> /etc/ssh/sshd_config
      echo "# Vault SSH CA - Trust certificates signed by Vault" >> /etc/ssh/sshd_config
      echo "TrustedUserCAKeys /etc/ssh/vault-ca/trusted-user-ca-keys.pem" >> /etc/ssh/sshd_config
    fi

    # Restart sshd
    systemctl restart sshd

    echo "Vault SSH CA trust configured."

    # Install Python (required for Ansible)
    yum install -y python3 python3-pip || dnf install -y python3 python3-pip

    echo "Target VM setup complete."
  EOF

  tags = merge(local.common_tags, {
    Name = var.target_vm_count > 1 ? "${var.name_prefix}-target-${count.index + 1}" : "${var.name_prefix}-target"
    Role = "target-vm"
  })

  depends_on = [data.http.vault_ca_public_key]
}
