# PromptOps Service

Non-privileged infrastructure reasoning layer using GPT-4.

## What This Service Does

Translates natural language infrastructure intent into Terraform variable files.

**It cannot execute infrastructure changes by design.**

## Credentials

This service has exactly one credential: `OPENAI_API_KEY`

It should never have:
- GCP credentials
- AAP credentials
- SSH keys
- Any cloud access

## Usage

```bash
# Set API key
export OPENAI_API_KEY="sk-..."

# Install dependencies
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Run web UI
.venv/bin/streamlit run web.py
```

## Files

- `web.py` - Streamlit web interface
- `app.py` - CLI interface
- `prompts/system.txt` - LLM system prompt
- `prompts/planning.txt` - Planning guidelines

## Output

Writes `terraform/terraform.tfvars` when user expresses infrastructure intent.

That's it. No execution.
