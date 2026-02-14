# Variables for GuardDuty Organization Deployment

variable "primary_region" {
  description = "Primary AWS region for state and finding aggregation"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for all AWS resource names"
  type        = string
}

variable "audit_account_id" {
  description = "AWS account ID of the audit account (delegated administrator for GuardDuty)"
  type        = string
  default     = ""
}

variable "management_account_id" {
  description = "AWS account ID of the management account (auto-detected if empty)"
  type        = string
  default     = ""
}

variable "guardduty_org_exists" {
  description = "Whether GuardDuty organization configuration already exists"
  type        = bool
  default     = false
}

variable "guardduty_delegated_admin" {
  description = "Existing GuardDuty delegated admin account ID (empty if none)"
  type        = string
  default     = ""
}
