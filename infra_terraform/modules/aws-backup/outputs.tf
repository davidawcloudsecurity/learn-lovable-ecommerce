#----------------------------------------------------------------------------
# Backup Vault Outputs
#----------------------------------------------------------------------------

output "backup_vault_id" {
  description = "The name of the backup vault"
  value       = aws_backup_vault.this.id
}

output "backup_vault_arn" {
  description = "The ARN of the backup vault"
  value       = aws_backup_vault.this.arn
}

output "backup_vault_name" {
  description = "The name of the backup vault"
  value       = aws_backup_vault.this.name
}

output "backup_vault_kms_key_arn" {
  description = "The server-side encryption key that is used to protect your backups"
  value       = aws_backup_vault.this.kms_key_arn
}

output "backup_vault_recovery_points" {
  description = "The number of recovery points that are stored in a backup vault"
  value       = aws_backup_vault.this.recovery_points
}

#----------------------------------------------------------------------------
# Backup Plan Outputs
#----------------------------------------------------------------------------

output "backup_plan_id" {
  description = "The id of the backup plan"
  value       = aws_backup_plan.this.id
}

output "backup_plan_arn" {
  description = "The ARN of the backup plan"
  value       = aws_backup_plan.this.arn
}

output "backup_plan_name" {
  description = "The display name of the backup plan"
  value       = aws_backup_plan.this.name
}

output "backup_plan_version" {
  description = "Unique, randomly generated, Unicode, UTF-8 encoded string that serves as the version ID of the backup plan"
  value       = aws_backup_plan.this.version
}

output "backup_plan_tags_all" {
  description = "A map of tags assigned to the backup plan, including those inherited from the provider"
  value       = aws_backup_plan.this.tags_all
}

#----------------------------------------------------------------------------
# Backup Selection Outputs
#----------------------------------------------------------------------------

output "backup_selection_ids" {
  description = "Backup selection identifiers"
  value       = aws_backup_selection.this[*].id
}

output "backup_selection_names" {
  description = "The display names of the backup selections"
  value       = aws_backup_selection.this[*].name
}

#----------------------------------------------------------------------------
# IAM Role Outputs
#----------------------------------------------------------------------------

output "backup_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the backup service role"
  value       = aws_iam_role.backup.arn
}

output "backup_role_name" {
  description = "The name of the backup service role"
  value       = aws_iam_role.backup.name
}

output "backup_role_id" {
  description = "The ID of the backup service role"
  value       = aws_iam_role.backup.id
}

output "backup_role_unique_id" {
  description = "The stable and unique string identifying the backup service role"
  value       = aws_iam_role.backup.unique_id
}

#----------------------------------------------------------------------------
# Vault Lock Configuration Outputs
#----------------------------------------------------------------------------

output "vault_lock_configuration" {
  description = "The backup vault lock configuration, if enabled"
  value = var.enable_vault_lock ? {
    backup_vault_name   = aws_backup_vault_lock_configuration.this[0].backup_vault_name
    changeable_for_days = aws_backup_vault_lock_configuration.this[0].changeable_for_days
    min_retention_days  = aws_backup_vault_lock_configuration.this[0].min_retention_days
    max_retention_days  = aws_backup_vault_lock_configuration.this[0].max_retention_days
  } : null
}

#----------------------------------------------------------------------------
# Notification Configuration Outputs
#----------------------------------------------------------------------------

output "vault_notifications_configuration" {
  description = "The backup vault notifications configuration, if enabled"
  value = var.enable_vault_notifications ? {
    backup_vault_name   = aws_backup_vault_notifications.this[0].backup_vault_name
    sns_topic_arn       = aws_backup_vault_notifications.this[0].sns_topic_arn
    backup_vault_events = aws_backup_vault_notifications.this[0].backup_vault_events
  } : null
}

#----------------------------------------------------------------------------
# Configuration Summary Outputs
#----------------------------------------------------------------------------

output "backup_configuration_summary" {
  description = "Summary of the backup configuration"
  value = {
    vault_name             = aws_backup_vault.this.name
    plan_name              = aws_backup_plan.this.name
    number_of_backup_rules = length(var.backup_rules)
    number_of_selections   = length(local.backup_selections)
    vault_policy_enabled   = var.enable_vault_policy
    vault_lock_enabled     = var.enable_vault_lock
    notifications_enabled  = var.enable_vault_notifications
    kms_encryption_enabled = var.kms_key_arn != null
  }
}
