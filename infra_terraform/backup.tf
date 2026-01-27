# AWS Backup Configuration
resource "aws_backup_vault" "main" {
  name        = "main-backup-vault"
  kms_key_arn = aws_kms_key.rds_key.arn
}

resource "aws_backup_plan" "main" {
  name = "main-backup-plan"

  rule {
    rule_name         = "DailyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(25 5 ? * * *)"
    lifecycle {
      cold_storage_after = 30
      delete_after       = 120
    }
  }

  rule {
    rule_name         = "WeeklyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 ? * SUN *)"
    lifecycle {
      cold_storage_after = 90
      delete_after       = 365
    }
  }

  rule {
    rule_name         = "MonthlyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 4 1 * ? *)"
    lifecycle {
      cold_storage_after = 90
      delete_after       = 2555
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "aws-backup-service-role-2"

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
