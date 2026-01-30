# PromptOps Architecture

This document explains how PromptOps works, from user intent to running infrastructure.

## The Big Picture

PromptOps separates thinking from doing. An LLM thinks about what infrastructure you need. Terraform and Ansible actually create and configure it.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   YOU: "I need 5 GPU VMs for machine learning"                               │
│                                                                              │
│                              ▼                                               │
│                                                                              │
│   ┌────────────────────────────────────────────┐                            │
│   │           PromptOps Web UI                 │                            │
│   │                                            │                            │
│   │   Your words go to GPT-4, which figures    │                            │
│   │   out what GPU, what region, what size.    │                            │
│   │                                            │                            │
│   │   It writes a config file. That's all.    │                            │
│   │   No cloud access. No execution.           │                            │
│   └─────────────────────┬──────────────────────┘                            │
│                         │                                                    │
│                         │ terraform.tfvars                                   │
│                         ▼                                                    │
│   ┌────────────────────────────────────────────┐                            │
│   │              Terraform                      │                            │
│   │                                            │                            │
│   │   1. Configures Vault SSH CA               │                            │
│   │   2. Creates the VMs on Google Cloud       │                            │
│   │   3. Tells Ansible to configure them       │                            │
│   └─────────────────────┬──────────────────────┘                            │
│                         │                                                    │
│                         │ "Here are the VM IPs, go configure them"           │
│                         ▼                                                    │
│   ┌────────────────────────────────────────────┐                            │
│   │     Ansible Automation Platform            │                            │
│   │                                            │                            │
│   │   Gets ephemeral SSH keys from Vault.      │                            │
│   │   SSHs into each VM.                       │                            │
│   │   Installs Python, Streamlit, demo app.    │                            │
│   │   Shreds the keys when done.               │                            │
│   └─────────────────────┬──────────────────────┘                            │
│                         │                                                    │
│                         ▼                                                    │
│                                                                              │
│   RESULT: Running GPU VMs with demo apps at http://<ip>:8501                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    PromptOps                                         │
│                                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐       │
│  │   User      │     │  PromptOps  │     │  Terraform  │     │    AAP      │       │
│  │   (You)     │     │   Web UI    │     │             │     │             │       │
│  └──────┬──────┘     └──────┬──────┘     └──────┬──────┘     └──────┬──────┘       │
│         │                   │                   │                   │              │
│         │  "Create 5 VMs"   │                   │                   │              │
│         │──────────────────>│                   │                   │              │
│         │                   │                   │                   │              │
│         │                   │  GPT-4 API        │                   │              │
│         │                   │  (reasoning)      │                   │              │
│         │                   │                   │                   │              │
│         │  terraform.tfvars │                   │                   │              │
│         │<──────────────────│                   │                   │              │
│         │                   │                   │                   │              │
│         │  "Run Plan"       │                   │                   │              │
│         │──────────────────────────────────────>│                   │              │
│         │                   │                   │                   │              │
│         │                   │                   │  1. Vault SSH CA  │              │
│         │                   │                   │─────────────────────────────────>│
│         │                   │                   │                   │    Vault     │
│         │                   │                   │                   │              │
│         │                   │                   │  2. Create VMs    │              │
│         │                   │                   │─────────────────────────────────>│
│         │                   │                   │                   │    GCP       │
│         │                   │                   │                   │              │
│         │                   │                   │  3. Trigger AAP   │              │
│         │                   │                   │──────────────────>│              │
│         │                   │                   │                   │              │
│         │                   │                   │                   │  4. Get SSH  │
│         │                   │                   │                   │     keys     │
│         │                   │                   │                   │────────────> │
│         │                   │                   │                   │    Vault     │
│         │                   │                   │                   │              │
│         │                   │                   │                   │  5. SSH +    │
│         │                   │                   │                   │     Install  │
│         │                   │                   │                   │────────────> │
│         │                   │                   │                   │    VMs       │
│         │                   │                   │                   │              │
│         │  App URLs         │                   │                   │              │
│         │<─────────────────────────────────────────────────────────│              │
│         │                   │                   │                   │              │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Vault SSH CA Flow

No static SSH keys are stored anywhere. Vault generates ephemeral credentials for each job run.

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                             Vault SSH CA Architecture                                │
│                                                                                      │
│   TERRAFORM (one-time setup)                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                              │   │
│   │   1. Enable SSH secrets engine at /ssh                                       │   │
│   │   2. Generate CA signing key                                                 │   │
│   │   3. Create SSH role "promptops" (allow /ssh/issue)                          │   │
│   │   4. Enable AppRole auth                                                     │   │
│   │   5. Create policy for SSH issuance                                          │   │
│   │   6. Create AppRole with role_id + secret_id                                 │   │
│   │                                                                              │   │
│   │   Output: CA public key → embedded in VM startup script                      │   │
│   │           AppRole creds → passed to AAP playbook                             │   │
│   │                                                                              │   │
│   └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│   VM BOOT (automatic)                                                                │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                              │   │
│   │   Startup script:                                                            │   │
│   │   1. Write CA public key to /etc/ssh/trusted-user-ca-keys.pem               │   │
│   │   2. Add "TrustedUserCAKeys" to sshd_config                                  │   │
│   │   3. Restart sshd                                                            │   │
│   │                                                                              │   │
│   │   Result: VM trusts any SSH cert signed by Vault CA                          │   │
│   │                                                                              │   │
│   └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│   AAP JOB RUN (each time)                                                            │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                              │   │
│   │   Playbook:                                                                  │   │
│   │   1. Authenticate to Vault (AppRole login)                                   │   │
│   │   2. Call POST /ssh/issue/promptops                                          │   │
│   │      → Vault generates private key + signs public key                        │   │
│   │      → Returns private_key + signed_key (cert)                               │   │
│   │   3. Write keys to /tmp/vault-ssh-<hash>/                                    │   │
│   │   4. SSH to VM with -i id_rsa -o CertificateFile=id_rsa-cert.pub            │   │
│   │   5. Configure VM (install apps)                                             │   │
│   │   6. Shred keys (overwrite + delete)                                         │   │
│   │                                                                              │   │
│   │   Result: No keys persist after job completes                                │   │
│   │                                                                              │   │
│   └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Where Does the LLM Reasoning Happen?

The LLM (GPT-4) runs inside the PromptOps web application. Here's the detail:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PromptOps Web UI                                    │
│                                                                             │
│  ┌─────────────────┐      ┌─────────────────┐      ┌──────────────────┐   │
│  │                 │      │                 │      │                  │   │
│  │   Chat Input    │─────▶│   GPT-4 API     │─────▶│  terraform.tfvars│   │
│  │                 │      │                 │      │                  │   │
│  │  "I need 5 T4   │      │  Reads system   │      │  vm_count=5      │   │
│  │   GPUs in       │      │  prompt that    │      │  gpu_type=t4     │   │
│  │   us-west1"     │      │  explains GPU   │      │  gpu_count=1     │   │
│  │                 │      │  options, costs,│      │  zone=us-west1-a │   │
│  │                 │      │  constraints    │      │                  │   │
│  └─────────────────┘      └─────────────────┘      └──────────────────┘   │
│                                                                             │
│  The LLM has ONE credential: OpenAI API key                                │
│  The LLM has ZERO cloud credentials                                        │
│  The LLM can ONLY write a config file                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

The system prompt (`promptops/prompts/system.txt`) tells GPT-4:
- What GPU types exist (T4, V100, A100)
- What regions are available
- How to pick machine types that match GPUs
- What variables to output

GPT-4 reasons about your request and outputs a JSON block. The web app converts that to `terraform.tfvars`.

## How Terraform Triggers Ansible (Terraform Actions)

This is the key integration. Terraform doesn't just create the VM and stop. It also
tells Ansible to configure it using Terraform Actions, a feature introduced
in Terraform 1.14.

### What Are Terraform Actions?

Actions are a new block type in Terraform for expressing non-CRUD operations.
Things that need to happen for infrastructure to work but aren't infrastructure
themselves:

- Running a Lambda function
- Configuring a VM with Ansible
- Invalidating a CDN cache
- Triggering a webhook

Before Actions, these were handled with `local-exec` provisioners or fake data
sources. Actions are purpose-built for this.

Key properties of Actions:
- Declared in Terraform config (visible, not hidden in scripts)
- Triggered by resource lifecycle events (`after_create`, `after_update`, `before_destroy`)
- Do NOT create state. They just execute when triggered
- Can be invoked manually with `terraform apply -invoke action.<type>.<name>`

### How PromptOps Uses Actions

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           terraform apply                                   │
│                                                                             │
│  Step 1: Configure Vault SSH CA                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  vault_mount.ssh, vault_ssh_secret_backend_ca, etc.                 │   │
│  │                                                                      │   │
│  │  - Creates SSH secrets engine                                       │   │
│  │  - Generates CA signing key                                         │   │
│  │  - Creates SSH role and AppRole                                     │   │
│  └──────────────────────────────────────┬──────────────────────────────┘   │
│                                         │                                   │
│  Step 2: Create VMs                     │ depends_on                        │
│  ┌──────────────────────────────────────┴──────────────────────────────┐   │
│  │  module.compute (google_compute_instance)                           │   │
│  │                                                                      │   │
│  │  - Creates VMs on GCP (count = var.vm_count)                        │   │
│  │  - Attaches GPUs                                                    │   │
│  │  - Startup script installs Vault CA public key                      │   │
│  │  - Gets external IPs                                                │   │
│  └──────────────────────────────────────┬──────────────────────────────┘   │
│                                         │                                   │
│  Step 3: Create firewall rules          │ depends_on                        │
│  ┌──────────────────────────────────────┴──────────────────────────────┐   │
│  │  module.network (google_compute_firewall)                           │   │
│  │                                                                      │   │
│  │  - Opens SSH (port 22) and Streamlit (port 8501)                    │   │
│  └──────────────────────────────────────┬──────────────────────────────┘   │
│                                         │                                   │
│  Step 4: Trigger AAP via Action         │ depends_on                        │
│  ┌──────────────────────────────────────┴──────────────────────────────┐   │
│  │  terraform_data.aap_trigger                                         │   │
│  │                                                                      │   │
│  │  lifecycle {                                                         │   │
│  │    action_trigger {                                                  │   │
│  │      events  = [after_create, after_update]                         │   │
│  │      actions = [action.aap_job_launch.configure_vm]                 │   │
│  │    }                                                                 │   │
│  │  }                                                                   │   │
│  │                                                                      │   │
│  │  after_create fires ──► action.aap_job_launch.configure_vm          │   │
│  │                                                                      │   │
│  │  The action:                                                         │   │
│  │  - Calls AAP API                                                    │   │
│  │  - Passes extra_vars:                                               │   │
│  │      target_hosts = "34.56.78.90,34.56.78.91,..."                   │   │
│  │      vault_approle_role_id = "..."                                  │   │
│  │      vault_approle_secret_id = "..."                                │   │
│  │  - Waits for AAP job to complete                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Terraform Config

Action definition (`terraform/aap.tf`):
```hcl
action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    extra_vars = jsonencode({
      target_hosts            = join(",", module.compute.vm_ips)
      ssh_user                = var.ssh_user
      vault_addr              = var.vault_addr
      vault_namespace         = var.vault_namespace
      vault_ssh_role          = local.vault_ssh_role_name
      vault_approle_role_id   = local.vault_approle_role_id
      vault_approle_secret_id = local.vault_approle_secret_id
    })
  }
}
```

Lifecycle trigger (`terraform/main.tf`):
```hcl
resource "terraform_data" "aap_trigger" {
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

### Why terraform_data?

Actions can only be triggered from resource lifecycle blocks, not modules.
`terraform_data` is a lightweight resource that:
- Tracks the VM IPs via `input`. If any IP changes, it triggers `after_update`
- Has `depends_on` to ensure it runs after both VM and network are ready
- Creates no real infrastructure. It exists only to bind the action trigger

### Why Actions Instead of aap_job Resource?

The old approach used `aap_job` as a Terraform resource:

```hcl
# OLD approach - don't use this
resource "aap_job" "configure_vm" {
  job_template_id = var.aap_job_template_id
  extra_vars = jsonencode({ target_host = module.compute.vm_ip })
}
```

This had problems:
| Problem | With Resource | With Action |
|---------|---------------|-------------|
| State management | Job tracked in state file | No state, just fires |
| Destroy behavior | Tries to "destroy" a completed job | Nothing to destroy |
| Re-apply behavior | May re-trigger unexpectedly | Only fires on lifecycle events |
| Manual re-run | Must taint the resource | `terraform apply -invoke action.aap_job_launch.configure_vm` |
| Semantic fit | A job run isn't infrastructure | Actions are meant for side effects |

### Manual Re-run

To re-run Ansible without recreating the VMs:

```bash
terraform apply -invoke action.aap_job_launch.configure_vm
```

This is useful when:
- The playbook changed and you want to re-apply configuration
- The AAP job failed and you want to retry
- You want to reconfigure without touching infrastructure

## How Ansible Knows Where to Connect

Ansible doesn't use a pre-configured inventory. It receives the target IPs at runtime from Terraform.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     install_streamlit.yml                                   │
│                                                                             │
│  Play 1: Runs on localhost                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │  - Parse target_hosts (comma-separated IPs)                         │   │
│  │  - Authenticate to Vault (AppRole)                                  │   │
│  │  - For each target IP:                                              │   │
│  │      - POST /ssh/issue/promptops → get private_key + signed_key     │   │
│  │      - Write keys to /tmp/vault-ssh-<hash>/                         │   │
│  │      - add_host to "target" group with SSH credentials              │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                         │                                   │
│                                         │ hosts added to memory             │
│                                         ▼                                   │
│  Play 2: Runs on all targets                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │  - hosts: target                                                    │   │
│  │                                                                      │   │
│  │  - Install Python, pip                                              │   │
│  │  - Create virtualenv                                                │   │
│  │  - Install Streamlit                                                │   │
│  │  - Create demo app                                                  │   │
│  │  - Create systemd service                                           │   │
│  │  - Start service on port 8501                                       │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                         │                                   │
│                                         ▼                                   │
│  Play 3: Runs on localhost                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │  - Shred and remove all SSH key directories                         │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

This is called "runtime host injection" using `add_host`. No inventory files needed.

## Trust Boundaries

Different components have different levels of access:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  ┌───────────────────────────────────────┐                                 │
│  │         PromptOps (LLM)               │                                 │
│  │                                        │                                 │
│  │  Credentials: OpenAI API key only     │                                 │
│  │  Can do: Write config files           │                                 │
│  │  Cannot do: Access clouds, execute    │                                 │
│  │                                        │                                 │
│  │  WHY: LLMs can be tricked. Keep them  │                                 │
│  │       away from real infrastructure.  │                                 │
│  └───────────────────────────────────────┘                                 │
│                                                                             │
│  ┌───────────────────────────────────────┐                                 │
│  │            Terraform                   │                                 │
│  │                                        │                                 │
│  │  Credentials: GCP + AAP + Vault       │                                 │
│  │  Can do: Create/destroy VMs,          │                                 │
│  │          configure Vault SSH CA,      │                                 │
│  │          trigger AAP actions          │                                 │
│  │  Cannot do: Configure VMs internally  │                                 │
│  │                                        │                                 │
│  │  WHY: Infrastructure provisioning is  │                                 │
│  │       Terraform's job. Config is not. │                                 │
│  └───────────────────────────────────────┘                                 │
│                                                                             │
│  ┌───────────────────────────────────────┐                                 │
│  │     Ansible Automation Platform       │                                 │
│  │                                        │                                 │
│  │  Credentials: Vault AppRole (dynamic) │                                 │
│  │  Can do: Configure VMs, install apps  │                                 │
│  │  Cannot do: Create/destroy VMs        │                                 │
│  │                                        │                                 │
│  │  WHY: Configuration management is     │                                 │
│  │       Ansible's job. Provisioning not.│                                 │
│  └───────────────────────────────────────┘                                 │
│                                                                             │
│  ┌───────────────────────────────────────┐                                 │
│  │              Vault                     │                                 │
│  │                                        │                                 │
│  │  Role: SSH Certificate Authority      │                                 │
│  │  Can do: Issue ephemeral SSH certs    │                                 │
│  │  Cannot do: Access VMs directly       │                                 │
│  │                                        │                                 │
│  │  WHY: Secrets management is Vault's   │                                 │
│  │       job. No static keys anywhere.   │                                 │
│  └───────────────────────────────────────┘                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## The Complete Timeline

Here's what happens when you use PromptOps:

```
Time ──────────────────────────────────────────────────────────────────────────▶

│
│  YOU type: "I need 5 T4 GPUs in us-central1"
│
▼
┌──────────────────┐
│ PromptOps calls  │
│ GPT-4 API        │
│                  │
│ GPT-4 reasons:   │
│ - T4 is good for │
│   inference      │
│ - vm_count=5     │
│ - us-central1-a  │
│   has T4s        │
└────────┬─────────┘
         │
         │ Writes terraform.tfvars
         ▼
┌──────────────────┐
│ YOU click        │
│ "Run Plan"       │
│                  │
│ terraform plan   │
│ shows:           │
│ - Vault SSH CA   │
│ - 5 VMs          │
│ - Firewall rules │
└────────┬─────────┘
         │
         │ You review the plan
         ▼
┌──────────────────┐
│ YOU click        │
│ "Apply"          │
│                  │
│ terraform apply  │
│ - Vault setup    │
│ - Creates 5 VMs  │
└────────┬─────────┘
         │
         │ VMs exist, action_trigger fires
         ▼
┌──────────────────┐
│ Terraform Action │
│ triggers AAP job │
│                  │
│ Passes:          │
│ - 5 VM IPs       │
│ - AppRole creds  │
└────────┬─────────┘
         │
         │ AAP runs playbook
         ▼
┌──────────────────┐
│ Playbook:        │
│ - Vault login    │
│ - Get SSH keys   │
│ - SSH to 5 VMs   │
│ - Install apps   │
│ - Shred keys     │
└────────┬─────────┘
         │
         │ Apps running
         ▼
┌──────────────────┐
│ YOU visit        │
│ http://ip:8501   │
│                  │
│ See demo app on  │
│ each of 5 VMs    │
└──────────────────┘
```

## Summary

1. LLM reasons about your request using GPT-4
2. LLM writes a terraform.tfvars file (nothing else)
3. You review the plan
4. Terraform configures Vault SSH CA automatically
5. Terraform creates the VMs with startup scripts that trust Vault CA
6. Terraform fires an action to trigger AAP
7. AAP gets ephemeral SSH credentials from Vault
8. AAP configures the VMs and installs the app
9. You access the running apps

The LLM never touches infrastructure. Terraform, Vault, and Ansible do the real work.
