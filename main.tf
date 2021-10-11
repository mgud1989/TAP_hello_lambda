terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "" 
  region  = ""
}

# API Gateway

resource "aws_api_gateway_rest_api" "APIHello" {
  name = "APIHello"
}

resource "aws_api_gateway_method" "GETMethod" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_rest_api.APIHello.root_resource_id
  rest_api_id   = aws_api_gateway_rest_api.APIHello.id
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.APIHello.id
  resource_id             = aws_api_gateway_rest_api.APIHello.root_resource_id
  http_method             = aws_api_gateway_method.GETMethod.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambdaHelloWorld.invoke_arn
}

resource "aws_api_gateway_method_response" "response200" {
  rest_api_id = aws_api_gateway_rest_api.APIHello.id
  resource_id = aws_api_gateway_rest_api.APIHello.root_resource_id
  http_method = aws_api_gateway_method.GETMethod.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "integrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.APIHello.id
  resource_id = aws_api_gateway_rest_api.APIHello.root_resource_id
  http_method = aws_api_gateway_method.GETMethod.http_method
  status_code = aws_api_gateway_method_response.response200.status_code
  depends_on  = [
    aws_api_gateway_method.GETMethod,
    aws_api_gateway_integration.integration
  ]
}

resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.APIHello.id

  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_api_gateway_method.GETMethod,
    aws_api_gateway_integration.integration,
    aws_api_gateway_integration_response.integrationResponse
  ]
}

resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.deploy.id
  rest_api_id   = aws_api_gateway_rest_api.APIHello.id
  stage_name    = "dev"
}

# Lambda

resource "aws_iam_role" "lambdaRole" {
  name = "lambdaRole"

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
}

data "archive_file" "lambdaHelloWorldZip" {  
  type = "zip"
  source_dir  = "${path.module}/hello-world"  
  output_path = "${path.module}/hello-world.zip"
  }

resource "aws_lambda_function" "lambdaHelloWorld" {
  filename         = "${path.module}/hello-world.zip"
  function_name    = "hello-world"
  role             = aws_iam_role.lambdaRole.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambdaHelloWorldZip.output_base64sha256
#  source_code_hash = filebase64sha256("${path.module}/hello-world.zip")
  runtime          = "nodejs14.x"
  depends_on  = [
    data.archive_file.lambdaHelloWorldZip
  ]
}

resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowAPIInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "hello-world"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.APIHello.execution_arn}/*/GET/*"
}

output "endpoint" {
  value = aws_api_gateway_stage.dev.invoke_url
}
