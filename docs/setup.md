# Setup Guide

Step-by-step instructions to get PromptOps running.

## 1. Prerequisites

### Install Required Tools

**Python 3.9+**
```bash
python3 --version  # Should be 3.9 or higher
```

**Terraform 1.14+** (required for Terraform Actions)
```bash
# macOS
brew install terraform

# Verify - must be 1.14.0 or higher
terraform version
```

> **Why 1.14?** PromptOps uses [Terraform Actions](https://developer.hashicorp.com/terraform/language/block/action)
> to trigger AAP jobs after VM creation. Actions are a Terraform 1.14 feature that
> replaced the old workaround of using `aap_job` resources. See the
> [Terraform Actions announcement](https://www.hashicorp.com/en/blog/day-2-infrastructure-management-with-terraform-actions)
> for background.

**Google Cloud CLI**
```bash
# macOS
brew install google-cloud-sdk

# Login
gcloud auth login
gcloud auth application-default login
```

**HashiCorp Vault** (for SSH CA)
```bash
# macOS
brew install vault

# Verify
vault version
```

### Get API Keys

**OpenAI API Key**
1. Go to https://platform.openai.com/api-keys
2. Create a new key
3. Save it somewhere safe

**Google Cloud Project**
1. Create or select a project in Google Cloud Console
2. Enable the Compute Engine API
3. Request GPU quota if you don't have it (can take 24-48 hours)

## 2. Install PromptOps

```bash
# Clone the repo
git clone <your-repo-url>
cd promptops

# Create Python environment
cd promptops
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cd ..

# Initialize Terraform
cd terraform
terraform init
cd ..
```

## 3. Configure Vault SSH CA

PromptOps uses Vault as an SSH Certificate Authority. VMs trust the Vault CA,
and each AAP job run gets ephemeral SSH credentials from Vault. No static SSH
keys are stored anywhere.

### 3a. Set Your Vault Namespace (Enterprise Only)

If you're running Vault Enterprise, set the namespace before running the
remaining Vault commands:

```bash
export VAULT_NAMESPACE="admin"  # your namespace
```

OSS Vault users can skip this — leave `vault_namespace` empty in tfvars.

### 3b. Enable the SSH Secrets Engine

```bash
vault secrets enable ssh
```

### 3c. Configure the CA

```bash
# Generate a CA key pair (or provide your own)
vault write ssh/config/ca generate_signing_key=true
```

### 3d. Retrieve the CA Public Key

You'll need this for Terraform (the VM startup script installs it):

```bash
vault read -field=public_key ssh/config/ca
```

Save this value — it goes into `terraform.tfvars` as `vault_ca_public_key`.

### 3e. Create an SSH Role

```bash
vault write ssh/roles/promptops \
  key_type=ca \
  default_user=ubuntu \
  allowed_users="ubuntu" \
  ttl=30m \
  max_ttl=1h \
  allow_user_certificates=true \
  default_extensions='{"permit-pty":"","permit-user-rc":""}'
```

- `default_user`: matches the `ssh_user` in Terraform
- `ttl=30m`: certificates expire after 30 minutes (allows for VM boot + startup script + playbook run)
- `max_ttl=1h`: hard upper limit
- `default_extensions`: `permit-pty` is **required** — without it, sshd rejects the certificate even if the signature is valid

### 3f. Create a Vault Policy

```bash
vault policy write promptops-ssh - <<EOF
# Allow issuing SSH certificates
path "ssh/issue/promptops" {
  capabilities = ["update"]
}

# Allow reading the CA public key (optional, for verification)
path "ssh/config/ca" {
  capabilities = ["read"]
}
EOF
```

### 3g. Configure AppRole Authentication

```bash
# Enable AppRole auth method
vault auth enable approle

# Create a role tied to the SSH policy
vault write auth/approle/role/promptops \
  token_policies="promptops-ssh" \
  token_ttl=10m \
  token_max_ttl=30m \
  secret_id_num_uses=0 \
  secret_id_ttl=0

# Get the role ID (not sensitive — like a username)
vault read -field=role_id auth/approle/role/promptops/role-id

# Generate a secret ID (sensitive — like a password)
vault write -field=secret_id -f auth/approle/role/promptops/secret-id
```

Save both values. The `role_id` and `secret_id` are configured in AAP (step 4b),
**not** in Terraform.

## 4. Configure AAP

You need Ansible Automation Platform 2.5 running somewhere.

### 4a. Create Vault Credential Type (Custom)

AAP needs a credential type that injects `vault_approle_role_id` and
`vault_approle_secret_id` as extra vars into the playbook.

In AAP:
1. Go to Administration → Credential Types
2. Click Add
3. Set:
   - Name: `Vault AppRole`
   - Input Configuration:
     ```yaml
     fields:
       - id: vault_approle_role_id
         type: string
         label: Vault AppRole Role ID
       - id: vault_approle_secret_id
         type: string
         label: Vault AppRole Secret ID
         secret: true
     required:
       - vault_approle_role_id
       - vault_approle_secret_id
     ```
   - Injector Configuration:
     ```yaml
     extra_vars:
       vault_approle_role_id: '{{ vault_approle_role_id }}'
       vault_approle_secret_id: '{{ vault_approle_secret_id }}'
     ```
4. Save

### 4b. Create Vault AppRole Credential

1. Go to Resources → Credentials
2. Click Add
3. Set:
   - Name: `vault-approle-promptops`
   - Credential Type: `Vault AppRole` (the custom type from 4a)
   - Vault AppRole Role ID: (paste the role_id from step 3f)
   - Vault AppRole Secret ID: (paste the secret_id from step 3f)
4. Save

### 4c. Create Project

1. Go to Resources → Projects
2. Click Add
3. Set:
   - Name: `promptops`
   - SCM Type: Git
   - SCM URL: (your repo URL)
4. Save and sync

### 4d. Create Job Template

1. Go to Resources → Templates
2. Click Add → Job Template
3. Set:
   - Name: `promptops-streamlit`
   - Inventory: (any inventory — the playbook injects the host at runtime via `add_host`)
   - Project: `promptops`
   - Playbook: `playbooks/install_streamlit.yml`
   - Credentials: `vault-approle-promptops` (the credential from 4b)
4. Under **Prompt on launch**, check:
   - Extra Variables
5. **Do NOT set a Limit** on the job template. The playbook's first play runs on
   `localhost` to dynamically add the target host. If a limit is set to the VM IP,
   `localhost` won't match and the entire playbook will be skipped.
6. Save

> **No Machine Credential needed.** The playbook obtains its own SSH credentials
> from Vault at runtime. AAP only needs the AppRole credential to authenticate
> to Vault.

### 4e. Get Job Template ID

Look at the URL when viewing your job template:
```
https://your-aap.com/#/templates/job_template/42/details
                                              ^^
                                              This is the ID
```

### How Terraform Triggers This Job Template

PromptOps uses **Terraform Actions** (not resources) to trigger the AAP job.
This is defined in two files:

**`terraform/aap.tf`** — Defines the action:
```hcl
action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    # Only non-sensitive values. AppRole creds injected by AAP.
    extra_vars = jsonencode({
      target_host     = module.compute.vm_ip
      ssh_user        = var.ssh_user
      vault_addr      = var.vault_addr
      vault_namespace = var.vault_namespace
      vault_ssh_role  = var.vault_ssh_role
    })
  }
}
```

**`terraform/main.tf`** — Binds the action to a lifecycle event:
```hcl
resource "terraform_data" "aap_trigger" {
  input = module.compute.vm_ip
  depends_on = [module.compute, module.network]

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.aap_job_launch.configure_vm]
    }
  }
}
```

**Key points:**
- The action fires `after_create` (first deploy) and `after_update` (if the VM IP changes)
- `wait_for_completion = true` means Terraform waits for the AAP job to finish
- `extra_vars` passes the VM IP, SSH user, Vault address, namespace, and SSH role to the playbook
- AppRole credentials (`role_id`, `secret_id`) are injected by AAP's credential — never in Terraform
- The action does NOT create state — it just triggers the job
- You can manually re-trigger with: `terraform apply -invoke action.aap_job_launch.configure_vm`

## 5. Create terraform.tfvars

Copy the example and fill in your values:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# GCP
project_id = "your-actual-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# AAP
aap_host            = "https://your-aap.example.com"
aap_username        = "admin"
aap_password        = "your-password"
aap_job_template_id = 42

# Vault SSH CA
# Get this with: vault read -field=public_key ssh/config/ca
vault_addr          = "https://vault.example.com:8200"
vault_namespace     = "admin/promptops"  # Vault Enterprise only, leave "" for OSS
vault_ca_public_key = "ssh-rsa AAAA..."
vault_ssh_role      = "promptops"
```

> **Note:** `vault_approle_role_id` and `vault_approle_secret_id` are NOT in
> this file. They are managed by AAP's credential lookup — never stored in
> tfvars or Terraform state.

## 6. Run PromptOps

```bash
# Set OpenAI key
export OPENAI_API_KEY='sk-...'

# Start the web UI
cd promptops
.venv/bin/streamlit run web.py
```

Open http://localhost:8501 in your browser.

## 7. Test the Flow

1. Type: "I need a T4 GPU VM"
2. Click "Run Plan" - verify it looks right
3. Click "Apply" - creates VM and triggers AAP
4. Wait for AAP job to complete (watch the AAP job output for Vault auth + SSH)
5. Click the app link to see the Streamlit demo

### What happens under the hood

```
 User                Terraform              GCP VM                 AAP                  Vault
  |                     |                     |                     |                     |
  |  terraform apply    |                     |                     |                     |
  |-------------------->|                     |                     |                     |
  |                     |                     |                     |                     |
  |                     |  1. Create VM       |                     |                     |
  |                     |  (startup script    |                     |                     |
  |                     |   installs Vault    |                     |                     |
  |                     |   CA public key)    |                     |                     |
  |                     |-------------------->|                     |                     |
  |                     |                     |                     |                     |
  |                     |                     |  2. Boot            |                     |
  |                     |                     |  Configure sshd:    |                     |
  |                     |                     |  TrustedUserCAKeys  |                     |
  |                     |                     |                     |                     |
  |                     |  3. Trigger AAP job (Terraform Actions)   |                     |
  |                     |------------------------------------------>|                     |
  |                     |                     |                     |                     |
  |                     |                     |  4. AAP injects     |                     |
  |                     |                     |  AppRole creds      |                     |
  |                     |                     |  (credential lookup)|                     |
  |                     |                     |                     |                     |
  |                     |                     |                     |  5. AppRole login   |
  |                     |                     |                     |-------------------->|
  |                     |                     |                     |     client_token    |
  |                     |                     |                     |<--------------------|
  |                     |                     |                     |                     |
  |                     |                     |                     |  6. POST /ssh/issue |
  |                     |                     |                     |-------------------->|
  |                     |                     |                     |  private_key +      |
  |                     |                     |                     |  signed_cert (5min) |
  |                     |                     |                     |<--------------------|
  |                     |                     |                     |                     |
  |                     |                     |  7. SSH with        |                     |
  |                     |                     |  Vault-signed cert  |                     |
  |                     |                     |<--------------------|                     |
  |                     |                     |                     |                     |
  |                     |                     |  8. Install app     |                     |
  |                     |                     |  Start systemd svc  |                     |
  |                     |                     |<--------------------|                     |
  |                     |                     |                     |                     |
  |                     |                     |  9. Shred keys      |                     |
  |                     |                     |                     |                     |
  |  apply complete     |                     |  App running        |                     |
  |<--------------------|                     |  :8501              |                     |
```

**Step-by-step:**

1. Terraform creates the VM with Vault CA public key in the startup script
2. VM boots, startup script configures sshd to trust Vault-signed certificates
3. Terraform triggers AAP job via Terraform Actions
4. AAP injects AppRole credentials into the playbook via credential lookup
5. Playbook authenticates to Vault (AppRole), calls `POST /ssh/issue/promptops`
6. Vault returns an ephemeral private key + signed certificate (TTL: 5 min)
7. Playbook SSHes into the VM using the Vault-issued credentials
8. Playbook installs Streamlit, starts systemd service
9. Playbook shreds the ephemeral SSH credentials

## Troubleshooting

### "No GPU quota"

Request quota in Google Cloud Console:
1. Go to IAM & Admin → Quotas
2. Search for "GPUs (all regions)"
3. Request increase

### "AAP job fails: Missing required variables"

The playbook expects these variables:
- From Terraform extra_vars: `target_host`, `ssh_user`, `vault_addr`, `vault_namespace`, `vault_ssh_role`
- From AAP credential injection: `vault_approle_role_id`, `vault_approle_secret_id`

Check that:
1. The AAP Job Template has the `vault-approle-promptops` credential attached
2. The custom credential type injector is configured correctly (see step 4a)

### "Vault AppRole login fails (403)"

- Verify `role_id` and `secret_id` are correct: `vault read auth/approle/role/promptops/role-id`
- Regenerate `secret_id` if expired: `vault write -f auth/approle/role/promptops/secret-id`
- Check the policy is attached: `vault read auth/approle/role/promptops`

### "SSH Permission denied" after Vault issues credentials

- Verify the VM startup script ran: `gcloud compute ssh <vm> -- cat /etc/ssh/sshd_config | grep TrustedUserCAKeys`
- Verify the CA key is installed: `gcloud compute ssh <vm> -- cat /etc/ssh/trusted-ca-keys.pem`
- Check the Vault SSH role's `allowed_users` includes your `ssh_user`
- Check the cert TTL hasn't expired (default 5 min)

### "Could not match supplied host pattern" / "skipping: no hosts matched"

**Cause:** The AAP Job Template has a **Limit** field set. The playbook's first
play runs on `localhost` to inject the target via `add_host`. A limit prevents
`localhost` from matching, so the host is never added.

**Fix:** Remove the Limit from the Job Template in AAP:
1. Go to Resources → Templates
2. Edit `promptops-streamlit`
3. Clear the **Limit** field (leave it blank)
4. Save
5. Re-run: `terraform apply -invoke action.aap_job_launch.configure_vm`

### "terraform init fails"

Make sure you have internet access and the providers can be downloaded:
```bash
terraform providers
```

### "OPENAI_API_KEY not set"

Export it in your shell:
```bash
export OPENAI_API_KEY='sk-...'
```

Or add to your shell profile (~/.bashrc or ~/.zshrc).
