module "ecr_main" {
  source = "./modules/aws-ecr"  # Update path if needed

  # Required variables
  name         = "predictal-app"
  env_abbr     = "dev"
  region       = "us-east-1"

  # Encryption
  encryption_type        = "AES256"         # Or "KMS"
  enable_scanning_on_push = true
  scan_type              = "ENHANCED"
  scan_frequency         = "CONTINUOUS"

  # Optional: lifecycle policy
  create_lifecycle_policy = true
  lifecycle_policy        = file("${path.module}/lifecycle.json")

  # Optional: cross-region replication
  replication_regions = ["us-east-2", "us-west-1"]

  # Optional: pull-through cache
  pull_through_cache_rules = [
    {
      ecr_repository_prefix = "dockerhub"
      upstream_registry_url = "public.ecr.aws/docker/library"
    }
  ]

  # IAM access (repository policy)
  allowed_principals = [
    "arn:aws:iam::123456789012:role/ECRReaderRole"
  ]

  # PrivateLink (VPC endpoints)
  create_vpc_endpoints = true
  vpc_id               = "vpc-abc123"
  subnet_ids           = ["subnet-aaa111", "subnet-bbb222"]
  security_group_ids   = ["sg-xyz333"]

  # Optional: AWS Signer and CloudTrail
  enable_signing_profile      = true
  create_cloudtrail           = false  # Set to true if needed
  cloudtrail_s3_bucket_name   = "your-cloudtrail-bucket-name"
  cloudtrail_logs_role_arn    = "arn:aws:iam::123456789012:role/CloudTrailWriteRole"
  cloudtrail_log_retention    = 30

  tags = {
    Project     = "Predictal"
    Environment = "Dev"
    Owner       = "Platform Team"
  }
}
