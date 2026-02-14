#!/usr/bin/env python3
"""
GuardDuty Terraform State Sync Script.

Ensures existing GuardDuty resources are properly imported into Terraform state
before plan/apply runs.
"""

import json
import subprocess
import sys
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


def run_terraform_cmd(args: list) -> tuple:
    """Run a terraform command and return (success, output)."""
    cmd = ["terraform"] + args
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd="/work/terraform",
        )
        output = result.stdout + result.stderr
        return result.returncode == 0, output
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
    """Import a resource into Terraform state."""
    success, output = run_terraform_cmd(["import", address, resource_id])
    if success:
        return True
    if "Resource already managed" in output:
        return True
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
    except ClientError:
        return None


def region_to_module_suffix(region: str) -> str:
    """Convert region name to terraform module suffix (e.g., us-east-1 -> us_east_1)."""
    return region.replace("-", "_")


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
            is_delegated_admin = any(
                a["AdminAccountId"] == audit_account_id for a in admin_accounts
            )

            if is_delegated_admin:
                print(f"  Importing {admin_tf_address}...")
                success, output = run_terraform_cmd(
                    ["import", admin_tf_address, audit_account_id]
                )
                if success:
                    print("    Imported successfully")
                    imported_count += 1
                elif "Resource already managed" in output:
                    skipped_count += 1
                else:
                    print(f"    Import failed: {output[:200]}")
        except ClientError:
            pass

    print(
        f"\n  GuardDuty Delegated Admin: {imported_count} imported, {skipped_count} already in state"
    )


def sync_guardduty_org_config(config: dict, state_resources: set):
    """Sync GuardDuty organization configuration into Terraform state."""
    print("\n=== Syncing GuardDuty Org Config ===\n")

    imported_count = 0
    skipped_count = 0

    for region in ALL_REGIONS:
        region_suffix = region_to_module_suffix(region)

        org_config_tf_address = f"module.guardduty_org_config_{region_suffix}[0].aws_guardduty_organization_configuration.main"

        if resource_exists_in_state(org_config_tf_address, state_resources):
            skipped_count += 1
            continue

        gd_client = boto3.client("guardduty", region_name=region)

        try:
            detector_response = gd_client.list_detectors()
            detector_ids = detector_response.get("DetectorIds", [])
            if detector_ids:
                detector_id = detector_ids[0]
                try:
                    gd_client.describe_organization_configuration(
                        DetectorId=detector_id
                    )
                    print(f"  Importing {org_config_tf_address}...")
                    success, output = run_terraform_cmd(
                        ["import", org_config_tf_address, detector_id]
                    )
                    if success:
                        print("    Imported successfully")
                        imported_count += 1
                    elif "Resource already managed" in output:
                        skipped_count += 1
                    else:
                        print(f"    Import failed: {output[:200]}")
                except ClientError:
                    pass
        except ClientError:
            pass

    print(
        f"\n  GuardDuty Org Config: {imported_count} imported, {skipped_count} already in state"
    )


def sync_guardduty_detectors(
    config: dict, management_account_id: str, state_resources: set
):
    """Sync GuardDuty detectors into Terraform state.

    Only syncs audit account detectors - management and log_archive accounts
    are auto-enrolled by the organization configuration.
    """
    print("\n=== Syncing GuardDuty Detectors ===\n")

    account_ids = get_account_ids_from_tfvars()

    if not account_ids["audit"]:
        print("  No audit account ID found, skipping")
        return

    imported_count = 0
    skipped_count = 0

    account_prefix = "audit"
    assume_account_id = account_ids["audit"]

    for region in ALL_REGIONS:
        region_suffix = region_to_module_suffix(region)
        tf_address = f"module.guardduty_{account_prefix}_{region_suffix}[0].aws_guardduty_detector.main"

        if resource_exists_in_state(tf_address, state_resources):
            skipped_count += 1
            continue

        session = get_cross_account_session(assume_account_id, region)
        if not session:
            continue
        gd_client = session.client("guardduty")

        try:
            response = gd_client.list_detectors()
            detector_ids = response.get("DetectorIds", [])

            if detector_ids:
                detector_id = detector_ids[0]
                print(f"  Importing {tf_address}...")
                success, output = run_terraform_cmd(
                    ["import", tf_address, detector_id]
                )
                if success:
                    print("    Imported successfully")
                    imported_count += 1
                elif "Resource already managed" in output:
                    print("    Already in state")
                    skipped_count += 1
                else:
                    print(f"    Import failed: {output[:200]}")
        except ClientError:
            pass

    print(
        f"\n  GuardDuty Detectors: {imported_count} imported, {skipped_count} already in state"
    )


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

    # Sync GuardDuty delegated admin (management account)
    sync_guardduty_org_admin(config, state_resources)

    # Sync GuardDuty org config (audit account)
    sync_guardduty_org_config(config, state_resources)

    # Sync GuardDuty detectors
    sync_guardduty_detectors(config, account_id, state_resources)

    print("\n" + "=" * 50)
    print("  State Sync Complete")
    print("=" * 50 + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
