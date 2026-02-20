# Variables for GuardDuty Enabler Module

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "findings_export_enabled" {
  description = "Whether to create a publishing destination for findings export"
  type        = bool
  default     = false
}

variable "findings_bucket_arn" {
  description = "S3 bucket ARN for GuardDuty findings export"
  type        = string
  default     = ""
}

variable "findings_kms_key_arn" {
  description = "KMS key ARN for encrypting GuardDuty findings export"
  type        = string
  default     = ""
}
