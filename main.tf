# ===========================
# Terraform AWS ECR Module
# ===========================
# This module provisions a secure, policy‑driven Amazon Elastic Container Registry (ECR) with the
# following optional capabilities (all driven by variables):
#   • Private *and/or* public repositories
#   • Image scanning on‑push & continuous (enhanced) scanning rules
#   • Tag immutability
#   • KMS‑backed encryption at rest
#   • Lifecycle policies
#   • Pull‑through cache rules (e.g., to Docker Hub)
#   • Cross‑region replication
#   • Repository & registry resource policies
#   • Interface VPC Endpoints for PrivateLink access
#
# ──────────────────────────────────────────────────────────────
# FILE: main.tf
# -------------------------------------------------------------------
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  # Configure via usual AWS_* env vars or shared config/profile.
  region = var.region
}

data "aws_region" "current" {}

# ─────────────────────────────
# Optional customer‑managed KMS
# ─────────────────────────────
resource "aws_kms_key" "this" {
  count               = var.encryption_type == "KMS" && var.kms_key_id == null ? 1 : 0
  description         = "CMK for ECR encryption — managed by module"
  enable_key_rotation = true
  tags                = merge(var.tags, { "Name" = "${var.name}-ecr-kms" })
}

locals {
  kms_key_arn_effective = coalesce(var.kms_key_id, try(aws_kms_key.this[0].arn, null))
}

# ─────────────────────────────
# PRIVATE ECR REPOSITORY
# ─────────────────────────────
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? local.kms_key_arn_effective : null
  }

  scan_on_push = var.enable_scanning_on_push
  tags         = var.tags
}

# ─────────────────────────────
# PUBLIC ECR REPOSITORY (optional)
# ─────────────────────────────
resource "aws_ecrpublic_repository" "public" {
  count           = var.create_public_repo ? 1 : 0
  repository_name = var.name
  catalog_data { about_text = "Public repo for ${var.name}" }
  tags = var.tags
}

# ─────────────────────────────
# LIFECYCLE POLICY (optional)
# ─────────────────────────────
resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.create_lifecycle_policy && var.lifecycle_policy != "" ? 1 : 0
  repository = aws_ecr_repository.this.name
  policy     = var.lifecycle_policy
}

# ─────────────────────────────
# REPLICATION CONFIGURATION (optional)
# ─────────────────────────────
resource "aws_ecr_replication_configuration" "this" {
  count = length(var.replication_regions) > 0 ? 1 : 0

  replication_configuration {
    rules {
      destinations = [
        for r in var.replication_regions : {
          region = r
        }
      ]
    }
  }
}

# ─────────────────────────────
# PULL‑THROUGH CACHE RULES (optional)
# ─────────────────────────────
resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = { for idx, rule in var.pull_through_cache_rules : idx => rule }
  ecr_repository_prefix = each.value.ecr_repository_prefix
  upstream_registry_url = each.value.upstream_registry_url
}

# ─────────────────────────────
# REGISTRY‑WIDE SCANNING CONFIG
# ─────────────────────────────
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = var.scan_type # BASIC | ENHANCED

  rules {
    scan_frequency = "CONTINUOUS" # Keeps vulnerability DB fresh
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

# ─────────────────────────────
# REPOSITORY RESOURCE POLICY (optional)
# ─────────────────────────────
resource "aws_ecr_repository_policy" "this_repo_policy" {
  count      = length(var.allowed_principals) > 0 ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Sid       = "RepoAccess"
      Effect    = "Allow"
      Principal = { AWS = var.allowed_principals }
      Action    = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ]
    }]
  })
}

# ─────────────────────────────
# REGISTRY POLICY (optional)
# ─────────────────────────────
resource "aws_ecr_registry_policy" "this_registry_policy" {
  count  = var.registry_policy != "" ? 1 : 0
  policy = var.registry_policy
}

# ─────────────────────────────
# PRIVATE LINK (Interface VPC Endpoints)
# ─────────────────────────────
resource "aws_vpc_endpoint" "ecr_api" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = var.security_group_ids
  private_dns_enabled = true
  tags                = merge(var.tags, { "Name" = "${var.name}-ecr-api" })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = var.security_group_ids
  private_dns_enabled = true
  tags                = merge(var.tags, { "Name" = "${var.name}-ecr-dkr" })
}

# -------------------------------------------------------------------
# FILE: variables.tf
# -------------------------------------------------------------------
variable "region" {
  description = "AWS region to deploy resources in (provider override)"
  type        = string
  default     = null
}

variable "name" {
  description = "Repository name (will also be used for a public repo if enabled)"
  type        = string
}

variable "create_public_repo" {
  description = "Create a public ECR repo in addition to private"
  type        = bool
  default     = false
}

variable "image_tag_mutability" {
  type        = string
  default     = "IMMUTABLE"
  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "Valid options: IMMUTABLE, MUTABLE"
  }
}

variable "encryption_type" {
  description = "AES256 (default) or KMS"
  type        = string
  default     = "AES256"
  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "Valid options: AES256 or KMS"
  }
}

variable "kms_key_id" {
  description = "Existing CMK ARN to use when encryption_type = KMS (optional)"
  type        = string
  default     = null
}

variable "enable_scanning_on_push" {
  description = "Enable on‑push image scanning"
  type        = bool
  default     = true
}

variable "scan_type" {
  description = "Registry scan type: BASIC or ENHANCED"
  type        = string
  default     = "ENHANCED"
  validation {
    condition     = contains(["BASIC", "ENHANCED"], var.scan_type)
    error_message = "Valid options: BASIC, ENHANCED"
  }
}

variable "create_lifecycle_policy" {
  description = "Attach lifecycle policy JSON provided in lifecycle_policy variable"
  type        = bool
  default     = false
}

variable "lifecycle_policy" {
  description = "Lifecycle policy JSON string"
  type        = string
  default     = ""
}

variable "replication_regions" {
  description = "Set of regions to replicate images to (cross‑region replication)"
  type        = set(string)
  default     = []
}

variable "pull_through_cache_rules" {
  description = "List of pull‑through cache rules objects { ecr_repository_prefix, upstream_registry_url }"
  type = list(object({
    ecr_repository_prefix = string
    upstream_registry_url = string
  }))
  default = []
}

variable "registry_policy" {
  description = "Registry (account‑level) policy JSON"
  type        = string
  default     = ""
}

variable "allowed_principals" {
  description = "List of IAM principal ARNs to grant repo access via resource policy"
  type        = list(string)
  default     = []
}

variable "create_vpc_endpoints" {
  description = "Whether to provision Interface VPC Endpoints for ECR"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID where endpoints will be placed (required if create_vpc_endpoints)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for the interface endpoints"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security Group IDs to associate with the endpoints"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}

# -------------------------------------------------------------------
# FILE: outputs.tf
# -------------------------------------------------------------------
output "repository_url" {
  value       = aws_ecr_repository.this.repository_url
  description = "URI of the private ECR repository"
}

output "repository_arn" {
  value       = aws_ecr_repository.this.arn
  description = "ARN of the private ECR repository"
}

output "public_repository_uri" {
  description = "URI of the public ECR repository (if created)"
  value       = try(aws_ecrpublic_repository.public[0].repository_uri, null)
}

output "kms_key_arn" {
  value       = local.kms_key_arn_effective
  description = "ARN of the CMK used for encryption (if applicable)"
}

output "replication_id" {
  value       = try(aws_ecr_replication_configuration.this[0].id, null)
  description = "ID of the replication configuration rule (if created)"
}

output "vpc_endpoint_ids" {
  value       = concat(
    try([aws_vpc_endpoint.ecr_api[0].id], []),
    try([aws_vpc_endpoint.ecr_dkr[0].id], [])
  )
  description = "IDs of the interface VPC endpoints (if created)"
}
