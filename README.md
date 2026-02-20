# portfolio-aws-org-guardduty

Deploy GuardDuty organization-wide across all AWS regions with discovery-driven Terraform deployment.

## Overview

portfolio-aws-org-guardduty configures AWS GuardDuty across all 17 AWS regions in an AWS Organization. It designates a delegated administrator (audit account), enables detectors, and configures organization-wide auto-enable with all protection plans.

This project was extracted from [portfolio-aws-org-baseline](../portfolio-aws-org-baseline) for independent deployment and iteration.

## Features

- **Delegated Admin** - Configures audit account as GuardDuty delegated administrator in all regions
- **Detector Enablement** - Enables GuardDuty detectors in management and audit accounts across all regions
- **Organization Auto-Enable** - Configures `auto_enable_organization_members = ALL` for all regions
- **Findings Export** - Centralized S3 bucket in log-archive account with KMS encryption, lifecycle policies, and per-region publishing destinations
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
resource_prefix: "myorg"  # Must match org-baseline's resource_prefix
```

The `audit_account_id`, `primary_region`, and `tags` are auto-discovered from `portfolio-aws-org-baseline` via an SSM Parameter Store parameter at `/{resource_prefix}/org-baseline/config`. You can override any value in `config.yaml` if needed.

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
# Used to locate SSM parameter: /{resource_prefix}/org-baseline/config
resource_prefix: "myorg"

# Cross-account role name (default: OrganizationAccountAccessRole)
audit_account_role: "OrganizationAccountAccessRole"

# Optional overrides (auto-discovered from org-baseline SSM parameter if omitted)
# primary_region: "us-east-1"
# audit_account_id: "123456789012"
```

### SSM Auto-Discovery

When `portfolio-aws-org-baseline` is deployed, it writes organization configuration to SSM Parameter Store at `/{resource_prefix}/org-baseline/config`. This project reads that parameter during discovery to obtain:

- `audit_account_id` - Delegated admin account
- `primary_region` - Primary AWS region
- `management_account_id` - Management account
- `log_archive_account_id` - Log archive account
- `organization_id` - AWS Organization ID
- `tags` - Shared resource tags

If the SSM parameter is unavailable (e.g., first-time setup), discovery falls back to values in `config.yaml`.

## Project Structure

```
portfolio-aws-org-guardduty/
├── entrypoint.sh           # Main orchestration script
├── config.yaml             # Configuration file
├── requirements.txt        # Python dependencies
├── discovery/
│   ├── discover.py         # AWS discovery script
│   ├── state_sync.py       # Terraform state synchronization
│   └── cloudwatch_logger.py # CloudWatch Logs streaming helper
├── post-deployment/
│   └── verify-guardduty.py # Deployment verification (5 checks)
├── terraform/
│   ├── main.tf             # Root module (KMS, S3, CloudWatch)
│   ├── variables.tf        # Variable definitions
│   ├── outputs.tf          # Output definitions
│   ├── providers.tf        # Provider configurations (51 providers)
│   ├── versions.tf         # Version constraints
│   ├── guardduty-regional.tf  # Multi-region deployment
│   └── modules/
│       ├── guardduty-org/        # Delegated admin registration
│       ├── guardduty-enabler/    # Detector enablement + findings export
│       ├── guardduty-org-config/ # Organization configuration
│       ├── kms/                  # KMS key management
│       └── s3/                   # S3 bucket management
├── Dockerfile
└── Makefile
```

## Architecture

### Module Structure

| Module | Account | Purpose |
|--------|---------|---------|
| `guardduty-org` | Management | Designate delegated admin (per-region) |
| `guardduty-enabler` | Management + Delegated Admin | Enable GuardDuty detector (+ findings export on audit) |
| `guardduty-org-config` | Delegated Admin | Configure auto-enable, protection plans, member enrollment |
| `kms` | Log-Archive | KMS key for findings bucket encryption |
| `s3` | Log-Archive | Centralized findings export bucket |

### Deployment Phases

1. **Discovery** - Inspect existing GuardDuty state, check access logs bucket
2. **Terraform Init** - Initialize with S3 backend, sync existing resources into state
3. **Terraform Plan/Apply** - Deploy GuardDuty configuration
4. **Verification** - Validate configuration across all regions (delegated admin, detectors, publishing destinations)
5. **Summary** - Output deployment results

See [STEPS.md](STEPS.md) for detailed documentation of every deployment step.

### Multi-Account Architecture

```
Management Account
├── Registers delegated admin (17 regions)
├── GuardDuty detectors (17 regions, direct - org owner cannot be auto-enrolled)
├── Deployment CloudWatch Logs
└── Runs Terraform

Audit Account (Delegated Admin)
├── GuardDuty detectors (17 regions)
├── Organization auto-enable configuration
├── Member enrollment (log-archive account)
├── Publishing destinations → S3 findings bucket
└── All protection plans enabled

Log-Archive Account
├── GuardDuty detector (auto-enrolled as member by delegated admin)
├── KMS key for findings encryption
└── S3 bucket for centralized findings export

Other Member Accounts
└── Auto-enrolled by organization configuration
```

## State Management

- Terraform state stored in the org-baseline S3 bucket: `{resource_prefix}-tfstate-{account_id}`
- State key: `guardduty/terraform.tfstate` (separate prefix from org-baseline's `organization/terraform.tfstate`)
- The state bucket must be created by `portfolio-aws-org-baseline` before running this project

## Relationship to org-baseline

This project depends on `portfolio-aws-org-baseline` for:
- AWS Organization creation
- GuardDuty service access principal (`guardduty.amazonaws.com`) in the organization
- Shared accounts (audit account) creation
- SSM Parameter Store config at `/{resource_prefix}/org-baseline/config` (auto-discovery of account IDs and tags)

GuardDuty-specific resources (delegated admin, detectors, org config) are fully managed by this project.

## Security

This project includes automated security scanning via [portfolio-code-scanner](https://github.com/williambrady/portfolio-code-scanner).

## License

See [LICENSE](LICENSE) for details.
