# AWS Vault SSH CA Demo

Demonstrates Terraform 1.14+ Actions triggering AAP with zero-trust SSH credentials using HashiCorp Vault SSH CA.

> **Note:** This repository assumes you have an existing AAP (Ansible Automation Platform) controller. AAP is a licensed Red Hat product and is not deployed by this repository.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           AWS VPC                                │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     Target VMs                            │   │
│  │  • Vault SSH CA trust configured                         │   │
│  │  • Accepts certificates signed by Vault                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ▲                                   │
│                              │ SSH (Vault-signed cert)          │
│                              │                                   │
└──────────────────────────────┼───────────────────────────────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                  │
        ┌─────▼─────┐                    ┌──────▼──────┐
        │    AAP    │  ◄─── AppRole ───► │   Vault     │
        │ (existing)│      Auth          │  SSH CA     │
        └───────────┘                    └─────────────┘
              ▲
              │ Terraform Action triggers job
              │
        ┌─────┴─────┐
        │ Terraform │
        │   Apply   │
        └───────────┘
```

## Prerequisites

### Required
- **Terraform** >= 1.14.0 (required for Actions)
- **AWS CLI** configured with credentials
- **Existing AAP Controller** with API access

### Optional
- **Packer** >= 1.9.0 (for building custom AMIs)
- **Vault CLI** (for testing)

## Quick Start

```bash
cd aws

# Check prerequisites
task check

# Initialize Terraform
task setup

# Configure variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your values

# Run full demo
task demo
```

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `aap_host` | URL of your existing AAP controller |
| `aap_password` | AAP admin password |
| `aap_job_template_id` | ID of the job template to trigger |
| `vault_addr` | Vault server URL |
| `vault_token` | Vault token with SSH secrets engine permissions |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `target_vm_count` | `1` | Number of target VMs |
| `target_instance_type` | `t3.micro` | EC2 instance type |
| `vault_namespace` | `""` | Vault namespace (HCP/Enterprise) |
| `ssh_user` | `ec2-user` | SSH user for targets |
| `aap_cidr` | `""` | CIDR of AAP controller for SSH access |

## Task Commands

| Command | Description |
|---------|-------------|
| `task check` | Verify prerequisites |
| `task setup` | Initialize Terraform |
| `task demo` | Full demo flow |
| `task plan` | Show Terraform plan |
| `task apply` | Create infrastructure |
| `task show` | Show outputs |
| `task vault:status` | Check Vault SSH CA |
| `task vault:test` | Test certificate issuance |
| `task retrigger` | Re-run AAP action |
| `task destroy` | Destroy infrastructure |

## How It Works

1. **Terraform** creates VPC, security groups, and target VMs
2. **Target VMs** bootstrap with Vault CA trust configured in sshd
3. **Vault** SSH secrets engine and AppRole are configured
4. **Terraform Actions** trigger AAP job with:
   - Target VM IPs
   - Vault AppRole credentials
   - SSH role information
5. **AAP** authenticates to Vault via AppRole
6. **Vault** issues ephemeral SSH key + signed certificate
7. **AAP** connects to targets using Vault-signed credentials
8. **Credentials** are shredded after use - nothing stored

## Packer (Optional)

Build custom AMIs with Vault CA pre-baked:

```bash
task packer:init
cp packer/variables.pkrvars.hcl.example packer/variables.pkrvars.hcl
# Edit with your Vault CA public key
task packer:build
```

Then set `target_ami_id` in terraform.tfvars.

## Troubleshooting

### Vault SSH fails
```bash
task vault:status    # Check configuration
task vault:test      # Test certificate issuance
```

### Target SSH fails
Check the target VM has Vault CA trust configured:
```bash
# On target VM
cat /etc/ssh/vault-ca/trusted-user-ca-keys.pem
grep TrustedUserCAKeys /etc/ssh/sshd_config
```

### AAP cannot reach targets
Ensure `aap_cidr` is set to allow SSH from your AAP controller.

## Security Best Practices

This module follows AWS security best practices:
- **EBS encryption** enabled on all volumes
- **IMDSv2** required (no IMDSv1 fallback)
- **Security groups** use explicit ingress/egress rules
- **No 0.0.0.0/0** SSH access by default
- **Variable validation** on all inputs
