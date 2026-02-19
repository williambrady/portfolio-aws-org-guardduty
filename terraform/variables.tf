# Variables for GuardDuty Organization Deployment

variable "primary_region" {
  description = "Primary AWS region for state and finding aggregation"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for all AWS resource names"
  type        = string
}

variable "deployment_name" {
  description = "Deployment name used for CloudWatch log group naming"
  type        = string
}

variable "management_account_id" {
  description = "AWS account ID of the management account (auto-discovered from caller identity)"
  type        = string
  default     = ""
}

variable "audit_account_id" {
  description = "AWS account ID of the audit account (delegated administrator for GuardDuty)"
  type        = string
  default     = ""
}

variable "log_archive_account_id" {
  description = "AWS account ID of the log archive account (auto-discovered from org-baseline SSM parameter)"
  type        = string
  default     = ""
}

variable "access_logs_bucket_exists" {
  description = "Whether the access logs bucket exists in the log-archive account (auto-discovered)"
  type        = bool
  default     = false
}

variable "custom_tags" {
  description = "Custom tags applied to all resources (auto-discovered from org-baseline SSM parameter)"
  type        = map(string)
  default     = {}
}
