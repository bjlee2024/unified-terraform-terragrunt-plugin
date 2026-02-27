# Unified Terraform & Terragrunt Skill

A comprehensive Claude Code skill for Terraform, OpenTofu, and Terragrunt infrastructure-as-code development.

## What This Skill Provides

This skill equips Claude with expert knowledge of:

- **Terraform/OpenTofu**: Complete CLI commands, HCL syntax, provider configurations, state management, and best practices
- **Terragrunt**: DRY patterns, dependency management, remote state configuration, and multi-environment workflows
- **HCP Terraform Stacks**: Deployment configuration, orchestration rules, and component management
- **Real-world patterns**: Module development, CI/CD integration, testing strategies, and production workflows

## Features

### Terraform/OpenTofu Coverage

- ✅ Core workflow (init → plan → apply → destroy)
- ✅ Provider configuration (AWS, Azure, GCP, Kubernetes, etc.)
- ✅ State management (local, S3, Terraform Cloud)
- ✅ Module development and usage
- ✅ Variable and output management
- ✅ Workspace management
- ✅ Import and migration workflows
- ✅ Testing and validation

### Terragrunt Coverage

- ✅ DRY configuration patterns
- ✅ Dependency management (`dependency` blocks)
- ✅ Remote state configuration
- ✅ Multi-environment setup
- ✅ `generate` blocks for dynamic configs
- ✅ `before_hook` and `after_hook` automation
- ✅ Stack management (`run-all` commands)
- ✅ Terraform version management

### HCP Stacks Coverage

- ✅ Deployment configuration files
- ✅ Component definitions
- ✅ Orchestration rules
- ✅ Input/output variable management
- ✅ Provider configuration
- ✅ Stack operations (plan, apply, destroy)

## Installation

### Via Marketplace (Recommended)

```bash
# 1. Add the marketplace
/plugin marketplace add bjlee2024/unified-terraform-terragrunt-plugin

# 2. Install the plugin
/plugin install unified-terraform-terragrunt@unified-terraform-terragrunt-marketplace
```

### Via Direct Install

```bash
# Install directly from GitHub
/plugin install bjlee2024/unified-terraform-terragrunt-plugin
```

### Via Local Clone

```bash
# Clone and install locally
git clone git@github.com:bjlee2024/unified-terraform-terragrunt-plugin.git
/plugin install ./unified-terraform-terragrunt-plugin
```

> **Note**: Requires Claude Code v1.0.33+ with plugin support.

## Setup (CLI Tools)

After installing the plugin, run the setup script to ensure required CLI tools are available:

```bash
# Interactive mode (prompts before install)
./setup.sh

# Check tool status only (no installs)
./setup.sh --check

# Non-interactive mode (auto-install, for CI/CD)
./setup.sh --auto
```

### Managed Tools

| Tool | Minimum | Recommended | Platform |
|------|---------|-------------|----------|
| **Terraform** | >= 0.13.0 | >= 1.6.0 | macOS (Homebrew), Linux (binary) |
| **Terragrunt** | >= 0.38.0 | latest | macOS (Homebrew), Linux (binary) |

The setup script:
- Detects your platform (macOS/Linux) and architecture (amd64/arm64)
- Checks installed versions against minimum requirements
- Installs missing or outdated tools (Homebrew on macOS, binary download on Linux)
- Falls back to `~/.local/bin` if `/usr/local/bin` is not writable

## Quick Start

Once installed, the skill is available as `/unified-terraform-terragrunt:terraform` and activates automatically when working with Terraform/Terragrunt files.

### Example Usage

**Terraform workflow:**
```
You: "Help me initialize and plan this Terraform configuration"
Claude: [Uses skill to guide proper init → plan workflow with appropriate flags]
```

**Terragrunt DRY configuration:**
```
You: "Refactor this duplicated backend config using Terragrunt"
Claude: [Uses skill to create proper terragrunt.hcl with remote_state blocks]
```

**Module development:**
```
You: "Create a reusable AWS VPC module"
Claude: [Uses skill to scaffold module with proper variables, outputs, and documentation]
```

**State management:**
```
You: "Migrate my state from local to S3 backend"
Claude: [Uses skill to guide safe state migration with backup procedures]
```

## Tool Coverage

### Terraform/OpenTofu Commands

| Command | Coverage |
|---------|----------|
| `init` | Complete flag reference, backend migration, provider installation |
| `plan` | Output options, targeting, variable handling, refresh control |
| `apply` | Auto-approval, parallelism, targeting, state locking |
| `destroy` | Safe destruction patterns, targeting, confirmation bypass |
| `import` | Resource importing, ID formats, state verification |
| `state` | State manipulation, inspection, surgery operations |
| `workspace` | Multi-environment management, workspace isolation |
| `validate` | Syntax checking, configuration validation |
| `fmt` | Code formatting, diff options, recursive formatting |
| `output` | Output value extraction, JSON formatting |
| `graph` | Dependency visualization, DOT format generation |
| `taint` / `untaint` | Resource recreation, deprecation notes |
| `refresh` | State synchronization (deprecated patterns noted) |

### Terragrunt Commands

| Command | Coverage |
|---------|----------|
| `run-all plan` | Stack-wide planning, dependency ordering |
| `run-all apply` | Parallel execution, dependency resolution |
| `run-all destroy` | Safe stack destruction |
| `hclfmt` | HCL formatting for terragrunt.hcl files |
| `validate-inputs` | Input validation before execution |
| `output-all` | Multi-module output collection |
| `graph-dependencies` | Dependency visualization |

### HCP Stacks Operations

| Operation | Coverage |
|-----------|----------|
| Deployment config | Complete file structure and syntax |
| Component setup | Definition and configuration |
| Stack plan | Planning operations |
| Stack apply | Application workflows |
| Provider setup | Authentication and configuration |

## Reference Files

The skill includes deep-dive reference files for advanced topics:

### Terraform References
- `references/terraform/state-management.md` - Advanced state operations
- `references/terraform/providers.md` - Provider configuration patterns
- `references/terraform/modules.md` - Module development best practices
- `references/terraform/testing.md` - Testing strategies
- `references/terraform/ci-cd.md` - Pipeline integration

### Terragrunt References
- `references/terragrunt/dry-patterns.md` - DRY configuration techniques
- `references/terragrunt/dependencies.md` - Dependency management
- `references/terragrunt/hooks.md` - Hook automation patterns
- `references/terragrunt/multi-env.md` - Multi-environment strategies

### HCP Stacks References
- `references/hcp-stacks/deployment-config.md` - Deployment file structure
- `references/hcp-stacks/components.md` - Component patterns
- `references/hcp-stacks/orchestration.md` - Orchestration rules

### Shared References
- `references/shared/best-practices.md` - Universal IaC best practices
- `references/shared/security.md` - Security considerations
- `references/shared/troubleshooting.md` - Common issues and solutions

Claude loads these automatically when needed for complex tasks.

## Examples

The skill includes complete, runnable examples:

### Terraform Examples
- **Basic infrastructure**: Simple AWS resources
- **Module usage**: Consuming community modules
- **Module development**: Creating reusable modules
- **Multi-region**: Cross-region deployments
- **State backends**: S3, Terraform Cloud configurations

### Terragrunt Examples
- **Basic setup**: Single environment configuration
- **Multi-environment**: Dev/staging/prod patterns
- **Dependencies**: Inter-module dependencies
- **Remote state**: DRY state configuration
- **Hooks**: Automation with before/after hooks

### Pattern Examples
- **Monorepo layout**: Organizing large infrastructures
- **GitOps workflows**: PR-based infrastructure changes
- **Testing patterns**: Unit, integration, and E2E tests
- **Disaster recovery**: Backup and restore procedures

## Architecture

```
unified-terraform-terragrunt-plugin/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest (direct install)
│   └── marketplace.json         # Marketplace catalog (marketplace install)
├── skills/
│   └── terraform/
│       └── SKILL.md             # Core skill (~5K tokens, always loaded)
├── references/                  # Deep references (~30K tokens, on-demand)
├── examples/                    # Real-world examples (on-demand)
├── constitution.md              # AWS CLI safety rules (embedded in SKILL.md)
├── setup.sh                     # CLI tool installer
├── CLAUDE.md                    # Contributor guide
└── README.md                    # This file
```

The skill uses **progressive disclosure**:

1. **Core knowledge** (skills/terraform/SKILL.md): Always loaded, covers 80% of tasks
2. **Reference files** (references/): Loaded on-demand for complex scenarios
3. **Examples** (examples/): Complete implementations for learning

This ensures optimal token usage while maintaining comprehensive coverage.

## Token Budgets

- **Core skill**: ~5,000 tokens (always loaded)
- **Reference files**: ~30,000 tokens total (loaded selectively)
- **Examples**: Unlimited (loaded on demand)

Claude automatically manages loading to optimize context usage.

## Use Cases

### Development Workflows
- Infrastructure scaffolding
- Module development
- Configuration refactoring
- Code review and validation

### Operations
- State management and migration
- Resource importing
- Disaster recovery
- Drift detection and remediation

### Best Practices
- Security hardening
- Cost optimization
- Performance tuning
- Documentation generation

### CI/CD Integration
- Pipeline configuration
- Automated testing
- Approval workflows
- Deployment automation

## Requirements

- **Claude Code**: v1.0.33+ (plugin support required)
- **Terraform** or **OpenTofu**: v0.13+ minimum, v1.6+ recommended
- **Terragrunt**: v0.38+ (if using Terragrunt features)

Run `./setup.sh --check` to verify your environment.

## Contributing

See [CLAUDE.md](CLAUDE.md) for contributor documentation including:
- Repository architecture
- Content philosophy
- Development workflow
- Quality standards
- Contributing process

## License

Apache License 2.0

See [LICENSE](LICENSE) file for full license text.

## Attribution

This skill unifies and extends content from multiple source skills:

- **terraform-claude-code-skill** by lharries
- **claude-terragrunt-skill** by terryx
- **claude-hcp-terraform-skill** by terryx

Special thanks to the original authors for their foundational work.

## Support

### Documentation

- **User docs**: This README
- **Contributor docs**: [CLAUDE.md](CLAUDE.md)
- **Reference files**: See `references/` directory
- **Examples**: See `examples/` directory

### Official Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [OpenTofu Documentation](https://opentofu.org/docs)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs)
- [HCP Terraform Stacks](https://developer.hashicorp.com/terraform/cloud-docs/stacks)

### Community

- [Terraform GitHub](https://github.com/hashicorp/terraform)
- [OpenTofu GitHub](https://github.com/opentofu/opentofu)
- [Terragrunt GitHub](https://github.com/gruntwork-io/terragrunt)

---

**Version**: 1.0.0
**Last Updated**: 2026-02-27
