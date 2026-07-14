output "backup_bucket_id" {
  description = "Name of the backup S3 bucket."
  value       = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  description = "ARN of the backup S3 bucket."
  value       = aws_s3_bucket.backup.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt backups."
  value       = aws_kms_key.backup.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key."
  value       = aws_kms_alias.backup.name
}

output "log_bucket_id" {
  description = "Name of the S3 access-log bucket."
  value       = aws_s3_bucket.logs.id
}
