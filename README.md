# Serverless Bedrock AgentCore Data Analysis Pipeline

An event-driven, serverless pipeline that turns raw data uploads into AI-generated analysis reports — automatically, with no servers to manage.

---

## The Problem

Every time a new dataset lands, someone has to open it, understand the schema, spot anomalies, and write up a summary before any real work can begin. It's repetitive, it blocks teams, and it compounds at scale.

## The Solution

Upload a file. Get a report.

The pipeline listens for uploads to an S3 bucket, passes the data to Claude on Amazon Bedrock, and writes a structured Markdown analysis back to a separate output bucket — all without any manual steps.

```
Upload file → S3 input bucket → Lambda → Amazon Bedrock (Claude) → Markdown report → S3 output bucket
```

---

## What It Can Be Used For

| Use Case | Example |
|---|---|
| Sales & revenue review | Daily order exports → trend summaries and outlier detection |
| Operational monitoring | Metric snapshots → anomaly detection and action recommendations |
| Data pipeline validation | Intermediate samples → schema verification before hitting production |
| BI prep | Raw feeds → schema overview and visualization recommendations |
| New data source onboarding | Any new feed → automatic first-pass profile |

---

## Repository Structure

```
serverless-bedrock-agentcore-pipeline/
├── infra/                          # Terraform IaC — provisions all AWS resources
│   ├── providers.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── s3.tf
│   ├── iam.tf
│   ├── lambda.tf
│   ├── notifications.tf
│   └── outputs.tf
├── src/
│   └── lambda_function.py          # Python 3.11 Lambda orchestrator
├── docs/
│   └── architecture.md             # Architecture diagram, data flow, and security design
├── samples/
│   └── sample_sales_data.csv       # Ready-to-use test dataset
├── screenshots/                    # Output screenshots
└── README.md
```

---

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials
- IAM permissions to create S3, Lambda, IAM, and CloudWatch resources
- Amazon Bedrock access with Claude Sonnet 4 enabled in your region

> If your account has SCPs that restrict cross-region traffic, read the note in [docs/architecture.md](docs/architecture.md) before deploying.

---

## Deploy

```bash
cd infra
terraform init
cp terraform.tfvars.example terraform.tfvars
terraform apply -auto-approve
```

---

## Test

```bash
INPUT_BUCKET=$(terraform output -raw input_s3_bucket_name)
aws s3 cp ../samples/sample_sales_data.csv s3://$INPUT_BUCKET/sample_sales_data.csv

# Watch it run
aws logs tail /aws/lambda/bedrock-orchestrator-dev --follow

# Pull the report
OUTPUT_BUCKET=$(terraform output -raw output_s3_bucket_name)
aws s3 cp s3://$OUTPUT_BUCKET/reports/analysis_sample_sales_data.csv.md ./report.md
```

---

## Teardown

```bash
terraform destroy -auto-approve
```

---

## License

MIT
