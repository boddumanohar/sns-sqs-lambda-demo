terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

resource "aws_sns_topic" "post_image" {
  name = "process_image"

  policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[{
        "Effect": "Allow",
        "Principal": { "Service": "s3.amazonaws.com" },
        "Action": "SNS:Publish",
        "Resource": "*",
        "Condition":{
            "ArnLike":{"aws:SourceArn":"${aws_s3_bucket.bucket.arn}"}
        }
    }]
}
POLICY

}

resource "aws_sqs_queue" "generate_thumbnail" {
  name = "generate_thumbnail"
}

resource "aws_sqs_queue_policy" "sqs_policy_generate_thumbnail" {
  queue_url = aws_sqs_queue.generate_thumbnail.id

// TODO: make it specific by limiting the principle
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.generate_thumbnail.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_sns_topic.post_image.arn}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_sqs_queue_policy" "sqs_policy_generate_metadata" {
  queue_url = aws_sqs_queue.generate_metadata.id

// TODO: make it specific by limiting the principle
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.generate_metadata.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_sns_topic.post_image.arn}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_sqs_queue" "generate_metadata" {
  name = "generate_metadata"
}

resource "aws_sns_topic_subscription" "post_image_sqs_target1" {
  topic_arn = aws_sns_topic.post_image.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.generate_thumbnail.arn
}

resource "aws_sns_topic_subscription" "post_image_sqs_target2" {
  topic_arn = aws_sns_topic.post_image.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.generate_metadata.arn
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  inline_policy {
    name = "my_inline_policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["s3:*", "sqs:*", "logs:*"]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }
}

resource "aws_lambda_function" "generate_thumbnail" {
  function_name = "generate_thumbnail"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambdas/generate_thumbnail.lambda_handler"
  filename      = "../generate-thumbnail.zip"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("../generate-thumbnail.zip")
  timeout = 10
  runtime = "python3.8"
  layers = ["arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p38-Pillow:1"]

}

# Event source from SQS
resource "aws_lambda_event_source_mapping" "sqs_map_generate_thumbnail" {
  event_source_arn = aws_sqs_queue.generate_thumbnail.arn
  enabled          = true
  function_name    = aws_lambda_function.generate_thumbnail.arn
  batch_size       = 1
}

resource "aws_lambda_function" "generate_metadata" {
  function_name = "generate_metadata"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambdas/generate_metadata.lambda_handler"
  filename      = "../generate-metadata.zip"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("../generate-metadata.zip")
  timeout = 10
  runtime = "python3.8"
  layers = ["arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p38-Pillow:1"]

}

# Event source from SQS
resource "aws_lambda_event_source_mapping" "sqs_map_generate_metadata" {
  event_source_arn = aws_sqs_queue.generate_metadata.arn
  enabled          = true
  function_name    = aws_lambda_function.generate_metadata.arn
  batch_size       = 1
}

# resource "aws_s3_bucket_notification" "bucket_notification" {
#   bucket = aws_s3_bucket.bucket.id

#   topic {
#     topic_arn     = aws_sns_topic.post_image.arn
#     events        = ["s3:ObjectCreated:Put"]
#   }
# }

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id
  eventbridge = true
  # topic {
  #   topic_arn     = aws_sns_topic.post_image.arn
  #   events        = ["s3:ObjectCreated:Put"]
  # }
}

resource "aws_s3_bucket" "bucket" {
  bucket = "dev-s3-bucket-234asdf"
}

resource "aws_s3_bucket" "bucket2" {
  bucket = "dev-s3-bucket-234asdf-resized"
}

resource "aws_cloudwatch_event_rule" "s3tosns" {
  name        = "s3-putobject-to-sns"
  description = "event bridge rule to send a notification from S3 to SNS"

  event_pattern = <<PATTERN
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {
      "name": ["${aws_s3_bucket.bucket.id}"]
    }
  }
}
PATTERN
}

resource "aws_cloudwatch_event_target" "snstarget" {
  target_id = "snstarget"
  rule      = aws_cloudwatch_event_rule.s3tosns.name
  arn       = aws_sns_topic.post_image.arn
}
