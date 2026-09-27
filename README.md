# Serverless Bedrock AgentCore Data Analysis Pipeline

An event-driven, serverless data analysis pipeline on AWS. Upload a dataset to S3 and receive an AI-generated analysis report automatically — no servers to manage, no manual steps.

---

## The Problem

Data teams frequently receive raw files (CSV exports, JSON feeds, Excel reports) that need to be profiled, summarized, and reviewed before any downstream work can begin. This triage is repetitive and time-consuming:

- Someone has to open the file, understand the schema, spot anomalies, and write up a summary.
- That work often blocks engineers and analysts from starting the actual task.
- At scale — with many files arriving from different sources — the bottleneck compounds quickly.

## The Solution

This pipeline eliminates that manual triage step entirely. It listens for file uploads to an S3 bucket and automatically invokes an AI model (Claude via Amazon Bedrock) to produce a structured analysis report. The report is written back to a separate S3 output bucket and is immediately available for review.

The entire workflow is:

```
Upload file → S3 input bucket → Lambda trigger → Amazon Bedrock (Claude) → Markdown report → S3 output bucket
```

No polling, no scheduled jobs, no manual intervention.

---

## What It Can Be Used For

| Use Case | Example |
|---|---|
| **Sales & revenue data review** | Upload daily order exports; get a summary of trends, outliers, and top performers |
| **Operational monitoring** | Upload log or metric snapshots; get anomaly detection and recommended actions |
| **Data pipeline validation** | Upload intermediate dataset samples; verify schema and catch drift before it hits production |
| **Business intelligence prep** | Get schema overviews and visualization recommendations before building dashboards |
| **Onboarding new data sources** | Automatically profile any new feed the first time it arrives |

---

## Architecture

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

**Infrastructure is fully managed by Terraform** — a single `terraform apply` provisions all AWS resources.

### AWS Resources Provisioned

| Resource | Purpose |
|---|---|
| S3 Input Bucket | Receives raw dataset uploads; triggers the pipeline |
| S3 Output Bucket | Stores generated Markdown analysis reports |
| Lambda Function | Orchestrates the pipeline; reads input, calls Bedrock, writes output |
| IAM Role + Policies | Least-privilege execution role scoped to exact required actions |
| CloudWatch Log Group | Captures Lambda execution logs with 14-day retention |
| S3 Bucket Notification | Event trigger binding the input bucket to the Lambda function |

---

## Repository Structure

```
serverless-bedrock-agentcore-pipeline/
├── infra/                          # Terraform infrastructure (IaC)
│   ├── providers.tf                # Terraform & AWS provider config
│   ├── variables.tf                # Input variables with defaults
│   ├── terraform.tfvars.example    # Example variable values
│   ├── s3.tf                       # Input & output S3 buckets
│   ├── iam.tf                      # IAM roles and least-privilege policies
│   ├── lambda.tf                   # Lambda function and CloudWatch log group
│   ├── notifications.tf            # S3 event trigger → Lambda binding
│   └── outputs.tf                  # Exported resource names and ARNs
├── src/                            # Application code
│   └── lambda_function.py          # Lambda orchestrator (Python 3.11)
├── samples/                        # Sample datasets for testing
│   └── sample_sales_data.csv       # Example sales CSV to trigger the pipeline
├── screenshots/                    # UI and output screenshots for documentation
└── README.md
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials
- An AWS account with permissions to create: S3, Lambda, IAM, CloudWatch
- Amazon Bedrock access with Claude Sonnet 4 inference profile enabled in your region

> **Note on Bedrock model access:** Modern Claude models on Bedrock require an inference profile ID rather than a bare model ID. The default configuration uses `us.anthropic.claude-sonnet-4-20250514-v1:0`, which routes through the US cross-region inference profile. If your AWS account has Service Control Policies (SCPs) that restrict cross-region traffic, work with your account administrator to allow Bedrock inference profile invocations before deploying. See [Troubleshooting](#troubleshooting) for details.

---

## Deployment

**1. Clone the repository and navigate to the infra directory:**

```bash
git clone <repo-url>
cd serverless-bedrock-agentcore-pipeline/infra
```

**2. Initialize Terraform:**

```bash
terraform init
```

**3. Configure your variables:**

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to set your region, environment name, or model ID if needed.

**4. Preview the execution plan:**

```bash
terraform plan
```

**5. Deploy:**

```bash
terraform apply -auto-approve
```

Terraform will output the provisioned resource names on completion:

```
input_s3_bucket_name  = "serverless-agentcore-analysis-input-xxxxxx"
output_s3_bucket_name = "serverless-agentcore-analysis-output-xxxxxx"
lambda_function_name  = "bedrock-orchestrator-dev"
lambda_function_arn   = "arn:aws:lambda:us-east-1:..."
iam_role_arn          = "arn:aws:iam::...:role/bedrock-pipeline-orchestrator-role-dev"
```

---

## Testing the Pipeline

**1. Upload the sample dataset:**

```bash
INPUT_BUCKET=$(terraform output -raw input_s3_bucket_name)
aws s3 cp ../samples/sample_sales_data.csv s3://$INPUT_BUCKET/sample_sales_data.csv
```

**2. Monitor execution:**

```bash
aws logs tail /aws/lambda/bedrock-orchestrator-dev --follow
```

Look for the success log line:
```
Analysis complete. Report successfully saved to s3://<output-bucket>/reports/analysis_sample_sales_data.csv.md
```

**3. Retrieve the generated report:**

```bash
OUTPUT_BUCKET=$(terraform output -raw output_s3_bucket_name)
aws s3 cp s3://$OUTPUT_BUCKET/reports/analysis_sample_sales_data.csv.md ./analysis_report.md
```

Open `analysis_report.md` to review the AI-generated schema overview, insights, and visualization recommendations.

---

## Configuration Reference

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region for all resources |
| `environment` | `dev` | Environment tag (dev / staging / prod) |
| `bucket_prefix` | `serverless-agentcore-analysis` | Prefix for S3 bucket names |
| `bedrock_model_id` | `us.anthropic.claude-sonnet-4-20250514-v1:0` | Bedrock inference profile ID |
| `lambda_timeout` | `300` | Lambda timeout in seconds |
| `lambda_memory_size` | `1024` | Lambda memory in MB |

---

## Security Design

- **Least-privilege IAM**: the Lambda execution role is scoped to only the actions it needs — `s3:GetObject` on the input bucket, `s3:PutObject` on the output bucket, and `bedrock:InvokeModel` on Bedrock inference profile ARNs.
- **Encrypted storage**: both S3 buckets enforce AES-256 server-side encryption by default.
- **Public access blocked**: all four S3 public access block flags are set to `true` on both buckets.
- **Log retention**: CloudWatch logs are retained for 14 days and then automatically purged.

---

## Teardown

To destroy all provisioned AWS resources and avoid ongoing costs:

```bash
cd infra
terraform destroy -auto-approve
```

---

## Troubleshooting

**`ResourceNotFoundException: This model version has reached end of life`**
The model ID in your config is retired. Update `bedrock_model_id` in `terraform.tfvars` to a current inference profile ID (e.g. `us.anthropic.claude-sonnet-4-20250514-v1:0`) and re-run `terraform apply`.

**`ValidationException: on-demand throughput isn't supported`**
You're using a bare model ID instead of an inference profile ID. Ensure the `bedrock_model_id` value starts with a region prefix (`us.`, `eu.`, or `apac.`).

**`AccessDeniedException` from Bedrock**
Your AWS account may have a Service Control Policy (SCP) that blocks cross-region Bedrock inference profile routing. Cross-region profiles for US route internally through `us-west-2`. Contact your account administrator to allow `bedrock:InvokeModel` on `arn:aws:bedrock:*:*:inference-profile/*` in the SCP. Alternatively, switch to an Amazon-native model (e.g. Amazon Titan) which does not require cross-region routing.

**Lambda not triggering on upload**
Confirm the S3 event notification is configured correctly:
```bash
aws s3api get-bucket-notification-configuration --bucket <input-bucket-name>
```
Re-run `terraform apply` if the notification configuration is missing.

---

## Supported File Types

The pipeline accepts any file type that S3 can store. The Lambda reads the first 2KB of the file as a text sample and passes it to the model. Files that are human-readable in their raw form (CSV, JSON, TSV, plain text logs) produce the most useful analysis results. Binary formats (XLSX, Parquet) will be partially decoded but may yield lower-quality output without a pre-processing layer.

---

## License

MIT
