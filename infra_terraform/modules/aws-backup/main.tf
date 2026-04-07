data "aws_caller_identity" "current" {}

#----------------------------------------------------------------------------
# AWS Backup Vault
#----------------------------------------------------------------------------

resource "aws_backup_vault" "this" {
  name        = "bkp-vlt-${var.project_code}-${var.environment}-${var.name}"
  kms_key_arn = var.kms_key_arn

  tags = merge(
    {
      Name         = "bkp-vlt-${var.project_code}-${var.environment}-${var.name}"
      Agency-Code  = var.agency_code
      Environment  = var.environment
      Project-Code = var.project_code
      Zone         = var.zone_code
      Tier         = var.tier_code
    },
    var.tags
  )
}

resource "aws_backup_vault_policy" "this" {
  count             = var.enable_vault_policy ? 1 : 0
  backup_vault_name = aws_backup_vault.this.name

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Deny",
        "Principal" : "*",
        "Action" : "backup:DeleteRecoveryPoint",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_backup_vault_lock_configuration" "this" {
  count               = var.enable_vault_lock ? 1 : 0
  backup_vault_name   = aws_backup_vault.this.name
  changeable_for_days = var.vault_lock_changeable_for_days
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
}

#----------------------------------------------------------------------------
# AWS Backup Plan
#----------------------------------------------------------------------------

resource "aws_backup_plan" "this" {
  name = "${var.project_code}-${var.environment}-${var.name}-backup"

  dynamic "rule" {
    for_each = var.backup_rules
    content {
      rule_name                = rule.value.rule_name
      target_vault_name        = aws_backup_vault.this.name
      schedule                 = rule.value.schedule
      enable_continuous_backup = try(rule.value.enable_continuous_backup, false)
      start_window             = try(rule.value.start_window, null)
      completion_window        = try(rule.value.completion_window, null)

      dynamic "lifecycle" {
        for_each = try(rule.value.lifecycle, null) != null ? [rule.value.lifecycle] : []
        content {
          cold_storage_after = try(lifecycle.value.cold_storage_after, null)
          delete_after       = try(lifecycle.value.delete_after, null)
        }
      }

      dynamic "copy_action" {
        for_each = try(rule.value.copy_actions, [])
        content {
          destination_vault_arn = copy_action.value.destination_vault_arn

          dynamic "lifecycle" {
            for_each = try(copy_action.value.lifecycle, null) != null ? [copy_action.value.lifecycle] : []
            content {
              cold_storage_after = try(lifecycle.value.cold_storage_after, null)
              delete_after       = try(lifecycle.value.delete_after, null)
            }
          }
        }
      }
    }
  }

  dynamic "advanced_backup_setting" {
    for_each = var.advanced_backup_settings
    content {
      backup_options = advanced_backup_setting.value.backup_options
      resource_type  = advanced_backup_setting.value.resource_type
    }
  }

  tags = merge(
    {
      Name         = "${var.project_code}-${var.environment}-${var.name}-backup"
      Agency-Code  = var.agency_code
      Environment  = var.environment
      Project-Code = var.project_code
      Zone         = var.zone_code
      Tier         = var.tier_code
    },
    var.tags
  )
}

#----------------------------------------------------------------------------
# AWS Backup Selection
#----------------------------------------------------------------------------

locals {
  # Default backup selection if none provided
  default_backup_selections = tolist([
    {
      name          = "All"
      resources     = ["*"]
      not_resources = []
      conditions = [
        {
          string_equals = [
            {
              key   = "aws:ResourceTag/Project-Code"
              value = var.project_code
            },
            {
              key   = "aws:ResourceTag/Monthly-Backup"
              value = "Y"
            }
          ]
          string_not_equals = []
          string_like       = []
          string_not_like   = []
        }
      ]
    }
  ])

  # Use provided selections or default (skip default when disable_default_selection is true)
  backup_selections = var.disable_default_selection ? var.backup_selections : (length(var.backup_selections) > 0 ? var.backup_selections : local.default_backup_selections)
}

resource "aws_backup_selection" "this" {
  count        = length(local.backup_selections)
  name         = local.backup_selections[count.index].name
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  resources     = try(local.backup_selections[count.index].resources, ["*"])
  not_resources = try(local.backup_selections[count.index].not_resources, [])

  dynamic "condition" {
    for_each = try(local.backup_selections[count.index].conditions, [])
    content {
      dynamic "string_equals" {
        for_each = try(condition.value.string_equals, [])
        content {
          key   = string_equals.value.key
          value = string_equals.value.value
        }
      }

      dynamic "string_not_equals" {
        for_each = try(condition.value.string_not_equals, [])
        content {
          key   = string_not_equals.value.key
          value = string_not_equals.value.value
        }
      }

      dynamic "string_like" {
        for_each = try(condition.value.string_like, [])
        content {
          key   = string_like.value.key
          value = string_like.value.value
        }
      }

      dynamic "string_not_like" {
        for_each = try(condition.value.string_not_like, [])
        content {
          key   = string_not_like.value.key
          value = string_not_like.value.value
        }
      }
    }
  }
}

#----------------------------------------------------------------------------
# IAM Role for AWS Backup
#----------------------------------------------------------------------------

resource "aws_iam_role" "backup" {
  name = "iam-${var.project_code}-${var.environment}-${var.name}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
    ]
  })

  tags = merge(
    {
      Name         = "iam-${var.project_code}-${var.environment}-${var.name}-backup-role"
      Agency-Code  = var.agency_code
      Environment  = var.environment
      Project-Code = var.project_code
      Zone         = var.zone_code
      Tier         = var.tier_code
    },
    var.tags
  )
}

# Attach managed policies to the backup role
resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset(var.backup_service_managed_policies)

  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

#----------------------------------------------------------------------------
# AWS Backup Vault Notifications (Optional)
#----------------------------------------------------------------------------

resource "aws_backup_vault_notifications" "this" {
  count               = var.enable_vault_notifications ? 1 : 0
  backup_vault_name   = aws_backup_vault.this.name
  sns_topic_arn       = var.sns_topic_arn
  backup_vault_events = var.backup_vault_events
}

#----------------------------------------------------------------------------
# AWS Backup Global Settings (Optional)
#----------------------------------------------------------------------------

resource "aws_backup_global_settings" "this" {
  count           = var.enable_global_settings ? 1 : 0
  global_settings = var.global_settings
}

#----------------------------------------------------------------------------
# AWS Backup Region Settings (Optional)
#----------------------------------------------------------------------------

resource "aws_backup_region_settings" "this" {
  count                               = var.enable_region_settings ? 1 : 0
  resource_type_opt_in_preference     = var.resource_type_opt_in_preference
  resource_type_management_preference = var.resource_type_management_preference
}
