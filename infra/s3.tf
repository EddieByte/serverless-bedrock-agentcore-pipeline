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
