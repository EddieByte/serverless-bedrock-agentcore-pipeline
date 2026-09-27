# Package Lambda source code automatically into ZIP
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
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
