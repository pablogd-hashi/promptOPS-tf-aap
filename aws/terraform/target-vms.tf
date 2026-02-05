# -----------------------------------------------------------------------------
# Target VMs
# -----------------------------------------------------------------------------
# Creates target VMs with Vault SSH CA trust pre-configured.
# These VMs can be configured by AAP using Vault-issued SSH credentials.

resource "aws_instance" "target" {
  count = var.target_vm_count

  ami                         = local.target_ami
  instance_type               = var.target_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.target.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    vault_ca_public_key = local.vault_ca_public_key
    ssh_user            = var.ssh_user
  }))

  tags = merge(local.common_tags, {
    Name = var.target_vm_count > 1 ? "${var.name_prefix}-target-${count.index + 1}" : "${var.name_prefix}-target"
    Role = "target-vm"
  })

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [data.http.vault_ca_public_key]
}
