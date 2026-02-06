# Vault Credential Flow (Wrapped Secret ID)

This document explains how Vault credentials flow from Terraform to AAP without storing static secrets anywhere.

## Overview

Instead of storing AppRole credentials in AAP, Terraform generates a **wrapped secret_id** each time. The wrapped token is single-use and time-limited - even if it appears in logs, it's useless after the playbook unwraps it.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  TERRAFORM                                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                                                                       │   │
│  │   1. POST /auth/approle/role/promptops/secret-id                     │   │
│  │      Header: X-Vault-Wrap-TTL: 3h                                    │   │
│  │                                                                       │   │
│  │   2. Vault returns wrapped_token (not the actual secret_id)          │   │
│  │                                                                       │   │
│  │   3. Pass to AAP via extra_vars:                                     │   │
│  │      vault_wrapped_secret_id = "hvs.CAES..."                         │   │
│  │                                                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                              │                                               │
│                              ▼                                               │
│  AAP PLAYBOOK                                                                │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                                                                       │   │
│  │   4. POST /sys/wrapping/unwrap                                       │   │
│  │      Header: X-Vault-Token: <wrapped_token>                          │   │
│  │                                                                       │   │
│  │      → Vault returns the REAL secret_id                              │   │
│  │      → Wrapped token is now INVALID (single-use)                     │   │
│  │                                                                       │   │
│  │   5. POST /auth/approle/login                                        │   │
│  │      Body: { role_id: "...", secret_id: "<unwrapped>" }              │   │
│  │                                                                       │   │
│  │      → Vault returns client token                                    │   │
│  │                                                                       │   │
│  │   6. POST /ssh/issue/promptops                                       │   │
│  │      Header: X-Vault-Token: <client_token>                           │   │
│  │                                                                       │   │
│  │      → Vault returns ephemeral SSH private key + signed cert         │   │
│  │                                                                       │   │
│  │   7. SSH to VMs using Vault-issued credentials                       │   │
│  │                                                                       │   │
│  │   8. Shred SSH keys when done                                        │   │
│  │                                                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Why Wrapped Secrets?

| Approach | Problem |
|----------|---------|
| Plain secret_id in extra_vars | Visible in AAP job logs, reusable |
| Static secret_id in AAP credential | Expires every 3 hours, must manually rotate |
| **Wrapped secret_id** | Single-use, safe to log, auto-generated each run |

## No AAP Credential Setup Required

With the wrapped secret approach, you don't need to configure any Vault credentials in AAP. Everything flows through Terraform:

1. Terraform generates a fresh wrapped secret_id on each apply
2. Terraform passes it to AAP via the job launch action
3. Playbook unwraps and uses it
4. Wrapped token is invalidated after unwrap

## Security Properties

| Property | How It's Achieved |
|----------|-------------------|
| **Single-use** | Wrapped tokens are invalidated after unwrap |
| **Time-limited** | Wrapped token expires in 3 hours if not used |
| **Safe to log** | Even if logged, token is useless after unwrap |
| **No static secrets** | Fresh wrapped token generated each terraform apply |
| **Audit trail** | Vault logs both wrap and unwrap operations |

## How to Re-run the AAP Job

Since the wrapped token is single-use, you need to generate a new one to re-run:

```bash
# This generates a fresh wrapped secret_id and triggers AAP
terraform apply -invoke action.aap_job_launch.configure_vm
```

Or just run `terraform apply` which will:
1. Generate a new wrapped secret_id
2. Trigger the AAP job with the fresh token

## Troubleshooting

### "permission denied" on unwrap

The wrapped token may have:
- Already been used (single-use)
- Expired (3 hour TTL)

**Fix:** Run `terraform apply` to generate a fresh wrapped token.

### "wrapping token is not valid"

Same as above - the token was already unwrapped or expired.

### Playbook fails before unwrap

If the playbook fails before reaching the unwrap step, the wrapped token is still valid. You can re-run:

```bash
terraform apply -invoke action.aap_job_launch.configure_vm
```

But note this generates a NEW wrapped token - the old one is orphaned (will expire naturally).

## Vault Policy

The AppRole only needs these permissions:

```hcl
# Allow issuing SSH certificates
path "ssh/issue/promptops" {
  capabilities = ["create", "update"]
}

# Allow signing SSH keys
path "ssh/sign/promptops" {
  capabilities = ["create", "update"]
}
```

The unwrap operation (`/sys/wrapping/unwrap`) is authorized by the wrapped token itself - no additional policy needed.
