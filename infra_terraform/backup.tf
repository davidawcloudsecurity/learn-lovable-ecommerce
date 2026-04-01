# AWS Backup Configuration
resource "aws_backup_vault" "main" {
  name          = "main-backup-vault"
  kms_key_arn   = aws_kms_key.documentdb_key.arn
  force_destroy = true
}

# NOTE: Vault policy removed — the Deny on DeleteBackupVault/DeleteRecoveryPoint
# blocks terraform destroy. If you need it in production, add it back but be aware
# you'll need to manually remove the policy before destroying.

# NOTE: Vault lock removed — once changeable_for_days expires it becomes compliance
# mode and recovery points cannot be deleted until retention expires (90+ days).
# This blocks terraform destroy. Use governance-mode vault below instead.

# Governance-mode vault — allows privileged users to manage lock/retention
resource "aws_backup_vault" "governance" {
  name          = "governance-backup-vault"
  kms_key_arn   = aws_kms_key.documentdb_key.arn
  force_destroy = true
}

resource "aws_backup_vault_lock_configuration" "governance" {
  backup_vault_name   = aws_backup_vault.governance.name
  changeable_for_days = 30
  min_retention_days  = 1
  max_retention_days  = 2555
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
