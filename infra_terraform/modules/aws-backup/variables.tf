#----------------------------------------------------------------------------
# Project Configuration
#----------------------------------------------------------------------------

variable "name" {
  description = "Name suffix for the backup resources"
  type        = string
}

variable "agency_code" {
  description = "Agency code specified by the organisation"
  type        = string
}

variable "environment" {
  description = "Environment code such as npd or prd"
  type        = string
}

variable "project_code" {
  description = "Project Code defined by the organisation"
  type        = string
}

variable "zone_code" {
  description = "Indicate 'ez' for internet, 'iz' for intranet, 'mz' for management"
  type        = string
  default     = "na"
}

variable "tier_code" {
  description = "Tier code such as web, app, db, mgmt, etc"
  type        = string
  default     = "na"
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default     = {}
}

#----------------------------------------------------------------------------
# Backup Vault Configuration
#----------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of the KMS key to use for backup vault encryption"
  type        = string
  default     = null
}

variable "enable_vault_policy" {
  description = "Whether to enable the backup vault policy that prevents deletion of recovery points"
  type        = bool
  default     = true
}

variable "enable_vault_lock" {
  description = "Whether to enable backup vault lock configuration"
  type        = bool
  default     = false
}

variable "vault_lock_changeable_for_days" {
  description = "Number of days before the lock date. If omitted, the vault lock will be in governance mode"
  type        = number
  default     = null
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention period that the vault retains its recovery points"
  type        = number
  default     = 14
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention period that the vault retains its recovery points"
  type        = number
  default     = null
}

#----------------------------------------------------------------------------
# Backup Plan Configuration
#----------------------------------------------------------------------------

variable "backup_rules" {
  description = "List of backup rules for the backup plan"
  type = list(object({
    rule_name                = string
    schedule                 = string
    enable_continuous_backup = optional(bool, false)
    start_window             = optional(number)
    completion_window        = optional(number)
    lifecycle = optional(object({
      cold_storage_after = optional(number)
      delete_after       = optional(number)
    }))
    recovery_point_tags = optional(map(string))
    copy_actions = optional(list(object({
      destination_vault_arn = string
      lifecycle = optional(object({
        cold_storage_after = optional(number)
        delete_after       = optional(number)
      }))
    })), [])
  }))
  default = [
    {
      rule_name                = "MonthlyBackups"
      schedule                 = "cron(0 17 1 * ? *)"
      enable_continuous_backup = false
      lifecycle = {
        delete_after = 365
      }
    }
  ]
}

variable "advanced_backup_settings" {
  description = "Advanced backup settings for specific resource types"
  type = list(object({
    backup_options = map(string)
    resource_type  = string
  }))
  default = []
}

#----------------------------------------------------------------------------
# Backup Selection Configuration
#----------------------------------------------------------------------------

variable "backup_selections" {
  description = "List of backup selections for the backup plan"
  type = list(object({
    name          = string
    resources     = optional(list(string), ["*"])
    not_resources = optional(list(string), [])
    conditions = optional(list(object({
      string_equals = optional(list(object({
        key   = string
        value = string
      })), [])
      string_not_equals = optional(list(object({
        key   = string
        value = string
      })), [])
      string_like = optional(list(object({
        key   = string
        value = string
      })), [])
      string_not_like = optional(list(object({
        key   = string
        value = string
      })), [])
    })), [])
  }))
  default = []
}

#----------------------------------------------------------------------------
# IAM Configuration
#----------------------------------------------------------------------------

variable "backup_service_managed_policies" {
  description = "List of managed policy ARNs to attach to the backup service role"
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
  ]
}

#----------------------------------------------------------------------------
# Notification Configuration
#----------------------------------------------------------------------------

variable "enable_vault_notifications" {
  description = "Whether to enable backup vault notifications"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for backup vault notifications"
  type        = string
  default     = ""
}

variable "backup_vault_events" {
  description = "List of events that will trigger notifications"
  type        = list(string)
  default = [
    "BACKUP_JOB_STARTED",
    "BACKUP_JOB_COMPLETED",
    "BACKUP_JOB_SUCCESSFUL",
    "BACKUP_JOB_FAILED",
    "BACKUP_JOB_EXPIRED",
    "RESTORE_JOB_STARTED",
    "RESTORE_JOB_COMPLETED",
    "RESTORE_JOB_SUCCESSFUL",
    "RESTORE_JOB_FAILED",
    "COPY_JOB_STARTED",
    "COPY_JOB_SUCCESSFUL",
    "COPY_JOB_FAILED",
    "RECOVERY_POINT_MODIFIED",
    "BACKUP_PLAN_CREATED",
    "BACKUP_PLAN_MODIFIED"
  ]
}

#----------------------------------------------------------------------------
# Global Settings Configuration
#----------------------------------------------------------------------------

variable "enable_global_settings" {
  description = "Whether to configure AWS Backup global settings"
  type        = bool
  default     = false
}

variable "global_settings" {
  description = "Global settings for AWS Backup"
  type        = map(string)
  default     = {}
}

#----------------------------------------------------------------------------
# Region Settings Configuration
#----------------------------------------------------------------------------

variable "enable_region_settings" {
  description = "Whether to configure AWS Backup region settings"
  type        = bool
  default     = false
}

variable "resource_type_opt_in_preference" {
  description = "Resource type opt-in preferences for AWS Backup"
  type        = map(bool)
  default     = {}
}

variable "resource_type_management_preference" {
  description = "Resource type management preferences for AWS Backup"
  type        = map(bool)
  default     = {}
}
