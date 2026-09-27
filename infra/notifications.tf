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
