provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://127.0.0.1:4566"
    lambda   = "http://127.0.0.1:4566"
    dynamodb = "http://127.0.0.1:4566"
    iam      = "http://127.0.0.1:4566"
    sts      = "http://127.0.0.1:4566"
  }
}

resource "aws_s3_bucket" "start_bucket" {
  bucket = "s3-start-bucket-lab3"
}

resource "aws_s3_bucket" "finish_bucket" {
  bucket = "s3-finish-bucket-lab3"
}

resource "aws_s3_bucket_lifecycle_configuration" "finish_lifecycle" {
  bucket = aws_s3_bucket.finish_bucket.id

  rule {
    id     = "cleanup-old-files"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

resource "aws_dynamodb_table" "audit_table" {
  name           = "FileTransferAuditLog"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "filename"

  attribute {
    name = "filename"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_s3_dynamo_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "LambdaS3DynamoAccess"
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject"],
        Resource = [
          "${aws_s3_bucket.start_bucket.arn}/*",
          "${aws_s3_bucket.finish_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = ["dynamodb:PutItem"],
        Resource = [aws_dynamodb_table.audit_table.arn]
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "copy_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "S3ToS3CopyAndLog"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      FINISH_BUCKET  = aws_s3_bucket.finish_bucket.bucket
      DYNAMODB_TABLE = aws_dynamodb_table.audit_table.name
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.copy_processor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.start_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.start_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.copy_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}