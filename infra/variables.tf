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
  default     = "us.anthropic.claude-sonnet-4-20250514-v1:0"
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
