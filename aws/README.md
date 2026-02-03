# AWS AAP + Vault SSH CA Demo

Provisions AAP on AWS with Vault SSH CA. Demonstrates Terraform 1.14+ Actions triggering AAP with zero-trust SSH credentials.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           AWS VPC                                │
│                                                                  │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐                   │
│  │   ALB   │────▶│   AAP   │────▶│ Target  │                   │
│  │ (HTTPS) │     │         │     │   VMs   │                   │
│  └─────────┘     └─────────┘     └─────────┘                   │
│       │               │               ▲                         │
│       ▼               ▼               │                         │
│  ┌─────────┐     ┌─────────┐         │                         │
│  │ Route53 │     │  Vault  │─────────┘                         │
│  └─────────┘     │ SSH CA  │  Issues ephemeral certs           │
│                  └─────────┘                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
cd aws
task check                          # Verify prerequisites
task setup                          # Initialize Terraform
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars
task demo                           # Run full demo
```

## Two-Stage Deployment

When creating new AAP (`create_aap = true`), providers need the AAP URL at plan time, but AAP doesn't exist yet. Solution: two applies.

**Stage 1** - Create infrastructure:
```bash
# terraform.tfvars
aap_host = "https://placeholder.local"  # Default placeholder

terraform apply
```

**Stage 2** - Trigger AAP action:
```bash
# Get actual URL from outputs
terraform output aap_url

# Update terraform.tfvars
aap_host = "https://aap.your-domain.com"  # Actual URL

terraform apply  # Now triggers AAP action
```

**Using existing AAP** (`create_aap = false`): Set `aap_host` to your AAP URL and run once.

## Variables

### Required

| Variable | Description |
|----------|-------------|
| `aap_host` | AAP URL (placeholder on first run, actual URL on second) |
| `aap_password` | AAP admin password |
| `aap_job_template_id` | Job template ID to trigger |
| `vault_addr` | Vault server URL |
| `vault_token` | Vault token with admin permissions |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `create_aap` | `true` | Create AAP or use existing |
| `create_alb` | `true` | Create ALB with HTTPS |
| `target_vm_count` | `1` | Number of target VMs |
| `vault_namespace` | `""` | Vault namespace (Enterprise/HCP) |
| `ssh_user` | `ec2-user` | SSH user for targets |

## Terraform Cloud

### Environment Variables
```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY  (sensitive)
```

### Terraform Variables
```hcl
aap_host            = "https://placeholder.local"  # Update after Stage 1
aap_password        = "xxx"                        # sensitive
aap_job_template_id = 42
vault_addr          = "https://vault.example.com:8200"
vault_token         = "hvs.xxx"                    # sensitive
vault_namespace     = "admin"
```

For production, use [dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials) instead of static tokens.

## Task Commands

| Command | Description |
|---------|-------------|
| `task check` | Verify prerequisites |
| `task setup` | Initialize Terraform |
| `task demo` | Full demo flow |
| `task apply` | Create infrastructure |
| `task vault:status` | Check Vault SSH CA |
| `task vault:test` | Test issuing certificate |
| `task retrigger` | Re-run AAP action |
| `task destroy` | Destroy infrastructure |

## Packer (Optional)

Build custom AMIs with Vault CA pre-baked:

```bash
task packer:init
cp packer/variables.pkrvars.hcl.example packer/variables.pkrvars.hcl
# Edit with your Vault CA public key
task packer:build
```

Then set `aap_ami_id` and `target_ami_id` in terraform.tfvars.

## How It Works

1. **Terraform** creates VPC, AAP, target VMs with Vault CA trust in sshd
2. **Terraform Actions** trigger AAP job with target IPs and Vault credentials
3. **AAP** authenticates to Vault via AppRole, gets ephemeral SSH key + cert
4. **AAP** SSHs to targets using Vault-signed credentials
5. **Credentials shredded** after use - nothing stored

## Troubleshooting

**AAP not healthy**: ALB checks take ~5min. Check target health in AWS console.

**Vault SSH fails**: Run `task vault:status` and `task vault:test`

**Target SSH fails**: Check `/etc/ssh/sshd_config` has `TrustedUserCAKeys` directive
