# outputs.tf - Output values from the Terraform deployment

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution for the frontend."
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "api_gateway_invoke_url" {
  description = "The invoke URL of the API Gateway stage."
  value       = aws_api_gateway_stage.b2b_api_stage.invoke_url
}

output "product_catalog_dynamodb_table_name" {
  description = "The name of the DynamoDB product catalog table."
  value       = aws_dynamodb_table.product_catalog_table.name
}
