#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 '/path/to/MetalPilot.app' output.zip" >&2
  exit 2
fi

APP="$1"
OUTPUT="$2"

if [[ ! -d "$APP" ]]; then
  echo "Error: App bundle not found at $APP" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"

# Use ditto to create clean macOS-compatible zip archive with preserved code signatures and metadata
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT"
echo "Created: $OUTPUT"
