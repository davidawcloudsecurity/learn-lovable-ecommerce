# AWS Backup Configuration
resource "aws_backup_vault" "main" {
  name        = "main-backup-vault"
  kms_key_arn = aws_kms_key.documentdb_key.arn
}

resource "aws_backup_plan" "main" {
  name = "main-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 0 * * ? *)"   # Daily at 12 AM UTC (midnight)
    lifecycle {
      delete_after = 365
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "aws-backup-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "all" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "All"
  plan_id      = aws_backup_plan.main.id

  resources = ["*"]
  
  condition {
    string_equals {
      key   = "aws:ResourceTag/Monthly-Backup"
      value = "Y"
    }
  }
}

# Note: AWS Backup does not support ElastiCache
# ElastiCache Redis uses native backup features:
# - snapshot_retention_limit = 1 (configured in main.tf)
# - snapshot_window = "16:00-17:00" (configured in main.tf)
# - final_snapshot_identifier for cluster termination backup
