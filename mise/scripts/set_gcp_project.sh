#!/usr/bin/env bash
set -euo pipefail # Exit on error, undefined variable, or pipe failure

PROJECT_ID="${1:-}" # First argument, or empty if not provided

if [ -z "$PROJECT_ID" ]; then
  echo "Usage: $0 <project_id>" >&2
  exit 1
fi

gcloud config set project "$PROJECT_ID"
gcloud auth application-default set-quota-project "$PROJECT_ID"

echo "Successfully set GCP project and ADC quota project to: $PROJECT_ID"
