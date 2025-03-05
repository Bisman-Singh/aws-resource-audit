#!/usr/bin/env bash
#
# aws-resource-audit/audit.sh
# Audits AWS resources and generates a Markdown report.
# Lists EC2 instances, RDS instances, S3 buckets, and IAM users with key ages.
#
# Usage: ./audit.sh [-r region] [-p profile] [-o output_file] [-h]
#

set -euo pipefail

# ─── Defaults ───────────────────────────────────────────────────────────────────
REGION="us-east-1"
PROFILE=""
OUTPUT_FILE="audit-report.md"

# ─── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Functions ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Audits AWS resources and generates a Markdown report including:
  - EC2 Instances (ID, type, state, name)
  - RDS Instances (ID, engine, status, class)
  - S3 Buckets (name, region, approximate size)
  - IAM Users (username, access key age, last used)

Options:
  -r REGION   AWS region (default: us-east-1)
  -p PROFILE  AWS CLI profile name (default: uses default profile)
  -o FILE     Output file path (default: audit-report.md)
  -h          Show this help message

Prerequisites:
  - AWS CLI v2 installed and configured
  - Appropriate IAM permissions for read-only access to EC2, RDS, S3, IAM

Examples:
  $(basename "$0")                                  # Audit with defaults
  $(basename "$0") -r eu-west-1 -p production       # Specific region and profile
  $(basename "$0") -o /tmp/my-audit.md              # Custom output location
  $(basename "$0") -h                               # Show help
EOF
    exit 0
}

# Build AWS CLI base command with optional profile
aws_cmd() {
    local cmd="aws"
    if [[ -n "$PROFILE" ]]; then
        cmd="$cmd --profile $PROFILE"
    fi
    cmd="$cmd --region $REGION"
    echo "$cmd"
}

log_msg() {
    local level="$1"
    local msg="$2"
    local color=""
    case "$level" in
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
    esac
    echo -e "${color}[$level]${RESET} $msg"
}

# Calculate days between a date and now
days_since() {
    local date_str="$1"
    if [[ -z "$date_str" || "$date_str" == "null" || "$date_str" == "N/A" ]]; then
        echo "N/A"
        return
    fi

    local then_epoch now_epoch
    # Try macOS date format first, then Linux
    then_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${date_str%%+*}" "+%s" 2>/dev/null || \
                 date -d "$date_str" "+%s" 2>/dev/null || echo "0")
    now_epoch=$(date "+%s")

    if [[ "$then_epoch" == "0" ]]; then
        echo "N/A"
    else
        echo $(( (now_epoch - then_epoch) / 86400 ))
    fi
}

# ─── Parse arguments ────────────────────────────────────────────────────────────
while getopts ":r:p:o:h" opt; do
    case "$opt" in
        r) REGION="$OPTARG" ;;
        p) PROFILE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        h) usage ;;
        \?) echo "Error: Unknown option -$OPTARG" >&2; usage ;;
        :)  echo "Error: Option -$OPTARG requires an argument" >&2; usage ;;
    esac
done

# ─── Check prerequisites ────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH.${RESET}" >&2
    echo "Install it from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
    exit 1
fi

# Check if AWS credentials are configured
if ! $(aws_cmd) sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured or invalid.${RESET}" >&2
    echo "Run 'aws configure' to set up credentials." >&2
    exit 1
fi

# ─── Get account info ───────────────────────────────────────────────────────────
ACCOUNT_ID=$($(aws_cmd) sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "unknown")
CALLER_ARN=$($(aws_cmd) sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "unknown")

echo -e "${BOLD}AWS Resource Audit${RESET}"
echo -e "Region:   $REGION"
echo -e "Profile:  ${PROFILE:-default}"
echo -e "Account:  $ACCOUNT_ID"
echo -e "Output:   $OUTPUT_FILE"
echo ""

# ─── Start report ───────────────────────────────────────────────────────────────
{
    echo "# AWS Resource Audit Report"
    echo ""
    echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo "**Account:** $ACCOUNT_ID"
    echo "**Region:** $REGION"
    echo "**Auditor:** $CALLER_ARN"
    echo ""
    echo "---"
    echo ""

    # ─── EC2 Instances ───────────────────────────────────────────────────────────
    echo "## EC2 Instances"
    echo ""
    log_msg "INFO" "Fetching EC2 instances..." >&2

    ec2_data=$($(aws_cmd) ec2 describe-instances \
        --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$ec2_data" || "$ec2_data" == "None" ]]; then
        echo "No EC2 instances found in this region."
        echo ""
    else
        echo "| Instance ID | Type | State | Name |"
        echo "|------------|------|-------|------|"
        while IFS=$'\t' read -r id itype state name; do
            [[ -z "$id" ]] && continue
            name=${name:-"(unnamed)"}
            echo "| $id | $itype | $state | $name |"
        done <<< "$ec2_data"
        echo ""
        total_ec2=$(echo "$ec2_data" | grep -c . || echo "0")
        echo "**Total EC2 instances:** $total_ec2"
        echo ""
    fi

    echo "---"
    echo ""

    # ─── RDS Instances ───────────────────────────────────────────────────────────
    echo "## RDS Instances"
    echo ""
    log_msg "INFO" "Fetching RDS instances..." >&2

    rds_data=$($(aws_cmd) rds describe-db-instances \
        --query 'DBInstances[*].[DBInstanceIdentifier,Engine,DBInstanceStatus,DBInstanceClass,AllocatedStorage]' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$rds_data" || "$rds_data" == "None" ]]; then
        echo "No RDS instances found in this region."
        echo ""
    else
        echo "| DB Instance ID | Engine | Status | Class | Storage (GB) |"
        echo "|---------------|--------|--------|-------|-------------|"
        while IFS=$'\t' read -r dbid engine status dbclass storage; do
            [[ -z "$dbid" ]] && continue
            echo "| $dbid | $engine | $status | $dbclass | $storage |"
        done <<< "$rds_data"
        echo ""
        total_rds=$(echo "$rds_data" | grep -c . || echo "0")
        echo "**Total RDS instances:** $total_rds"
        echo ""
    fi

    echo "---"
    echo ""

    # ─── S3 Buckets ──────────────────────────────────────────────────────────────
    echo "## S3 Buckets"
    echo ""
    log_msg "INFO" "Fetching S3 buckets..." >&2

    bucket_names=$($(aws_cmd) s3api list-buckets \
        --query 'Buckets[*].Name' --output text 2>/dev/null || echo "")

    if [[ -z "$bucket_names" || "$bucket_names" == "None" ]]; then
        echo "No S3 buckets found."
        echo ""
    else
        echo "| Bucket Name | Region | Estimated Size |"
        echo "|------------|--------|----------------|"

        for bucket in $bucket_names; do
            [[ -z "$bucket" ]] && continue

            # Get bucket location
            b_region=$($(aws_cmd) s3api get-bucket-location \
                --bucket "$bucket" \
                --query 'LocationConstraint' --output text 2>/dev/null || echo "unknown")
            [[ "$b_region" == "None" || -z "$b_region" ]] && b_region="us-east-1"

            # Get approximate size using CloudWatch (last 24h average)
            b_size=$($(aws_cmd) cloudwatch get-metric-statistics \
                --namespace AWS/S3 \
                --metric-name BucketSizeBytes \
                --dimensions Name=BucketName,Value="$bucket" Name=StorageType,Value=StandardStorage \
                --start-time "$(date -u -v-1d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -d '1 day ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo '2026-04-17T00:00:00')" \
                --end-time "$(date -u '+%Y-%m-%dT%H:%M:%S')" \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[0].Average' \
                --output text 2>/dev/null || echo "N/A")

            if [[ "$b_size" != "N/A" && "$b_size" != "None" && -n "$b_size" ]]; then
                # Convert to human-readable
                b_size_int=${b_size%.*}
                if [[ "$b_size_int" -ge 1073741824 ]]; then
                    b_size_hr="$(echo "scale=2; $b_size_int / 1073741824" | bc) GB"
                elif [[ "$b_size_int" -ge 1048576 ]]; then
                    b_size_hr="$(echo "scale=2; $b_size_int / 1048576" | bc) MB"
                elif [[ "$b_size_int" -ge 1024 ]]; then
                    b_size_hr="$(echo "scale=2; $b_size_int / 1024" | bc) KB"
                else
                    b_size_hr="${b_size_int} B"
                fi
            else
                b_size_hr="N/A"
            fi

            echo "| $bucket | $b_region | $b_size_hr |"
        done
        echo ""
        total_s3=$(echo "$bucket_names" | wc -w | xargs)
        echo "**Total S3 buckets:** $total_s3"
        echo ""
    fi

    echo "---"
    echo ""

    # ─── IAM Users ───────────────────────────────────────────────────────────────
    echo "## IAM Users & Access Key Age"
    echo ""
    log_msg "INFO" "Fetching IAM users and access keys..." >&2

    # IAM is global, no region needed
    iam_users=$(aws iam list-users --query 'Users[*].UserName' --output text 2>/dev/null || echo "")

    if [[ -z "$iam_users" || "$iam_users" == "None" ]]; then
        echo "No IAM users found."
        echo ""
    else
        echo "| Username | Access Key ID | Key Age (days) | Last Used | Status |"
        echo "|----------|--------------|----------------|-----------|--------|"

        for user in $iam_users; do
            [[ -z "$user" ]] && continue

            # List access keys for this user
            keys_data=$(aws iam list-access-keys --user-name "$user" \
                --query 'AccessKeyMetadata[*].[AccessKeyId,Status,CreateDate]' \
                --output text 2>/dev/null || echo "")

            if [[ -z "$keys_data" || "$keys_data" == "None" ]]; then
                echo "| $user | (no keys) | - | - | - |"
            else
                while IFS=$'\t' read -r key_id status create_date; do
                    [[ -z "$key_id" ]] && continue
                    key_age=$(days_since "$create_date")

                    # Get last used date
                    last_used=$(aws iam get-access-key-last-used --access-key-id "$key_id" \
                        --query 'AccessKeyLastUsed.LastUsedDate' --output text 2>/dev/null || echo "N/A")
                    [[ "$last_used" == "None" ]] && last_used="Never"

                    # Flag old keys
                    local age_flag=""
                    if [[ "$key_age" != "N/A" && "$key_age" -gt 90 ]]; then
                        age_flag=" :warning:"
                    fi

                    echo "| $user | $key_id | ${key_age}${age_flag} | $last_used | $status |"
                done <<< "$keys_data"
            fi
        done
        echo ""
        total_iam=$(echo "$iam_users" | wc -w | xargs)
        echo "**Total IAM users:** $total_iam"
        echo ""
    fi

    echo "---"
    echo ""
    echo "*Report generated by aws-resource-audit*"

} > "$OUTPUT_FILE"

# ─── Completion ──────────────────────────────────────────────────────────────────
echo ""
log_msg "INFO" "Audit complete. Report saved to: $OUTPUT_FILE"
echo ""
echo -e "${BOLD}Done.${RESET}"
