# ecr2 

Add a toggle

variable "enable_signer" {
  description = "Create AWS Signer profile if true; reuse existing if false"
  type        = bool
  default     = false
}

variable "existing_signing_profile_arn" {
  description = "ARN of existing profile to reuse when enable_signer=false"
  type        = string
  default     = ""
}
2. Wrap resource in conditional count
h
Copy
Edit
resource "aws_signer_signing_profile" "container" {
  count       = var.enable_signer ? 1 : 0
  name        = local.signing_profile_name
  platform_id = var.signer_platform_id

  lifecycle {
    prevent_destroy = true
  }
}
3. Build a “works in both modes” local
hcl
Copy
Edit
locals {
  signing_profile_name = substr(
    replace("ecr-container-signing-${var.env_abbr}-${var.name}", "/[^a-zA-Z0-9]/", ""),
    0,
    64
  )

  signing_profile_arn = var.enable_signer
    ? aws_signer_signing_profile.container[0].arn
    : var.existing_signing_profile_arn
}
4. Use the local everywhere instead of hardcoding
Wherever you reference the signer profile ARN, swap in:


local.signing_profile_arn
5. First-time creation vs. reuse
First run:
enable_signer = true
Terraform creates the profile, stores it in state, and will not try to recreate it next time.

Reuse existing:
enable_signer = false and set existing_signing_profile_arn to the ARN of the existing profile.

Import existing into state (if it’s in AWS but not in Terraform yet):

terraform import aws_signer_signing_profile.container[0] signing-profile/<existing-name>

