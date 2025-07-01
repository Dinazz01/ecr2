module "ecr_main" {
  source = "./modules/aws-ecr" # Adjust path if module is remote or renamed

  name                   = "my-app-repo"
  region                 = "us-east-1"
  image_tag_mutability   = "IMMUTABLE"
  encryption_type        = "KMS" # or "AES256"
  enable_scanning_on_push = true
  scan_type              = "ENHANCED"

  create_lifecycle_policy = true
  lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })

  replication_regions = ["us-west-1", "us-east-2"]

  pull_through_cache_rules = [
    {
      ecr_repository_prefix = "dockerhub"
      upstream_registry_url = "public.ecr.aws/docker/library"
    }
  ]

  allowed_principals = [
    "arn:aws:iam::123456789012:role/ECRReaderRole"
  ]

  registry_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = "*",
      Action = ["ecr:DescribeRepositories"]
    }]
  })

  create_vpc_endpoints = true
  vpc_id               = "vpc-0123456789abcdef0"
  subnet_ids           = ["subnet-0123abcd", "subnet-0456efgh"]
  security_group_ids   = ["sg-01a2bc3d"]

  tags = {
    Environment = "dev"
    Team        = "platform"
  }
}
