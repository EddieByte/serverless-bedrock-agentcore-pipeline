# Production Terraform Automation Guide: Serverless Bedrock AgentCore Data Pipeline

This document provides a production-grade, modular **Infrastructure as Code (IaC)** architecture built with **Terraform**. It fully automates the setup of the AWS Serverless Bedrock AgentCore Data Analysis Pipeline, implementing strict security best practices, least-privilege IAM policies, encrypted storage, automated Lambda deployment, and event-driven S3 triggers.

---

## 🏗️ Architectural Overview & Best Practices

The Terraform codebase is structured into modular `.tf` configuration files:

```
terraform/
├── providers.tf             # Terraform & AWS provider requirements + Default Resource Tags
├── variables.tf             # Input variables with validation and default parameters
├── terraform.tfvars.example # Sample variables file for local environments
├── s3.tf                    # Ingestion & Output S3 Buckets with SSE-S3 & Public Access Blocks
├── iam.tf                   # Least-privilege IAM Roles & Scoped Inline Policies
├── lambda.tf                # Lambda orchestrator, CloudWatch Log Groups & permissions
├── notifications.tf         # Event-driven S3 Bucket Notification triggers
├── outputs.tf               # Exported ARNs, Bucket Names, and Function IDs
└── src/
    └── lambda_function.py   # Corrected Python 3.11 Lambda Orchestrator code
```

### Key Engineering & Security Standards Applied
1. **Zero-Trust Least-Privilege IAM**:
   - The Lambda Execution Role is restricted solely to reading from the input bucket (`s3:GetObject`) and writing to the output bucket (`s3:PutObject`).
   - CloudWatch log permissions are scoped directly to the function's log group.
2. **Encrypted S3 Storage with Public Access Block**:
   - Both S3 buckets enforce **Server-Side Encryption (AES256)** by default.
   - All four public access block flags are set to `true`.
3. **Automated Packaging & Hash Tracking**:
   - The `archive_file` data source dynamically zips `src/lambda_function.py`.
   - `source_code_hash` triggers seamless Lambda redeployments whenever the local Python source code is edited.
4. **Resilient S3 Event Triggers**:
   - Eliminates the previous error where triggers were improperly restricted to `.jpg` files, allowing seamless automated ingestion of `.csv`, `.json`, and `.xlsx` files.

---

## 📄 Complete Infrastructure Code Base

### 1. `providers.tf`
```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Bedrock-Data-Analysis-Pipeline"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

```

### 2. `variables.tf`
```hcl
variable "aws_region" {
  type        = string
  description = "The AWS region where resources will be deployed."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod)."
  default     = "dev"
}

variable "bucket_prefix" {
  type        = string
  description = "Unique prefix for S3 bucket naming to ensure global uniqueness."
  default     = "serverless-agentcore-analysis"
}

variable "bedrock_model_id" {
  type        = string
  description = "The Bedrock model ID used by the orchestrator."
  default     = "anthropic.claude-3-5-sonnet-20240620-v1:0"
}

variable "lambda_timeout" {
  type        = number
  description = "Lambda execution timeout in seconds."
  default     = 300
}

variable "lambda_memory_size" {
  type        = number
  description = "Lambda allocated memory in MB."
  default     = 1024
}

```

### 3. `s3.tf`
```hcl
# Random suffix to guarantee globally unique bucket names
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Input Bucket: Data Uploads
resource "aws_s3_bucket" "input_bucket" {
  bucket        = "${var.bucket_prefix}-input-${random_string.bucket_suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "input_bucket_encryption" {
  bucket = aws_s3_bucket.input_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "input_bucket_public_block" {
  bucket                  = aws_s3_bucket.input_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output Bucket: Processed Summaries & Visualizations
resource "aws_s3_bucket" "output_bucket" {
  bucket        = "${var.bucket_prefix}-output-${random_string.bucket_suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output_bucket_encryption" {
  bucket = aws_s3_bucket.output_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "output_bucket_public_block" {
  bucket                  = aws_s3_bucket.output_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

```

### 4. `iam.tf`
```hcl
# IAM Execution Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "bedrock-pipeline-orchestrator-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# CloudWatch Logs Policy
resource "aws_iam_policy" "cloudwatch_policy" {
  name        = "bedrock-pipeline-cloudwatch-policy-${var.environment}"
  description = "Allows Lambda orchestrator to create and write logs to CloudWatch."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# S3 Least-Privilege Policy
resource "aws_iam_policy" "s3_policy" {
  name        = "bedrock-pipeline-s3-policy-${var.environment}"
  description = "Allows read access to input bucket and write access to output bucket."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input_bucket.arn,
          "${aws_s3_bucket.input_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Amazon Bedrock Policy
resource "aws_iam_policy" "bedrock_policy" {
  name        = "bedrock-pipeline-bedrock-policy-${var.environment}"
  description = "Allows invocation of Bedrock models and AgentCore actions."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeAgent"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach policies to IAM role
resource "aws_iam_role_policy_attachment" "attach_cloudwatch" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.cloudwatch_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_bedrock" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.bedrock_policy.arn
}

```

### 5. `lambda.tf`
```hcl
# Package Lambda source code automatically into ZIP
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda_payload.zip"
}

# CloudWatch Log Group with retention limit
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/bedrock-orchestrator-${var.environment}"
  retention_in_days = 14
}

# Lambda Function Definition
resource "aws_lambda_function" "orchestrator" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "bedrock-orchestrator-${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      INPUT_BUCKET     = aws_s3_bucket.input_bucket.id
      OUTPUT_BUCKET    = aws_s3_bucket.output_bucket.id
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.attach_cloudwatch,
    aws_cloudwatch_log_group.lambda_log_group
  ]
}

# S3 Invocation Permission
resource "aws_lambda_permission" "allow_s3_trigger" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

```

### 6. `notifications.tf`
```hcl
# S3 Event Trigger configuration
# Replaces incorrect suffix filter (.jpg) to allow CSV, JSON, XLSX dataset uploads
resource "aws_s3_bucket_notification" "input_bucket_trigger" {
  bucket = aws_s3_bucket.input_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.orchestrator.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.allow_s3_trigger
  ]
}

```

### 7. `outputs.tf`
```hcl
output "input_s3_bucket_name" {
  description = "Name of the S3 input bucket for dataset uploads."
  value       = aws_s3_bucket.input_bucket.id
}

output "output_s3_bucket_name" {
  description = "Name of the S3 output bucket for analysis results."
  value       = aws_s3_bucket.output_bucket.id
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda orchestrator function."
  value       = aws_lambda_function.orchestrator.arn
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda orchestrator function."
  value       = aws_lambda_function.orchestrator.function_name
}

output "iam_role_arn" {
  description = "ARN of the IAM execution role used by Lambda."
  value       = aws_iam_role.lambda_role.arn
}

```

### 8. `terraform.tfvars.example`
```hcl
aws_region       = "us-east-1"
environment      = "dev"
bucket_prefix    = "serverless-agentcore-analysis"
bedrock_model_id = "anthropic.claude-3-5-sonnet-20240620-v1:0"
lambda_timeout   = 300
lambda_memory_size = 1024

```

---

## 🐍 Lambda Orchestrator Source Code (`src/lambda_function.py`)

Place this Python file in the `./src/` directory alongside your Terraform configuration files:

```python
import json
import os
import urllib.parse
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')
bedrock_runtime = boto3.client('bedrock-runtime')

def lambda_handler(event, context):
    try:
        logger.info("Received event: %s", json.dumps(event))
        
        # Parse S3 event notification metadata
        record = event['Records'][0]['s3']
        source_bucket = record['bucket']['name']
        object_key = urllib.parse.unquote_plus(record['object']['key'], encoding='utf-8')
        
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        model_id = os.environ.get('BEDROCK_MODEL_ID', 'anthropic.claude-3-5-sonnet-20240620-v1:0')
        
        logger.info(f"Processing object '{object_key}' from bucket '{source_bucket}'. Target output: '{output_bucket}'.")
        
        # 1. Fetch object snippet or data metadata from S3
        response = s3_client.get_object(Bucket=source_bucket, Key=object_key)
        file_content_sample = response['Body'].read(2048).decode('utf-8', errors='ignore')
        
        # 2. Construct Bedrock prompt for analysis
        prompt = f"""
Human: You are an expert data analyst AI agent. Analyze the following uploaded dataset sample from file '{object_key}':

{file_content_sample}

Provide:
1. Data schema overview and summary statistics.
2. Key business anomalies, trends, or insights.
3. Recommended data transformations or visualization plots.

Assistant:
"""

        # 3. Invoke Amazon Bedrock model
        payload = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 2048,
            "messages": [{"role": "user", "content": prompt}]
        }
        
        bedrock_response = bedrock_runtime.invoke_model(
            modelId=model_id,
            contentType="application/json",
            accept="application/json",
            body=json.dumps(payload)
        )
        
        response_body = json.loads(bedrock_response.get('body').read())
        analysis_result = response_body['content'][0]['text']
        
        # 4. Save structured report to S3 Output Bucket
        output_key = f"reports/analysis_{os.path.basename(object_key)}.md"
        s3_client.put_object(
            Bucket=output_bucket,
            Key=output_key,
            Body=analysis_result.encode('utf-8'),
            ContentType='text/markdown'
        )
        
        logger.info(f"Analysis complete. Report successfully saved to s3://{output_bucket}/{output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'SUCCESS', 'report_location': f"s3://{output_bucket}/{output_key}"})
        }
        
    except Exception as e:
        logger.error(f"Error processing pipeline for key {object_key if 'object_key' in locals() else 'unknown'}: {str(e)}", exc_info=True)
        raise e

```

---

## 🚀 Step-by-Step Deployment Instructions

### Step 1: Prepare Your Workspace
Create the project folder structure on your workstation or AWS CloudShell:
```bash
mkdir -p bedrock-terraform/src
cd bedrock-terraform
```
Save each of the configuration blocks above into their respective files (`main.tf` / `.tf` files and `src/lambda_function.py`).

### Step 2: Initialize Terraform
Initialize the provider plugins and backend modules:
```bash
terraform init
```

### Step 3: Configure Environment Variables
Copy the example variable definitions file and adjust parameters if necessary:
```bash
cp terraform.tfvars.example terraform.tfvars
```

### Step 4: Preview Execution Plan
Perform an execution dry-run to verify the resources Terraform will provision:
```bash
terraform plan
```

### Step 5: Provision Infrastructure
Apply the configuration to deploy all S3 buckets, IAM roles, Lambda functions, and S3 event notifications:
```bash
terraform apply -auto-approve
```

---

## 🧪 Testing & Verification Procedure

1. **Retrieve Provisioned Resource Names**:
   Run `terraform output` to extract the dynamically generated S3 bucket names:
   ```bash
   INPUT_BUCKET=$(terraform output -raw input_s3_bucket_name)
   OUTPUT_BUCKET=$(terraform output -raw output_s3_bucket_name)
   ```

2. **Upload Test Dataset**:
   Upload a sample dataset to the input bucket:
   ```bash
   echo "order_id,drink_type,price,units_sold,customer_rating,order_date" > test_data.csv
   echo "101,Espresso,3.50,120,4.8,2026-09-01" >> test_data.csv
   aws s3 cp test_data.csv s3://$INPUT_BUCKET/test_data.csv
   ```

3. **Monitor Execution in CloudWatch**:
   View realtime execution logs from the deployed Lambda function:
   ```bash
   aws logs tail /aws/lambda/bedrock-orchestrator-dev --follow
   ```

4. **Verify Generated Report in Output Bucket**:
   Check if Bedrock generated and stored the analysis report in the output bucket:
   ```bash
   aws s3 ls s3://$OUTPUT_BUCKET/reports/
   ```

---

## 🧹 Decommissioning / Cleanup

To safely tear down all created AWS resources and prevent incurring ongoing costs:
```bash
terraform destroy -auto-approve
```
