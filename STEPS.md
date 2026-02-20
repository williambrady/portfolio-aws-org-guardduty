# Deployment Steps

This document describes every step that occurs during a `make apply` deployment, including where values are retrieved and decision logic.

## Pre-Deployment (entrypoint.sh)

### 0.1 AWS Credential Check

- Calls `aws sts get-caller-identity` to verify credentials
- Extracts `ACCOUNT_ID` and `CALLER_ARN` from the response
- **Fails if:** No valid AWS credentials are available

### 0.2 Load Configuration from config.yaml

- Reads `resource_prefix` from `/work/config.yaml` (required, fails if missing)
- Reads `deployment_name` from `/work/config.yaml` (required, fails if missing)
- Reads `primary_region` from `/work/config.yaml` (defaults to `us-east-1`)

### 0.3 CloudWatch Logging Setup

- Constructs log group name: `/{resource_prefix}/deployments/{deployment_name}`
- Creates CloudWatch log group via `aws logs create-log-group` (idempotent, ignores if exists)
- Creates initial log stream: `{timestamp}/config`
- Starts background `cloudwatch_logger.py` process reading from a FIFO pipe
- All subsequent phase output is tee'd to both stdout and CloudWatch via `tee_log` helper
- Each phase creates a separate log stream: `{timestamp}/{phase_name}`

### 0.4 State Bucket Verification

- Constructs bucket name: `{resource_prefix}-tfstate-{ACCOUNT_ID}`
- Calls `aws s3api head-bucket` to verify it exists
- State key: `guardduty/terraform.tfstate`
- **Fails if:** Bucket does not exist (must be created by `portfolio-aws-org-baseline` first)

### 0.5 Runtime Configuration Logging

- Writes timestamp, action, account ID, caller ARN, terraform args, and effective settings to the `config` log stream

## Phase 1: Discovery (discover.py)

### 1.1 Load config.yaml

- Reads from `/work/config.yaml` (Docker) or `../config.yaml` (local fallback)
- Extracts `resource_prefix` (required)

### 1.2 Get Caller Identity

- Calls `sts.get_caller_identity()` to get `management_account_id`
- Uses `primary_region` from config for the initial STS client

### 1.3 Read SSM Parameter

- Path: `/{resource_prefix}/org-baseline/config`
- Written by `portfolio-aws-org-baseline` during its deployment
- Contains JSON with: `audit_account_id`, `log_archive_account_id`, `primary_region`, `organization_id`, `tags`
- **If SSM parameter exists:** Values override config.yaml defaults
- **If SSM parameter missing:** Falls back to config.yaml values

### 1.4 Merge Configuration

Priority order (highest wins):
1. `config.yaml` explicit overrides (e.g., `audit_account_id` if set)
2. SSM parameter values
3. Hardcoded defaults (`primary_region` defaults to `us-east-1`)

Resolved values:
- `primary_region` - from config.yaml or SSM
- `audit_account_id` - from config.yaml or SSM (required)
- `log_archive_account_id` - from SSM only
- `organization_id` - from SSM only
- `custom_tags` - from SSM `tags` field, or config.yaml `tags`

### 1.5 Validate GuardDuty Organization

- **Fails if:** `audit_account_id` is empty (not in config or SSM)
- Calls `organizations.list_delegated_administrators(ServicePrincipal="guardduty.amazonaws.com")`
- **Fails if:** No delegated admin registered (org-baseline must run first)
- **Fails if:** Delegated admin doesn't match `audit_account_id`
- Assumes role into audit account via `OrganizationAccountAccessRole`
- Queries `guardduty.describe_organization_configuration` for protection plan status

### 1.6 Check Access Logs Bucket (for findings export)

- **Skipped if:** `log_archive_account_id` is empty
- Assumes role into log-archive account
- Calls `s3.head_bucket` for `{resource_prefix}-access-logs-{log_archive_account_id}`
- Sets `access_logs_bucket_exists = True/False`
- This bucket is created by `portfolio-aws-org-baseline` and used for S3 access logging on the findings bucket
- **If missing:** Prints warning, findings bucket created without access logging

### 1.7 Write discovery.json

- Writes GuardDuty org status to `/work/terraform/discovery.json`

### 1.8 Write bootstrap.auto.tfvars.json

- Writes to `/work/terraform/bootstrap.auto.tfvars.json`
- Contains: `primary_region`, `resource_prefix`, `deployment_name`, `management_account_id`, `audit_account_id`, `log_archive_account_id`, `access_logs_bucket_exists`, `custom_tags`
- Terraform reads this file automatically during plan/apply

## Phase 2: Terraform Init + State Sync

### 2.1 Clean Local State

- Removes `.terraform/` and `.terraform.lock.hcl` to prevent stale backend config

### 2.2 Terraform Init

- Initializes with S3 backend configuration:
  - `bucket` = `{resource_prefix}-tfstate-{ACCOUNT_ID}`
  - `key` = `guardduty/terraform.tfstate`
  - `region` = `{primary_region}`
  - `encrypt` = `true`
- Downloads provider plugins (hashicorp/aws ~> 5.0)
- Initializes 51 provider configurations (17 management + 17 audit + 17 log-archive)

### 2.3 State Sync (state_sync.py)

Imports existing AWS resources into Terraform state to avoid conflicts on first apply or after manual changes. Also cleans up stale resources from previous architectural changes.

#### 2.3.0a Cleanup Removed Resources

- Scans state for management account `aws_guardduty_member.members` entries
- The management account (org owner) cannot be enrolled as a GuardDuty member, so these entries are stale
- Runs `terraform state rm` for each matching address
- **Skipped if:** No management account member enrollments found in state

#### 2.3.0b Provider Warm-Up (empty state only)

- **Triggered when:** Terraform state has 0 resources (first deployment or after state reset)
- Runs `terraform plan -refresh-only -input=false -compact-warnings` (timeout: 300s)
- Initializes all 51 provider configurations and caches credentials
- **Why:** Each `terraform import` reinitializes all 51 providers. On empty state, this causes silent import failures due to provider initialization issues or STS rate limiting. Running a refresh-only plan first ensures all providers are ready.
- Import commands use retry logic (2 attempts with 5s delay) as defense-in-depth

#### 2.3.1 Sync CloudWatch Log Group

- Address: `aws_cloudwatch_log_group.deployments`
- Log group is pre-created by entrypoint.sh (step 0.3) before Terraform runs
- Import ID: `/{resource_prefix}/deployments/{deployment_name}`
- **Skipped if:** Already in state

#### 2.3.2 Sync GuardDuty Delegated Admin

- For each of 17 regions:
  - Address: `module.guardduty_org_{region}[0].aws_guardduty_organization_admin_account.main`
  - Calls `guardduty.list_organization_admin_accounts()` from management account
  - Import ID: `{audit_account_id}`
  - **Skipped if:** Already in state or not currently configured in AWS

#### 2.3.3 Sync GuardDuty Detectors

- For management account (17 regions):
  - Address: `module.guardduty_mgmt_{region}[0].aws_guardduty_detector.main`
  - Uses current credentials (management account)
  - Calls `guardduty.list_detectors()`
  - Import ID: `{detector_id}`
  - **Skipped if:** Already in state or no detector exists
- For audit account (17 regions):
  - Address: `module.guardduty_audit_{region}[0].aws_guardduty_detector.main`
  - Assumes role into audit account
  - Calls `guardduty.list_detectors()`
  - Import ID: `{detector_id}`
  - **Skipped if:** Already in state or no detector exists

#### 2.3.4 Sync Publishing Destinations

- For each of 17 regions (audit account):
  - Address: `module.guardduty_audit_{region}[0].aws_guardduty_publishing_destination.findings[0]`
  - Assumes role into audit account
  - Calls `guardduty.list_publishing_destinations()` for each detector
  - Looks for `DestinationType == "S3"`
  - Import ID: `{detector_id}:{destination_id}`
  - **Skipped if:** Already in state or no S3 publishing destination exists

## Phase 3: Terraform Apply

Terraform creates/updates resources across three account contexts using 51 provider configurations.

### 3.1 Management Account Resources

**Deployment Logging (primary region only):**
- `module.kms_deployment_logs` - KMS key for CloudWatch log encryption
- `aws_cloudwatch_log_group.deployments` - Deployment log group with 365-day retention

**GuardDuty Delegated Admin (17 regions):**
- `module.guardduty_org_{region}` - Registers audit account as delegated admin
- Resource: `aws_guardduty_organization_admin_account`
- One per region, runs from management account context

**GuardDuty Detectors (17 regions):**
- `module.guardduty_mgmt_{region}` - Enables GuardDuty detector in management account
- The management account is NOT auto-enrolled by organization configuration (it is the org owner, not a member)
- Resources per region:
  - `aws_guardduty_detector` with S3 logs, K8s audit logs, malware protection
  - `aws_guardduty_detector_feature` for LAMBDA_NETWORK_LOGS
  - `aws_guardduty_detector_feature` for RDS_LOGIN_EVENTS
- No publishing destination (findings export is only on the delegated admin's detectors)
- `depends_on` the corresponding `guardduty_org` module

### 3.2 Audit Account Resources

**GuardDuty Detectors (17 regions):**
- `module.guardduty_audit_{region}` - Enables GuardDuty detector
- Resources per region:
  - `aws_guardduty_detector` with S3 logs, K8s audit logs, malware protection
  - `aws_guardduty_detector_feature` for LAMBDA_NETWORK_LOGS
  - `aws_guardduty_detector_feature` for RDS_LOGIN_EVENTS
  - `aws_guardduty_publishing_destination` for S3 findings export (conditional on `log_archive_account_id != ""`)
- `depends_on` the corresponding `guardduty_org` module

**Organization Configuration + Member Enrollment (17 regions):**
- `module.guardduty_org_config_{region}` - Configures auto-enable, protection plans, and member enrollment
- Resources per region:
  - `aws_guardduty_organization_configuration` with `auto_enable_organization_members = ALL`
  - `aws_guardduty_organization_configuration_feature` for S3_DATA_EVENTS (auto_enable = ALL)
  - `aws_guardduty_organization_configuration_feature` for EKS_AUDIT_LOGS (auto_enable = ALL)
  - `aws_guardduty_organization_configuration_feature` for EBS_MALWARE_PROTECTION (auto_enable = ALL)
  - `aws_guardduty_organization_configuration_feature` for RUNTIME_MONITORING (auto_enable = ALL, with EKS/ECS/EC2 agent management)
  - `aws_guardduty_organization_configuration_feature` for LAMBDA_NETWORK_LOGS (auto_enable = ALL)
  - `aws_guardduty_organization_configuration_feature` for RDS_LOGIN_EVENTS (auto_enable = ALL)
  - `aws_guardduty_member` for log-archive account (explicit enrollment ensures detector with all protection plans)
- The management account is NOT enrolled as a member (org owner cannot be a member; gets direct detectors in section 3.1)
- `lifecycle { ignore_changes = [email, invite] }` on `aws_guardduty_member` prevents perpetual replacement cycles (email not read back by API, invite drifts from true to null)
- `depends_on` the corresponding audit detector module

### 3.3 Log-Archive Account Resources

**Conditional on:** `log_archive_account_id != ""`

**KMS Key:**
- `module.kms_guardduty_findings` - Encryption key for findings bucket
- Service principal: `guardduty.amazonaws.com`
- Actions: GenerateDataKey, Encrypt, Decrypt, ReEncrypt*, DescribeKey
- Account root also has full kms:* access

**S3 Bucket:**
- `module.s3_guardduty_findings` - Findings export destination
- Bucket name: `{resource_prefix}-guardduty-findings-{log_archive_account_id}`
- KMS encryption using the findings KMS key
- Versioning enabled
- Public access block (all four settings enabled)
- Bucket policy with:
  - DenyNonSSL - Denies all requests without TLS
  - AllowGuardDutyPutObject - Allows `guardduty.amazonaws.com` to write with `bucket-owner-full-control` ACL
  - AllowGuardDutyGetBucketLocation - Allows `guardduty.amazonaws.com` to read bucket location
- Access logging to `{resource_prefix}-access-logs-{log_archive_account_id}` (conditional on `access_logs_bucket_exists`)
- Lifecycle rules:
  - Abort incomplete multipart uploads after 7 days
  - Transition to STANDARD_IA at 90 days
  - Transition to GLACIER at 365 days
  - Expire at 730 days

## Phase 4: Post-Deployment Verification (verify-guardduty.py)

Runs after apply (required) and after plan (optional, non-blocking).

### 4.1 Check Service Access

- Calls `organizations.list_aws_service_access_for_organization()`
- Verifies `guardduty.amazonaws.com` is in the enabled services list

### 4.2 Check Delegated Admin (17 regions)

- For each region, calls `guardduty.list_organization_admin_accounts()` from management account
- Verifies the admin account ID matches `audit_account_id`

### 4.3 Check Organization Auto-Enable (17 regions)

- Assumes role into audit account (delegated admin)
- Lists detectors, gets the detector ID
- Calls `guardduty.describe_organization_configuration()`
- Verifies:
  - `AutoEnableOrganizationMembers == "ALL"`
  - S3 logs auto-enable is true
  - Kubernetes audit logs auto-enable is true
  - Malware protection auto-enable is true

### 4.4 Check Detectors (3 accounts x 17 regions)

For management, log-archive, and audit accounts:
- Assumes role into the account (or uses current creds for management)
- Calls `guardduty.list_detectors()` and `guardduty.get_detector()`
- Verifies detector status is ENABLED
- Checks data sources: S3, Kubernetes, Malware protection

### 4.5 Check Publishing Destinations (17 regions)

- Assumes role into audit account
- For each region, lists publishing destinations on the detector
- Verifies an S3-type destination exists
- Calls `guardduty.describe_publishing_destination()` for destination ARN
- Verifies status is `PUBLISHING` (healthy)

### Verification Exit Behavior

- **On plan:** Verification runs but failures don't block (non-zero exit ignored)
- **On apply:** Verification runs; failures produce a warning but don't fail the deployment

## Phase 5: Summary

- Outputs `terraform output -json guardduty_summary` containing:
  - `delegated_admin` - Audit account ID
  - `regions_configured` - Number of regions (17)
  - `management_account` - Management account ID
  - `findings_bucket` - S3 bucket name for findings export

## CloudWatch Log Streams

Each deployment creates log streams under `/{resource_prefix}/deployments/{deployment_name}`:

| Stream | Content |
|--------|---------|
| `{timestamp}/config` | Runtime configuration, effective settings |
| `{timestamp}/discover` | Discovery output |
| `{timestamp}/init` | Terraform init output |
| `{timestamp}/import` | State sync (terraform import) output |
| `{timestamp}/plan` or `{timestamp}/apply` | Terraform plan/apply output |
| `{timestamp}/verify` | Post-deployment verification output |
| `{timestamp}/summary` | Final deployment summary |
