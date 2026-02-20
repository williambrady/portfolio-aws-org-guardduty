# AWS GuardDuty Organization Module
# Designates an audit account as the GuardDuty delegated administrator
#
# This module must be called from the MANAGEMENT account context.
# It enables the specified audit account as the organization admin for GuardDuty.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# GuardDuty Delegated Administrator
# -----------------------------------------------------------------------------

resource "aws_guardduty_organization_admin_account" "main" {
  admin_account_id = var.audit_account_id

  lifecycle {
    ignore_changes = [admin_account_id]
  }
}
