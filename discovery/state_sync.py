#!/usr/bin/env python3
"""
GuardDuty Terraform State Sync Script.

Ensures existing GuardDuty resources are properly imported into Terraform state
before plan/apply runs.
"""

import json
import subprocess
import sys
import time
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

ALL_REGIONS = [
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-central-1",
    "eu-north-1",
    "ap-southeast-1",
    "ap-southeast-2",
    "ap-northeast-1",
    "ap-northeast-2",
    "ap-northeast-3",
    "ap-south-1",
    "ca-central-1",
    "sa-east-1",
]

# Number of retries for terraform import commands
IMPORT_RETRIES = 2
IMPORT_RETRY_DELAY = 5


def run_terraform_cmd(args: list, timeout: int = 120) -> tuple:
    """Run a terraform command and return (success, output)."""
    cmd = ["terraform"] + args
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd="/work/terraform",
            timeout=timeout,
        )
        output = result.stdout + result.stderr
        return result.returncode == 0, output
    except subprocess.TimeoutExpired:
        return False, f"Command timed out after {timeout}s: {' '.join(cmd)}"
    except Exception as e:
        return False, str(e)


def get_state_resources() -> set:
    """Get set of all resource addresses in current Terraform state."""
    success, output = run_terraform_cmd(["state", "list"])
    if success:
        return set(output.strip().split("\n")) if output.strip() else set()
    return set()


def resource_exists_in_state(address: str, state_resources: set) -> bool:
    """Check if a resource exists in the Terraform state."""
    return address in state_resources


def import_resource(address: str, resource_id: str) -> bool:
    """Import a resource into Terraform state with retries.

    Returns True if the resource was successfully imported or already exists.
    """
    for attempt in range(1, IMPORT_RETRIES + 1):
        success, output = run_terraform_cmd(["import", "-input=false", address, resource_id])
        if success:
            return True
        if "Resource already managed" in output:
            return True
        if attempt < IMPORT_RETRIES:
            print(f"    Retry {attempt}/{IMPORT_RETRIES - 1} after {IMPORT_RETRY_DELAY}s...")
            time.sleep(IMPORT_RETRY_DELAY)
    return False


def get_account_ids_from_tfvars() -> dict:
    """Get account IDs from bootstrap.auto.tfvars.json."""
    tfvars_path = Path("/work/terraform/bootstrap.auto.tfvars.json")
    result = {"management": "", "audit": ""}

    if tfvars_path.exists():
        try:
            with open(tfvars_path) as f:
                tfvars = json.load(f)
            result["management"] = tfvars.get("management_account_id", "")
            result["audit"] = tfvars.get("audit_account_id", "")
        except Exception:
            pass

    return result


def get_cross_account_session(account_id: str, region: str):
    """Get boto3 session for cross-account access via OrganizationAccountAccessRole."""
    sts = boto3.client("sts")
    try:
        response = sts.assume_role(
            RoleArn=f"arn:aws:iam::{account_id}:role/OrganizationAccountAccessRole",
            RoleSessionName="state-sync",
        )
        credentials = response["Credentials"]
        return boto3.Session(
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials["SessionToken"],
            region_name=region,
        )
    except ClientError as e:
        print(f"    Failed to assume role into {account_id}: {e}")
        return None


def region_to_module_suffix(region: str) -> str:
    """Convert region name to terraform module suffix (e.g., us-east-1 -> us_east_1)."""
    return region.replace("-", "_")


def warm_up_providers():
    """Run terraform refresh to initialize all provider credentials.

    Each terraform import command re-initializes all 51 providers. Running
    a refresh first caches provider credentials and validates connectivity,
    preventing import failures due to provider initialization issues.
    """
    print("\n=== Warming Up Terraform Providers ===\n")
    success, output = run_terraform_cmd(
        ["plan", "-refresh-only", "-input=false", "-compact-warnings"],
        timeout=300,
    )
    if success:
        print("  Provider initialization successful")
    else:
        # Extract meaningful error lines (skip plan output noise)
        error_lines = [line for line in output.split("\n") if "error" in line.lower() or "Error" in line]
        if error_lines:
            print("  Provider initialization warnings:")
            for line in error_lines[:5]:
                print(f"    {line.strip()}")
        else:
            print("  Provider initialization completed with warnings")


def sync_cloudwatch_log_group(state_resources: set):
    """Sync CloudWatch log group into Terraform state.

    The log group is pre-created by entrypoint.sh (via aws logs create-log-group)
    before Terraform runs to allow immediate logging. Terraform is the source of
    truth for retention, KMS encryption, and tags.
    """
    print("\n=== Syncing CloudWatch Log Group ===\n")

    tf_address = "aws_cloudwatch_log_group.deployments"

    if resource_exists_in_state(tf_address, state_resources):
        print("  Already in state, skipping")
        return

    tfvars_path = Path("/work/terraform/bootstrap.auto.tfvars.json")
    if not tfvars_path.exists():
        print("  No tfvars found, skipping")
        return

    with open(tfvars_path) as f:
        tfvars = json.load(f)

    resource_prefix = tfvars.get("resource_prefix", "")
    deployment_name = tfvars.get("deployment_name", "")
    if not resource_prefix or not deployment_name:
        print("  Missing resource_prefix or deployment_name, skipping")
        return

    log_group_name = f"/{resource_prefix}/deployments/{deployment_name}"

    print(f"  Importing {tf_address} ({log_group_name})...")
    if import_resource(tf_address, log_group_name):
        print("    Imported successfully")
    else:
        print("    Import failed (will be retried on next run)")


def sync_guardduty_org_admin(config: dict, state_resources: set):
    """Sync GuardDuty delegated administrator into Terraform state."""
    print("\n=== Syncing GuardDuty Delegated Admin ===\n")

    account_ids = get_account_ids_from_tfvars()

    if not account_ids["audit"]:
        print("  No audit account ID found, skipping")
        return

    audit_account_id = account_ids["audit"]
    imported_count = 0
    skipped_count = 0
    failed_count = 0

    for region in ALL_REGIONS:
        region_suffix = region_to_module_suffix(region)

        admin_tf_address = f"module.guardduty_org_{region_suffix}[0].aws_guardduty_organization_admin_account.main"

        if resource_exists_in_state(admin_tf_address, state_resources):
            skipped_count += 1
            continue

        gd_client = boto3.client("guardduty", region_name=region)

        try:
            response = gd_client.list_organization_admin_accounts()
            admin_accounts = response.get("AdminAccounts", [])
            is_delegated_admin = any(a["AdminAccountId"] == audit_account_id for a in admin_accounts)

            if is_delegated_admin:
                print(f"  Importing {admin_tf_address}...")
                if import_resource(admin_tf_address, audit_account_id):
                    print("    Imported successfully")
                    imported_count += 1
                else:
                    print(f"    Import failed for {region}")
                    failed_count += 1
        except ClientError as e:
            print(f"    Error checking {region}: {e}")
            failed_count += 1

    summary = f"\n  GuardDuty Delegated Admin: {imported_count} imported, {skipped_count} already in state"
    if failed_count:
        summary += f", {failed_count} failed"
    print(summary)


def sync_guardduty_detectors(config: dict, management_account_id: str, state_resources: set):
    """Sync GuardDuty detectors into Terraform state.

    Syncs both management and audit account detectors. Management account
    detectors use current credentials (no assume role). Audit account
    detectors use cross-account role assumption.
    """
    print("\n=== Syncing GuardDuty Detectors ===\n")

    account_ids = get_account_ids_from_tfvars()

    if not account_ids["audit"]:
        print("  No audit account ID found, skipping")
        return

    imported_count = 0
    skipped_count = 0
    failed_count = 0

    # Sync both management and audit account detectors
    accounts_to_sync = [
        ("mgmt", None),
        ("audit", account_ids["audit"]),
    ]

    for account_prefix, assume_account_id in accounts_to_sync:
        for region in ALL_REGIONS:
            region_suffix = region_to_module_suffix(region)
            tf_address = f"module.guardduty_{account_prefix}_{region_suffix}[0].aws_guardduty_detector.main"

            if resource_exists_in_state(tf_address, state_resources):
                skipped_count += 1
                continue

            # Management account uses current credentials, audit uses cross-account
            if assume_account_id:
                session = get_cross_account_session(assume_account_id, region)
                if not session:
                    failed_count += 1
                    continue
                gd_client = session.client("guardduty")
            else:
                gd_client = boto3.client("guardduty", region_name=region)

            try:
                response = gd_client.list_detectors()
                detector_ids = response.get("DetectorIds", [])

                if detector_ids:
                    detector_id = detector_ids[0]
                    print(f"  Importing {tf_address}...")
                    if import_resource(tf_address, detector_id):
                        print("    Imported successfully")
                        imported_count += 1
                    else:
                        print(f"    Import failed for {account_prefix}/{region}")
                        failed_count += 1
            except ClientError as e:
                print(f"    Error checking {account_prefix}/{region}: {e}")
                failed_count += 1

    summary = f"\n  GuardDuty Detectors: {imported_count} imported, {skipped_count} already in state"
    if failed_count:
        summary += f", {failed_count} failed"
    print(summary)


def sync_guardduty_publishing_destinations(state_resources: set):
    """Sync GuardDuty publishing destinations into Terraform state.

    Publishing destinations export findings to S3. These are configured on the
    audit account's detectors (one per region).
    """
    print("\n=== Syncing GuardDuty Publishing Destinations ===\n")

    account_ids = get_account_ids_from_tfvars()

    if not account_ids["audit"]:
        print("  No audit account ID found, skipping")
        return

    imported_count = 0
    skipped_count = 0
    failed_count = 0

    for region in ALL_REGIONS:
        region_suffix = region_to_module_suffix(region)
        tf_address = f"module.guardduty_audit_{region_suffix}[0].aws_guardduty_publishing_destination.findings[0]"

        if resource_exists_in_state(tf_address, state_resources):
            skipped_count += 1
            continue

        session = get_cross_account_session(account_ids["audit"], region)
        if not session:
            failed_count += 1
            continue
        gd_client = session.client("guardduty")

        try:
            detectors = gd_client.list_detectors()
            detector_ids = detectors.get("DetectorIds", [])

            if not detector_ids:
                continue

            detector_id = detector_ids[0]
            destinations = gd_client.list_publishing_destinations(DetectorId=detector_id)

            for dest in destinations.get("Destinations", []):
                if dest.get("DestinationType") == "S3":
                    dest_id = dest["DestinationId"]
                    import_id = f"{detector_id}:{dest_id}"
                    print(f"  Importing {tf_address}...")
                    if import_resource(tf_address, import_id):
                        print("    Imported successfully")
                        imported_count += 1
                    else:
                        print(f"    Import failed for {region}")
                        failed_count += 1
                    break
        except ClientError as e:
            print(f"    Error checking {region}: {e}")
            failed_count += 1

    summary = f"\n  GuardDuty Publishing Destinations: {imported_count} imported, {skipped_count} already in state"
    if failed_count:
        summary += f", {failed_count} failed"
    print(summary)


def main():
    """Main state sync function."""
    print("=" * 50)
    print("  GuardDuty State Sync")
    print("=" * 50)
    print("")

    # Load config
    config_path = Path("/work/config.yaml")
    if not config_path.exists():
        config_path = Path(__file__).parent.parent / "config.yaml"

    with open(config_path) as f:
        config = json.load(f) if str(config_path).endswith(".json") else __import__("yaml").safe_load(f)

    # Get management account ID
    sts = boto3.client("sts")
    account_id = sts.get_caller_identity()["Account"]

    # Get current Terraform state
    state_resources = get_state_resources()
    print(f"  Current state has {len(state_resources)} resources")

    # Warm up all providers before running imports. Each terraform import
    # command reinitializes all 51 providers. A refresh-only plan caches
    # credentials and prevents import failures on empty state.
    if len(state_resources) == 0:
        warm_up_providers()

    # Sync CloudWatch log group (pre-created by entrypoint.sh before Terraform)
    sync_cloudwatch_log_group(state_resources)

    # Sync GuardDuty delegated admin (management account)
    sync_guardduty_org_admin(config, state_resources)

    # Note: GuardDuty org config is NOT imported because the existing AWS state
    # has auto_enable = NONE. Importing it would force a destroy+recreate cycle
    # to change it to ALL. Letting Terraform create it fresh applies the correct
    # configuration directly.

    # Sync GuardDuty detectors
    sync_guardduty_detectors(config, account_id, state_resources)

    # Sync GuardDuty publishing destinations (findings export to S3)
    sync_guardduty_publishing_destinations(state_resources)

    print("\n" + "=" * 50)
    print("  State Sync Complete")
    print("=" * 50 + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
