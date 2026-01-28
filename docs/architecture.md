# PromptOps Architecture

This document explains how PromptOps works, from user intent to running infrastructure.

## The Big Picture

PromptOps separates thinking from doing. An LLM thinks about what infrastructure you need. Terraform and Ansible actually create and configure it.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   YOU: "I need a GPU VM for machine learning"                                │
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
│   │   Reads the config file.                   │                            │
│   │   Creates the VM on Google Cloud.          │                            │
│   │   Then tells Ansible to configure it.      │                            │
│   └─────────────────────┬──────────────────────┘                            │
│                         │                                                    │
│                         │ "Here's the VM IP, go configure it"                │
│                         ▼                                                    │
│   ┌────────────────────────────────────────────┐                            │
│   │     Ansible Automation Platform            │                            │
│   │                                            │                            │
│   │   SSHs into the new VM.                    │                            │
│   │   Installs Python, Streamlit, demo app.    │                            │
│   │   Starts the service.                      │                            │
│   └─────────────────────┬──────────────────────┘                            │
│                         │                                                    │
│                         ▼                                                    │
│                                                                              │
│   RESULT: A running GPU VM with a demo app at http://<ip>:8501              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
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
│  │  "I need 2 T4   │      │  Reads system   │      │  project_id=...  │   │
│  │   GPUs in       │      │  prompt that    │      │  gpu_type=t4     │   │
│  │   us-west1"     │      │  explains GPU   │      │  gpu_count=2     │   │
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
tells Ansible to configure it — using **Terraform Actions**, a feature introduced
in Terraform 1.14.

### What Are Terraform Actions?

Actions are a new block type in Terraform for expressing **non-CRUD operations** —
things that need to happen for infrastructure to work but aren't infrastructure
themselves:

- Running a Lambda function
- Configuring a VM with Ansible
- Invalidating a CDN cache
- Triggering a webhook

Before Actions, these were handled with `local-exec` provisioners or fake data
sources — workarounds that didn't fit Terraform's model. Actions are purpose-built
for this.

**Key properties of Actions:**
- Declared in Terraform config (visible, not hidden in scripts)
- Triggered by resource lifecycle events (`after_create`, `after_update`, `before_destroy`)
- Do NOT create state — they just execute when triggered
- Can be invoked manually with `terraform apply -invoke action.<type>.<name>`

### How PromptOps Uses Actions

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           terraform apply                                   │
│                                                                             │
│  Step 1: Create the VM                                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  module.compute (google_compute_instance)                           │   │
│  │                                                                      │   │
│  │  - Creates VM on GCP                                                │   │
│  │  - Attaches GPU                                                     │   │
│  │  - Gets external IP: 34.56.78.90                                    │   │
│  └──────────────────────────────────────┬──────────────────────────────┘   │
│                                         │                                   │
│  Step 2: Create firewall rules          │ depends_on                        │
│  ┌──────────────────────────────────────┴──────────────────────────────┐   │
│  │  module.network (google_compute_firewall)                           │   │
│  │                                                                      │   │
│  │  - Opens SSH (port 22) and Streamlit (port 8501)                    │   │
│  └──────────────────────────────────────┬──────────────────────────────┘   │
│                                         │                                   │
│  Step 3: Trigger AAP via Action         │ depends_on                        │
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
│  │      target_host = "34.56.78.90"                                    │   │
│  │      ssh_user = "ubuntu"                                            │   │
│  │  - Waits for AAP job to complete                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Terraform Config

**Action definition** (`terraform/aap.tf`):
```hcl
action "aap_job_launch" "configure_vm" {
  config {
    job_template_id     = var.aap_job_template_id
    wait_for_completion = true

    extra_vars = jsonencode({
      target_host = module.compute.vm_ip
      ssh_user    = var.ssh_user
    })
  }
}
```

**Lifecycle trigger** (`terraform/main.tf`):
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

### Why terraform_data?

Actions can only be triggered from resource lifecycle blocks, not modules.
`terraform_data` is a lightweight resource that:
- Tracks the VM IP via `input` — if the IP changes, it triggers `after_update`
- Has `depends_on` to ensure it runs after both VM and network are ready
- Creates no real infrastructure — it exists only to bind the action trigger

### Why Actions Instead of aap_job Resource?

The old approach used `aap_job` as a Terraform **resource**:

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
| State management | Job tracked in state file | No state — just fires |
| Destroy behavior | Tries to "destroy" a completed job | Nothing to destroy |
| Re-apply behavior | May re-trigger unexpectedly | Only fires on lifecycle events |
| Manual re-run | Must taint the resource | `terraform apply -invoke action.aap_job_launch.configure_vm` |
| Semantic fit | A job run isn't infrastructure | Actions are meant for side effects |

### Manual Re-run

To re-run Ansible without recreating the VM:

```bash
terraform apply -invoke action.aap_job_launch.configure_vm
```

This is useful when:
- The playbook changed and you want to re-apply configuration
- The AAP job failed and you want to retry
- You want to reconfigure without touching infrastructure

## How Ansible Knows Where to Connect

Ansible doesn't use a pre-configured inventory. It receives the target IP at runtime from Terraform.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     install_streamlit.yml                                   │
│                                                                             │
│  Play 1: Runs on localhost                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                      │   │
│  │  - name: Add target host to inventory                               │   │
│  │    add_host:                                                        │   │
│  │      name: "{{ target_host }}"      ◄── comes from Terraform        │   │
│  │      groups: target                                                 │   │
│  │      ansible_host: "{{ target_host }}"                              │   │
│  │      ansible_user: "{{ ssh_user }}"                                 │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                         │                                   │
│                                         │ host added to memory              │
│                                         ▼                                   │
│  Play 2: Runs on the target                                                 │
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
│  │  Credentials: GCP + AAP               │                                 │
│  │  Can do: Create/destroy VMs,          │                                 │
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
│  │  Credentials: SSH keys                │                                 │
│  │  Can do: Configure VMs, install apps  │                                 │
│  │  Cannot do: Create/destroy VMs        │                                 │
│  │                                        │                                 │
│  │  WHY: Configuration management is     │                                 │
│  │       Ansible's job. Provisioning not.│                                 │
│  └───────────────────────────────────────┘                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## The Complete Timeline

Here's what happens when you use PromptOps:

```
Time ──────────────────────────────────────────────────────────────────────────▶

│
│  YOU type: "I need a T4 GPU in us-central1"
│
▼
┌──────────────────┐
│ PromptOps calls  │
│ GPT-4 API        │
│                  │
│ GPT-4 reasons:   │
│ - T4 is good for │
│   inference      │
│ - us-central1-a  │
│   has T4s        │
│ - n1-standard-4  │
│   pairs well     │
└────────┬─────────┘
         │
         │ Writes terraform.tfvars
         ▼
┌──────────────────┐
│ YOU click        │
│ "Run Plan"       │
│                  │
│ terraform plan   │
│ shows what will  │
│ be created       │
└────────┬─────────┘
         │
         │ You review the plan
         ▼
┌──────────────────┐
│ YOU click        │
│ "Apply"          │
│                  │
│ terraform apply  │
│ creates VM       │
│ (takes ~60 sec)  │
└────────┬─────────┘
         │
         │ VM exists, action_trigger fires
         ▼
┌──────────────────┐
│ Terraform Action │
│ triggers AAP job │
│                  │
│ AAP runs         │
│ playbook,        │
│ installs app     │
└────────┬─────────┘
         │
         │ App is running
         ▼
┌──────────────────┐
│ YOU visit        │
│ http://ip:8501   │
│                  │
│ See demo app     │
│ "Hello from AAP" │
└──────────────────┘
```

## Summary

1. **LLM reasons** about your request using GPT-4
2. **LLM writes** a terraform.tfvars file (nothing else)
3. **You review** the plan
4. **Terraform creates** the VM and fires an action to trigger AAP
5. **AAP configures** the VM and installs the app
6. **You access** the running app

The LLM never touches infrastructure. Terraform and Ansible do the real work.
