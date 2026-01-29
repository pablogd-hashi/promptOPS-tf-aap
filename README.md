# PromptOps

PromptOps is a demo that lets users describe infrastructure needs in natural language, while keeping Terraform as the single source of truth for what is actually allowed. The LLM does not design infrastructure from scratch — it works within constraints defined by your Terraform modules and helps users pick valid configurations.

## The Key Idea

The LLM does not have free "will"" to design whatever infrastructure it wants. Instead, it selects from options that are explicitly allowed by a platform contract defined in Terraform modules. When a user asks for something outside those boundaries, the LLM refuses and explains what alternatives are available.

```
User: "I need a V100 GPU"

LLM: "Not possible. Platform only offers T4 GPUs.
      Want me to use 2 T4s instead for more power?"
```

The platform boundaries come from Terraform modules with strict validations. The LLM knows what is allowed because PromptOps reads the module files from disk and copies the constraint information directly into the prompt — nothing more, nothing less.

## Quick Start

### With OpenAI

```bash
export OPENAI_API_KEY='sk-...'

cd promptops
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/streamlit run web.py
```

### If you prefer to use Ollama ( local)

```bash
export PROMPTOPS_LOCAL=true  

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

The following constraints are enforced by Terraform module validations, not by the LLM. The LLM just reads these constraints and respects them when generating configurations.

| Variable | Allowed Values |
|----------|----------------|
| `machine_type` | n1-standard-4, n1-standard-8 |
| `gpu_type` | nvidia-tesla-t4 |
| `gpu_count` | 1-2 |
| `disk_size_gb` | 50-200 |
| `allow_ssh` | true/false (port 22) |
| `allow_streamlit` | true/false (port 8501) |
| `boot_disk_encrypted` | true/false |

There are no other machine types available, no other GPU options, and no arbitrary ports — just what the modules allow.

## How PromptOps Sends Context To The LLM

The LLM has no background access to your environment. It cannot browse files, call APIs, or discover things on its own. PromptOps explicitly reads specific files from disk and copies sanitized text into the prompt. Here is exactly what happens.

### Files Read

| File | What is extracted |
|------|-------------------|
| `terraform/variables.tf` | Variable names, types, descriptions, defaults |
| `terraform/modules/*/variables.tf` | Validation constraints (allowed values, min/max) |

That is the complete list. No other files are read, no API calls are made, and no cloud resources are accessed.

### What IS Sent to the LLM

The following metadata is extracted from the Terraform files and included in the prompt:

- Variable names (e.g., `machine_type`, `gpu_count`)
- Variable types (e.g., `string`, `number`, `bool`)
- Descriptions from the Terraform files
- Allowed values from `validation` blocks (e.g., `["n1-standard-4", "n1-standard-8"]`)
- Min/max ranges from `validation` blocks (e.g., `50-200`)
- Default values (non-sensitive only)

### What is NOT Sent

- `terraform.tfvars` (your actual values, project IDs, secrets)
- `terraform.tfstate` (infrastructure state)
- Cloud credentials or API keys
- Environment variables
- Any file outside the explicit list above

### Sanitization

Variables marked `sensitive = true` in Terraform have their defaults excluded from what gets sent to the LLM. Only structured metadata is extracted from the files, not raw file contents, and comments are not included.

### Debug Mode

If you want to see exactly what is sent to the LLM, you can enable debug mode:

```bash
export PROMPTOPS_DEBUG_CONTEXT=true
```

This will log the full prompt to the console, show an "LLM Context" expandable panel in the Streamlit UI, and display every file that was read along with byte counts.

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

The LLM never discovers anything on its own. It only knows what PromptOps explicitly pasted into the prompt.

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

Each module has validation blocks that reject invalid values. For example:

```hcl
variable "machine_type" {
  validation {
    condition = contains(["n1-standard-4", "n1-standard-8"], var.machine_type)
    error_message = "Machine type must be n1-standard-4 or n1-standard-8."
  }
}
```

## Why This Matters

Without modules constraining what is possible, an LLM can suggest any configuration it wants. A user might deploy something expensive or insecure without realizing it. With modules defining strict boundaries, the LLM is bounded to what the platform allows, and Terraform will reject any configuration that does not pass validation anyway.

The difference is between letting an AI design arbitrary infrastructure (which is risky) versus having an AI help users configure a well-defined platform (which is controlled).

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

After Terraform creates the VM, it triggers Ansible Automation Platform (AAP) to install a demo Streamlit app. This integration uses Terraform Actions, which is a feature introduced in Terraform 1.14.

### What are Terraform Actions?

Terraform Actions solve a problem that has been around for a while: how do you run non-CRUD operations (like triggering Ansible, invoking a Lambda, or invalidating a cache) as part of your infrastructure workflow? Before Actions existed, people used workarounds like `local-exec` provisioners or fake data sources. These approaches were brittle and did not really fit Terraform's mental model.

Actions work differently. They are declared in your Terraform config rather than hidden in shell scripts, they trigger on resource lifecycle events (`after_create`, `after_update`, `before_destroy`), and they do not manage state — they just run when needed. You can also invoke them manually with `terraform apply -invoke action.aap_job_launch.configure_vm`.

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

The flow works like this: first `module.compute` creates the VM and gets an IP address, then `module.network` creates the firewall rules, then `terraform_data.aap_trigger` completes which triggers the `after_create` event, then `action.aap_job_launch.configure_vm` fires and calls the AAP API with the VM IP, and finally AAP runs the playbook and installs Streamlit on the VM.

### Why Actions Instead of Resources?

The older approach used an `aap_job` resource:

```hcl
# OLD - Don't use this
resource "aap_job" "configure_vm" {
  job_template_id = var.aap_job_template_id
  extra_vars = jsonencode({ target_host = module.compute.vm_ip })
}
```

There are several problems with treating the job as a resource. The job becomes managed state that Terraform tracks, which means `terraform destroy` tries to "destroy" the job (which does not really make sense). Re-running `terraform apply` might re-trigger the job unexpectedly, and in some providers the job runs during the plan phase. Actions fix these issues because they run exactly when you want them to (on lifecycle events) and do not pollute your state file.

### Manual Invocation

You can re-run the Ansible configuration without recreating the VM:

```bash
terraform apply -invoke action.aap_job_launch.configure_vm
```

This is useful when the playbook has changed and you want to re-apply it, when an AAP job failed and you want to retry, or when you want to reconfigure the VM without recreating the infrastructure.

See [docs/setup.md](docs/setup.md) for AAP configuration and [docs/architecture.md](docs/architecture.md) for detailed diagrams.
