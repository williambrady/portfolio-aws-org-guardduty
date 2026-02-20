#!/usr/bin/env python3
"""
GuardDuty Organization Discovery Script.

Discovers existing GuardDuty organization configuration and generates
Terraform variables for the deployment.
"""

import json
import sys
from pathlib import Path

import boto3
import yaml
from botocore.exceptions import ClientError


def load_config() -> dict:
    """Load configuration from config.yaml."""
    config_path = Path("/work/config.yaml")
    if not config_path.exists():
        config_path = Path(__file__).parent.parent / "config.yaml"

    if not config_path.exists():
        print("Error: config.yaml not found")
        sys.exit(1)

    with open(config_path) as f:
        return yaml.safe_load(f)


def discover_guardduty_org_config(primary_region: str, audit_account_id: str) -> dict:
    """Discover existing GuardDuty organization configuration.

    Returns information about GuardDuty organization status:
    - Whether GuardDuty is enabled organization-wide
    - The delegated admin account ID
    - Whether auto-enable is configured
    """
    result = {
        "guardduty_org_exists": False,
        "guardduty_delegated_admin": "",
        "guardduty_auto_enable": False,
        "guardduty_s3_protection": False,
        "guardduty_eks_protection": False,
        "guardduty_malware_protection": False,
    }

    try:
        org_client = boto3.client("organizations", region_name=primary_region)
        try:
            response = org_client.list_delegated_administrators(ServicePrincipal="guardduty.amazonaws.com")
            admins = response.get("DelegatedAdministrators", [])
            if admins:
                result["guardduty_delegated_admin"] = admins[0]["Id"]
                result["guardduty_org_exists"] = True
                print(f"    Delegated Admin: {result['guardduty_delegated_admin']}")

                if result["guardduty_delegated_admin"] == audit_account_id:
                    try:
                        sts_client = boto3.client("sts", region_name=primary_region)
                        assumed = sts_client.assume_role(
                            RoleArn=f"arn:aws:iam::{audit_account_id}:role/OrganizationAccountAccessRole",
                            RoleSessionName="guardduty-discovery",
                        )
                        creds = assumed["Credentials"]
                        audit_guardduty = boto3.client(
                            "guardduty",
                            region_name=primary_region,
                            aws_access_key_id=creds["AccessKeyId"],
                            aws_secret_access_key=creds["SecretAccessKey"],
                            aws_session_token=creds["SessionToken"],
                        )

                        detectors = audit_guardduty.list_detectors()
                        if detectors.get("DetectorIds"):
                            detector_id = detectors["DetectorIds"][0]

                            org_config = audit_guardduty.describe_organization_configuration(DetectorId=detector_id)
                            result["guardduty_auto_enable"] = (
                                org_config.get("AutoEnable", False)
                                or org_config.get("AutoEnableOrganizationMembers", "") == "ALL"
                            )

                            datasources = org_config.get("DataSources", {})
                            s3_logs = datasources.get("S3Logs", {})
                            result["guardduty_s3_protection"] = s3_logs.get("AutoEnable", False)

                            kubernetes = datasources.get("Kubernetes", {})
                            audit_logs = kubernetes.get("AuditLogs", {})
                            result["guardduty_eks_protection"] = audit_logs.get("AutoEnable", False)

                            malware = datasources.get("MalwareProtection", {})
                            scan_ec2 = malware.get("ScanEc2InstanceWithFindings", {})
                            ebs = scan_ec2.get("EbsVolumes", {})
                            result["guardduty_malware_protection"] = ebs.get("AutoEnable", False)

                            enabled = []
                            if result["guardduty_auto_enable"]:
                                enabled.append("AutoEnable=ALL")
                            if result["guardduty_s3_protection"]:
                                enabled.append("S3")
                            if result["guardduty_eks_protection"]:
                                enabled.append("EKS")
                            if result["guardduty_malware_protection"]:
                                enabled.append("Malware")
                            if enabled:
                                print(f"    Protection plans: {', '.join(enabled)}")
                            else:
                                print("    Protection plans: None auto-enabled")
                    except ClientError as e:
                        print(f"    Warning: Could not check org config from audit account: {e}")
            else:
                print("    Delegated Admin: None configured")
        except ClientError as e:
            if "AccessDenied" not in str(e):
                print(f"    Warning: Could not list delegated admins: {e}")

    except ClientError as e:
        print(f"    Warning: Could not check GuardDuty status: {e}")

    return result


def read_ssm_org_config(resource_prefix: str, region: str) -> dict:
    """Read org-baseline configuration from SSM Parameter Store.

    Returns the parsed JSON config dict, or empty dict if unavailable.
    """
    ssm_path = f"/{resource_prefix}/org-baseline/config"
    try:
        ssm = boto3.client("ssm", region_name=region)
        response = ssm.get_parameter(Name=ssm_path, WithDecryption=True)
        value = json.loads(response["Parameter"]["Value"])
        print(f"SSM Parameter: {ssm_path}")
        print("    Source: portfolio-aws-org-baseline")
        return value
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "ParameterNotFound":
            print(f"SSM Parameter: {ssm_path} (not found)")
            print("    Falling back to config.yaml values")
        else:
            print(f"SSM Parameter: {ssm_path} (error: {code})")
            print("    Falling back to config.yaml values")
        return {}


def main():
    """Main discovery function."""
    print("=" * 50)
    print("  GuardDuty Organization Discovery")
    print("=" * 50)
    print("")

    # Load configuration
    config = load_config()
    resource_prefix = config.get("resource_prefix", "")

    if not resource_prefix:
        print("Error: resource_prefix is required in config.yaml")
        return 1

    # Get caller identity (needed before SSM call to determine region)
    initial_region = config.get("primary_region", "us-east-1")
    sts = boto3.client("sts", region_name=initial_region)
    identity = sts.get_caller_identity()
    management_account_id = identity["Account"]

    # Read org-baseline config from SSM Parameter Store
    ssm_config = read_ssm_org_config(resource_prefix, initial_region)

    # Merge: SSM values take precedence, config.yaml provides overrides/fallbacks
    primary_region = config.get("primary_region") or ssm_config.get("primary_region", "us-east-1")
    audit_account_id = config.get("audit_account_id") or ssm_config.get("audit_account_id", "")
    log_archive_account_id = ssm_config.get("log_archive_account_id", "")
    organization_id = ssm_config.get("organization_id", "")
    custom_tags = ssm_config.get("tags", config.get("tags", {}))

    print(f"Management Account: {management_account_id}")
    print(f"Primary Region: {primary_region}")
    print(f"Audit Account: {audit_account_id or '(not configured)'}")
    if log_archive_account_id:
        print(f"Log Archive Account: {log_archive_account_id}")
    if organization_id:
        print(f"Organization ID: {organization_id}")
    print("")

    # Discover GuardDuty organization configuration
    discovery = {}

    print("GuardDuty Organization:")
    if not audit_account_id:
        print("    ERROR: audit_account_id not available")
        print("    Ensure org-baseline SSM parameter exists or set audit_account_id in config.yaml")
        print("")
        print("This project requires portfolio-aws-org-baseline to be deployed first.")
        return 1

    guardduty_info = discover_guardduty_org_config(primary_region, audit_account_id)
    discovery.update(guardduty_info)

    if not guardduty_info["guardduty_org_exists"]:
        print("    ERROR: GuardDuty delegated admin is not registered")
        print("")
        print("The GuardDuty delegated admin must be registered by portfolio-aws-org-baseline")
        print("before this project can run. Deploy portfolio-aws-org-baseline first.")
        return 1

    if guardduty_info["guardduty_delegated_admin"] != audit_account_id:
        print("    ERROR: Delegated admin mismatch")
        print(f"    Expected: {audit_account_id}")
        print(f"    Actual:   {guardduty_info['guardduty_delegated_admin']}")
        return 1

    print("")

    # Check for access logs bucket in log-archive account (created by org-baseline)
    access_logs_bucket_exists = False
    if log_archive_account_id:
        access_logs_bucket_name = f"{resource_prefix}-access-logs-{log_archive_account_id}"
        print("Access Logs Bucket:")
        try:
            sts_client = boto3.client("sts", region_name=primary_region)
            assumed = sts_client.assume_role(
                RoleArn=f"arn:aws:iam::{log_archive_account_id}:role/OrganizationAccountAccessRole",
                RoleSessionName="guardduty-discovery-s3",
            )
            creds = assumed["Credentials"]
            s3_client = boto3.client(
                "s3",
                region_name=primary_region,
                aws_access_key_id=creds["AccessKeyId"],
                aws_secret_access_key=creds["SecretAccessKey"],
                aws_session_token=creds["SessionToken"],
            )
            s3_client.head_bucket(Bucket=access_logs_bucket_name)
            access_logs_bucket_exists = True
            print(f"    {access_logs_bucket_name} exists")
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            if error_code in ("404", "NoSuchBucket"):
                print(f"    WARNING: {access_logs_bucket_name} not found")
                print("    Findings bucket will be created without access logging")
                print("    Deploy portfolio-aws-org-baseline first to create the access logs bucket")
            else:
                print(f"    WARNING: Could not check bucket: {e}")
                print("    Findings bucket will be created without access logging")
        print("")

    # Look up log-archive account email for GuardDuty member enrollment
    # (Management account is excluded - org owner cannot be enrolled as a member)
    log_archive_account_email = ""
    if log_archive_account_id:
        print("Account Emails (for GuardDuty member enrollment):")
        try:
            org_client = boto3.client("organizations", region_name=primary_region)
            response = org_client.describe_account(AccountId=log_archive_account_id)
            log_archive_account_email = response["Account"]["Email"]
            print(f"    Log Archive: {log_archive_account_email}")
        except ClientError as e:
            print(f"    WARNING: Could not look up log-archive email: {e}")
            print("    GuardDuty member enrollment will be skipped")
        print("")

    # Write discovery.json
    discovery_path = Path("/work/terraform/discovery.json")
    if not discovery_path.parent.exists():
        discovery_path = Path(__file__).parent.parent / "terraform" / "discovery.json"

    with open(discovery_path, "w") as f:
        json.dump(discovery, f, indent=2, default=str)
    print(f"Discovery output written to {discovery_path}")

    # Generate bootstrap.auto.tfvars.json
    deployment_name = config.get("deployment_name", "portfolio-aws-org-guardduty")

    tfvars = {
        "primary_region": primary_region,
        "resource_prefix": resource_prefix,
        "deployment_name": deployment_name,
        "management_account_id": management_account_id,
        "audit_account_id": audit_account_id,
        "log_archive_account_id": log_archive_account_id,
        "log_archive_account_email": log_archive_account_email,
        "access_logs_bucket_exists": access_logs_bucket_exists,
        "custom_tags": custom_tags,
    }

    tfvars_path = Path("/work/terraform/bootstrap.auto.tfvars.json")
    if not tfvars_path.parent.exists():
        tfvars_path = Path(__file__).parent.parent / "terraform" / "bootstrap.auto.tfvars.json"

    with open(tfvars_path, "w") as f:
        json.dump(tfvars, f, indent=2)
    print(f"Terraform variables written to {tfvars_path}")

    print("")
    print("=" * 50)
    print("  Discovery Complete")
    print("=" * 50)
    print("")

    return 0


if __name__ == "__main__":
    sys.exit(main())
