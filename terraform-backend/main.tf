terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "twin"
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

locals {
  backend_bucket = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
  backend_table  = "${var.project_name}-terraform-locks"
}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.backend_bucket

  tags = {
    Name        = "Terraform State Bucket"
    Project     = var.project_name
    ManagedBy   = "terraform"
    Purpose     = "terraform-state"
  }
}

# Enable versioning for state file history
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.backend_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "Terraform State Lock Table"
    Project   = var.project_name
    ManagedBy = "terraform"
    Purpose   = "terraform-locks"
  }
}

# Outputs
output "backend_bucket" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "backend_table" {
  description = "DynamoDB table name for Terraform locks"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_region" {
  description = "AWS region for backend resources"
  value       = var.region
}