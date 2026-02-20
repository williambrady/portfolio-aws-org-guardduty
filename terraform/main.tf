# GuardDuty Organization Deployment
# Manages GuardDuty across all regions in an AWS Organization

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  accounts_exist     = var.audit_account_id != ""
  audit_account_id   = var.audit_account_id
  log_archive_exists = var.log_archive_account_id != ""

  findings_bucket_arn  = local.log_archive_exists ? module.s3_guardduty_findings[0].bucket_arn : ""
  findings_kms_key_arn = local.log_archive_exists ? module.kms_guardduty_findings[0].key_arn : ""

  # Accounts to enroll as GuardDuty members via the delegated admin.
  # Log-archive is enrolled explicitly to ensure it has a detector with all
  # protection plans. The management account CANNOT be enrolled as a member
  # (it is the org owner, not a member - the CreateMembers API silently drops
  # it). Management gets a direct detector via guardduty_mgmt_* modules instead.
  guardduty_member_accounts = local.log_archive_exists && var.log_archive_account_email != "" ? [{
    account_id = var.log_archive_account_id
    email      = var.log_archive_account_email
  }] : []

  common_tags = merge(
    {
      ManagedBy      = "portfolio-aws-org-guardduty"
      ResourcePrefix = var.resource_prefix
    },
    var.custom_tags
  )
}

# -----------------------------------------------------------------------------
# Deployment Logging - KMS Key + CloudWatch Log Group
# -----------------------------------------------------------------------------

module "kms_deployment_logs" {
  source = "./modules/kms"

  alias_name  = "${var.resource_prefix}-guardduty-deployment-logs"
  description = "Encryption key for GuardDuty deployment CloudWatch logs"

  service_principals = [
    "logs.${data.aws_region.current.name}.amazonaws.com"
  ]
  service_principal_actions = [
    "kms:Encrypt*",
    "kms:Decrypt*",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:Describe*"
  ]
  additional_policy_statements = [
    {
      Sid    = "AllowCloudWatchLogsEncryptionContext"
      Effect = "Allow"
      Principal = {
        Service = "logs.${data.aws_region.current.name}.amazonaws.com"
      }
      Action = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      Resource = "*"
      Condition = {
        ArnLike = {
          "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/${var.resource_prefix}/*"
        }
      }
    }
  ]

  common_tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "deployments" {
  name              = "/${var.resource_prefix}/deployments/${var.deployment_name}"
  retention_in_days = 365
  kms_key_id        = module.kms_deployment_logs.key_arn

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# GuardDuty Findings Export - KMS Key (Log Archive Account)
# -----------------------------------------------------------------------------

module "kms_guardduty_findings" {
  source = "./modules/kms"
  count  = local.log_archive_exists ? 1 : 0

  alias_name  = "${var.resource_prefix}-guardduty-findings"
  description = "Encryption key for GuardDuty findings export bucket"

  service_principals = [
    "guardduty.amazonaws.com"
  ]
  service_principal_actions = [
    "kms:GenerateDataKey",
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:DescribeKey"
  ]

  common_tags = local.common_tags

  providers = {
    aws = aws.log_archive
  }
}

# -----------------------------------------------------------------------------
# GuardDuty Findings Export - S3 Bucket (Log Archive Account)
# -----------------------------------------------------------------------------

module "s3_guardduty_findings" {
  source = "./modules/s3"
  count  = local.log_archive_exists ? 1 : 0

  bucket_name = "${var.resource_prefix}-guardduty-findings-${var.log_archive_account_id}"
  kms_key_arn = module.kms_guardduty_findings[0].key_arn

  access_logging_enabled = var.access_logs_bucket_exists
  access_logging_bucket  = "${var.resource_prefix}-access-logs-${var.log_archive_account_id}"

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${var.resource_prefix}-guardduty-findings-${var.log_archive_account_id}",
          "arn:aws:s3:::${var.resource_prefix}-guardduty-findings-${var.log_archive_account_id}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowGuardDutyPutObject"
        Effect = "Allow"
        Principal = {
          Service = "guardduty.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.resource_prefix}-guardduty-findings-${var.log_archive_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowGuardDutyGetBucketLocation"
        Effect = "Allow"
        Principal = {
          Service = "guardduty.amazonaws.com"
        }
        Action   = "s3:GetBucketLocation"
        Resource = "arn:aws:s3:::${var.resource_prefix}-guardduty-findings-${var.log_archive_account_id}"
      }
    ]
  })

  lifecycle_rules = [
    {
      id     = "guardduty-findings-lifecycle"
      status = "Enabled"
      transitions = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
        },
        {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
      expiration_days = 730
    }
  ]

  common_tags = local.common_tags

  providers = {
    aws = aws.log_archive
  }
}
