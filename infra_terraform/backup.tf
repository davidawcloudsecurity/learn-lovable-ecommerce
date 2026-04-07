# ============================================================
# AWS Backup — using modular approach from gen-ai-platform-infra
# ============================================================

# Existing standalone vaults (kept for backward compatibility with locked vaults)
resource "aws_backup_vault" "main" {
  name          = "ecommerce-backup-vault"
  force_destroy = true
}

resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  changeable_for_days = 3
  min_retention_days  = 1
  max_retention_days  = 35
}

resource "aws_backup_vault" "v2" {
  name          = "ecommerce-backup-vault-2"
  force_destroy = true
}

resource "aws_backup_vault_lock_configuration" "v2" {
  backup_vault_name  = aws_backup_vault.v2.name
  min_retention_days = 1
  max_retention_days = 35
}

resource "aws_backup_vault" "v3" {
  name          = "ecommerce-backup-vault-no-governance"
  force_destroy = true
}

# ============================================================
# Modular AWS Backup (duplicated from gen-ai-platform-infra)
# ============================================================
module "backup" {
  source = "./modules/aws-backup"

  name         = "main"
  agency_code  = "demo"
  environment  = "dev"
  project_code = "ecommerce"

  # No KMS key — set to null for testing
  kms_key_arn = null

  # Disable vault policy for testing (allows deleting recovery points)
  enable_vault_policy = false

  # Backup rules — daily + weekly like the original inline plan
  backup_rules = [
    {
      rule_name                = "DailyBackup"
      schedule                 = "cron(0 5 ? * * *)"
      enable_continuous_backup = false
      start_window             = 60
      completion_window        = 180
      lifecycle = {
        delete_after = 7
      }
    },
    {
      rule_name                = "WeeklyBackup"
      schedule                 = "cron(0 5 ? * SUN *)"
      enable_continuous_backup = false
      start_window             = 60
      completion_window        = 180
      lifecycle = {
        delete_after = 30
      }
    }
  ]

  # Explicit backup selections targeting EC2 + RDS by ARN
  backup_selections = [
    {
      name = "ec2-instances"
      resources = [
        aws_instance.frontend.arn,
        aws_instance.backend.arn,
      ]
    },
    {
      name = "rds-instances"
      resources = [
        aws_db_instance.postgres.arn,
      ]
    }
  ]
}

# ============================================================
# On-demand backup on terraform apply
# ============================================================
resource "null_resource" "backup_rds" {
  depends_on = [module.backup]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${module.backup.backup_vault_name} --resource-arn ${aws_db_instance.postgres.arn} --iam-role-arn ${module.backup.backup_role_arn} --lifecycle '{\"DeleteAfterDays\":7}' --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "backup_frontend" {
  depends_on = [module.backup]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${module.backup.backup_vault_name} --resource-arn ${aws_instance.frontend.arn} --iam-role-arn ${module.backup.backup_role_arn} --lifecycle '{\"DeleteAfterDays\":7}' --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "backup_backend" {
  depends_on = [module.backup]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${module.backup.backup_vault_name} --resource-arn ${aws_instance.backend.arn} --iam-role-arn ${module.backup.backup_role_arn} --lifecycle '{\"DeleteAfterDays\":7}' --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}
