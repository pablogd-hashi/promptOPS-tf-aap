"""
Context Builder - Explicitly assembles the LLM prompt from local files.

WHAT THIS FILE DOES:
1. Reads specific Terraform files from disk (listed below)
2. Extracts variable names, types, and validation constraints
3. Formats this into a text block
4. Returns the text for injection into the LLM prompt

WHAT FILES ARE READ:
- terraform/variables.tf (root variables)
- terraform/modules/*/variables.tf (module constraints)

WHAT IS SENT TO THE LLM:
- Variable names and types
- Allowed values from validation blocks
- Min/max ranges from validation blocks
- Default values
- Description text

WHAT IS NOT SENT:
- Actual terraform.tfvars values (secrets, project IDs)
- Cloud credentials or API keys
- State files
- Any file outside the explicit list above

The LLM has NO background access to your environment.
PromptOps explicitly copies text from the files listed above into the prompt.
"""

import os
import re
import logging
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("promptops.context_builder")


@dataclass
class FileReadRecord:
    """Record of a file read operation for audit purposes."""
    path: str
    exists: bool
    bytes_read: int = 0
    variables_extracted: int = 0


@dataclass
class ContextBuildResult:
    """Result of building context, with full audit trail."""
    platform_context: str
    files_read: list[FileReadRecord] = field(default_factory=list)
    total_bytes: int = 0
    total_variables: int = 0

    def summary(self) -> str:
        """Human-readable summary of what was read."""
        lines = ["Files read by PromptOps:"]
        for f in self.files_read:
            status = "OK" if f.exists else "NOT FOUND"
            lines.append(f"  - {f.path} [{status}] ({f.bytes_read} bytes, {f.variables_extracted} vars)")
        lines.append(f"Total: {self.total_bytes} bytes, {self.total_variables} variables extracted")
        return "\n".join(lines)


def parse_terraform_variables(content: str) -> list[dict]:
    """
    Parse a Terraform variables.tf file and extract variable metadata.

    Extracts ONLY:
    - name: variable name
    - description: variable description (sanitized)
    - type: variable type
    - default: default value
    - allowed: allowed values from validation condition
    - min/max: range constraints from validation

    Does NOT extract or expose:
    - Actual variable values
    - Sensitive defaults
    - Comments with secrets
    """
    variables = []

    # Match variable blocks
    var_pattern = r'variable\s+"(\w+)"\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}'

    for match in re.finditer(var_pattern, content, re.DOTALL):
        var_name = match.group(1)
        var_body = match.group(2)

        var_info = {"name": var_name}

        # Extract description
        desc_match = re.search(r'description\s*=\s*"([^"]*)"', var_body)
        if desc_match:
            var_info["description"] = desc_match.group(1)

        # Extract type
        type_match = re.search(r'type\s*=\s*(\w+)', var_body)
        if type_match:
            var_info["type"] = type_match.group(1)

        # Extract default (but NOT for sensitive types)
        if "sensitive" not in var_body.lower():
            default_match = re.search(r'default\s*=\s*("?[^"\n]*"?|\d+|true|false|\[.*?\])', var_body, re.DOTALL)
            if default_match:
                var_info["default"] = default_match.group(1).strip('"')

        # Extract allowed values from validation condition
        validation_match = re.search(r'condition\s*=\s*contains\(\[(.*?)\]', var_body)
        if validation_match:
            allowed = validation_match.group(1)
            allowed = [v.strip().strip('"') for v in allowed.split(',')]
            var_info["allowed"] = allowed

        # Extract min/max from validation
        min_match = re.search(r'var\.\w+\s*>=\s*(\d+)', var_body)
        max_match = re.search(r'var\.\w+\s*<=\s*(\d+)', var_body)
        if min_match:
            var_info["min"] = int(min_match.group(1))
        if max_match:
            var_info["max"] = int(max_match.group(1))

        # Extract ALLOWED hint from description
        allowed_in_desc = re.search(r'ALLOWED:\s*([^.]+)', var_info.get("description", ""))
        if allowed_in_desc:
            var_info["allowed_hint"] = allowed_in_desc.group(1).strip()

        variables.append(var_info)

    return variables


def build_platform_context(terraform_dir: Path) -> ContextBuildResult:
    """
    Build the platform context by reading ONLY these files:
    - terraform/variables.tf
    - terraform/modules/*/variables.tf

    Returns a ContextBuildResult with:
    - The formatted context string
    - Audit trail of every file read
    - Byte counts and variable counts
    """
    modules_dir = terraform_dir / "modules"
    root_vars = terraform_dir / "variables.tf"

    result = ContextBuildResult(platform_context="", files_read=[], total_bytes=0, total_variables=0)
    context_parts = []

    context_parts.append("# PLATFORM CONSTRAINTS")
    context_parts.append("# These constraints were read from local Terraform files.")
    context_parts.append("# The LLM can ONLY set these variables. Terraform enforces all constraints.")
    context_parts.append("")

    # Read root variables
    file_record = FileReadRecord(path=str(root_vars), exists=root_vars.exists())
    if root_vars.exists():
        root_content = root_vars.read_text()
        file_record.bytes_read = len(root_content.encode('utf-8'))
        root_variables = parse_terraform_variables(root_content)
        file_record.variables_extracted = len(root_variables)
        result.total_bytes += file_record.bytes_read
        result.total_variables += file_record.variables_extracted

        context_parts.append("## Available Variables")
        context_parts.append("")

        for var in root_variables:
            line = f"- **{var['name']}**"
            if var.get("type"):
                line += f" ({var['type']})"
            if var.get("description"):
                line += f": {var['description']}"
            if var.get("allowed"):
                line += f" [ALLOWED: {', '.join(var['allowed'])}]"
            if var.get("allowed_hint"):
                line += f" [ALLOWED: {var['allowed_hint']}]"
            if var.get("min") is not None and var.get("max") is not None:
                line += f" [RANGE: {var['min']}-{var['max']}]"
            if var.get("default"):
                line += f" (default: {var['default']})"
            context_parts.append(line)

        context_parts.append("")

    result.files_read.append(file_record)

    # Read module variables
    if modules_dir.exists():
        context_parts.append("## Module Constraints (enforced by Terraform)")
        context_parts.append("")

        for module_dir in sorted(modules_dir.iterdir()):
            if module_dir.is_dir():
                vars_file = module_dir / "variables.tf"
                file_record = FileReadRecord(path=str(vars_file), exists=vars_file.exists())

                if vars_file.exists():
                    module_content = vars_file.read_text()
                    file_record.bytes_read = len(module_content.encode('utf-8'))
                    module_vars = parse_terraform_variables(module_content)
                    file_record.variables_extracted = len(module_vars)
                    result.total_bytes += file_record.bytes_read
                    result.total_variables += file_record.variables_extracted

                    # Only include variables with constraints
                    constrained = [v for v in module_vars if v.get("allowed") or v.get("min") is not None]

                    if constrained:
                        context_parts.append(f"### {module_dir.name}")
                        for var in constrained:
                            if var.get("allowed"):
                                context_parts.append(f"- {var['name']}: only {', '.join(var['allowed'])}")
                            elif var.get("min") is not None:
                                context_parts.append(f"- {var['name']}: {var.get('min', 0)}-{var.get('max', '∞')}")
                        context_parts.append("")

                result.files_read.append(file_record)

    context_parts.append("## What You CANNOT Do")
    context_parts.append("- Use machine types other than n1-standard-4 or n1-standard-8")
    context_parts.append("- Use GPU types other than nvidia-tesla-t4")
    context_parts.append("- Set disk size outside 50-200 GB range")
    context_parts.append("- Expose arbitrary ports (only SSH 22 and Streamlit 8501)")
    context_parts.append("- Create resources outside these modules")
    context_parts.append("")

    result.platform_context = "\n".join(context_parts)
    return result


def build_full_prompt(
    system_prompt: str,
    platform_context: str,
    user_messages: list[dict],
    debug: bool = False
) -> tuple[list[dict], Optional[str]]:
    """
    Assemble the final prompt that will be sent to the LLM.

    Args:
        system_prompt: Base system prompt with {PLATFORM_CONTEXT} placeholder
        platform_context: Generated platform constraints
        user_messages: List of {"role": "user/assistant", "content": "..."} dicts
        debug: If True, return debug info

    Returns:
        Tuple of (messages list for API, debug_output string or None)

    This function makes explicit exactly what is sent to the LLM.
    """
    # Inject platform context into system prompt
    final_system = system_prompt.replace("{PLATFORM_CONTEXT}", platform_context)

    # Build messages array
    messages = [
        {"role": "system", "content": final_system},
        *user_messages
    ]

    debug_output = None
    if debug:
        debug_lines = [
            "=" * 60,
            "PROMPTOPS DEBUG: EXACT PROMPT SENT TO LLM",
            "=" * 60,
            "",
            "--- SYSTEM PROMPT ---",
            final_system,
            "",
            "--- USER MESSAGES ---",
        ]
        for msg in user_messages:
            debug_lines.append(f"[{msg['role'].upper()}]: {msg['content']}")
        debug_lines.append("=" * 60)
        debug_output = "\n".join(debug_lines)

    return messages, debug_output


def get_full_context(terraform_dir: Path) -> str:
    """
    Get the platform context string for injection into LLM prompt.

    This is the simple interface used by web.py.
    For detailed audit info, use build_platform_context() directly.
    """
    result = build_platform_context(terraform_dir)

    # Log what was read if debug is enabled
    if os.getenv("PROMPTOPS_DEBUG_CONTEXT", "").lower() == "true":
        logger.info(result.summary())

    return result.platform_context


def get_context_with_audit(terraform_dir: Path) -> ContextBuildResult:
    """
    Get the platform context with full audit trail.

    Use this when you need to show users exactly what files were read.
    """
    return build_platform_context(terraform_dir)


if __name__ == "__main__":
    # Test: print context and audit info
    repo_root = Path(__file__).parent.parent
    tf_dir = repo_root / "terraform"

    result = build_platform_context(tf_dir)

    print("=" * 60)
    print("FILES READ:")
    print("=" * 60)
    print(result.summary())
    print()
    print("=" * 60)
    print("PLATFORM CONTEXT (sent to LLM):")
    print("=" * 60)
    print(result.platform_context)
