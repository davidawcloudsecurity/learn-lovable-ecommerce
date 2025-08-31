#!/bin/bash

# Usage: ./push_tf_state_with_backup.sh /path/to/target/folder

set -e  # Exit on any error

TARGET_DIR="$1"
DATE=$(date +%Y%m%d_%H%M%S)

# Validate input
if [ -z "$TARGET_DIR" ]; then
  echo "❌ Usage: $0 /path/to/target/folder"
  exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "❌ Error: $TARGET_DIR is not a valid directory."
  exit 1
fi

if [ ! -f "terraform.tfstate" ]; then
  echo "❌ terraform.tfstate not found in current directory."
  exit 1
fi

# Optional: create target folder if it doesn't exist
mkdir -p "$TARGET_DIR"

# Backup the current terraform.tfstate with a timestamp
echo "📦 Creating backup of terraform.tfstate as terraform.tfstate.backup.$DATE"
cp terraform.tfstate "terraform.tfstate.backup.$DATE"

# Copy current tfstate and backup to target folder
echo "📤 Copying terraform.tfstate to $TARGET_DIR"
cp terraform.tfstate "$TARGET_DIR/terraform.tfstate"

echo "📤 Copying terraform.tfstate.backup.$DATE to $TARGET_DIR"
cp "terraform.tfstate.backup.$DATE" "$TARGET_DIR/terraform.tfstate.backup.$DATE"

# Optionally copy Terraform's built-in backup file if it exists
if [ -f "terraform.tfstate.backup" ]; then
  echo "📤 Copying terraform.tfstate.backup (Terraform's own) to $TARGET_DIR"
  cp terraform.tfstate.backup "$TARGET_DIR/terraform.tfstate.backup"
fi

echo "✅ Terraform state and backups pushed to $TARGET_DIR"
