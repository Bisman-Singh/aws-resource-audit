# AWS Resource Audit

A Bash script that audits AWS resources across EC2, RDS, S3, and IAM, then generates a comprehensive Markdown report.

## Features

- **EC2 Instances**: Lists instance ID, type, state, and name tag
- **RDS Instances**: Lists DB identifier, engine, status, class, and storage
- **S3 Buckets**: Lists bucket name, region, and estimated size via CloudWatch
- **IAM Users**: Lists usernames, access key IDs, key age, last used date, and status
- Flags access keys older than 90 days with a warning
- Outputs a clean Markdown report
- Supports AWS profiles and region selection

## Requirements

- Bash 4.0+
- AWS CLI v2 installed and configured
- IAM permissions for read-only access to: EC2, RDS, S3, IAM, CloudWatch, STS
- `bc` (for size calculations)

## Usage

```bash
chmod +x audit.sh

# Run with defaults (us-east-1, default profile)
./audit.sh

# Specify region and profile
./audit.sh -r eu-west-1 -p production

# Custom output file
./audit.sh -o /tmp/my-audit.md

# Show help
./audit.sh -h
```

### Flags

| Flag | Description |
|------|-------------|
| `-r REGION` | AWS region (default: `us-east-1`) |
| `-p PROFILE` | AWS CLI profile name |
| `-o FILE` | Output file path (default: `audit-report.md`) |
| `-h` | Show help message |

## Sample Report Output

```markdown
# AWS Resource Audit Report

**Generated:** 2026-04-18 10:00:00
**Account:** 123456789012
**Region:** us-east-1

---

## EC2 Instances

| Instance ID | Type | State | Name |
|------------|------|-------|------|
| i-0abc123def456 | t3.medium | running | web-server-01 |
| i-0def789ghi012 | t3.large | stopped | staging-api |

**Total EC2 instances:** 2

---

## RDS Instances

| DB Instance ID | Engine | Status | Class | Storage (GB) |
|---------------|--------|--------|-------|-------------|
| prod-database | mysql | available | db.r5.large | 100 |

**Total RDS instances:** 1

---

## S3 Buckets

| Bucket Name | Region | Estimated Size |
|------------|--------|----------------|
| my-app-assets | us-east-1 | 2.45 GB |
| my-app-logs | us-east-1 | 15.72 GB |

**Total S3 buckets:** 2

---

## IAM Users & Access Key Age

| Username | Access Key ID | Key Age (days) | Last Used | Status |
|----------|--------------|----------------|-----------|--------|
| deploy-bot | AKIA1234EXAMPLE | 45 | 2026-04-17 | Active |
| old-admin | AKIA5678EXAMPLE | 120 :warning: | 2025-12-01 | Active |

**Total IAM users:** 2
```



<sub><sup>Originally developed and tested locally during learning. Later organized and pushed to GitHub for portfolio visibility.</sup></sub>
