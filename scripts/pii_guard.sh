#!/bin/bash
#
# pii_guard.sh - Scans source files for possible PII leaks before release.
# -------------------------------------------------------------
# Uses simple pattern matching against security/pii-rules.yaml
# and skips entries found in pii-allowlist.txt.

RULES_FILE="security/pii-rules.yaml"
ALLOWLIST="security/pii-allowlist.txt"
EXIT_CODE=0

echo "🔍 Running PII Guard..."
if [[ ! -f "$RULES_FILE" ]]; then
  echo "⚠️  Rules file not found: $RULES_FILE"
  exit 0
fi

while IFS= read -r rule; do
  [[ -z "$rule" || "$rule" == \#* ]] && continue
  matches=$(grep -rInE "$rule" --exclude-from="$ALLOWLIST" . || true)
  if [[ -n "$matches" ]]; then
    echo "🚨 Potential PII detected for rule: $rule"
    echo "$matches"
    EXIT_CODE=1
  fi
done < "$RULES_FILE"

if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ No PII found."
else
  echo "❌ PII found! Review matches before continuing."
fi

exit $EXIT_CODE

