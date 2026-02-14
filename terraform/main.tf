# GuardDuty Organization Deployment
# Manages GuardDuty across all regions in an AWS Organization

data "aws_caller_identity" "current" {}

locals {
  accounts_exist = var.audit_account_id != ""
}
