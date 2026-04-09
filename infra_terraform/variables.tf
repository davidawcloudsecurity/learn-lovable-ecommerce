variable "backup_vault_lock_changeable_for_days" {
  description = "Number of days the vault lock is changeable"
  type        = number
  default     = 30
}

variable "backup_vault_lock_min_retention_days" {
  description = "Minimum retention days for vault lock"
  type        = number
  default     = 1
}

variable "backup_vault_lock_max_retention_days" {
  description = "Maximum retention days for vault lock"
  type        = number
  default     = 2555
}
