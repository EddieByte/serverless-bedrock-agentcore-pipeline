# Architecture

## Overview

The pipeline is fully event-driven. There are no scheduled jobs or polling loops — a file upload to S3 is the only trigger.

```
┌─────────────────┐     ObjectCreated      ┌──────────────────────┐
│  S3 Input Bucket │ ──────────────────────▶│   Lambda Orchestrator │
│  (CSV/JSON/XLSX) │                        │   (Python 3.11)       │
└─────────────────┘                        └──────────┬───────────┘
                                                       │
                                           ┌───────────▼───────────┐
                                           │  Amazon Bedrock        │
                                           │  (Claude Sonnet 4)     │
                                           └───────────┬───────────┘
                                                       │
                                           ┌───────────▼───────────┐
                                           │  S3 Output Bucket      │
                                           │  reports/*.md          │
                                           └───────────────────────┘
```

## Data Flow

1. A file is uploaded to the **S3 input bucket** (CSV, JSON, TSV, or plain text).
2. S3 fires an `ObjectCreated` event notification to the **Lambda orchestrator**.
3. Lambda reads the first 2KB of the uploaded file as a text sample.
4. Lambda constructs a structured analysis prompt and calls **Amazon Bedrock** (Claude Sonnet 4 via cross-region inference profile).
5. Bedrock returns a Markdown-formatted analysis report covering schema, insights, and recommendations.
6. Lambda writes the report to the **S3 output bucket** under `reports/analysis_<filename>.md`.

## AWS Resources

| Resource | Name Pattern | Purpose |
|---|---|---|
| S3 Input Bucket | `<prefix>-input-<suffix>` | Receives raw dataset uploads; triggers the pipeline |
| S3 Output Bucket | `<prefix>-output-<suffix>` | Stores generated Markdown analysis reports |
| Lambda Function | `bedrock-orchestrator-<env>` | Orchestrates the pipeline — reads input, calls Bedrock, writes output |
| IAM Role | `bedrock-pipeline-orchestrator-role-<env>` | Least-privilege execution role for Lambda |
| IAM Policy (CloudWatch) | `bedrock-pipeline-cloudwatch-policy-<env>` | Allows Lambda to write execution logs |
| IAM Policy (S3) | `bedrock-pipeline-s3-policy-<env>` | Scoped read on input bucket, write on output bucket |
| IAM Policy (Bedrock) | `bedrock-pipeline-bedrock-policy-<env>` | Allows `InvokeModel` on inference profile and foundation model ARNs |
| CloudWatch Log Group | `/aws/lambda/bedrock-orchestrator-<env>` | Lambda execution logs; 14-day retention |
| S3 Bucket Notification | — | Binds `ObjectCreated:*` events on the input bucket to the Lambda function |

## Security Design

- **Least-privilege IAM**: the Lambda execution role is scoped to only the actions it needs — `s3:GetObject` on the input bucket, `s3:PutObject` on the output bucket, and `bedrock:InvokeModel` scoped to inference profile and foundation model ARNs.
- **Encrypted storage**: both S3 buckets enforce AES-256 server-side encryption by default.
- **Public access blocked**: all four S3 public access block flags are set to `true` on both buckets.
- **Log retention**: CloudWatch logs are automatically purged after 14 days.

## Infrastructure Management

All resources are provisioned and managed by Terraform. The `archive_file` data source in `lambda.tf` automatically zips `src/lambda_function.py` at apply time. The `source_code_hash` attribute ensures Lambda is redeployed whenever the Python source changes — no manual packaging required.

Bucket names are globally unique by appending a random 6-character suffix generated at apply time.
