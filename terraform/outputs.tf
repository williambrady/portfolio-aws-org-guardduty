# Outputs for GuardDuty Organization Deployment

output "delegated_admin_account_id" {
  description = "The audit account ID configured as GuardDuty delegated administrator"
  value       = var.audit_account_id
}

output "regions_configured" {
  description = "Number of regions where GuardDuty is configured"
  value       = local.accounts_exist ? 17 : 0
}

output "guardduty_summary" {
  description = "Summary of GuardDuty organization configuration"
  value = {
    delegated_admin    = var.audit_account_id
    regions_configured = local.accounts_exist ? 17 : 0
    management_account = data.aws_caller_identity.current.account_id
  }
}
