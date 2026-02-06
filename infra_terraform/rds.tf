# RDS Subnet Group (matching production configuration)
resource "aws_db_subnet_group" "sqlserver_subnet_group" {
  name       = "ecommerce-sqlserver-subnet-group"
  subnet_ids = [aws_subnet.private_db.id, aws_subnet.private_db_1b.id]
  description = "Database subnet group for SQL Server"

  tags = {
    Name = "ecommerce-sqlserver-subnet-group"
    Project = "ecommerce"
    Environment = "uat"
  }
}

# RDS Parameter Group (matching production SQL Server configuration)
resource "aws_db_parameter_group" "sqlserver_params" {
  family = "sqlserver-ee-16.0"
  name   = "ecommerce-sqlserver-params"
  description = "SQL Server parameter group for ecommerce project"

  tags = {
    Name = "ecommerce-sqlserver-params"
    Project = "ecommerce"
    Environment = "uat"
  }
}

# Secrets Manager for RDS credentials
resource "aws_secretsmanager_secret" "sqlserver_credentials" {
  name        = "ecommerce/sqlserver/master"
  description = "SQL Server master user credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "sqlserver_credentials" {
  secret_id = aws_secretsmanager_secret.sqlserver_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.sqlserver_password.result
  })
}

resource "random_password" "sqlserver_password" {
  length  = 16
  special = true
}

# KMS Key for RDS encryption
resource "aws_kms_key" "rds_key" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "rds_key_alias" {
  name          = "alias/rds-key"
  target_key_id = aws_kms_key.rds_key.key_id
}

# RDS SQL Server Instance (matching production configuration)
resource "aws_db_instance" "sqlserver" {
  identifier = "ecommerce-sqlserver-db"
  
  # Engine configuration (matching production)
  engine         = "sqlserver-ee"
  engine_version = "16.00.4085.2.v1"
  instance_class = "db.m5.xlarge"
  
  # Database configuration (matching production)
  username = "admin"
  password = random_password.sqlserver_password.result
  
  # Storage configuration (matching production)
  allocated_storage     = 666
  max_allocated_storage = 1000
  storage_type         = "gp3"
  iops                 = 3000
  storage_throughput   = 125
  storage_encrypted    = true
  kms_key_id          = aws_kms_key.rds_key.arn
  
  # Network configuration (matching production)
  db_subnet_group_name   = aws_db_subnet_group.sqlserver_subnet_group.name
  vpc_security_group_ids = [aws_security_group.private_db.id]
  publicly_accessible    = false
  multi_az              = true
  
  # Backup configuration (matching production)
  backup_retention_period = 30
  backup_window          = "18:00-19:00"
  maintenance_window     = "thu:20:00-thu:20:30"
  
  # Monitoring and logging (matching production)
  monitoring_interval = 0
  enabled_cloudwatch_logs_exports = ["agent", "error"]
  
  # Parameter and option groups (matching production)
  parameter_group_name = aws_db_parameter_group.sqlserver_params.name
  option_group_name   = aws_db_option_group.sqlserver_backup_restore.name
  
  # Security and access (matching production)
  deletion_protection = true
  skip_final_snapshot = false
  copy_tags_to_snapshot = true
  iam_database_authentication_enabled = false
  
  # Performance Insights (matching production)
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.rds_key.arn
  performance_insights_retention_period = 7
  
  # Auto minor version upgrade (matching production)
  auto_minor_version_upgrade = true
  
  # CA Certificate (matching production)
  ca_cert_identifier = "rds-ca-rsa2048-g1"
  
  # SQL Server specific settings
  timezone = "UTC"
  license_model = "license-included"
  character_set_name = "SQL_Latin1_General_CP1_CI_AS"
  
  tags = {
    Name = "ecommerce-sqlserver-db"
    Project = "ecommerce"
    Environment = "uat"
    Service = "database"
    Terraform = "true"
    ManageBy = "terraform"
  }
}

# SQL Server Option Group (matching production)
resource "aws_db_option_group" "sqlserver_backup_restore" {
  name                     = "sqlserver-backup-restore"
  option_group_description = "Option group for SQL Server backup and restore"
  engine_name              = "sqlserver-ee"
  major_engine_version     = "16.00"

  option {
    option_name = "SQLSERVER_BACKUP_RESTORE"
    option_settings {
      name  = "IAM_ROLE_ARN"
      value = aws_iam_role.sqlserver_backup_restore.arn
    }
  }

  tags = {
    Name = "sqlserver-backup-restore"
  }
}

# IAM Role for SQL Server Backup/Restore
resource "aws_iam_role" "sqlserver_backup_restore" {
  name = "sqlserver-backup-restore-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "sqlserver_backup_restore" {
  name = "sqlserver-backup-restore-policy"
  role = aws_iam_role.sqlserver_backup_restore.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::ecommerce-sqlserver-backup/*",
          "arn:aws:s3:::ecommerce-sqlserver-backup"
        ]
      }
    ]
  })
}

# AWS Backup Plan for RDS (matching case requirements)
resource "aws_backup_vault" "rds_backup_vault" {
  name        = "rds-backup-vault"
  kms_key_arn = aws_kms_key.rds_key.arn
  
  tags = {
    Name = "rds-backup-vault"
  }
}

resource "aws_backup_plan" "rds_backup_plan" {
  name = "rds-backup-plan"

  # Daily backups - 14 days retention
  rule {
    rule_name         = "daily_backup_rule"
    target_vault_name = aws_backup_vault.rds_backup_vault.name
    schedule          = "cron(0 5 ? * * *)"  # Daily at 5 AM UTC
    
    start_window      = 480  # 8 hours
    completion_window = 10080  # 7 days
    
    lifecycle {
      cold_storage_after = 0  # Disable cold storage as requested
      delete_after       = 14  # 14 days retention
    }
    
    recovery_point_tags = {
      BackupType = "Daily"
    }
  }

  # Weekly backups - 5 weeks retention  
  rule {
    rule_name         = "weekly_backup_rule"
    target_vault_name = aws_backup_vault.rds_backup_vault.name
    schedule          = "cron(0 5 ? * SUN *)"  # Weekly on Sunday at 5 AM UTC
    
    start_window      = 480
    completion_window = 10080
    
    lifecycle {
      cold_storage_after = 0  # Disable cold storage
      delete_after       = 35  # 5 weeks retention
    }
    
    recovery_point_tags = {
      BackupType = "Weekly"
    }
  }

  # Monthly backups - 13 months retention
  rule {
    rule_name         = "monthly_backup_rule"
    target_vault_name = aws_backup_vault.rds_backup_vault.name
    schedule          = "cron(0 5 1 * ? *)"  # Monthly on 1st day at 5 AM UTC
    
    start_window      = 480
    completion_window = 10080
    
    lifecycle {
      cold_storage_after = 0  # Disable cold storage
      delete_after       = 395  # 13 months retention (13 * 30.4 days)
    }
    
    recovery_point_tags = {
      BackupType = "Monthly"
    }
  }

  tags = {
    Name = "rds-backup-plan"
  }
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup_role" {
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

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Backup Selection
resource "aws_backup_selection" "rds_backup_selection" {
  iam_role_arn = aws_iam_role.backup_role.arn
  name         = "rds-backup-selection"
  plan_id      = aws_backup_plan.rds_backup_plan.id

  resources = [
    aws_db_instance.sqlserver.arn
  ]
}

# RDS Proxy IAM Role
resource "aws_iam_role" "rds_proxy_role" {
  name = "ecommerce-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "rds_proxy_policy" {
  name = "rds-proxy-policy"
  role = aws_iam_role.rds_proxy_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.sqlserver_credentials.arn,
          aws_secretsmanager_secret.backend_user_credentials.arn
        ]
      }
    ]
  })
}

# Additional secret for backend user
resource "aws_secretsmanager_secret" "backend_user_credentials" {
  name        = "ecommerce/sqlserver/backend"
  description = "Backend user credentials for SQL Server"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "backend_user_credentials" {
  secret_id = aws_secretsmanager_secret.backend_user_credentials.id
  secret_string = jsonencode({
    username = "backend_user"
    password = random_password.backend_user_password.result
  })
}

resource "random_password" "backend_user_password" {
  length  = 16
  special = true
}

# RDS Proxy (Note: RDS Proxy does not support SQL Server)
# Commenting out RDS Proxy configuration as SQL Server is not supported
# For SQL Server connection pooling, consider application-level pooling or connection string optimization

# # RDS Proxy
# resource "aws_db_proxy" "postgres_proxy" {
#   name                   = "ecommerce-postgres-proxy"
#   engine_family         = "POSTGRESQL"
#   auth {
#     auth_scheme = "SECRETS"
#     secret_arn  = aws_secretsmanager_secret.postgres_credentials.arn
#     iam_auth    = "DISABLED"
#   }
#   auth {
#     auth_scheme = "SECRETS"
#     secret_arn  = aws_secretsmanager_secret.backend_user_credentials.arn
#     iam_auth    = "DISABLED"
#   }
#   role_arn               = aws_iam_role.rds_proxy_role.arn
#   vpc_subnet_ids         = [aws_subnet.private_db.id, aws_subnet.private_db_1b.id]
#   vpc_security_group_ids = [aws_security_group.private_db.id]
#   
#   require_tls = true
#   idle_client_timeout = 1800
#   debug_logging = false

#   tags = {
#     Name = "ecommerce-postgres-proxy"
#     Project = "ecommerce"
#     Environment = "uat"
#   }
# }

# # RDS Proxy Target
# resource "aws_db_proxy_default_target_group" "postgres_proxy_target" {
#   db_proxy_name = aws_db_proxy.postgres_proxy.name

#   connection_pool_config {
#     connection_borrow_timeout    = 120
#     max_connections_percent      = 100
#     max_idle_connections_percent = 50
#   }
# }

# resource "aws_db_proxy_target" "postgres_proxy_target" {
#   db_instance_identifier = aws_db_instance.postgres.identifier
#   db_proxy_name          = aws_db_proxy.postgres_proxy.name
#   target_group_name      = aws_db_proxy_default_target_group.postgres_proxy_target.name
# }

# Outputs
output "rds_endpoint" {
  value = aws_db_instance.sqlserver.endpoint
}

output "rds_port" {
  value = aws_db_instance.sqlserver.port
}
