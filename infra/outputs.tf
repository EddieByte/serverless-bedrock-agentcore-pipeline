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
