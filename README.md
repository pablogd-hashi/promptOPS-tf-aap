# PromptOps

Tell an AI what infrastructure you need. It reasons within platform constraints. Terraform enforces everything.

## The Key Idea

The LLM doesn't design infrastructure. It selects options from a platform contract.

```
User: "I need a V100 GPU"

LLM: "Not possible. Platform only offers T4 GPUs.
      Want me to use 2 T4s instead for more power?"
```

The platform is defined by Terraform modules with strict validations. The LLM knows what's allowed because PromptOps reads the module files and pastes the constraints into the prompt.

## Quick Start

```bash
export OPENAI_API_KEY='sk-...'

cd promptops
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/streamlit run web.py
```

## What You Can Ask

**Valid requests (LLM configures):**
- "I need a GPU VM" → creates VM with T4
- "Make it cheaper" → uses smaller machine type
- "Enable Streamlit access" → opens port 8501
- "Enable disk encryption" → turns on CMEK
- "Use 2 GPUs" → sets gpu_count = 2

**Invalid requests (LLM refuses):**
- "Use a V100" → "Not available. Only T4 allowed."
- "Open port 9000" → "Not supported. Only SSH and Streamlit ports."
- "Use n1-standard-32" → "Not allowed. Only n1-standard-4 or n1-standard-8."
- "500GB disk" → "Out of range. Platform allows 50-200 GB."

## Platform Constraints

These are enforced by Terraform modules, not by the LLM:

| Variable | Allowed Values |
|----------|----------------|
| `machine_type` | n1-standard-4, n1-standard-8 |
| `gpu_type` | nvidia-tesla-t4 |
| `gpu_count` | 1-2 |
| `disk_size_gb` | 50-200 |
| `allow_ssh` | true/false (port 22) |
| `allow_streamlit` | true/false (port 8501) |
| `boot_disk_encrypted` | true/false |

No other machine types. No other GPUs. No arbitrary ports.

## How PromptOps Sends Context To The LLM

**The LLM has NO background access to your environment.**

PromptOps explicitly reads specific files from disk and copies sanitized text into the prompt. Here is exactly what happens:

### Files Read

| File | What is extracted |
|------|-------------------|
| `terraform/variables.tf` | Variable names, types, descriptions, defaults |
| `terraform/modules/*/variables.tf` | Validation constraints (allowed values, min/max) |

**That's it.** No other files are read. No API calls. No cloud access.

### What IS Sent to the LLM

- Variable names (e.g., `machine_type`, `gpu_count`)
- Variable types (e.g., `string`, `number`, `bool`)
- Descriptions from the Terraform files
- Allowed values from `validation` blocks (e.g., `["n1-standard-4", "n1-standard-8"]`)
- Min/max ranges from `validation` blocks (e.g., `50-200`)
- Default values (non-sensitive only)

### What is NOT Sent

- ❌ `terraform.tfvars` (your actual values, project IDs, secrets)
- ❌ `terraform.tfstate` (infrastructure state)
- ❌ Cloud credentials or API keys
- ❌ Environment variables
- ❌ Any file outside the explicit list above

### Sanitization

- Variables marked `sensitive = true` in Terraform have their defaults excluded
- Only structured metadata is extracted, not raw file contents
- Comments are not included

### Debug Mode

To see exactly what is sent to the LLM, set:

```bash
export PROMPTOPS_DEBUG_CONTEXT=true
```

This will:
1. Log the full prompt to the console
2. Show an "LLM Context" expandable panel in the Streamlit UI
3. Display every file read with byte counts

### The Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  1. PromptOps reads terraform/variables.tf                          │
│     PromptOps reads terraform/modules/*/variables.tf                │
│                                                                     │
│  2. Extracts ONLY:                                                  │
│     - Variable names, types, descriptions                           │
│     - Validation constraints (allowed values, ranges)               │
│     - Non-sensitive defaults                                        │
│                                                                     │
│  3. Formats as text block, injects into system prompt               │
│                                                                     │
│  4. User asks: "Use a V100"                                         │
│                                                                     │
│  5. LLM sees constraints in prompt, responds:                       │
│     "Not available. Platform only offers T4."                       │
│                                                                     │
│  6. If valid, LLM outputs JSON with variable values                 │
│                                                                     │
│  7. PromptOps writes terraform.tfvars                               │
│                                                                     │
│  8. Terraform applies and enforces (double-check)                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**The LLM never discovers anything.** It only knows what PromptOps explicitly pasted into the prompt.

## Module Structure

```
terraform/
├── main.tf              # Wires modules together
├── variables.tf         # Root variables (what LLM can set)
├── modules/
│   ├── compute_vm/      # VM with GPU, machine type constraints
│   ├── network_policy/  # Firewall rules, only SSH + Streamlit
│   └── encryption_policy/  # CMEK encryption
```

Each module has validation blocks that reject invalid values:

```hcl
variable "machine_type" {
  validation {
    condition = contains(["n1-standard-4", "n1-standard-8"], var.machine_type)
    error_message = "Machine type must be n1-standard-4 or n1-standard-8."
  }
}
```

## Why This Matters

**Without modules:** LLM can suggest anything. User might deploy it. Expensive mistake.

**With modules:** LLM is bounded. Terraform rejects invalid configs. Platform policy enforced.

This is the difference between:
- "AI that helps you design infrastructure" (dangerous)
- "AI that helps you configure a platform" (controlled)

## Files

```
promptops/
├── terraform/
│   ├── modules/           # Platform capabilities
│   ├── main.tf            # Module composition
│   └── variables.tf       # What LLM can configure
├── promptops/
│   ├── web.py             # Web UI
│   ├── context_builder.py # Reads modules, builds LLM context
│   └── prompts/           # System prompt with {PLATFORM_CONTEXT}
├── ansible/
│   └── playbooks/         # Day-2 configuration
└── docs/
    └── architecture.md    # Detailed diagrams
```

## AAP Integration with Terraform Actions

After Terraform creates the VM, it triggers AAP to install a demo Streamlit app using **Terraform Actions** — a feature introduced in Terraform 1.14.

### What are Terraform Actions?

Terraform Actions solve a long-standing problem: how do you run non-CRUD operations (like triggering Ansible, invoking a Lambda, or invalidating a cache) as part of your infrastructure workflow?

Before Actions, people used workarounds like `local-exec` provisioners or fake data sources. These were brittle and didn't fit Terraform's mental model.

**Actions are different:**
- They're declared in your Terraform config (not hidden in shell scripts)
- They trigger on resource lifecycle events (`after_create`, `after_update`, `before_destroy`)
- They don't manage state — they just run when needed
- They can be invoked manually: `terraform apply -invoke action.aap_job_launch.configure_vm`

### How PromptOps Uses Actions

```hcl
# terraform/aap.tf
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

# terraform/main.tf
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

**The flow:**
1. `module.compute` creates the VM → gets an IP
2. `module.network` creates firewall rules
3. `terraform_data.aap_trigger` completes → triggers `after_create` event
4. `action.aap_job_launch.configure_vm` fires → calls AAP API with the VM IP
5. AAP runs the playbook → installs Streamlit on the VM

### Why Actions Instead of Resources?

The old approach used an `aap_job` **resource**:

```hcl
# OLD - Don't use this
resource "aap_job" "configure_vm" {
  job_template_id = var.aap_job_template_id
  extra_vars = jsonencode({ target_host = module.compute.vm_ip })
}
```

Problems with resources:
- The job is treated as managed state — Terraform tracks it
- `terraform destroy` tries to "destroy" the job (what does that even mean?)
- Re-running `terraform apply` might re-trigger the job unexpectedly
- The job runs during the plan phase in some providers

**Actions fix this:** They run exactly when you want (on lifecycle events) and don't pollute your state file.

### Manual Invocation

You can re-run the Ansible configuration without recreating the VM:

```bash
terraform apply -invoke action.aap_job_launch.configure_vm
```

This is useful when:
- The playbook changed and you want to re-apply
- AAP job failed and you want to retry
- You want to reconfigure without recreating infrastructure

See [docs/setup.md](docs/setup.md) for AAP configuration and [docs/architecture.md](docs/architecture.md) for detailed diagrams.

## License

MIT
