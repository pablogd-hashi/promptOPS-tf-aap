# Demo Walkthrough: Terraform Actions + Vault SSH CA + AAP

This document is designed for presenting the demo. It shows exactly where the magic happens in the code, explains the credential flow, and highlights areas for improvement.

## Quick Reference: Key Files

| File | Purpose | Show in Demo |
|------|---------|--------------|
| `terraform/aap.tf` | Terraform Action that triggers AAP | Yes |
| `terraform/vault.tf` | Vault SSH CA setup + AppRole | Yes |
| `terraform/main.tf:73-85` | Action trigger binding | Yes |
| `ansible/install_streamlit.yml` | Playbook that uses Vault SSH | Yes |

---

## Part 1: How AAP Gets Triggered

### The Terraform Action (terraform/aap.tf)

```hcl
action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    extra_vars = jsonencode({
      # Target hosts - the VMs we just created
      target_hosts = join(",", module.compute.vm_ips)
      ssh_user     = var.ssh_user

      # Vault credentials for SSH - THIS IS THE KEY PART
      vault_addr              = var.vault_addr
      vault_namespace         = var.vault_namespace
      vault_ssh_role          = local.vault_ssh_role_name
      vault_approle_role_id   = local.vault_approle_role_id    # From vault.tf
      vault_approle_secret_id = local.vault_approle_secret_id  # From vault.tf
    })
  }
}
```

**Key Points to Highlight:**
1. `extra_vars` passes Vault AppRole credentials to the playbook
2. No static SSH keys - playbook will fetch ephemeral keys from Vault
3. `wait_for_completion = true` means Terraform waits for AAP job to finish

### The Trigger Binding (terraform/main.tf:73-85)

```hcl
resource "terraform_data" "aap_trigger" {
  # Track VM IPs - if any change, re-trigger
  input = join(",", module.compute.vm_ips)

  depends_on = [module.compute, module.network]

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.aap_job_launch.configure_vm]
    }
  }
}
```

**Key Points:**
1. `terraform_data` is a lightweight resource that exists only to bind the action
2. `after_create` fires when VMs are first created
3. `after_update` fires if VM IPs change (scale up/down)
4. `depends_on` ensures network is ready before triggering AAP

---

## Part 2: How Terraform Fetches Vault Credentials

### Vault Setup (terraform/vault.tf)

```hcl
# 1. Create SSH secrets engine
resource "vault_mount" "ssh" {
  count = local.ssh_mount_exists ? 0 : 1
  path  = "ssh"
  type  = "ssh"
}

# 2. Generate CA signing key
resource "vault_ssh_secret_backend_ca" "ssh_ca" {
  backend              = "ssh"
  generate_signing_key = true
}

# 3. Create SSH role for issuing certificates
resource "vault_ssh_secret_backend_role" "promptops" {
  name                    = "promptops"
  backend                 = "ssh"
  key_type                = "ca"
  allow_user_certificates = true
  allowed_users           = var.ssh_user
  ttl                     = "1800"  # 30 min expiry

  # CRITICAL: permit-pty required for interactive SSH
  allowed_extensions = "permit-pty,permit-user-rc,permit-port-forwarding"
  default_extensions = {
    "permit-pty"     = ""
    "permit-user-rc" = ""
  }
}

# 4. Create AppRole for AAP to authenticate
resource "vault_approle_auth_backend_role" "promptops" {
  backend        = "approle"
  role_name      = "promptops"
  token_policies = [vault_policy.ssh_issue.name]
}

# 5. Generate Secret ID for AppRole
resource "vault_approle_auth_backend_role_secret_id" "promptops" {
  backend   = "approle"
  role_name = vault_approle_auth_backend_role.promptops.role_name
}

# 6. Export credentials for AAP
locals {
  vault_approle_role_id   = vault_approle_auth_backend_role.promptops.role_id
  vault_approle_secret_id = vault_approle_auth_backend_role_secret_id.promptops.secret_id
}
```

### The Vault Policy (least privilege)

```hcl
resource "vault_policy" "ssh_issue" {
  name = "promptops-ssh-issue"

  policy = <<-EOT
    # Allow issuing SSH certificates (generates key + signs)
    path "ssh/issue/promptops" {
      capabilities = ["create", "update"]
    }

    # Allow signing SSH keys (signs existing key)
    path "ssh/sign/promptops" {
      capabilities = ["create", "update"]
    }
  EOT
}
```

**Key Points:**
1. AppRole credentials are created by Terraform
2. Credentials are passed to AAP via `extra_vars`
3. Policy only allows SSH certificate operations - nothing else

---

## Part 3: How AAP Uses Vault Credentials

### The Ansible Playbook Flow

```yaml
# Play 1: Get SSH credentials from Vault (runs on AAP controller)
- name: Setup Vault SSH credentials
  hosts: localhost
  tasks:
    # Authenticate to Vault using AppRole
    - name: Login to Vault
      uri:
        url: "{{ vault_addr }}/v1/auth/approle/login"
        method: POST
        body_format: json
        body:
          role_id: "{{ vault_approle_role_id }}"
          secret_id: "{{ vault_approle_secret_id }}"
      register: vault_login

    # Get ephemeral SSH key + signed certificate
    - name: Issue SSH credentials
      uri:
        url: "{{ vault_addr }}/v1/ssh/issue/{{ vault_ssh_role }}"
        method: POST
        headers:
          X-Vault-Token: "{{ vault_login.json.auth.client_token }}"
        body_format: json
        body:
          key_type: "rsa"
          username: "{{ ssh_user }}"
      register: ssh_creds

    # Write keys to temp directory
    - name: Write private key
      copy:
        content: "{{ ssh_creds.json.data.private_key }}"
        dest: "/tmp/vault-ssh/id_rsa"
        mode: '0600'

    - name: Write signed certificate
      copy:
        content: "{{ ssh_creds.json.data.signed_key }}"
        dest: "/tmp/vault-ssh/id_rsa-cert.pub"
        mode: '0644'

    # Add target hosts to inventory
    - name: Add hosts
      add_host:
        name: "{{ item }}"
        groups: targets
        ansible_user: "{{ ssh_user }}"
        ansible_ssh_private_key_file: "/tmp/vault-ssh/id_rsa"
      loop: "{{ target_hosts.split(',') }}"

# Play 2: Configure VMs (runs on target VMs)
- name: Configure targets
  hosts: targets
  tasks:
    - name: Install Streamlit
      # ... installation tasks ...

# Play 3: Cleanup (runs on AAP controller)
- name: Cleanup credentials
  hosts: localhost
  tasks:
    - name: Shred SSH keys
      command: shred -u /tmp/vault-ssh/*
```

---

## Part 4: The Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CREDENTIAL FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  TERRAFORM                           VAULT                                   │
│  ┌─────────────────┐                ┌─────────────────┐                     │
│  │ 1. Create SSH   │───────────────>│ SSH CA created  │                     │
│  │    secrets      │                │                 │                     │
│  │    engine       │                └─────────────────┘                     │
│  │                 │                                                        │
│  │ 2. Create       │───────────────>┌─────────────────┐                     │
│  │    AppRole +    │                │ role_id +       │                     │
│  │    get creds    │<───────────────│ secret_id       │                     │
│  │                 │                └─────────────────┘                     │
│  │ 3. Create VMs   │                                                        │
│  │    (with CA     │───────────────>┌─────────────────┐                     │
│  │    public key)  │                │ VMs trust Vault │                     │
│  │                 │                │ CA certificates │                     │
│  │ 4. Trigger AAP  │                └─────────────────┘                     │
│  │    action with  │                                                        │
│  │    Vault creds  │                                                        │
│  └────────┬────────┘                                                        │
│           │                                                                  │
│           │ extra_vars: { vault_approle_role_id, vault_approle_secret_id }  │
│           ▼                                                                  │
│  AAP                                VAULT                                    │
│  ┌─────────────────┐                ┌─────────────────┐                     │
│  │ 5. Playbook     │───────────────>│ Authenticate    │                     │
│  │    logs into    │                │ AppRole         │                     │
│  │    Vault        │<───────────────│ Return token    │                     │
│  │                 │                └─────────────────┘                     │
│  │ 6. Request SSH  │                                                        │
│  │    credentials  │───────────────>┌─────────────────┐                     │
│  │                 │                │ Generate RSA    │                     │
│  │                 │<───────────────│ key + sign cert │                     │
│  │                 │                │ (30 min TTL)    │                     │
│  │ 7. SSH to VMs   │                └─────────────────┘                     │
│  │    with signed  │                                                        │
│  │    certificate  │───────────────>┌─────────────────┐                     │
│  │                 │                │ VM validates    │                     │
│  │ 8. Configure    │                │ cert against    │                     │
│  │    VMs          │                │ trusted CA key  │                     │
│  │                 │                └─────────────────┘                     │
│  │ 9. Shred keys   │                                                        │
│  └─────────────────┘                                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Areas for Improvement

### Current Antipatterns

| Issue | Location | Impact | Fix |
|-------|----------|--------|-----|
| HTTP checks for existing resources | `vault.tf:21-32` | Race conditions, fragile | Use `terraform import` for existing resources |
| `count = local.X_exists ? 0 : 1` | `vault.tf:34-40` | Confusing state management | Remove conditional creation |
| Secrets in extra_vars | `aap.tf:28-29` | Visible in AAP job logs | Use AAP credential type instead |
| No timeout on AAP action | `aap.tf:17` | Can hang forever | Add `wait_for_completion_timeout_seconds` |

### Code to Fix

**1. Remove HTTP checks antipattern (vault.tf)**
```hcl
# BEFORE (antipattern)
data "http" "ssh_mount_check" {
  url = "${var.vault_addr}/v1/sys/mounts/ssh"
  # ...
}

resource "vault_mount" "ssh" {
  count = local.ssh_mount_exists ? 0 : 1
  # ...
}

# AFTER (better)
# Use terraform import if resource exists:
#   terraform import vault_mount.ssh ssh
resource "vault_mount" "ssh" {
  path = "ssh"
  type = "ssh"
}
```

**2. Add timeout to AAP action (aap.tf)**
```hcl
action "aap_job_launch" "configure_vm" {
  config {
    job_template_id                     = var.aap_job_template_id
    wait_for_completion                 = true
    wait_for_completion_timeout_seconds = 600  # ADD THIS
    # ...
  }
}
```

**3. Use AAP credential type instead of extra_vars**

Instead of passing `vault_approle_role_id` and `vault_approle_secret_id` in extra_vars (visible in logs), create a "HashiCorp Vault Secret Lookup" credential in AAP and reference it in the job template.

### Security Improvements

| Improvement | Why | How |
|-------------|-----|-----|
| Rotate AppRole secret_id | Current one never rotates | Add `terraform taint` to rotation script |
| Reduce SSH cert TTL | 30 min may be too long | Change `ttl = "300"` (5 min) |
| Add CIDR restrictions | AppRole accepts from anywhere | Add `secret_id_bound_cidrs` to role |
| Audit logging | No visibility into Vault access | Enable Vault audit device |

---

## Part 6: Demo Script

### Setup (before demo)
```bash
# Export Vault token
export VAULT_TOKEN="your-token"
export VAULT_ADDR="https://vault.example.com:8200"

# Initialize Terraform
cd terraform && terraform init
```

### Live Demo Steps

1. **Show the Terraform config** (2 min)
   - Open `aap.tf` - "This is the action that triggers AAP"
   - Open `vault.tf` - "This sets up Vault SSH CA and AppRole"
   - Open `main.tf:73-85` - "This binds the action to VM creation"

2. **Run terraform plan** (1 min)
   ```bash
   terraform plan -var-file=demo.tfvars
   ```
   - Point out the Vault resources
   - Point out the VM creation
   - Point out "Action will be invoked: action.aap_job_launch.configure_vm"

3. **Run terraform apply** (3-5 min)
   ```bash
   terraform apply -var-file=demo.tfvars
   ```
   - Watch Vault resources create
   - Watch VMs create
   - Watch AAP job get triggered
   - Show AAP UI with job running in parallel

4. **Show the result** (1 min)
   ```bash
   terraform output vm_ips
   # Visit http://<ip>:8501 in browser
   ```

5. **Show no static keys** (30 sec)
   ```bash
   # No SSH keys in AAP
   # No SSH keys in Terraform state (AppRole creds yes, but not SSH)
   # Keys are generated per-job and shredded
   ```

### Manual Re-run (if needed)
```bash
# Re-run AAP without recreating VMs
terraform apply -invoke action.aap_job_launch.configure_vm
```

---

## Part 7: Key Talking Points

1. **"No static SSH keys anywhere"**
   - VMs trust Vault CA public key (baked in at boot)
   - AAP gets ephemeral keys from Vault per job
   - Keys expire in 30 minutes and are shredded after use

2. **"Terraform Actions vs local-exec"**
   - Actions are declarative, visible in config
   - Actions don't pollute state with job runs
   - Actions can be re-invoked manually

3. **"Separation of concerns"**
   - Terraform: Creates infrastructure + Vault setup
   - Vault: Issues ephemeral credentials
   - AAP: Configures VMs with those credentials
   - Each tool does one thing well

4. **"The LLM (if using PromptOps) never touches credentials"**
   - LLM only writes terraform.tfvars
   - Human reviews and approves
   - Terraform/Vault/AAP handle execution

---

## Appendix: File Locations

```
promptOPS-tf-aap/
├── terraform/
│   ├── aap.tf           # Terraform Action definition
│   ├── vault.tf         # Vault SSH CA + AppRole setup
│   ├── main.tf          # Action trigger + modules
│   ├── variables.tf     # Input variables
│   └── outputs.tf       # VM IPs, URLs
├── ansible/
│   └── install_streamlit.yml  # Playbook using Vault SSH
└── docs/
    ├── architecture.md  # Full architecture doc
    ├── setup.md         # Setup instructions
    └── demo-walkthrough.md  # THIS FILE
```
