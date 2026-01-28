#!/usr/bin/env python3
"""
PromptOps Service - Infrastructure Reasoning Layer

This service uses GPT-4.x to reason about infrastructure intent and generate
Terraform variable files. It is deliberately designed with zero execution privilege.

CRITICAL DESIGN CONSTRAINTS:
- This service cannot execute Terraform or Ansible by design
- This service has no cloud credentials
- This service cannot shell out to infrastructure tools
- This service can only write files to plans/ and terraform variable files

If this service gains execution capability, the architecture has failed.
"""

import os
import sys
import json
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any

try:
    from openai import OpenAI
except ImportError:
    print("Error: openai package not installed")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)


class PromptOpsService:
    """
    Non-privileged infrastructure reasoning service.

    This service translates natural language intent into Terraform configurations.
    It has no ability to execute infrastructure changes.
    """

    def __init__(self):
        """Initialize the PromptOps service."""
        # LLM Provider configuration
        # Set PROMPTOPS_LOCAL=true to use Ollama instead of OpenAI
        self.use_local = os.getenv("PROMPTOPS_LOCAL", "").lower() == "true"

        if self.use_local:
            local_url = os.getenv("PROMPTOPS_LOCAL_URL", "http://localhost:11434/v1")
            self.model = os.getenv("PROMPTOPS_LOCAL_MODEL", "llama3.1")
            self.client = OpenAI(base_url=local_url, api_key="ollama")
            print(f"Using local model: {self.model} via {local_url}")
        else:
            self.api_key = os.getenv("OPENAI_API_KEY")
            if not self.api_key:
                raise ValueError(
                    "OPENAI_API_KEY environment variable not set.\n"
                    "Set OPENAI_API_KEY for OpenAI, or PROMPTOPS_LOCAL=true for Ollama.\n"
                    "This service should NEVER have GCP, AWS, or Ansible credentials."
                )
            self.client = OpenAI(api_key=self.api_key)
            self.model = os.getenv("PROMPTOPS_MODEL", "gpt-4o")

        # Load system prompt
        self.system_prompt = self._load_prompt("system.txt")
        self.planning_prompt = self._load_prompt("planning.txt")

        # Conversation history
        self.messages = [
            {"role": "system", "content": self.system_prompt}
        ]

        # Paths (write-only, no execution)
        self.repo_root = Path(__file__).parent.parent
        self.intent_dir = self.repo_root / "plans" / "intent"
        self.tfvars_path = self.repo_root / "terraform" / "environments" / "staging" / "terraform.tfvars"

        # Ensure output directories exist
        self.intent_dir.mkdir(parents=True, exist_ok=True)

    def _load_prompt(self, filename: str) -> str:
        """Load a prompt template from the prompts directory."""
        prompt_path = Path(__file__).parent / "prompts" / filename
        try:
            return prompt_path.read_text().strip()
        except FileNotFoundError:
            raise ValueError(f"Prompt file not found: {prompt_path}")

    def _call_gpt4(self, user_message: str) -> str:
        """
        Call GPT-4.x for reasoning.

        This is the only external API this service calls.
        No cloud provider APIs. No infrastructure APIs.
        """
        self.messages.append({"role": "user", "content": user_message})

        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=self.messages,
                temperature=0.7,
                max_tokens=2000
            )

            assistant_message = response.choices[0].message.content
            self.messages.append({"role": "assistant", "content": assistant_message})

            return assistant_message

        except Exception as e:
            return f"Error calling GPT-4: {str(e)}"

    def _extract_terraform_vars(self, response: str) -> Optional[Dict[str, Any]]:
        """
        Extract Terraform variable values from GPT-4 response.

        Looks for JSON blocks in the response that contain Terraform variables.
        """
        # Simple extraction: look for JSON blocks
        import re
        json_pattern = r'```json\s*(\{.*?\})\s*```'
        matches = re.findall(json_pattern, response, re.DOTALL)

        if not matches:
            return None

        try:
            return json.loads(matches[0])
        except json.JSONDecodeError:
            return None

    def _write_intent_document(self, user_intent: str, response: str):
        """Write an intent document capturing the user's request and the service's reasoning."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        intent_file = self.intent_dir / f"intent_{timestamp}.md"

        content = f"""# Infrastructure Intent Document

**Date**: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

## User Intent

{user_intent}

## PromptOps Analysis

{response}

## Status

- Generated: {timestamp}
- Terraform vars: {"Written" if self.tfvars_path.exists() else "Not yet generated"}
- Speculative plan: Run `terraform/speculative/run_plan.sh` to validate

---

This document was generated by the PromptOps reasoning service.
The service has no execution privileges and cannot apply infrastructure changes.
"""

        intent_file.write_text(content)
        print(f"\n[Intent document written to: {intent_file.relative_to(self.repo_root)}]")

    def _write_terraform_vars(self, vars_dict: Dict[str, Any]):
        """
        Write Terraform variable values to terraform.tfvars.

        This is the ONLY infrastructure-affecting action this service takes.
        It writes files. It does not execute changes.
        """
        # Ensure parent directory exists
        self.tfvars_path.parent.mkdir(parents=True, exist_ok=True)

        # Generate tfvars content
        content = f"""# Terraform Variables for GPU Infrastructure
# Generated by PromptOps service on {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
#
# This file was generated by an LLM reasoning service.
# The service cannot execute Terraform.
# Review this file and run 'terraform plan' manually.

"""

        for key, value in vars_dict.items():
            if isinstance(value, str):
                content += f'{key} = "{value}"\n'
            elif isinstance(value, (int, float)):
                content += f'{key} = {value}\n'
            elif isinstance(value, bool):
                content += f'{key} = {str(value).lower()}\n'
            elif isinstance(value, list):
                content += f'{key} = {json.dumps(value)}\n'
            else:
                content += f'{key} = {json.dumps(value)}\n'

        self.tfvars_path.write_text(content)
        print(f"\n[Terraform vars written to: {self.tfvars_path.relative_to(self.repo_root)}]")
        print("[Run speculative plan to validate: terraform/speculative/run_plan.sh]")

    def process_intent(self, user_intent: str) -> str:
        """
        Process infrastructure intent through GPT-4.

        This is the core reasoning loop:
        1. Accept natural language intent
        2. Reason about infrastructure requirements
        3. Generate Terraform variable values
        4. Write outputs to disk

        No execution occurs. Only reasoning and file writing.
        """
        # Enhance the prompt with planning instructions
        full_prompt = f"{self.planning_prompt}\n\nUser request: {user_intent}"

        # Get response from GPT-4
        response = self._call_gpt4(full_prompt)

        # Write intent document
        self._write_intent_document(user_intent, response)

        # Extract and write Terraform vars if present
        tf_vars = self._extract_terraform_vars(response)
        if tf_vars:
            self._write_terraform_vars(tf_vars)

        return response

    def interactive_session(self):
        """
        Run an interactive PromptOps session.

        This is suitable for live demos where the presenter interacts with the service.
        """
        print("=" * 70)
        print("PromptOps Service - Infrastructure Reasoning Layer")
        print("=" * 70)
        print()
        print("This service reasons about infrastructure intent using GPT-4.")
        print("It has NO execution privileges and NO cloud credentials.")
        print("It can only write plans and Terraform variable files.")
        print()
        print("Type 'quit' or 'exit' to end the session.")
        print("=" * 70)
        print()

        while True:
            try:
                user_input = input("\n> ").strip()

                if user_input.lower() in ['quit', 'exit', 'q']:
                    print("\nEnding PromptOps session.")
                    break

                if not user_input:
                    continue

                print("\n[Reasoning...]")
                response = self.process_intent(user_input)
                print(f"\n{response}")

            except KeyboardInterrupt:
                print("\n\nSession interrupted. Exiting.")
                break
            except Exception as e:
                print(f"\nError: {e}")


def main():
    """Entry point for the PromptOps service."""
    try:
        service = PromptOpsService()
        service.interactive_session()
    except ValueError as e:
        print(f"Configuration error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
