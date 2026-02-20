# Outputs for GuardDuty Organization Deployment

output "delegated_admin_account_id" {
  description = "The audit account ID configured as GuardDuty delegated administrator"
  value       = var.audit_account_id
}

output "regions_configured" {
  description = "Number of regions where GuardDuty is configured"
  value       = local.accounts_exist ? 17 : 0
}

output "deployment_log_group" {
  description = "CloudWatch log group for deployment logs"
  value       = aws_cloudwatch_log_group.deployments.name
}

output "findings_bucket_name" {
  description = "S3 bucket name for GuardDuty findings export"
  value       = local.log_archive_exists ? module.s3_guardduty_findings[0].bucket_id : ""
}

output "findings_kms_key_arn" {
  description = "KMS key ARN used for GuardDuty findings encryption"
  value       = local.log_archive_exists ? module.kms_guardduty_findings[0].key_arn : ""
}

output "guardduty_summary" {
  description = "Summary of GuardDuty organization configuration"
  value = {
    delegated_admin    = var.audit_account_id
    regions_configured = local.accounts_exist ? 17 : 0
    management_account = data.aws_caller_identity.current.account_id
    findings_bucket    = local.log_archive_exists ? module.s3_guardduty_findings[0].bucket_id : ""
  }
}
