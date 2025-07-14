# main.tf - Main Terraform configuration file

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1" # Example region, choose your desired AWS region
}

# -----------------------------------------------------------------------------
# 1. Networking (VPC, Subnets, Internet Gateway)
# -----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0" # Use a specific version

  name = "b2b-ecommerce-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"] # Deploy across multiple AZs for high availability
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true # For cost optimization, consider false for higher availability
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = {
    Environment = "Development"
    Project     = "B2BEcommerce"
  }
}

# -----------------------------------------------------------------------------
# 2. Frontend Hosting (S3, CloudFront)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "b2b-ecommerce-frontend-static-assets-${var.environment}" # Unique bucket name
  acl    = "private" # S3 bucket should be private, CloudFront will access it

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { AWS = aws_cloudfront_origin_access_identity.s3_origin_access_identity.iam_arn },
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_cloudfront_origin_access_identity" "s3_origin_access_identity" {
  comment = "OAI for B2B E-commerce S3 bucket"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "S3-B2B-Frontend-Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for B2B E-commerce frontend"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "S3-B2B-Frontend-Origin"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

# -----------------------------------------------------------------------------
# 3. Backend (API Gateway & Lambda) - Example for a single microservice
# -----------------------------------------------------------------------------

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_exec_role" {
  name = "b2b-ecommerce-lambda-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Example Lambda Function (e.g., for Product Catalog)
resource "aws_lambda_function" "product_catalog_lambda" {
  function_name = "b2b-product-catalog-service-${var.environment}"
  handler       = "index.handler" # Assuming Node.js or Python handler
  runtime       = "nodejs18.x"    # Or python3.9, etc.
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 30 # seconds
  memory_size   = 128 # MB

  # For simplicity, using a local zip. In production, use S3 bucket for code.
  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_code/product_catalog" # Path to your Lambda code
  output_path = "${path.module}/lambda_code/product_catalog.zip"
}

# Security Group for Lambda functions in VPC
resource "aws_security_group" "lambda_sg" {
  name        = "b2b-ecommerce-lambda-sg-${var.environment}"
  description = "Allow outbound traffic for Lambda functions"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

# API Gateway for the Lambda function
resource "aws_api_gateway_rest_api" "b2b_api" {
  name        = "b2b-ecommerce-api-${var.environment}"
  description = "API Gateway for B2B E-commerce Microservices"

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

resource "aws_api_gateway_resource" "product_resource" {
  rest_api_id = aws_api_gateway_rest_api.b2b_api.id
  parent_id   = aws_api_gateway_rest_api.b2b_api.root_resource_id
  path_part   = "products"
}

resource "aws_api_gateway_method" "product_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.b2b_api.id
  resource_id   = aws_api_gateway_resource.product_resource.id
  http_method   = "GET"
  authorization = "NONE" # For public endpoints, use COGNITO_USER_POOLS for authenticated.
}

resource "aws_api_gateway_integration" "product_lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.b2b_api.id
  resource_id             = aws_api_gateway_resource.product_resource.id
  http_method             = aws_api_gateway_method.product_get_method.http_method
  integration_http_method = "POST" # Lambda proxy integration typically uses POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.product_catalog_lambda.invoke_arn
}

resource "aws_lambda_permission" "apigateway_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.product_catalog_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.b2b_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "b2b_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.b2b_api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.b2b_api.body)) # Trigger redeployment on API changes
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "b2b_api_stage" {
  deployment_id = aws_api_gateway_deployment.b2b_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.b2b_api.id
  stage_name    = var.environment

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

# -----------------------------------------------------------------------------
# 4. Database (DynamoDB Example)
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "product_catalog_table" {
  name         = "b2b-product-catalog-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # On-demand capacity for cost efficiency and auto-scaling
  hash_key     = "ProductId"

  attribute {
    name = "ProductId"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}

# -----------------------------------------------------------------------------
# 5. Monitoring (CloudWatch Log Group for Lambda)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.product_catalog_lambda.function_name}"
  retention_in_days = 30 # Adjust retention as needed

  tags = {
    Environment = var.environment
    Project     = "B2BEcommerce"
  }
}
