# Quick Reference

> **Part of:** [terraform-skill](../SKILL.md)
> **Purpose:** Command cheat sheets and decision flowcharts

This document provides quick lookup tables, command references, and decision flowcharts. For detailed patterns, see [code-patterns.md](code-patterns.md). For testing details, see [testing-frameworks.md](testing-frameworks.md).

---

## Table of Contents

1. [Command Cheat Sheet](#command-cheat-sheet)
2. [Decision Flowcharts](#decision-flowcharts)
3. [Version-Specific Guidance](#version-specific-guidance)

---

## Command Cheat Sheet

### Static Analysis

```bash
# Format and validate
terraform fmt -recursive -check
terraform validate

# Linting
tflint --init && tflint

# Security scanning
trivy config .
checkov -d .
```

### Native Tests (1.6+)

```bash
# Run all tests
terraform test

# Run tests in specific directory
terraform test -test-directory=tests/unit/

# Verbose output
terraform test -verbose
```

### Plan Validation

```bash
# Generate and review plan
terraform plan -out tfplan

# Convert plan to JSON
terraform show -json tfplan | jq -r '.' > tfplan.json

# Check for specific changes
terraform show tfplan | grep "will be created"
```

### State Manipulation

```bash
# Import existing resources into state
terraform import google_compute_instance.web projects/PROJECT/zones/ZONE/instances/INSTANCE_NAME

# Move resources between addresses (refactoring)
terraform state mv google_compute_instance.old google_compute_instance.new
terraform state mv module.old.aws_instance.web module.new.aws_instance.web

# Remove resources from state (without destroying)
terraform state rm google_compute_instance.temp

# Show specific resource state
terraform state show google_compute_instance.web

# Pull state to local file
terraform state pull > terraform.tfstate

# Push state from file (use with caution)
terraform state push terraform.tfstate
```

---

## Decision Flowcharts

### Testing Approach Selection

```
Need to test Terraform code?
│
├─ Just syntax/format?
│  └─ terraform validate + fmt
│
├─ Static security scan?
│  └─ trivy + checkov
│
├─ Terraform 1.6+?
│  ├─ Simple logic test?
│  │  └─ Native terraform test
│  │
│  └─ Complex integration?
│     └─ Terratest
│
└─ Pre-1.6?
   ├─ Go team?
   │  └─ Terratest
   │
   └─ Neither?
      └─ Plan to upgrade Terraform
```

### Module Development Workflow

```bash
1. Plan
   ├─ Define inputs (variables.tf)
   ├─ Define outputs (outputs.tf)
   └─ Document purpose (README.md)

2. Implement
   ├─ Create resources (main.tf)
   ├─ Pin versions (versions.tf)
   └─ Add examples (examples/simple, examples/complete)

3. Test
   ├─ Static analysis (validate, fmt, lint)
   ├─ Unit tests (native or Terratest)
   └─ Integration tests (examples/)

4. Document
   ├─ Update README with usage
   ├─ Document inputs/outputs
   └─ Add CHANGELOG

5. Publish
   ├─ Tag version (git tag v1.0.0)
   ├─ Push to registry
   └─ Announce changes
```

### Refactoring Decision Tree

```bash
What are you refactoring?

├─ Resource addressing (count[0] → for_each["key"])
│  └─ Use: moved blocks + for_each conversion
│     See: [code-patterns.md](code-patterns.md#count-to-for_each-migration)
│
├─ Secrets in state
│  └─ Use: Google Secret Manager + write-only arguments (1.11+)
│     See: [code-patterns.md](code-patterns.md#secrets-remediation)
│
├─ Legacy Terraform syntax (0.12/0.13)
│  └─ Use: Modern feature migration
│     See: [code-patterns.md](code-patterns.md#terraform-version-upgrades)
│
└─ Module structure (rename, reorganize)
   └─ Use: moved blocks to preserve resources
```

---

## Version-Specific Guidance

### Terraform 1.0-1.5

- ❌ No native testing framework
- ✅ Use Terratest
- ✅ Focus on static analysis
- ✅ terraform plan validation

### Terraform 1.6+

- ✅ NEW: Native `terraform test`
- ✅ Consider migrating simple tests from Terratest
- ✅ Keep Terratest for complex integration

### Terraform 1.7+

- ✅ NEW: Mock providers for unit testing
- ✅ Reduce costs with mocking
- ✅ Use real integration tests for final validation

---

## Pre-Commit Checklist

See [module-patterns.md](module-patterns.md) for module structure details and [code-patterns.md](code-patterns.md) for coding standards.

### Essential Checks

```bash
# Always run before commit
terraform fmt -recursive
terraform validate
```

### Quick Review

- [ ] `count`/`for_each` at top of resource blocks
- [ ] All variables have descriptions
- [ ] All outputs have descriptions
- [ ] `terraform.tfvars` only at composition level
- [ ] Remote state configured
- [ ] Using `try()` not `element(concat())`
- [ ] Secrets use external data sources (not in state)

---

## Version Management Quick Reference

See [code-patterns.md](code-patterns.md#version-management) for detailed guidance.

### Constraint Syntax

| Syntax | Meaning | Use Case |
|--------|---------|----------|
| `"~> 5.0"` | Pessimistic (5.0.x) | **Recommended** for stability |
| `"5.0.0"` | Exact version | Avoid (inflexible) |
| `">= 5.0, < 6.0"` | Range | Any 5.x version |

### Strategy by Component

| Component | Recommendation | Example |
|-----------|----------------|---------|
| **Terraform** | Pin minor | `required_version = "~> 1.9"` |
| **Providers** | Pin major | `version = "~> 5.0"` |
| **Modules (prod)** | Pin exact | `version = "5.1.2"` |

---

**Back to:** [Main Skill File](../SKILL.md)
