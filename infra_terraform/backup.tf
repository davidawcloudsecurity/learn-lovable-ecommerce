# ============================================================
# AWS Backup — covers EC2 instances and RDS
# ============================================================

resource "aws_backup_vault" "main" {
  name          = "ecommerce-backup-vault"
  force_destroy = true
}

# Governance-mode vault lock (no changeable_for_days = no compliance mode)
resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name = aws_backup_vault.main.name
  min_retention_days = 1
  max_retention_days = 35
}

resource "aws_backup_plan" "main" {
  name = "ecommerce-backup-plan"

  # Daily backup — keep 7 days
  rule {
    rule_name         = "DailyBackup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 ? * * *)"
    start_window      = 60
    completion_window  = 180

    lifecycle {
      delete_after = 7
    }
  }

  # Weekly backup — keep 30 days
  rule {
    rule_name         = "WeeklyBackup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 ? * SUN *)"
    start_window      = 60
    completion_window  = 180

    lifecycle {
      delete_after = 30
    }
  }
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "ecommerce-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restores" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup selection — EC2 instances
resource "aws_backup_selection" "ec2" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "ec2-instances"
  plan_id      = aws_backup_plan.main.id

  resources = [
    aws_instance.frontend.arn,
    aws_instance.backend.arn,
  ]
}

# Backup selection — RDS
resource "aws_backup_selection" "rds" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "rds-instances"
  plan_id      = aws_backup_plan.main.id

  resources = [
    aws_db_instance.postgres.arn,
  ]
}

# ============================================================
# On-demand backup on terraform apply
# ============================================================
resource "null_resource" "backup_rds" {
  depends_on = [aws_backup_selection.rds]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.main.name} --resource-arn ${aws_db_instance.postgres.arn} --iam-role-arn ${aws_iam_role.backup.arn} --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "backup_frontend" {
  depends_on = [aws_backup_selection.ec2]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.main.name} --resource-arn ${aws_instance.frontend.arn} --iam-role-arn ${aws_iam_role.backup.arn} --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "backup_backend" {
  depends_on = [aws_backup_selection.ec2]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.main.name} --resource-arn ${aws_instance.backend.arn} --iam-role-arn ${aws_iam_role.backup.arn} --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}
