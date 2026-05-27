#!/bin/bash
# Usage: bash run-sfdx-retrieve.sh
# This script attempts multiple safe sfdx retrieve commands with debug logging.
# 1) Ensure you're authenticated: sfdx auth:web:login -a myOrg
# 2) Run this script to attempt retrieval and capture logs.

set -euo pipefail

PKG="scripts/sfdx-retrieve-validation-triggers-package.xml"
LOG="sfdx-retrieve-debug.log"

echo "Running: sfdx force:source:retrieve -x $PKG --loglevel TRACE"
SFDX_JSON_TO_STDOUT=true sfdx force:source:retrieve -x "$PKG" --loglevel TRACE > "$LOG" 2>&1 || {
  echo "Retrieve failed. See $LOG for details."
  exit 1
}

echo "Retrieve completed. See $LOG for output."