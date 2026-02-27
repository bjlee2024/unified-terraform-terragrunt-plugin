# Contributor Guide: Unified Terraform & Terragrunt Skill

This document is for contributors who want to understand, maintain, or extend this skill.

## Table of Contents

1. [Repository Architecture](#repository-architecture)
2. [Content Philosophy](#content-philosophy)
3. [File Roles](#file-roles)
4. [Token Budget Documentation](#token-budget-documentation)
5. [Development Workflow](#development-workflow)
6. [Quality Standards](#quality-standards)
7. [Contributing Process](#contributing-process)

---

## Repository Architecture

The skill follows a **progressive disclosure** architecture:

```
unified-terraform-terragrunt/
├── SKILL.md                    # Core skill (5K tokens) - ALWAYS loaded
├── references/                 # Deep references (~30K tokens) - Load on demand
│   ├── terraform/              # Terraform-specific references
│   ├── terragrunt/             # Terragrunt-specific references
│   └── hcp-stacks/             # HCP Stacks references
├── examples/                   # Real-world examples - Load on demand
│   ├── terraform/
│   ├── terragrunt/
│   └── patterns/
├── CLAUDE.md                   # This file (contributor guide)
├── README.md                   # User documentation
└── .claude-plugin/
    └── marketplace.json        # Plugin metadata
```

### Progressive Disclosure Principle

1. **Core Layer (SKILL.md)**: Essential patterns, common workflows, quick reference
2. **Reference Layer (references/)**: Deep dives, edge cases, advanced features
3. **Example Layer (examples/)**: Complete implementations, real-world scenarios

This structure ensures Claude loads only what's needed, respecting token budgets while maintaining access to comprehensive documentation.

---

## Content Philosophy

### What to Include in SKILL.md (Core)

✅ **Include:**
- Common workflow patterns (init → plan → apply)
- Most-used CLI commands with essential flags
- Standard configurations (providers, backends, modules)
- Quick troubleshooting for frequent issues
- Cross-references to reference files
- Critical best practices

❌ **Exclude:**
- Exhaustive flag listings (put in references/)
- Rare edge cases (put in references/)
- Multiple alternative approaches (pick best, reference others)
- Historical context or rationale (put in references/)
- Verbose explanations (be concise, link to references/)

### What to Include in references/ (Deep Dive)

✅ **Include:**
- Complete flag documentation
- Advanced use cases
- Edge case handling
- Performance tuning
- Security considerations
- Historical context and design decisions
- Comparison of alternative approaches

### What to Include in examples/ (Practical)

✅ **Include:**
- Complete, runnable examples
- Multi-file project structures
- Real-world patterns (multi-environment, modules, etc.)
- Common integration scenarios
- Annotated configurations

---

## File Roles

### SKILL.md (Core Skill File)

**Purpose**: Provide Claude with essential knowledge to handle 80% of tasks without additional loading.

**Structure**:
```markdown
# Overview (what this skill provides)
# Quick Reference (command cheat sheet)
# Common Workflows (init → plan → apply, etc.)
# Standard Configurations (providers, backends, modules)
# Troubleshooting (frequent issues)
# References (links to deep-dive files)
```

**Token Budget**: ~5,000 tokens (strict limit)

### references/ (Deep Reference Library)

**Purpose**: Comprehensive documentation for complex scenarios.

**Organization**:
- `terraform/`: Terraform-specific deep dives
- `terragrunt/`: Terragrunt-specific deep dives
- `hcp-stacks/`: HCP Stacks documentation
- `shared/`: Cross-cutting concerns (state management, CI/CD)

**Token Budget**: ~30,000 tokens total (load selectively)

### examples/ (Practical Implementations)

**Purpose**: Show complete, real-world implementations.

**Organization**:
- `terraform/`: Terraform-only examples
- `terragrunt/`: Terragrunt-only examples
- `patterns/`: Design patterns (DRY, immutable infrastructure, etc.)

**Token Budget**: Unlimited (load on demand)

---

## Token Budget Documentation

### Core Skill (~5K tokens)

The core skill must remain under 5,000 tokens to ensure fast loading and broad compatibility. This allows Claude to have essential knowledge without hitting context limits.

**Measurement**:
```bash
# Count tokens (approximate with words * 1.3)
wc -w SKILL.md | awk '{print $1 * 1.3}'
```

**Optimization Strategies**:
1. Use tables instead of prose
2. Link to references/ instead of duplicating
3. Prefer examples over explanations
4. Remove redundant information
5. Use shorthand where clear

### Reference Files (~30K tokens total)

Reference files collectively target ~30K tokens, distributed across topics:
- Terraform core: ~10K tokens
- Terragrunt: ~8K tokens
- HCP Stacks: ~5K tokens
- Shared concepts: ~7K tokens

**Loading Strategy**: Load only relevant references based on task context.

---

## Development Workflow

### Testing Changes

1. **Local Testing**:
   ```bash
   # Invoke skill locally
   cd /path/to/unified-terraform-terragrunt
   claude --skill ./SKILL.md "terraform plan --help"
   ```

2. **Validation Checklist**:
   - [ ] Token count under budget (SKILL.md < 5K)
   - [ ] Cross-references valid (all links work)
   - [ ] Examples runnable (test with real Terraform)
   - [ ] Markdown properly formatted
   - [ ] No sensitive data (API keys, credentials)

3. **Integration Testing**:
   ```bash
   # Test with real project
   cd /path/to/terraform/project
   claude --skill /path/to/skill "help me refactor this"
   ```

### Updating Reference Files

1. **Edit reference file** (e.g., `references/terraform/state-management.md`)
2. **Update cross-references** in SKILL.md if needed
3. **Test loading**: Ensure file loads correctly when referenced
4. **Validate examples**: Ensure code blocks are runnable

### Adding New Features

1. **Determine layer**: Core (SKILL.md) or Reference (references/)
2. **Update relevant file(s)**
3. **Add cross-references**: Link from SKILL.md to references/
4. **Add example** (if applicable): Complete implementation in examples/
5. **Test end-to-end**: Verify workflow works

---

## Quality Standards

### Code Examples

✅ **Good**:
```hcl
# Correct: Complete, runnable example
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    Name = "web-server"
  }
}
```

❌ **Bad**:
```hcl
# Incomplete: Missing required attributes
resource "aws_instance" "web" {
  instance_type = "t3.micro"
}
```

### Documentation Style

✅ **Good**:
```markdown
## terraform apply

Apply Terraform changes:
```bash
terraform apply -auto-approve
```

Common flags:
- `-target=resource`: Apply only specific resource
- `-var-file=file`: Load variables from file

See [references/terraform/apply.md](references/terraform/apply.md) for advanced options.
```

❌ **Bad**:
```markdown
## terraform apply

The `terraform apply` command is used to apply the changes required to reach the desired state of the configuration. This command will show you what changes will be made and ask for confirmation before proceeding. You can use various flags to customize the behavior...
```

### Cross-References

✅ **Good**:
```markdown
For advanced state management, see [State Management Reference](references/terraform/state-management.md).
```

❌ **Bad**:
```markdown
See the state management docs for more info.
```

---

## Contributing Process

### 1. Identify Need

- User feedback
- Missing documentation
- Outdated content
- New tool features

### 2. Plan Changes

- Determine affected files (core vs. reference)
- Check token budget impact
- Plan cross-reference updates

### 3. Implement

- Edit relevant files
- Add examples if needed
- Update cross-references
- Validate markdown formatting

### 4. Test

- Verify token counts
- Test examples (run actual commands)
- Check cross-reference links
- Test with real projects

### 5. Document

- Update CHANGELOG.md (if exists)
- Update README.md (if user-facing)
- Add comments to complex examples

### 6. Submit

- Create pull request (if using version control)
- Describe changes clearly
- Link to related issues/requests
- Include test results

---

## Maintenance Guidelines

### Regular Updates

**Quarterly** (every 3 months):
- Review official Terraform/Terragrunt release notes
- Update deprecated patterns
- Add new features to references/
- Refresh examples with current best practices

**Annual** (once per year):
- Full content audit
- Token budget optimization
- Example refresh (remove outdated patterns)
- Architecture review

### Deprecation Policy

When deprecating content:
1. Mark as deprecated in SKILL.md
2. Add migration guide to references/
3. Keep deprecated content for 2 minor versions
4. Remove after 2 versions (with notice)

### Versioning

Follow semantic versioning:
- **Major**: Breaking changes (skill structure, removed features)
- **Minor**: New features, additions
- **Patch**: Bug fixes, typo corrections

---

## Attribution

This skill unifies content from multiple source skills:
- `lharries/terraform-claude-code-skill`
- `terryx/claude-terragrunt-skill`
- `terryx/claude-hcp-terraform-skill`

When contributing, respect original licenses (Apache 2.0) and maintain attribution where applicable.

---

## Getting Help

### Questions?

- Check README.md for user documentation
- Review existing examples/ for patterns
- Examine references/ for deep dives

### Issues?

- Document the problem clearly
- Provide reproduction steps
- Include relevant configuration files
- Share error messages (sanitized)

---

## License

This skill is distributed under the Apache 2.0 License. See LICENSE file for details.

Contributions must be compatible with Apache 2.0.
