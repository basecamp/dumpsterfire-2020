data "aws_canonical_user_id" "current_user" {}

data "aws_iam_policy_document" "allow_bucket_to_publish_events" {
  statement {
    sid    = "allow_owner_to_publish"
    effect = "Allow"
    resources = [
      aws_sns_topic.processor.arn
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:Receive"
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = ["729823136633"]
    }
  }

  statement {
    sid = "allow_${aws_s3_bucket.raw.id}_to_publish"
    resources = [
      aws_sns_topic.processor.arn
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    effect = "Allow"
    actions = [
      "SNS:Publish"
    ]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.raw.arn]
    }
  }
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "allowS3Write"
    effect = "Allow"
    resources = [
      aws_s3_bucket.raw.arn,
      "${aws_s3_bucket.raw.arn}/*",
      aws_s3_bucket.rules.arn,
      "${aws_s3_bucket.rules.arn}/*",
      aws_s3_bucket.cloudfront.arn,
      "${aws_s3_bucket.cloudfront.arn}/*"
    ]
    actions = [
      "s3:GetObject*",
      "s3:PutObject*",
      "s3:DeleteObject*",
      "s3:List*",
      "s3:GetBucketNotification",
      "s3:PutBucketCORS",
      "s3:PutBucketNotification",
      "s3:PutBucketLogging",
      "s3:GetLifecycleConfiguration",
      "s3:GetInventoryConfiguration",
      "s3:GetBucketTagging",
      "s3:GetBucketLogging",
      "s3:ListBucket"
    ]
  }
  statement {
    sid    = "allowSQSPublish"
    effect = "Allow"
    resources = [
      aws_sqs_queue.print.arn,
      aws_sqs_queue.print_vip.arn,
      aws_sqs_queue.print_alpha.arn,
      aws_sqs_queue.complete.arn,
      aws_sqs_queue.reply.arn,
      aws_sqs_queue.complete_reply.arn,
      aws_sqs_queue.screener.arn,
      aws_sqs_queue.moderated.arn,
      aws_sqs_queue.moderated_vip.arn,
      aws_sqs_queue.moderated_alpha.arn
    ]
    actions = [
      "sqs:*"
    ]
  }
}

data "aws_iam_policy_document" "lambda_edge" {
  statement {
    sid    = "DoTheNeedful"
    effect = "Allow"
    resources = [
      "arn:aws:logs:*:*:*"
    ]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }
}

data "aws_iam_policy_document" "printer" {
  statement {
    sid    = "allowSQSReceiveDelete"
    effect = "Allow"
    resources = [
      aws_sqs_queue.print.arn,
      aws_sqs_queue.print_vip.arn,
      aws_sqs_queue.print_alpha.arn,
      aws_sqs_queue.moderated.arn,
      aws_sqs_queue.moderated_vip.arn,
      aws_sqs_queue.moderated_alpha.arn,
      aws_sqs_queue.lock.arn,
      aws_sqs_queue.debug.arn
    ]
    actions = [
      "sqs:DeleteMessage",
      "sqs:ReceiveMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
  }

  statement {
    sid    = "allowSQSPublish"
    effect = "Allow"
    resources = [
      aws_sqs_queue.screener.arn,
      aws_sqs_queue.complete.arn,
      aws_sqs_queue.moderated.arn,
      aws_sqs_queue.moderated_vip.arn,
      aws_sqs_queue.moderated_alpha.arn,
      aws_sqs_queue.lock.arn,
      aws_sqs_queue.debug.arn
    ]
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
  }

  statement {
    sid    = "allowS3WriteRules"
    effect = "Allow"
    resources = [
      aws_s3_bucket.raw.arn,
      "${aws_s3_bucket.raw.arn}/*",
      aws_s3_bucket.rules.arn,
      "${aws_s3_bucket.rules.arn}/*"
    ]
    actions = [
      "s3:GetObject*",
      "s3:PutObject*",
      "s3:List*",
      "s3:ListBucket",
      "s3:DeleteObject*"
    ]
  }
  statement {
    sid       = "allowLambdaInvoke"
    effect    = "Allow"
    resources = [aws_lambda_function.rescreener.arn]
    actions = [
      "lambda:InvokeFunction",
    ]
  }
}

data "aws_iam_policy_document" "raw_bucket_policy" {
  statement {
    sid    = "AllowSESPuts"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.raw.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:Referer"
      values   = ["729823136633"]
    }
  }
}

// IAM role
resource "aws_iam_role" "dumpster_lambda" {
  name = "${var.primary_name}_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "dumpster_lambda_cloudfront" {
  name = "${var.primary_name}_lambda_cloudfront"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "edgelambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_execute" {
  role       = aws_iam_role.dumpster_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execute" {
  role       = aws_iam_role.dumpster_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_queue" {
  role       = aws_iam_role.dumpster_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "s3_write" {
  name        = "${var.primary_name}-lambdaPermissions"
  description = "Allows write access to s3 buckets"

  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.dumpster_lambda.name
  policy_arn = aws_iam_policy.s3_write.arn
}

resource "aws_iam_policy" "lambda_edge" {
  name        = "${var.primary_name}_lambda_edge"
  description = "Allow running @edge"
  policy      = data.aws_iam_policy_document.lambda_edge.json
}

resource "aws_iam_role_policy_attachment" "lambda_edge" {
  role       = aws_iam_role.dumpster_lambda_cloudfront.name
  policy_arn = aws_iam_policy.lambda_edge.arn
}

resource "aws_iam_policy" "printer" {
  name        = "${var.primary_name}-printer"
  description = "Allows the printer to receive/delete SQS messages"

  policy = data.aws_iam_policy_document.printer.json
}

resource "aws_iam_user" "printer" {
  name = "${var.primary_name}-printer"

}

resource "aws_iam_user_policy_attachment" "printer" {
  user       = aws_iam_user.printer.name
  policy_arn = aws_iam_policy.printer.arn
}

resource "aws_iam_user_policy_attachment" "printer_lambda" {
  user       = aws_iam_user.printer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
}
