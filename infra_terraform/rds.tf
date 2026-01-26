# RDS Subnet Group (matching existing configuration)
resource "aws_db_subnet_group" "postgres_subnet_group" {
  name       = "ecommerce-postgres-subnet-group"
  subnet_ids = [aws_subnet.private_db.id, aws_subnet.private_db_1b.id]
  description = "Database subnet group for postgres"

  tags = {
    Name = "ecommerce-postgres-subnet-group"
    Project = "ecommerce"
    Environment = "uat"
  }
}

# RDS Parameter Group (matching existing configuration)
resource "aws_db_parameter_group" "postgres_params" {
  family = "postgres15"  # Changed to match engine version 15.12
  name   = "ecommerce-postgres-params"
  description = "PostgreSQL parameter group for ecommerce project"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "ecommerce-postgres-params"
    Project = "ecommerce"
    Environment = "uat"
  }
}

# Secrets Manager for RDS credentials
resource "aws_secretsmanager_secret" "postgres_credentials" {
  name        = "ecommerce/postgres/master"
  description = "PostgreSQL master user credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres_credentials" {
  secret_id = aws_secretsmanager_secret.postgres_credentials.id
  secret_string = jsonencode({
    username = "wordpress"
    password = random_password.postgres_password.result
  })
}

resource "random_password" "postgres_password" {
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

# RDS PostgreSQL Instance (matching production configuration)
resource "aws_db_instance" "postgres" {
  identifier = "ecommerce-postgres-db"
  
  # Engine configuration (matching existing)
  engine         = "postgres"
  engine_version = "15.12"
  instance_class = "db.t3.large"
  
  # Database configuration (matching existing)
  db_name  = "applicationdb"
  username = "app_db_user"
  password = random_password.postgres_password.result
  
  # Storage configuration (matching existing)
  allocated_storage     = 400
  max_allocated_storage = 500
  storage_type         = "gp3"
  storage_encrypted    = true
  kms_key_id          = aws_kms_key.rds_key.arn
  
  # Network configuration (matching existing)
  db_subnet_group_name   = aws_db_subnet_group.postgres_subnet_group.name
  vpc_security_group_ids = [aws_security_group.private_db.id]
  publicly_accessible    = false
  multi_az              = true
  
  # Backup configuration (matching existing + case requirements)
  backup_retention_period = 7   # Current: 7 days, Case requests: 14 days
  backup_window          = "19:00-20:00"  # Matching existing
  maintenance_window     = "sat:20:00-sat:21:00"  # Matching existing
  
  # Monitoring and logging (matching existing)
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.postgres_params.name
  
  # Security and access (matching existing)
  deletion_protection = true  # Matching existing
  skip_final_snapshot = false
  copy_tags_to_snapshot = true
  iam_database_authentication_enabled = true
  
  # Performance Insights (matching existing)
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.rds_key.arn
  performance_insights_retention_period = 7
  
  # Auto minor version upgrade (matching existing)
  auto_minor_version_upgrade = true
  
  # CA Certificate (matching existing)
  ca_cert_identifier = "rds-ca-rsa2048-g1"
  
  tags = {
    Name = "ecommerce-postgres-db"
    Project = "ecommerce"
    Environment = "uat"
    Service = "database"
    Terraform = "true"
    ManageBy = "terraform"
    "Monthly-Backup" = "Y"
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
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
    aws_db_instance.postgres.arn
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
          aws_secretsmanager_secret.postgres_credentials.arn,
          aws_secretsmanager_secret.backend_user_credentials.arn
        ]
      }
    ]
  })
}

# Additional secret for backend user
resource "aws_secretsmanager_secret" "backend_user_credentials" {
  name        = "ecommerce/postgres/backend"
  description = "Backend user credentials for RDS Proxy"
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

# RDS Proxy
resource "aws_db_proxy" "postgres_proxy" {
  name                   = "ecommerce-postgres-proxy"
  engine_family         = "POSTGRESQL"
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.postgres_credentials.arn
    iam_auth    = "DISABLED"
  }
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.backend_user_credentials.arn
    iam_auth    = "DISABLED"
  }
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_subnet_ids         = [aws_subnet.private_db.id, aws_subnet.private_db_1b.id]
  vpc_security_group_ids = [aws_security_group.private_db.id]
  
  require_tls = true
  idle_client_timeout = 1800
  debug_logging = false

  tags = {
    Name = "ecommerce-postgres-proxy"
    Project = "ecommerce"
    Environment = "uat"
  }
}

# RDS Proxy Target
resource "aws_db_proxy_default_target_group" "postgres_proxy_target" {
  db_proxy_name = aws_db_proxy.postgres_proxy.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "postgres_proxy_target" {
  db_instance_identifier = aws_db_instance.postgres.id
  db_proxy_name          = aws_db_proxy.postgres_proxy.name
  target_group_name      = aws_db_proxy_default_target_group.postgres_proxy_target.name
}

# Outputs
output "rds_proxy_endpoint" {
  value = aws_db_proxy.postgres_proxy.endpoint
}
