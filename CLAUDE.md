# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWS GuardDuty organization-wide deployment using Terraform wrapped in Docker. Deploys GuardDuty across all 17 AWS regions with delegated admin, detectors, and organization-wide auto-enable configuration.

**Stack:** Terraform (infrastructure), Python (discovery/verification), Bash (orchestration), Docker (distribution)

**Relationship:** This project was extracted from `portfolio-aws-org-baseline` to allow independent deployment. The AWS Organization and GuardDuty service access principals remain managed by `portfolio-aws-org-baseline`.

## Architecture

### Core Principles

1. **Terraform as State Owner** - Single source of truth for GuardDuty infrastructure state
2. **Config-Driven** - `config.yaml` in project root defines deployment specification
3. **Discovery-Driven** - Python discovers existing resources before Terraform runs
4. **Idempotent Operations** - All deployments safe to retry
5. **Modular Design** - Reusable Terraform modules for each GuardDuty component

### Data Flow

```
config.yaml → discover.py → bootstrap.auto.tfvars.json → state_sync.py → Terraform → AWS
```

### Account Types

- **Management Account** - AWS Organization root, runs Terraform, registers delegated admin
- **Audit Account** - Delegated admin for GuardDuty, hosts detectors and org configuration

### Three-Phase GuardDuty Architecture

1. **Delegated Admin Registration** (Management Account) - 17 `guardduty-org` modules
2. **Detector Enablement** (Audit Account) - 17 `guardduty-enabler` modules
3. **Organization Configuration** (Audit Account) - 17 `guardduty-org-config` modules with 180s propagation wait

## Directory Structure

```
portfolio-aws-org-guardduty/
├── entrypoint.sh           # Main orchestration script
├── config.yaml             # Deployment configuration
├── requirements.txt        # Python dependencies
├── discovery/
│   ├── discover.py         # AWS discovery, generates tfvars
│   └── state_sync.py       # Terraform state synchronization
├── post-deployment/
│   └── verify-guardduty.py # GuardDuty verification
├── terraform/
│   ├── main.tf             # Root module
│   ├── variables.tf        # Variable definitions
│   ├── outputs.tf          # Output definitions
│   ├── providers.tf        # Provider configurations (34 providers)
│   ├── versions.tf         # Terraform/provider version constraints
│   ├── guardduty-regional.tf  # Multi-region deployment (676 lines)
│   └── modules/
│       ├── guardduty-org/        # Per-region delegated admin registration
│       ├── guardduty-enabler/    # Single-region detector enablement
│       └── guardduty-org-config/ # Per-region organization configuration
├── Dockerfile
└── Makefile
```

## Commands

All code runs inside Docker containers. Use the Makefile:

```bash
# Build Docker image
make build

# Discover current AWS state
AWS_PROFILE=my-profile make discover

# Show Terraform plan
AWS_PROFILE=my-profile make plan

# Apply configuration
AWS_PROFILE=my-profile make apply

# Open interactive shell
AWS_PROFILE=my-profile make shell
```

## Configuration

Edit `config.yaml` to customize:

- `resource_prefix` - Prefix for all resource names. **Required.**
- `primary_region` - Primary AWS region
- `audit_account_id` - Audit account ID (delegated admin). **Required.**
- `audit_account_role` - Cross-account role name (default: `OrganizationAccountAccessRole`)
- `tags` - Custom tags applied to all resources

## Module Architecture

### Provider Aliases

- 17 management account regional providers (default + 16 aliases)
- 17 audit account regional providers with cross-account role assumption
- Total: 34 providers

### Key Modules

**GuardDuty Org Module** - Designates delegated admin (management account context):
- `aws_guardduty_organization_admin_account` per region

**GuardDuty Enabler Module** - Enables detector (audit account context):
- `aws_guardduty_detector` with S3, K8s, malware protection
- `aws_guardduty_detector_feature` for Lambda and RDS protection

**GuardDuty Org Config Module** - Organization-wide settings (audit account context):
- `aws_guardduty_organization_configuration` with auto_enable = ALL
- Organization features: S3, EKS, malware, runtime monitoring, Lambda, RDS

## Post-Deployment

### verify-guardduty.py

Validates GuardDuty configuration across all 17 regions:
- Service access enabled in Organizations
- Delegated admin correctly configured
- Organization auto-enable applied
- Detectors enabled in management, log-archive, and audit accounts

## Rules

- **No Claude Attribution** - Do not mention Claude, AI, or any AI assistant in commit messages, documentation, or code comments.
- **Use python3** - Always use `python3` instead of `python` when executing Python scripts.
- **Run pre-commit before pushing** - Always run `pre-commit run --all-files` before pushing changes.
