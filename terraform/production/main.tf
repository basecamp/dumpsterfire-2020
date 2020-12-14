variable "primary_name" {
  default = "dumpsterfire"
}

locals {
  domain         = "${var.primary_name}.email"
  display_name   = "DumpsterFire"
  staging_email  = "burnme@df2020-flow-test"
  source_account = "<your-account-here>"
}

# Route53 Zone
resource "aws_route53_zone" "primary" {
  name    = local.domain
  comment = "HostedZone created by Route53 Registrar"
}

# SNS queues/permissions
resource "aws_sns_topic" "processor" {
  name         = "${var.primary_name}-processor"
  display_name = "DumpsterFire2020 Processor"
}

resource "aws_sns_topic_policy" "processor" {
  arn = aws_sns_topic.processor.arn

  policy = data.aws_iam_policy_document.allow_bucket_to_publish_events.json
}

# SQS Queue for Printing
resource "aws_sqs_queue" "print" {
  name       = "${var.primary_name}-print.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 20
}

resource "aws_sqs_queue" "print_vip" {
  name       = "${var.primary_name}-print-vip.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 20
}

resource "aws_sqs_queue" "moderated" {
  name       = "${var.primary_name}-moderated.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 20
}

resource "aws_sqs_queue" "moderated_vip" {
  name       = "${var.primary_name}-moderated-vip.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 20
}

resource "aws_sqs_queue" "print_alpha" {
  name       = "${var.primary_name}-print-alpha.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 20
}

resource "aws_sqs_queue" "moderated_alpha" {
  name       = "${var.primary_name}-moderated-alpha.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 20
}

# SQS Queue for Complete
resource "aws_sqs_queue" "complete" {
  name       = "${var.primary_name}-complete.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 10
}

# SQS Queue for Complete
resource "aws_sqs_queue" "reply" {
  name       = "${var.primary_name}-reply.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 10
}

resource "aws_sqs_queue" "screener" {
  name       = "${var.primary_name}-screener.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 10
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 20
}

resource "aws_sqs_queue" "incinerator" {
  name       = "${var.primary_name}-incinerator.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 10
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 10
}

resource "aws_sqs_queue" "lock" {
  name       = "${var.primary_name}-lock.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 120
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 10
}

resource "aws_sqs_queue" "debug" {
  name       = "${var.primary_name}-debug.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 120
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 10
}

# SQS Queue for Complete
resource "aws_sqs_queue" "complete_reply" {
  name       = "${var.primary_name}-complete-reply.fifo"
  fifo_queue = true

  visibility_timeout_seconds = 10
  message_retention_seconds  = 1209600
  max_message_size           = 262144
  receive_wait_time_seconds  = 10
}

# S3 Buckets
resource "aws_s3_bucket" "logs" {
  bucket = "${var.primary_name}-bucket-logs"
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket" "raw" {
  bucket = "${var.primary_name}-bucket"
  acl    = "private"

  logging {
    target_bucket = aws_s3_bucket.logs.id
    target_prefix = "raw-log/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket" "rules" {
  bucket = "${var.primary_name}-rules"
  acl    = "private"
}

resource "aws_s3_bucket" "cloudfront" {
  bucket = "${var.primary_name}-cloudfront"

  grant {
    id = data.aws_canonical_user_id.current_user.id
    permissions = [
      "FULL_CONTROL",
    ]
    type = "CanonicalUser"
  }

  grant {
    id = "<from your account>"
    permissions = [
      "FULL_CONTROL",
    ]
    type = "CanonicalUser"
  }

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 60
  }

  website {
    error_document = "index.html"
    index_document = "index.html"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "access-identity-${var.primary_name}"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled             = true
  aliases             = [local.domain, "*.${local.domain}"]
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    origin_id   = "S3-${aws_s3_bucket.cloudfront.bucket}"
    domain_name = aws_s3_bucket.cloudfront.bucket_regional_domain_name
    custom_header {
      name  = "Access-Control-Allow-Origin"
      value = "*"
    }

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.cloudfront.bucket}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = aws_lambda_function.cloudfront_redirect.qualified_arn
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 1500
    compress               = true
  }

  ordered_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.cloudfront.bucket}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    compress               = false
    max_ttl                = 1500
    default_ttl            = 300
    min_ttl                = 0
    path_pattern           = "*.json"
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = "<your-certificat-arn>"
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront-logs/"
  }
}

resource "aws_route53_record" "website" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_website" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "www.${local.domain}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# ACM Certificate and domain validation
resource "aws_acm_certificate" "cert" {
  domain_name               = local.domain
  subject_alternative_names = ["*.${local.domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

resource "aws_route53_record" "domain_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = aws_route53_zone.primary.zone_id
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

resource "aws_acm_certificate_validation" "domain" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.domain_validation : record.fqdn]
}

resource "aws_s3_bucket_policy" "raw" {
  bucket = aws_s3_bucket.raw.id
  policy = data.aws_iam_policy_document.raw_bucket_policy.json
}

# S3 Notification for /inbound
resource "aws_s3_bucket_notification" "raw" {
  bucket = aws_s3_bucket.raw.id

  topic {
    id        = "ObjectCopy"
    topic_arn = aws_sns_topic.processor.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

# SES domain verification/dkim
resource "aws_ses_domain_identity" "inbound" {
  domain = local.domain
}

resource "aws_route53_record" "inbound_amazonses_verification_record" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "_amazonses.${aws_route53_zone.primary.name}"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.inbound.verification_token]
}

resource "aws_ses_domain_identity_verification" "inbound_verification" {
  domain = aws_ses_domain_identity.inbound.id

  depends_on = [aws_route53_record.inbound_amazonses_verification_record]
}

resource "aws_ses_domain_dkim" "inbound" {
  domain = aws_ses_domain_identity.inbound.domain
}

resource "aws_route53_record" "inbound_amazonses_dkim_record" {
  count   = 3
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${element(aws_ses_domain_dkim.inbound.dkim_tokens, count.index)}._domainkey.${aws_route53_zone.primary.name}"
  type    = "CNAME"
  ttl     = "600"
  records = ["${element(aws_ses_domain_dkim.inbound.dkim_tokens, count.index)}.dkim.amazonses.com"]
}

resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = aws_route53_zone.primary.name
  type    = "MX"
  ttl     = "600"
  records = ["10 inbound-smtp.us-east-1.amazonaws.com"]
}

# SES receiving rules
resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "${var.primary_name}-rule-set"
}

resource "aws_ses_receipt_rule" "filter" {
  name          = "filter"
  rule_set_name = aws_ses_receipt_rule_set.main.id
  recipients = [
    "burnme@${aws_route53_zone.primary.name}"
  ]
  scan_enabled = true
  tls_policy   = "Require"
  enabled      = true


  lambda_action {
    function_arn    = aws_lambda_function.email_filter.arn
    invocation_type = "RequestResponse"
    position        = 1
  }
}

resource "aws_ses_receipt_rule" "store" {
  name          = "store"
  rule_set_name = aws_ses_receipt_rule_set.main.id
  recipients = [
    "burnme@${aws_route53_zone.primary.name}",
    local.staging_email
  ]
  scan_enabled = true
  tls_policy   = "Require"
  enabled      = true


  s3_action {
    bucket_name       = aws_s3_bucket.raw.id
    object_key_prefix = "inbound/"
    position          = 1
  }
  depends_on = [aws_s3_bucket_policy.raw]
}

// Processor Lambda
resource "aws_lambda_function" "processor" {
  function_name    = "${var.primary_name}-processor"
  description      = "Performs job processing"
  filename         = "${path.module}/processor.zip"
  role             = aws_iam_role.dumpster_lambda.arn
  handler          = "processor.Processor.handler"
  runtime          = "ruby2.7"
  timeout          = "60"
  source_code_hash = filebase64sha256("${path.module}/processor.zip")
}

resource "aws_lambda_permission" "processor_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.processor.arn
}

resource "aws_sns_topic_subscription" "processor_subscription" {
  topic_arn = aws_sns_topic.processor.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.processor.arn
}


# Email Filter Lambda
resource "aws_lambda_function" "email_filter" {
  function_name    = "${var.primary_name}-email-filter"
  description      = "Performs basic mail filtering"
  filename         = "${path.module}/email_filter.zip"
  role             = aws_iam_role.dumpster_lambda.arn
  handler          = "index-async.handler"
  runtime          = "nodejs12.x"
  timeout          = "60"
  source_code_hash = filebase64sha256("${path.module}/email_filter.zip")
}

resource "aws_lambda_permission" "email_filter_ses" {
  statement_id   = "AllowExecutionFromSES"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.email_filter.function_name
  principal      = "ses.amazonaws.com"
  source_account = local.source_account
}

// Cleanup Lambda
resource "aws_lambda_function" "cleanup" {
  function_name    = "${var.primary_name}-cleanup"
  description      = "Performs job cleanup"
  filename         = "${path.module}/cleanup.zip"
  role             = aws_iam_role.dumpster_lambda.arn
  handler          = "cleanup.Cleanup.handler"
  runtime          = "ruby2.7"
  timeout          = "60"
  source_code_hash = filebase64sha256("${path.module}/cleanup.zip")
}

resource "aws_lambda_permission" "cleanup_sqs" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.complete.arn
}

resource "aws_lambda_event_source_mapping" "cleanup" {
  event_source_arn = aws_sqs_queue.complete.arn
  function_name    = aws_lambda_function.cleanup.arn
  batch_size       = 1
}

// Screener Lambda
resource "aws_lambda_function" "screener" {
  function_name    = "${var.primary_name}-screener"
  description      = "Performs job screening"
  filename         = "${path.module}/screener.zip"
  role             = aws_iam_role.dumpster_lambda.arn
  handler          = "screener.Screener.handler"
  runtime          = "ruby2.7"
  timeout          = "10"
  source_code_hash = filebase64sha256("${path.module}/screener.zip")
}

resource "aws_lambda_permission" "screener_sqs" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.screener.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.screener.arn
}

resource "aws_lambda_event_source_mapping" "screener" {
  event_source_arn = aws_sqs_queue.screener.arn
  function_name    = aws_lambda_function.screener.arn
  batch_size       = 10
}

// Screener Lambda
resource "aws_lambda_function" "rescreener" {
  function_name    = "${var.primary_name}-rescreener"
  description      = "Re-screens the print-queue"
  filename         = "${path.module}/screener.zip"
  role             = aws_iam_role.dumpster_lambda.arn
  handler          = "rescreener.Rescreener.handler"
  runtime          = "ruby2.7"
  timeout          = 900
  source_code_hash = filebase64sha256("${path.module}/screener.zip")
}

// Website redirect lambda
resource "aws_lambda_function" "cloudfront_redirect" {
  function_name    = "${var.primary_name}-cloudfront-redirect"
  description      = "Redirect to hey.science"
  filename         = "${path.module}/cloudfront-redirect.zip"
  role             = aws_iam_role.dumpster_lambda_cloudfront.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  timeout          = 3
  publish          = true
  source_code_hash = filebase64sha256("${path.module}/cloudfront-redirect.zip")
}
