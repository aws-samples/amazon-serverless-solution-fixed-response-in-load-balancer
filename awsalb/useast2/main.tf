provider "aws" {
  region = var.aws_region
}

# AWS IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_east2"
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

# Additional IAM policies for the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_vpc_access_execution_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "elb_readonly_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "elb_full_access_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = aws_iam_role.lambda_role.name
}

# AWS Lambda for apply503.py
resource "aws_lambda_function" "apply503_lambda" {
  filename      = "apply503.zip"
  function_name = "apply503_lambda_east2"
  role          = aws_iam_role.lambda_role.arn
  handler       = "apply503.lambda_handler"
  runtime       = "python3.8"
}

# AWS Lambda for revert503.py
resource "aws_lambda_function" "revert503_lambda" {
  filename      = "revert503.zip"
  function_name = "revert503_lambda_east2"
  role          = aws_iam_role.lambda_role.arn
  handler       = "revert503.lambda_handler"
  runtime       = "python3.8"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = var.subnet1_cidr
  availability_zone = var.availability_zone_subnet1
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = var.subnet2_cidr
  availability_zone = var.availability_zone_subnet2
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route" "route_to_internet" {
  route_table_id         = aws_vpc.my_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_igw.id
}

resource "aws_lb" "my_load_balancer" {
  name    = "my-load-balancer-east2"
  subnets = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

resource "aws_security_group" "lb_sg" {
  name_prefix = "lb-sg-east2"

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "target_group1" {
  name        = "target-group-1-east2"
  port        = 1000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpc.id
}

resource "aws_lb_target_group" "target_group2" {
  name        = "target-group-2-east2"
  port        = 2000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpc.id
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.my_load_balancer.arn
  port              = 8000
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.target_group1.arn
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "listener_rule1" {
  listener_arn = aws_lb_listener.listener.arn
  priority     = 1

  action {
    type           = "forward"
    target_group_arn = aws_lb_target_group.target_group1.arn
  }

  condition {
    http_header {
      http_header_name  = "User-Agent"
      values = ["Mozilla"]
    }
  }

  condition {
    http_header {
      http_header_name  = "Referer"
      values = ["https://www.amazon.com/"]
    }
  }
}

resource "aws_lb_listener_rule" "listener_rule2" {
  listener_arn = aws_lb_listener.listener.arn
  priority     = 2

  action {
    type           = "forward"
    target_group_arn = aws_lb_target_group.target_group2.arn
  }

  condition {
    http_header {
      http_header_name  = "User-Agent"
      values = ["Chrome"]
    }
  }
}

resource "aws_lb_listener_rule" "listener_rule3" {
  listener_arn = aws_lb_listener.listener.arn
  priority     = 3

  action {
    type  = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "You've reached the listener! Congrats!"
      status_code  = "503"
    }
  }

  condition {
    source_ip {
      values = ["10.0.0.1/32"]
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "load_balancer_alarm" {
  alarm_name          = "load-balancer-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0

  dimensions = {
    LoadBalancer = aws_lb.my_load_balancer.name
    TargetGroup  = aws_lb_target_group.target_group1.name
  }
}

# AWS API Gateway
resource "aws_api_gateway_rest_api" "my_api" {
  name        = "MyAPI-east2"
  description = "My API Gateway"
}

# API Gateway resource for /maint
resource "aws_api_gateway_resource" "maint_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "maint"
}

# API Gateway resource for /original
resource "aws_api_gateway_resource" "original_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "original"
}

# API Gateway method for /maint
resource "aws_api_gateway_method" "maint_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.maint_resource.id
  http_method   = "PUT"
  authorization = "NONE"
}

# API Gateway method for /original
resource "aws_api_gateway_method" "original_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.original_resource.id
  http_method   = "PUT"
  authorization = "NONE"
}

# API Gateway integration for /maint
resource "aws_api_gateway_integration" "maint_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.maint_resource.id
  http_method             = aws_api_gateway_method.maint_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.apply503_lambda.invoke_arn
}

# API Gateway integration for /original
resource "aws_api_gateway_integration" "original_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.original_resource.id
  http_method             = aws_api_gateway_method.original_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.revert503_lambda.invoke_arn
}

# API Gateway method response for /maint
resource "aws_api_gateway_method_response" "maint_method_response" {
  depends_on   = [aws_api_gateway_integration.maint_integration]
  rest_api_id  = aws_api_gateway_rest_api.my_api.id
  resource_id  = aws_api_gateway_resource.maint_resource.id
  http_method  = aws_api_gateway_method.maint_method.http_method
  status_code  = "200"
}

# API Gateway method response for /original
resource "aws_api_gateway_method_response" "original_method_response" {
  depends_on   = [aws_api_gateway_integration.original_integration]
  rest_api_id  = aws_api_gateway_rest_api.my_api.id
  resource_id  = aws_api_gateway_resource.original_resource.id
  http_method  = aws_api_gateway_method.original_method.http_method
  status_code  = "200"
}

# API Gateway integration response for /maint
resource "aws_api_gateway_integration_response" "maint_integration_response" {
  depends_on   = [aws_api_gateway_deployment.my_api_deployment]
  rest_api_id  = aws_api_gateway_rest_api.my_api.id
  resource_id  = aws_api_gateway_resource.maint_resource.id
  http_method  = aws_api_gateway_method.maint_method.http_method
  status_code  = "200"
  response_templates = {
    "application/json" = ""
  }
}

# API Gateway integration response for /original
resource "aws_api_gateway_integration_response" "original_integration_response" {
  depends_on   = [aws_api_gateway_deployment.my_api_deployment]
  rest_api_id  = aws_api_gateway_rest_api.my_api.id
  resource_id  = aws_api_gateway_resource.original_resource.id
  http_method  = aws_api_gateway_method.original_method.http_method
  status_code  = "200"
  response_templates = {
    "application/json" = jsonencode({ "message": "Reverted 503" })
  }
}

resource "aws_api_gateway_deployment" "my_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  stage_name  = "prod"

  # Create a deployment when there are methods defined
  depends_on = [
    aws_api_gateway_method.maint_method,
    aws_api_gateway_method.original_method,
    aws_api_gateway_integration.maint_integration,
    aws_api_gateway_integration.original_integration,
  ]  
}

# AWS Lambda Permissions for API Gateway
resource "aws_lambda_permission" "apply503_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvokeApply503"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.apply503_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Construct the ARN by removing "/prod" and appending "/*/PUT/maint" to the execution ARN
  source_arn    = replace(aws_api_gateway_deployment.my_api_deployment.execution_arn, "/prod", "/*/PUT/maint")
}

resource "aws_lambda_permission" "revert503_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvokeRevert503"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.revert503_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  
  # Construct the ARN by removing "/prod" and appending "/*/PUT/maint" to the execution ARN
  source_arn    = replace(aws_api_gateway_deployment.my_api_deployment.execution_arn, "/prod", "/*/PUT/original")
}

# Add the SNS Topic
resource "aws_sns_topic" "my_sns_topic" {
  name = "MySNSTopic-east2"
}

# Create SNS topic subscriptions for each email address
resource "aws_sns_topic_subscription" "email_subscription_1" {
  topic_arn = aws_sns_topic.my_sns_topic.arn
  protocol  = "email"
  endpoint  = "user1@example.com"
}

# Modify the Lambda Role Permissions
data "aws_iam_policy_document" "lambda_publish_sns" {
  statement {
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.my_sns_topic.arn]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_sns_publish_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"  # Alternatively, you can use a custom policy if you want to restrict access
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_policy" "lambda_publish_sns_policy" {
  name        = "lambda-publish-sns-policy-east2"
  description = "Allows Lambda to publish to the SNS topic"
  policy      = data.aws_iam_policy_document.lambda_publish_sns.json
}

resource "aws_iam_role_policy_attachment" "lambda_publish_sns_policy_attachment" {
  policy_arn = aws_iam_policy.lambda_publish_sns_policy.arn
  role       = aws_iam_role.lambda_role.name
}

# Outputs
output "api_gateway_base_url" {
  value = aws_api_gateway_deployment.my_api_deployment.invoke_url
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "subnet1_cidr" {
  default = "10.0.1.0/24"
}

variable "subnet2_cidr" {
  default = "10.0.2.0/24"
}

variable "availability_zone_subnet1" {
  default = "us-east-2c"
}

variable "availability_zone_subnet2" {
  default = "us-east-2b"
}
