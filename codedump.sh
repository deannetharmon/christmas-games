#!/usr/bin/env bash
#
# ejournal_codedump.sh
# 1. Dumps .swift files recursively
# 2. Adds line numbers for AI reference
# 3. Excludes Pods, Tests, and Previews to reduce noise
#
set -euo pipefail

OUTPUT_FILE="swiftcode.txt"

# Overwrite output
: > "$OUTPUT_FILE"

echo "🔍 Scanning for Swift files (ignoring Pods, Tests, and Previews)..."

# Find command explanation:
# -not -path "*/Pods/*"            : Ignore third-party libraries
# -not -path "*/Tests/*"           : Ignore Unit/UI Tests
# -not -path "*/Preview Content/*" : Ignore SwiftUI preview assets
# -not -path "*/.*"                : Ignore hidden folders (like .git)
find . -type f -iname "*.swift" \
  -not -path "*/Pods/*" \
  -not -path "*/Tests/*" \
  -not -path "*/Preview Content/*" \
  -not -path "*/.*" \
  -print0 | \
while IFS= read -r -d '' file; do
  {
    echo "################################################################################"
    echo "START FILE: $file"
    echo "################################################################################"
    
    # -b a : number all lines
    # -w 4 : 4 digits wide
    # -s ' | ' : separator
    nl -b a -w 4 -s ' | ' "$file"
    
    printf "\n\n"
    echo "END FILE: $file"
    printf "\n\n"
  } >> "$OUTPUT_FILE"
done

# Summary check
count_files=$(grep -c "^START FILE: " "$OUTPUT_FILE" || true)
printf "✅ Wrote %d focused Swift file(s) with line numbers into %s\n" "${count_files:-0}" "$OUTPUT_FILE"