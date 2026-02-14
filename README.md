# portfolio-aws-org-guardduty

Deploy GuardDuty organization-wide across all AWS regions with discovery-driven Terraform deployment.

## Overview

portfolio-aws-org-guardduty configures AWS GuardDuty across all 17 AWS regions in an AWS Organization. It designates a delegated administrator (audit account), enables detectors, and configures organization-wide auto-enable with all protection plans.

This project was extracted from [portfolio-aws-org-baseline](../portfolio-aws-org-baseline) for independent deployment and iteration.

## Features

- **Delegated Admin** - Configures audit account as GuardDuty delegated administrator in all regions
- **Detector Enablement** - Enables GuardDuty detector in the audit account across all regions
- **Organization Auto-Enable** - Configures `auto_enable_organization_members = ALL` for all regions
- **Protection Plans** (auto-enabled for all member accounts):
  - S3 Data Events protection
  - Kubernetes Audit Logs
  - Malware Protection (EBS scanning)
  - Lambda Network Logs (GuardDuty.6)
  - RDS Login Events (GuardDuty.9)
  - Runtime Monitoring with EKS, ECS Fargate, EC2 agent management

## Prerequisites

- **Docker** - Required for running the deployment
- **AWS CLI** - Configured with a profile for the management account
- **AWS Organization** - Must already exist (managed by `portfolio-aws-org-baseline`)
- **GuardDuty Service Access** - Must be enabled in Organizations (managed by `portfolio-aws-org-baseline`)
- **Audit Account** - Must already exist in the organization

## Quick Start

### 1. Configure

Edit `config.yaml`:

```yaml
resource_prefix: "myorg"
primary_region: "us-east-1"
audit_account_id: "123456789012"  # Your audit account ID
```

### 2. Plan

```bash
AWS_PROFILE=management-account make plan
```

### 3. Apply

```bash
AWS_PROFILE=management-account make apply
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `make discover` | Discover current AWS state without changes |
| `make plan` | Discovery + Terraform plan (preview changes) |
| `make apply` | Discovery + Terraform apply + post-deployment verification |
| `make destroy` | Destroy all managed resources (use with caution) |
| `make shell` | Open interactive shell in container for debugging |

### Examples

```bash
# Preview changes
AWS_PROFILE=mgmt make plan

# Apply GuardDuty configuration
AWS_PROFILE=mgmt make apply

# Debug: open shell in container
AWS_PROFILE=mgmt make shell
```

## Configuration Reference

```yaml
# REQUIRED: Prefix for all AWS resource names
resource_prefix: "myorg"

# REQUIRED: Primary AWS region
primary_region: "us-east-1"

# REQUIRED: Audit account ID (delegated admin for GuardDuty)
audit_account_id: "123456789012"

# Cross-account role name (default: OrganizationAccountAccessRole)
audit_account_role: "OrganizationAccountAccessRole"

# Custom tags
tags:
  owner: "platform-team"
  contact: "platform@example.com"
```

## Project Structure

```
portfolio-aws-org-guardduty/
├── entrypoint.sh           # Main orchestration script
├── config.yaml             # Configuration file
├── requirements.txt        # Python dependencies
├── discovery/
│   ├── discover.py         # AWS discovery script
│   └── state_sync.py       # Terraform state synchronization
├── post-deployment/
│   └── verify-guardduty.py # Deployment verification
├── terraform/
│   ├── main.tf             # Root module
│   ├── variables.tf        # Variable definitions
│   ├── outputs.tf          # Output definitions
│   ├── providers.tf        # Provider configurations (34 providers)
│   ├── versions.tf         # Version constraints
│   ├── guardduty-regional.tf  # Multi-region deployment
│   └── modules/
│       ├── guardduty-org/        # Delegated admin registration
│       ├── guardduty-enabler/    # Detector enablement
│       └── guardduty-org-config/ # Organization configuration
├── Dockerfile
└── Makefile
```

## Architecture

### Module Structure

| Module | Account | Purpose |
|--------|---------|---------|
| `guardduty-org` | Management | Designate delegated admin (per-region) |
| `guardduty-enabler` | Delegated Admin | Enable GuardDuty detector |
| `guardduty-org-config` | Delegated Admin | Configure auto-enable and protection plans |

### Deployment Phases

1. **Discovery** - Inspect existing GuardDuty state
2. **Terraform Init** - Initialize with S3 backend, sync existing resources
3. **Terraform Plan/Apply** - Deploy GuardDuty configuration
4. **Verification** - Validate configuration across all regions

### Multi-Account Architecture

```
Management Account
├── Registers delegated admin (17 regions)
└── Runs Terraform

Audit Account (Delegated Admin)
├── GuardDuty detectors (17 regions)
├── Organization auto-enable configuration
└── All protection plans enabled

Member Accounts
└── Auto-enrolled by organization configuration
```

## State Management

- Terraform state stored in S3: `{resource_prefix}-guardduty-tfstate-{account_id}/guardduty/terraform.tfstate`
- State bucket created automatically on first run with KMS encryption, versioning, and public access blocked

## Relationship to org-baseline

This project depends on `portfolio-aws-org-baseline` for:
- AWS Organization creation
- GuardDuty service access principal (`guardduty.amazonaws.com`) in the organization
- Shared accounts (audit account) creation

GuardDuty-specific resources (delegated admin, detectors, org config) are fully managed by this project.

## Security

This project includes automated security scanning via [portfolio-code-scanner](https://github.com/williambrady/portfolio-code-scanner).

## License

See [LICENSE](LICENSE) for details.
