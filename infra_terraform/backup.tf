# AWS Backup Configuration
resource "aws_backup_vault" "main" {
  name = "main-backup-vault"
}

resource "aws_backup_vault_policy" "main" {
  backup_vault_name = aws_backup_vault.main.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyBackupDeletion"
        Effect = "Deny"
        Principal = "*"
        Action = [
          "backup:DeleteBackupVault",
          "backup:DeleteRecoveryPoint"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name           = aws_backup_vault.main.name
  changeable_for_days         = 30
  min_retention_days          = 90
  max_retention_days          = 2555
}

resource "aws_backup_plan" "main" {
  name = "main-backup-plan"

  rule {
    rule_name         = "DailyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(25 5 ? * * *)"   # Daily at 2AM SGT
    lifecycle {
      cold_storage_after = 30
      delete_after       = 120
    }
  }

  rule {
    rule_name         = "WeeklyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 ? * SUN *)"   # Weekly on Sunday at 3AM SGT
    lifecycle {
      cold_storage_after = 90
      delete_after       = 365
    }
  }

  rule {
    rule_name         = "MonthlyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 4 1 * ? *)"   # First day of every month at 4AM SGT
    lifecycle {
      cold_storage_after = 90
      delete_after       = 2555
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
