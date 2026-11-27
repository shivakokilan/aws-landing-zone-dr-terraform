output "scp_guardrail_id" {
  description = "AWS Organizations Service Control Policy guardrail ID"
  value       = aws_organizations_policy.guardrail_deny_unencrypted_s3.id
}

output "primary_backup_bucket" {
  description = "Primary S3 archive bucket in UAE (me-central-1)"
  value       = aws_s3_bucket.primary_archive.id
}

output "dr_replica_bucket" {
  description = "Cross-region DR S3 replica bucket in Mumbai (ap-south-1)"
  value       = aws_s3_bucket.dr_replica.id
}

output "aws_backup_vault_arn" {
  description = "ARN of the KMS-encrypted AWS Backup vault"
  value       = aws_backup_vault.primary_vault.arn
}
