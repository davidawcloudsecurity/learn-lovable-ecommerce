data "aws_caller_identity" "current" {}

# ============================================================
# AWS Backup — vault 1 (compliance locked, no selections)
# ============================================================

resource "aws_backup_vault" "main" {
  name = "bkp-vlt-ecommerce-dev-main"
  tags = { Name = "bkp-vlt-ecommerce-dev-main" }
}

resource "aws_backup_vault_policy" "main" {
  backup_vault_name = aws_backup_vault.main.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "backup:DeleteRecoveryPoint"
      Resource  = "*"
    }]
  })
}

resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  changeable_for_days = var.backup_vault_lock_changeable_for_days
  min_retention_days  = 90
  max_retention_days  = var.backup_vault_lock_max_retention_days
}

resource "aws_backup_plan" "main" {
  name = "ecommerce-dev-main-backup"

  rule {
    rule_name         = "DailyBackups"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 ? * * *)"
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

# ============================================================
# AWS Backup — vault 2 (35-day daily, active selections)
# ============================================================

resource "aws_backup_vault" "main_2" {
  name = "bkp-vlt-ecommerce-dev-main-2"
  tags = { Name = "bkp-vlt-ecommerce-dev-main-2" }
}

resource "aws_backup_vault_policy" "main_2" {
  backup_vault_name = aws_backup_vault.main_2.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "backup:DeleteRecoveryPoint"
      Resource  = "*"
    }]
  })
}

resource "aws_backup_vault_lock_configuration" "main_2" {
  backup_vault_name   = aws_backup_vault.main_2.name
  changeable_for_days = var.backup_vault_lock_changeable_for_days
  min_retention_days  = var.backup_vault_lock_min_retention_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
}

resource "aws_backup_plan" "main_2" {
  name = "ecommerce-dev-main-2-backup"

  rule {
    rule_name         = "DailyBackups"
    target_vault_name = aws_backup_vault.main_2.name
    schedule          = "cron(0 2 ? * * *)"
    lifecycle { delete_after = 15 }
  }

  rule {
    rule_name         = "WeeklyBackups"
    target_vault_name = aws_backup_vault.main_2.name
    schedule          = "cron(0 3 ? * SUN *)"
    lifecycle { delete_after = 35 }
  }

  rule {
    rule_name         = "YearlyBackups"
    target_vault_name = aws_backup_vault.main_2.name
    schedule          = "cron(0 4 1 1 ? *)"
    lifecycle { delete_after = 395 }
  }
}

# ============================================================
# IAM Role for AWS Backup (shared by both vaults)
# ============================================================

resource "aws_iam_role" "backup" {
  name = "iam-ecommerce-dev-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = { Name = "iam-ecommerce-dev-backup" }
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
  ])
  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

# ============================================================
# Backup Selections (vault 2)
# ============================================================

resource "aws_backup_selection" "ec2" {
  name         = "ec2-instances"
  plan_id      = aws_backup_plan.main_2.id
  iam_role_arn = aws_iam_role.backup.arn
  resources = [
    aws_instance.frontend.arn,
    aws_instance.backend.arn,
  ]
}

resource "aws_backup_selection" "rds" {
  name         = "rds-instances"
  plan_id      = aws_backup_plan.main_2.id
  iam_role_arn = aws_iam_role.backup.arn
  resources = [
    aws_db_instance.postgres.arn,
  ]
}

resource "aws_backup_selection" "s3" {
  name         = "s3-assets"
  plan_id      = aws_backup_plan.main_2.id
  iam_role_arn = aws_iam_role.backup.arn
  resources = [
    aws_s3_bucket.assets.arn,
  ]
}

/*
resource "null_resource" "backup_rds" {
  depends_on = [aws_backup_vault.main_2]
  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.main_2.name} --resource-arn ${aws_db_instance.postgres.arn} --iam-role-arn ${aws_iam_role.backup.arn} --lifecycle '{\"DeleteAfterDays\":15}' --region ${var.region}"
  }
  triggers = { always_run = timestamp() }
}

resource "null_resource" "backup_frontend" {
  depends_on = [aws_backup_vault.main_2]
  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.main_2.name} --resource-arn ${aws_instance.frontend.arn} --iam-role-arn ${aws_iam_role.backup.arn} --lifecycle '{\"DeleteAfterDays\":15}' --region ${var.region}"
  }
  triggers = { always_run = timestamp() }
}

resource "null_resource" "backup_backend" {
  depends_on = [aws_backup_vault.main_2]
  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.main_2.name} --resource-arn ${aws_instance.backend.arn} --iam-role-arn ${aws_iam_role.backup.arn} --lifecycle '{\"DeleteAfterDays\":15}' --region ${var.region}"
  }
  triggers = { always_run = timestamp() }
}
*/

# ============================================================
# On-demand backup on terraform apply (targets vault 2)
# ============================================================

resource "null_resource" "backup_s3" {
  depends_on = [aws_backup_vault.main_2, aws_s3_bucket_policy.assets]
  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.main_2.name} --resource-arn ${aws_s3_bucket.assets.arn} --iam-role-arn ${aws_iam_role.backup.arn} --lifecycle '{\"DeleteAfterDays\":15}' --region ${var.region}"
  }
  triggers = { always_run = timestamp() }
}

# ============================================================
# Outputs
# ============================================================

output "backup_vault_name" {
  value = aws_backup_vault.main_2.name
}

output "backup_role_arn" {
  value = aws_iam_role.backup.arn
}
