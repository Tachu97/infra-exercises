variable "aws_region" {
  description = "AWS region where the backup bucket is created."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for backups."
  type        = string
  default     = "my-app-backups-prod"
}

variable "backup_uploader_role_arn" {
  description = "ARN of the cross-account IAM role allowed to upload backups."
  type        = string
  default     = "arn:aws:iam::123456789012:role/backup_uploader"
}

variable "log_bucket_name" {
  description = "Name for the S3 access-log bucket (created alongside the main bucket)."
  type        = string
  default     = "my-app-backups-prod-access-logs"
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default = {
    ManagedBy   = "terraform"
    Environment = "production"
    Purpose     = "backup"
  }
}
