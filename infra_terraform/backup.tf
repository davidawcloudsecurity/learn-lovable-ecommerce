# ============================================================
# AWS Backup — modular approach from gen-ai-platform-infra (PRD)
# ============================================================
module "backup" {
  source = "./modules/aws-backup"

  name         = "main"
  agency_code  = "demo"
  environment  = "dev"
  project_code = "ecommerce"

  # No KMS key — set to null for testing
  kms_key_arn = null

  # Vault policy — prevent backup deletion (prod pattern)
  enable_vault_policy = true

  # Vault lock — WORM compliance (prod pattern)
  enable_vault_lock              = true
  vault_lock_changeable_for_days = 30     # 3-day grace period to modify lock
  vault_lock_min_retention_days  = 90   # Minimum 90-day retention
  vault_lock_max_retention_days  = 2555 # Maximum 7-year retention

  # Backup rules — prod pattern: daily + weekly + monthly with cold storage tiering
  backup_rules = [
    {
      rule_name                = "DailyBackups"
      schedule                 = "cron(0 2 ? * * *)"
      enable_continuous_backup = false
      lifecycle = {
        cold_storage_after = 30  # Move to cold storage after 30 days
        delete_after       = 120 # Keep for 120 days total
      }
    },
    {
      rule_name                = "WeeklyBackups"
      schedule                 = "cron(0 3 ? * SUN *)"
      enable_continuous_backup = false
      lifecycle = {
        cold_storage_after = 90  # Move to cold storage after 90 days
        delete_after       = 365 # Keep for 1 year
      }
    },
    {
      rule_name                = "MonthlyBackups"
      schedule                 = "cron(0 4 1 * ? *)"
      enable_continuous_backup = false
      lifecycle = {
        cold_storage_after = 90   # Move to cold storage after 90 days
        delete_after       = 2555 # Keep for 7 years (compliance)
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
# AWS Backup — new vault (-2) with 35-day daily retention
# ============================================================
module "backup_2" {
  source = "./modules/aws-backup"

  name         = "main-2"
  agency_code  = "demo"
  environment  = "dev"
  project_code = "ecommerce"

  kms_key_arn = null

  enable_vault_policy = true

  # Vault lock with 35-day minimum to allow shorter daily retention
  enable_vault_lock              = true
  vault_lock_changeable_for_days = 30
  vault_lock_min_retention_days  = 15
  vault_lock_max_retention_days  = 2555

  backup_rules = [
    {
      rule_name                = "DailyBackups"
      schedule                 = "cron(0 2 ? * * *)"
      enable_continuous_backup = false
      lifecycle = {
        delete_after = 15
      }
    },
    {
      rule_name                = "WeeklyBackups"
      schedule                 = "cron(0 3 ? * SUN *)"
      enable_continuous_backup = false
      lifecycle = {
        delete_after = 35
      }
    },
    {
      rule_name                = "MonthlyBackups"
      schedule                 = "cron(0 4 1 1 ? *)"
      enable_continuous_backup = false
      lifecycle = {
        delete_after = 395
      }
    }
  ]

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
# On-demand backup on terraform apply (targets -2 vault)
# ============================================================
resource "null_resource" "backup_rds" {
  depends_on = [module.backup_2]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${module.backup_2.backup_vault_name} --resource-arn ${aws_db_instance.postgres.arn} --iam-role-arn ${module.backup_2.backup_role_arn} --lifecycle '{\"DeleteAfterDays\":15}' --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "backup_frontend" {
  depends_on = [module.backup_2]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${module.backup_2.backup_vault_name} --resource-arn ${aws_instance.frontend.arn} --iam-role-arn ${module.backup_2.backup_role_arn} --lifecycle '{\"DeleteAfterDays\":15}' --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "null_resource" "backup_backend" {
  depends_on = [module.backup_2]

  provisioner "local-exec" {
    command = "aws backup start-backup-job --backup-vault-name ${module.backup_2.backup_vault_name} --resource-arn ${aws_instance.backend.arn} --iam-role-arn ${module.backup_2.backup_role_arn} --lifecycle '{\"DeleteAfterDays\":15}' --region ${var.region}"
  }

  triggers = {
    always_run = timestamp()
  }
}
