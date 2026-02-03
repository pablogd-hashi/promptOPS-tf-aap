# Packer variables example
# Copy to variables.pkrvars.hcl and fill in your values

aws_region = "us-east-1"

# Vault configuration
vault_addr      = "https://vault.example.com:8200"
vault_namespace = "admin"  # Leave empty for OSS Vault

# Vault SSH CA public key
# Get this from: curl $VAULT_ADDR/v1/ssh/public_key
vault_ca_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ..."

# SSH user for target VMs
ssh_user = "ec2-user"
