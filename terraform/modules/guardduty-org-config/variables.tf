# Variables for GuardDuty Organization Configuration Module

variable "member_accounts" {
  description = "Accounts to enroll as GuardDuty members via the delegated admin"
  type = list(object({
    account_id = string
    email      = string
  }))
  default = []
}
