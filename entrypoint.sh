#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "============================================"
echo "  GuardDuty Organization Deployment"
echo "============================================"
echo ""

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Please provide AWS credentials via:"
    echo "  - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
    echo "  - Mounted ~/.aws directory with AWS_PROFILE set"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo -e "${GREEN}Authenticated to account: ${ACCOUNT_ID}${NC}"
echo -e "${GREEN}Caller: ${CALLER_ARN}${NC}"
echo ""

# Load configuration from config.yaml
echo -e "${YELLOW}Loading configuration...${NC}"

PRIMARY_REGION=$(python3 -c "import yaml; print(yaml.safe_load(open('/work/config.yaml'))['primary_region'])" 2>/dev/null || echo "us-east-1")
RESOURCE_PREFIX=$(python3 -c "import yaml; print(yaml.safe_load(open('/work/config.yaml'))['resource_prefix'])" 2>/dev/null)
if [ -z "${RESOURCE_PREFIX}" ]; then
    echo -e "${RED}Error: resource_prefix is required in config.yaml${NC}"
    exit 1
fi
echo -e "${GREEN}Primary region: ${PRIMARY_REGION}${NC}"
echo -e "${GREEN}Resource prefix: ${RESOURCE_PREFIX}${NC}"
echo ""

# State bucket configuration
STATE_BUCKET="${RESOURCE_PREFIX}-guardduty-tfstate-${ACCOUNT_ID}"
STATE_KEY="guardduty/terraform.tfstate"
STATE_REGION="${PRIMARY_REGION}"

# Step 1: Create state bucket if it doesn't exist (bootstrap only)
echo -e "${YELLOW}Checking Terraform state bucket...${NC}"
if ! aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    echo -e "${YELLOW}Creating state bucket: ${STATE_BUCKET}${NC}"

    # Create KMS key for state bucket
    echo -e "${YELLOW}Creating KMS key for state bucket...${NC}"
    KMS_KEY_ID=$(aws kms create-key \
        --description "KMS key for GuardDuty Terraform state bucket encryption" \
        --tags TagKey=Name,TagValue=${RESOURCE_PREFIX}-guardduty-tfstate-key \
               TagKey=Purpose,TagValue="S3 bucket encryption" \
               TagKey=ProtectsBucket,TagValue="${STATE_BUCKET}" \
               TagKey=ManagedBy,TagValue=portfolio-aws-org-guardduty \
        --region "${STATE_REGION}" \
        --query 'KeyMetadata.KeyId' \
        --output text \
        --no-cli-pager)

    # Create alias for the key
    aws kms create-alias \
        --alias-name "alias/${RESOURCE_PREFIX}-guardduty-tfstate" \
        --target-key-id "${KMS_KEY_ID}" \
        --region "${STATE_REGION}" \
        --no-cli-pager

    # Enable key rotation
    aws kms enable-key-rotation \
        --key-id "${KMS_KEY_ID}" \
        --region "${STATE_REGION}" \
        --no-cli-pager

    KMS_KEY_ARN="arn:aws:kms:${STATE_REGION}:${ACCOUNT_ID}:key/${KMS_KEY_ID}"

    # Create bucket (us-east-1 doesn't use LocationConstraint)
    if [ "${STATE_REGION}" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "${STATE_BUCKET}" \
            --region "${STATE_REGION}" \
            --no-cli-pager
    else
        aws s3api create-bucket \
            --bucket "${STATE_BUCKET}" \
            --region "${STATE_REGION}" \
            --create-bucket-configuration LocationConstraint="${STATE_REGION}" \
            --no-cli-pager
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${STATE_BUCKET}" \
        --versioning-configuration Status=Enabled \
        --no-cli-pager

    # Enable KMS encryption
    aws s3api put-bucket-encryption \
        --bucket "${STATE_BUCKET}" \
        --server-side-encryption-configuration "{
            \"Rules\": [{
                \"ApplyServerSideEncryptionByDefault\": {
                    \"SSEAlgorithm\": \"aws:kms\",
                    \"KMSMasterKeyID\": \"${KMS_KEY_ARN}\"
                },
                \"BucketKeyEnabled\": true
            }]
        }" \
        --no-cli-pager

    # Block public access
    aws s3api put-public-access-block \
        --bucket "${STATE_BUCKET}" \
        --public-access-block-configuration '{
            "BlockPublicAcls": true,
            "IgnorePublicAcls": true,
            "BlockPublicPolicy": true,
            "RestrictPublicBuckets": true
        }' \
        --no-cli-pager

    # Add bucket policy for SSL enforcement
    aws s3api put-bucket-policy \
        --bucket "${STATE_BUCKET}" \
        --policy "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Sid\": \"DenyNonSSL\",
                    \"Effect\": \"Deny\",
                    \"Principal\": \"*\",
                    \"Action\": \"s3:*\",
                    \"Resource\": [
                        \"arn:aws:s3:::${STATE_BUCKET}\",
                        \"arn:aws:s3:::${STATE_BUCKET}/*\"
                    ],
                    \"Condition\": {
                        \"Bool\": {
                            \"aws:SecureTransport\": \"false\"
                        }
                    }
                }
            ]
        }" \
        --no-cli-pager

    echo -e "${GREEN}State bucket created with KMS encryption${NC}"
else
    echo -e "${GREEN}State bucket exists${NC}"
fi
echo ""

# Parse command line arguments
ACTION="${1:-apply}"
TERRAFORM_ARGS="${@:2}"

case "$ACTION" in
    discover)
        echo -e "${YELLOW}Running discovery only...${NC}"
        python3 /work/discovery/discover.py
        exit 0
        ;;
    shell)
        echo -e "${YELLOW}Opening interactive shell...${NC}"
        exec /bin/bash
        ;;
    plan)
        TF_ACTION="plan"
        ;;
    apply)
        TF_ACTION="apply -auto-approve"
        ;;
    destroy)
        TF_ACTION="destroy -auto-approve"
        ;;
    *)
        echo "Usage: $0 [discover|plan|apply|destroy|shell]"
        exit 1
        ;;
esac

# Phase 1: Discovery
echo ""
echo "============================================"
echo "  Phase 1: Discovery"
echo "============================================"
echo ""
python3 /work/discovery/discover.py
echo ""

# Phase 2: Terraform Init
echo ""
echo "============================================"
echo "  Phase 2: Terraform Init"
echo "============================================"
echo ""

cd /work/terraform

# Clear local Terraform state to prevent stale backend config
rm -rf .terraform .terraform.lock.hcl

# Initialize Terraform with S3 backend
echo -e "${YELLOW}Initializing Terraform...${NC}"
STATE_EXISTS=$(aws s3api head-object --bucket "${STATE_BUCKET}" --key "${STATE_KEY}" 2>/dev/null && echo "true" || echo "false")

if [ "${STATE_EXISTS}" = "true" ]; then
    terraform init -input=false \
        -backend-config="bucket=${STATE_BUCKET}" \
        -backend-config="key=${STATE_KEY}" \
        -backend-config="region=${STATE_REGION}" \
        -backend-config="encrypt=true"
else
    terraform init -input=false -reconfigure \
        -backend-config="bucket=${STATE_BUCKET}" \
        -backend-config="key=${STATE_KEY}" \
        -backend-config="region=${STATE_REGION}" \
        -backend-config="encrypt=true"
fi

# Sync existing resources into Terraform state
echo ""
echo -e "${YELLOW}Syncing Terraform state with existing resources...${NC}"
python3 /work/discovery/state_sync.py

# Phase 3: Terraform Plan/Apply
echo ""
echo "============================================"
echo "  Phase 3: Terraform ${TF_ACTION}"
echo "============================================"
echo ""

echo -e "${YELLOW}Running terraform ${TF_ACTION}...${NC}"
terraform ${TF_ACTION} ${TERRAFORM_ARGS}

# Phase 4: Post-Deployment Verification
if [ "$TF_ACTION" = "plan" ]; then
    echo ""
    echo "============================================"
    echo "  Phase 4: GuardDuty Organization Preview"
    echo "============================================"
    echo ""
    echo -e "${YELLOW}Verifying GuardDuty organization configuration...${NC}"
    python3 /work/post-deployment/verify-guardduty.py || true
    echo ""
fi

if [ "$TF_ACTION" = "apply -auto-approve" ]; then
    echo ""
    echo "============================================"
    echo "  Phase 4: Post-Deployment Verification"
    echo "============================================"
    echo ""

    echo -e "${YELLOW}Verifying GuardDuty organization configuration...${NC}"
    python3 /work/post-deployment/verify-guardduty.py || true
    GUARDDUTY_EXIT_CODE=$?

    if [ $GUARDDUTY_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}GuardDuty organization verification completed successfully${NC}"
    else
        echo -e "${YELLOW}Warning: GuardDuty verification encountered issues (exit code: $GUARDDUTY_EXIT_CODE)${NC}"
    fi
    echo ""
fi

# Phase 5: Summary
if [ "$TF_ACTION" = "apply -auto-approve" ]; then
    echo ""
    echo "============================================"
    echo "  Phase 5: Summary"
    echo "============================================"
    echo ""
    terraform output -json guardduty_summary 2>/dev/null | jq . || echo "No summary output available"
    echo ""
    echo -e "${GREEN}GuardDuty organization deployment complete!${NC}"
fi
