#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: ./init_project.sh <project_name> [destination_dir]"
  exit 1
fi

PROJECT_NAME="$1"
DEST_DIR="${2:-$PWD}"
TARGET_PATH="$DEST_DIR/$PROJECT_NAME"

if [[ -e "$TARGET_PATH" ]]; then
  echo "Error: target already exists at $TARGET_PATH"
  exit 1
fi

flutter create "$TARGET_PATH"
cp "$PWD/AGENTS.md" "$TARGET_PATH/AGENTS.md"
cp "$PWD/AI_CONTEXT.md" "$TARGET_PATH/AI_CONTEXT.md"

echo "Project created: $TARGET_PATH"
echo "AGENTS copied to: $TARGET_PATH/AGENTS.md"
echo "AI context copied to: $TARGET_PATH/AI_CONTEXT.md"
