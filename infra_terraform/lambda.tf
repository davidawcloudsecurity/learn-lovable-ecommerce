# Create Lambda deployment package
resource "null_resource" "lambda_zip" {
  triggers = {
    # Re-zip when any Lambda file changes
    lambda_code = filemd5("../lambda/lambda.js")
    app_code    = filemd5("../lambda/app.js")
    package_json = filemd5("../lambda/package.json")
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ../lambda
      zip -r lambda-api.zip . -x "*.zip" "node_modules/*"
    EOT
  }
}

# Check if role exists
data "aws_iam_role" "existing_role" {
  count = var.create_new_role ? 0 : 1
  name  = "lambda-execution-role"
}

# Data source to calculate hash after zip is created
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../lambda"
  output_path = "../lambda/lambda-api.zip"
  excludes    = ["lambda-api.zip", "node_modules"]
  depends_on  = [null_resource.lambda_zip]
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  count = var.create_new_role ? 1 : 0
  name  = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Use local to select the right role ARN
locals {
  lambda_role_arn = var.create_new_role ? aws_iam_role.lambda_role[0].arn : data.aws_iam_role.existing_role[0].arn
}

# IAM Policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_vpc_policy" {
  count      = var.create_new_role ? 1 : 0
  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "api" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "ecommerce-api"
  role            = local.lambda_role_arn
  handler         = "lambda.handler"
  runtime         = "nodejs16.x"
  timeout         = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      POSTGRES_HOST     = aws_db_instance.postgres.address
      POSTGRES_DB       = aws_db_instance.postgres.db_name
      POSTGRES_USER     = aws_db_instance.postgres.username
      POSTGRES_PASSWORD = aws_db_instance.postgres.password
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_app.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    null_resource.lambda_zip
  ]
}

# Security Group for Lambda
resource "aws_security_group" "lambda_sg" {
  name_prefix = "lambda-sg"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.private_db.id]
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/ecommerce-api"
  retention_in_days = 7
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "ecommerce-api"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api.invoke_arn
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api" {
  depends_on = [
    aws_api_gateway_integration.lambda,
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

# Output API URL
output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}
