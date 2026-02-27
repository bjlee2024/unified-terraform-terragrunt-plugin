---
name: unified-terraform-terragrunt:setup
description: Check and install required CLI tools (Terraform, Terragrunt) for the unified-terraform-terragrunt plugin
---

# Setup Skill

This skill runs the plugin's `setup.sh` script to detect and install required CLI tools.

## What It Does

- Detects the platform (macOS / Linux) and architecture (amd64 / arm64)
- Checks if **Terraform** (>= 0.13.0, recommended >= 1.6.0) and **Terragrunt** (>= 0.38.0) are installed
- Installs missing or outdated tools (via Homebrew on macOS, binary download on Linux)

## Modes

| Flag | Behavior |
|------|----------|
| *(none)* | Interactive — prompts before installing |
| `--check` | Check status only, no installs |
| `--auto` | Non-interactive, auto-install (for CI/CD) |

## Instructions

1. Determine the plugin root directory (where `setup.sh` lives). Use the directory of this skill file: resolve `../../setup.sh` relative to this SKILL.md.
2. **Default to `--check` mode first** so the user can see the current status before any changes.
3. Show the user the check results and ask if they want to proceed with installation if any tools are missing or outdated.
4. If the user confirms, run `setup.sh` without flags (interactive mode) or with `--auto` if the user requests non-interactive installation.
5. After completion, report the final status to the user.

## Execution

```bash
# Step 1: Always check first
bash "${PLUGIN_ROOT}/setup.sh" --check

# Step 2: Install if needed (after user confirmation)
bash "${PLUGIN_ROOT}/setup.sh"

# Or non-interactive:
bash "${PLUGIN_ROOT}/setup.sh" --auto
```

Where `${PLUGIN_ROOT}` is the directory containing `setup.sh` (the repository root of this plugin).
