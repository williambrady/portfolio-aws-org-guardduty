# GuardDuty - Multi-Region Deployment
# Enables GuardDuty organization configuration across all regions
#
# Architecture:
# - guardduty-org module: Called from management account to designate delegated admin
# - guardduty-enabler module: Called for management + audit accounts (explicit detectors)
# - guardduty-org-config module: Called from audit account to configure auto-enable
#   and enroll log-archive as a member
#
# The management account is the org OWNER and cannot be enrolled as a GuardDuty
# member (CreateMembers API silently drops it). It gets direct detectors instead.
# The audit account (delegated admin) also requires an explicit detector.
# Log-archive is enrolled as a member by the org-config module.

# =============================================================================
# GuardDuty Delegated Administrator (Management Account)
# =============================================================================
# Designates audit account as GuardDuty delegated administrator.
# MUST run from management account context.

module "guardduty_org_us_east_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_us_east_2" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.us_east_2
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_us_west_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.us_west_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_us_west_2" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.us_west_2
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_eu_west_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.eu_west_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_eu_west_2" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.eu_west_2
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_eu_west_3" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.eu_west_3
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_eu_central_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.eu_central_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_eu_north_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.eu_north_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_ap_southeast_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.ap_southeast_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_ap_southeast_2" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.ap_southeast_2
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_ap_northeast_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.ap_northeast_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_ap_northeast_2" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.ap_northeast_2
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_ap_northeast_3" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.ap_northeast_3
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_ap_south_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.ap_south_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_ca_central_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.ca_central_1
  }

  audit_account_id = local.audit_account_id
}

module "guardduty_org_sa_east_1" {
  source = "./modules/guardduty-org"
  count  = local.accounts_exist ? 1 : 0

  providers = {
    aws = aws.sa_east_1
  }

  audit_account_id = local.audit_account_id
}

# =============================================================================
# Audit Account - GuardDuty Detectors (Delegated Admin)
# =============================================================================
# The audit account needs an explicit detector as the delegated administrator.
# This detector is referenced by the org-config module's data source.

module "guardduty_audit_us_east_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit
  }

  depends_on = [module.guardduty_org_us_east_1]
}

module "guardduty_audit_us_east_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_us_east_2
  }

  depends_on = [module.guardduty_org_us_east_2]
}

module "guardduty_audit_us_west_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_us_west_1
  }

  depends_on = [module.guardduty_org_us_west_1]
}

module "guardduty_audit_us_west_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_us_west_2
  }

  depends_on = [module.guardduty_org_us_west_2]
}

module "guardduty_audit_eu_west_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_eu_west_1
  }

  depends_on = [module.guardduty_org_eu_west_1]
}

module "guardduty_audit_eu_west_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_eu_west_2
  }

  depends_on = [module.guardduty_org_eu_west_2]
}

module "guardduty_audit_eu_west_3" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_eu_west_3
  }

  depends_on = [module.guardduty_org_eu_west_3]
}

module "guardduty_audit_eu_central_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_eu_central_1
  }

  depends_on = [module.guardduty_org_eu_central_1]
}

module "guardduty_audit_eu_north_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_eu_north_1
  }

  depends_on = [module.guardduty_org_eu_north_1]
}

module "guardduty_audit_ap_southeast_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_ap_southeast_1
  }

  depends_on = [module.guardduty_org_ap_southeast_1]
}

module "guardduty_audit_ap_southeast_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_ap_southeast_2
  }

  depends_on = [module.guardduty_org_ap_southeast_2]
}

module "guardduty_audit_ap_northeast_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_ap_northeast_1
  }

  depends_on = [module.guardduty_org_ap_northeast_1]
}

module "guardduty_audit_ap_northeast_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_ap_northeast_2
  }

  depends_on = [module.guardduty_org_ap_northeast_2]
}

module "guardduty_audit_ap_northeast_3" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_ap_northeast_3
  }

  depends_on = [module.guardduty_org_ap_northeast_3]
}

module "guardduty_audit_ap_south_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_ap_south_1
  }

  depends_on = [module.guardduty_org_ap_south_1]
}

module "guardduty_audit_ca_central_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_ca_central_1
  }

  depends_on = [module.guardduty_org_ca_central_1]
}

module "guardduty_audit_sa_east_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags             = local.common_tags
  findings_export_enabled = local.log_archive_exists
  findings_bucket_arn     = local.findings_bucket_arn
  findings_kms_key_arn    = local.findings_kms_key_arn

  providers = {
    aws = aws.audit_sa_east_1
  }

  depends_on = [module.guardduty_org_sa_east_1]
}

# =============================================================================
# Management Account - GuardDuty Detectors (Direct)
# =============================================================================
# The management account is the org OWNER, not a member. It cannot be enrolled
# via aws_guardduty_member (the CreateMembers API silently drops it). Instead,
# we create detectors directly using management account providers.

module "guardduty_mgmt_us_east_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws
  }

  depends_on = [module.guardduty_org_us_east_1]
}

module "guardduty_mgmt_us_east_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.us_east_2
  }

  depends_on = [module.guardduty_org_us_east_2]
}

module "guardduty_mgmt_us_west_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.us_west_1
  }

  depends_on = [module.guardduty_org_us_west_1]
}

module "guardduty_mgmt_us_west_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.us_west_2
  }

  depends_on = [module.guardduty_org_us_west_2]
}

module "guardduty_mgmt_eu_west_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.eu_west_1
  }

  depends_on = [module.guardduty_org_eu_west_1]
}

module "guardduty_mgmt_eu_west_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.eu_west_2
  }

  depends_on = [module.guardduty_org_eu_west_2]
}

module "guardduty_mgmt_eu_west_3" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.eu_west_3
  }

  depends_on = [module.guardduty_org_eu_west_3]
}

module "guardduty_mgmt_eu_central_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.eu_central_1
  }

  depends_on = [module.guardduty_org_eu_central_1]
}

module "guardduty_mgmt_eu_north_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.eu_north_1
  }

  depends_on = [module.guardduty_org_eu_north_1]
}

module "guardduty_mgmt_ap_southeast_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.ap_southeast_1
  }

  depends_on = [module.guardduty_org_ap_southeast_1]
}

module "guardduty_mgmt_ap_southeast_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.ap_southeast_2
  }

  depends_on = [module.guardduty_org_ap_southeast_2]
}

module "guardduty_mgmt_ap_northeast_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.ap_northeast_1
  }

  depends_on = [module.guardduty_org_ap_northeast_1]
}

module "guardduty_mgmt_ap_northeast_2" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.ap_northeast_2
  }

  depends_on = [module.guardduty_org_ap_northeast_2]
}

module "guardduty_mgmt_ap_northeast_3" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.ap_northeast_3
  }

  depends_on = [module.guardduty_org_ap_northeast_3]
}

module "guardduty_mgmt_ap_south_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.ap_south_1
  }

  depends_on = [module.guardduty_org_ap_south_1]
}

module "guardduty_mgmt_ca_central_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.ca_central_1
  }

  depends_on = [module.guardduty_org_ca_central_1]
}

module "guardduty_mgmt_sa_east_1" {
  source = "./modules/guardduty-enabler"

  count = local.accounts_exist ? 1 : 0

  common_tags = local.common_tags

  providers = {
    aws = aws.sa_east_1
  }

  depends_on = [module.guardduty_org_sa_east_1]
}

# =============================================================================
# GuardDuty Organization Configuration + Member Enrollment
# (Audit Account - Delegated Admin)
# =============================================================================
# Configures auto-enable and protection plan settings, then enrolls
# log-archive as a GuardDuty member. The management account gets direct
# detectors above (org owner cannot be enrolled as a member).
# MUST run from AUDIT account (delegated admin).

module "guardduty_org_config_us_east_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit
  }

  depends_on = [module.guardduty_audit_us_east_1]
}

module "guardduty_org_config_us_east_2" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_us_east_2
  }

  depends_on = [module.guardduty_audit_us_east_2]
}

module "guardduty_org_config_us_west_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_us_west_1
  }

  depends_on = [module.guardduty_audit_us_west_1]
}

module "guardduty_org_config_us_west_2" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_us_west_2
  }

  depends_on = [module.guardduty_audit_us_west_2]
}

module "guardduty_org_config_eu_west_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_eu_west_1
  }

  depends_on = [module.guardduty_audit_eu_west_1]
}

module "guardduty_org_config_eu_west_2" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_eu_west_2
  }

  depends_on = [module.guardduty_audit_eu_west_2]
}

module "guardduty_org_config_eu_west_3" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_eu_west_3
  }

  depends_on = [module.guardduty_audit_eu_west_3]
}

module "guardduty_org_config_eu_central_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_eu_central_1
  }

  depends_on = [module.guardduty_audit_eu_central_1]
}

module "guardduty_org_config_eu_north_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_eu_north_1
  }

  depends_on = [module.guardduty_audit_eu_north_1]
}

module "guardduty_org_config_ap_southeast_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_ap_southeast_1
  }

  depends_on = [module.guardduty_audit_ap_southeast_1]
}

module "guardduty_org_config_ap_southeast_2" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_ap_southeast_2
  }

  depends_on = [module.guardduty_audit_ap_southeast_2]
}

module "guardduty_org_config_ap_northeast_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_ap_northeast_1
  }

  depends_on = [module.guardduty_audit_ap_northeast_1]
}

module "guardduty_org_config_ap_northeast_2" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_ap_northeast_2
  }

  depends_on = [module.guardduty_audit_ap_northeast_2]
}

module "guardduty_org_config_ap_northeast_3" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_ap_northeast_3
  }

  depends_on = [module.guardduty_audit_ap_northeast_3]
}

module "guardduty_org_config_ap_south_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_ap_south_1
  }

  depends_on = [module.guardduty_audit_ap_south_1]
}

module "guardduty_org_config_ca_central_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_ca_central_1
  }

  depends_on = [module.guardduty_audit_ca_central_1]
}

module "guardduty_org_config_sa_east_1" {
  source = "./modules/guardduty-org-config"
  count  = local.accounts_exist ? 1 : 0

  member_accounts = local.guardduty_member_accounts

  providers = {
    aws = aws.audit_sa_east_1
  }

  depends_on = [module.guardduty_audit_sa_east_1]
}
