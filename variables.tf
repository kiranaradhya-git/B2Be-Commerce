# variables.tf - Input variables for the Terraform configuration

variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}
