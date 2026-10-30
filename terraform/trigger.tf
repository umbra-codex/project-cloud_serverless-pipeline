resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ingest.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.landing.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "landing" {
  bucket     = aws_s3_bucket.landing.id
  depends_on = [aws_lambda_permission.s3_invoke]

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
  }
}
