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

**Google Cloud CLI**
```bash
# macOS
brew install google-cloud-sdk

# Login
gcloud auth login
gcloud auth application-default login
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

**Vault Server**
You need a running Vault server. Terraform will configure the SSH CA automatically.
The Vault token needs permissions to:
- Enable secrets engines
- Create policies
- Enable auth methods
- Write to auth/approle

For a fresh Vault dev server, the root token works. For production, create a token with appropriate policies.

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

## 3. Configure AAP

You need Ansible Automation Platform 2.5 running somewhere.

### 3a. Create Project

1. Go to Resources → Projects
2. Click Add
3. Set:
   - Name: `promptops`
   - SCM Type: Git
   - SCM URL: (your repo URL)
4. Save and sync

### 3b. Create Job Template

1. Go to Resources → Templates
2. Click Add → Job Template
3. Set:
   - Name: `promptops-streamlit`
   - Inventory: (any inventory, the playbook injects hosts at runtime)
   - Project: `promptops`
   - Playbook: `ansible/playbooks/install_streamlit.yml`
4. Under **Prompt on launch**, check:
   - Extra Variables
5. Do NOT set a Limit. The playbook's first play runs on `localhost`.
6. Save

No Machine Credential needed. The playbook gets SSH credentials from Vault at runtime.

### 3c. Get Job Template ID

Look at the URL when viewing your job template:
```
https://your-aap.com/#/templates/job_template/42/details
                                              ^^
                                              This is the ID
```

## 4. Create terraform.tfvars

Copy the example and fill in your values:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# GCP
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Compute
vm_count      = 1
instance_name = "gpu-worker"

# Network
allow_ssh       = true
allow_streamlit = true

# AAP
aap_host            = "https://your-aap.example.com"
aap_username        = "admin"
aap_password        = "your-password"
aap_job_template_id = 42

# Vault
vault_addr      = "https://vault.example.com:8200"
vault_token     = "hvs.your-token"
vault_namespace = "admin"  # Leave empty for OSS Vault
```

Terraform configures Vault automatically:
- Creates SSH secrets engine at `/ssh`
- Generates CA signing key
- Creates SSH role "promptops" with permit-pty extension
- Creates AppRole auth with policy for /ssh/issue
- Passes AppRole credentials to AAP playbook

## 5. Run PromptOps

```bash
# Set OpenAI key
export OPENAI_API_KEY='sk-...'

# Start the web UI
cd promptops
.venv/bin/streamlit run web.py
```

Open http://localhost:8501 in your browser.

## 6. Test the Flow

1. Type: "I need a T4 GPU VM"
2. Click "Run Plan" and verify it looks right
3. Click "Apply" to create VM and trigger AAP
4. Wait for AAP job to complete
5. Click the app link to see the Streamlit demo

### What happens under the hood

```
 User                Terraform              Vault                  AAP                  GCP VM
  |                     |                     |                     |                     |
  |  terraform apply    |                     |                     |                     |
  |-------------------->|                     |                     |                     |
  |                     |                     |                     |                     |
  |                     |  1. Enable SSH      |                     |                     |
  |                     |     secrets engine  |                     |                     |
  |                     |-------------------->|                     |                     |
  |                     |                     |                     |                     |
  |                     |  2. Create CA,      |                     |                     |
  |                     |     role, AppRole   |                     |                     |
  |                     |-------------------->|                     |                     |
  |                     |                     |                     |                     |
  |                     |  3. Create VM       |                     |                     |
  |                     |  (startup script    |                     |                     |
  |                     |   installs CA key)  |                     |                     |
  |                     |------------------------------------------------------>|         |
  |                     |                     |                     |                     |
  |                     |                     |                     |  4. Boot, configure |
  |                     |                     |                     |     sshd to trust   |
  |                     |                     |                     |     Vault CA        |
  |                     |                     |                     |                     |
  |                     |  5. Trigger AAP job |                     |                     |
  |                     |  (pass AppRole creds|                     |                     |
  |                     |   + target IPs)     |                     |                     |
  |                     |------------------------------------------>|                     |
  |                     |                     |                     |                     |
  |                     |                     |  6. AppRole login   |                     |
  |                     |                     |<--------------------|                     |
  |                     |                     |     client_token    |                     |
  |                     |                     |-------------------->|                     |
  |                     |                     |                     |                     |
  |                     |                     |  7. POST /ssh/issue |                     |
  |                     |                     |<--------------------|                     |
  |                     |                     |  private_key +      |                     |
  |                     |                     |  signed_cert        |                     |
  |                     |                     |-------------------->|                     |
  |                     |                     |                     |                     |
  |                     |                     |                     |  8. SSH with        |
  |                     |                     |                     |  Vault-signed cert  |
  |                     |                     |                     |-------------------->|
  |                     |                     |                     |                     |
  |                     |                     |                     |  9. Install app     |
  |                     |                     |                     |-------------------->|
  |                     |                     |                     |                     |
  |                     |                     |                     |  10. Shred keys     |
  |                     |                     |                     |                     |
  |  apply complete     |                     |                     |  App running        |
  |<--------------------|                     |                     |  :8501              |
```

## Troubleshooting

### "No GPU quota"

Request quota in Google Cloud Console:
1. Go to IAM & Admin → Quotas
2. Search for "GPUs (all regions)"
3. Request increase

### "AAP job fails: Missing required variables"

The playbook expects these variables from Terraform:
- `target_hosts` (comma-separated IPs)
- `ssh_user`
- `vault_addr`
- `vault_namespace`
- `vault_ssh_role`
- `vault_approle_role_id`
- `vault_approle_secret_id`

Check that Terraform completed successfully before triggering AAP.

### "Vault SSH CA creation fails"

Verify your Vault token has permissions to:
- `sys/mounts/*` (enable secrets engines)
- `sys/policies/acl/*` (create policies)
- `sys/auth/*` (enable auth methods)
- `auth/approle/*` (create AppRole)

For dev/testing, use the root token.

### "SSH Permission denied" after Vault issues credentials

- Verify the VM startup script ran: check `/etc/ssh/sshd_config` for `TrustedUserCAKeys`
- Verify the CA key is installed: check `/etc/ssh/trusted-user-ca-keys.pem`
- Check the SSH role has `permit-pty` in default_extensions (Terraform sets this)
- Check the cert TTL hasn't expired (default 30 min)

### "Could not match supplied host pattern" / "skipping: no hosts matched"

The AAP Job Template has a Limit field set. The playbook's first play runs on `localhost`.
Clear the Limit field in the Job Template.

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
