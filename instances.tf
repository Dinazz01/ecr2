module "my_private_ecr_repo" {
  source = "./modules/aws-ecr"

  create                      = true
  create_repository           = true
  repository_type             = "private"  # key switch for private vs public
  repository_name             = "my-private-repo"
  repository_force_delete     = true
  repository_image_scan_on_push = true
  repository_image_tag_mutability = "MUTABLE"
  repository_encryption_type  = "AES256"
  repository_kms_key          = null  # or a KMS key ARN if needed

  attach_repository_policy    = true
  create_repository_policy    = true

  repository_read_access_arns         = ["arn:aws:iam::111122223333:root"]
  repository_read_write_access_arns   = ["arn:aws:iam::111122223333:user/my-ecr-user"]
  repository_lambda_read_access_arns  = []

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 30 days"
        selection    = {
          tagStatus     = "untagged"
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  create_lifecycle_policy = true

  tags = {
    Environment = "dev"
    Team        = "cloud"
  }
}

============================================================================================

module "my_public_ecr_repo" {
  source = "./modules/aws-ecr"

  create                      = true
  create_repository           = true
  repository_type             = "public"
  repository_name             = "my-public-repo"
  repository_force_delete     = true
  repository_image_scan_on_push = false
  repository_image_tag_mutability = "MUTABLE"
  repository_encryption_type  = "AES256"
  repository_kms_key          = null

  attach_repository_policy    = true
  create_repository_policy    = true

  public_repository_catalog_data = {
    description   = "My public repo"
    about_text    = "Public ECR for community images"
    usage_text    = "Use freely"
    architectures = ["x86"]
    operating_systems = ["Linux"]
  }

  repository_read_access_arns       = ["*"]
  repository_read_write_access_arns = []

  tags = {
    Environment = "public"
  }
}















