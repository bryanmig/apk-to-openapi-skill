#!/usr/bin/env bash
# detect-hermes.sh — Find and identify Hermes bytecode bundles in decompiled output
# Usage: detect-hermes.sh <decompiled-dir>
#
# Output (stdout, machine-readable):
#   HERMES:<path>   — Hermes bytecode found at <path>
#   PLAINJS:<path>  — Plain JavaScript bundle found at <path>
#   NONE            — No JS bundle found
set -euo pipefail

usage() {
  cat <<EOF
Usage: detect-hermes.sh <decompiled-dir>

Search a jadx-decompiled directory for React Native JavaScript bundles
and determine if they use Hermes bytecode.

Arguments:
  <decompiled-dir>  Path to jadx output directory (contains resources/ and sources/)

Output (machine-readable, on stdout):
  HERMES:<path>    Hermes bytecode bundle found
  PLAINJS:<path>   Plain JavaScript bundle found
  NONE             No JavaScript bundle found

Human-readable details are printed to stderr.
EOF
  exit 0
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

DECOMPILED_DIR="$1"

if [[ ! -d "$DECOMPILED_DIR" ]]; then
  echo "Error: Directory not found: $DECOMPILED_DIR" >&2
  exit 1
fi

# --- Search for JS bundles ---
# Common locations for React Native bundles
BUNDLE_NAMES=(
  "index.android.bundle"
  "index.bundle"
  "main.jsbundle"
  "index.js"
)

BUNDLE_DIRS=(
  "$DECOMPILED_DIR/resources/assets"
  "$DECOMPILED_DIR/resources"
  "$DECOMPILED_DIR/assets"
)

FOUND_BUNDLE=""

for dir in "${BUNDLE_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    continue
  fi
  for name in "${BUNDLE_NAMES[@]}"; do
    if [[ -f "$dir/$name" ]]; then
      FOUND_BUNDLE="$dir/$name"
      break 2
    fi
  done
done

# Fallback: search recursively
if [[ -z "$FOUND_BUNDLE" ]]; then
  for name in "${BUNDLE_NAMES[@]}"; do
    result=$(find "$DECOMPILED_DIR" -name "$name" -type f 2>/dev/null | head -1)
    if [[ -n "$result" ]]; then
      FOUND_BUNDLE="$result"
      break
    fi
  done
fi

if [[ -z "$FOUND_BUNDLE" ]]; then
  echo "No JavaScript bundle found in $DECOMPILED_DIR" >&2
  echo "NONE"
  exit 0
fi

FOUND_BUNDLE_ABS=$(realpath "$FOUND_BUNDLE")
BUNDLE_SIZE=$(wc -c < "$FOUND_BUNDLE_ABS" | tr -d ' ')
echo "Found bundle: $FOUND_BUNDLE_ABS ($BUNDLE_SIZE bytes)" >&2

# --- Check for Hermes magic bytes ---
# Hermes bytecode starts with: c6 1f bc 03 (first 4 bytes)
# This encodes the Greek word "Ἑρμῆ" (Hermes) in a specific way
MAGIC_BYTES=$(xxd -l 4 -p "$FOUND_BUNDLE_ABS" 2>/dev/null || od -A n -t x1 -N 4 "$FOUND_BUNDLE_ABS" 2>/dev/null | tr -d ' ')

if [[ "$MAGIC_BYTES" == "c61fbc03" ]]; then
  # Extract Hermes version from header (byte offset 4, 4 bytes, little-endian)
  HERMES_VER=$(xxd -s 4 -l 4 -p "$FOUND_BUNDLE_ABS" 2>/dev/null || echo "unknown")
  echo "Hermes bytecode detected (magic: $MAGIC_BYTES, version bytes: $HERMES_VER)" >&2

  # Also check with file command if available
  if command -v file &>/dev/null; then
    FILE_TYPE=$(file "$FOUND_BUNDLE_ABS")
    echo "file(1): $FILE_TYPE" >&2
  fi

  echo "HERMES:$FOUND_BUNDLE_ABS"
else
  # Check if it looks like JavaScript text
  FIRST_CHARS=$(head -c 100 "$FOUND_BUNDLE_ABS" 2>/dev/null | tr -d '\0')
  if echo "$FIRST_CHARS" | grep -q '[a-zA-Z({/]'; then
    echo "Plain JavaScript bundle detected" >&2
    echo "PLAINJS:$FOUND_BUNDLE_ABS"
  else
    echo "Unknown bundle format (magic: $MAGIC_BYTES)" >&2
    echo "PLAINJS:$FOUND_BUNDLE_ABS"
  fi
fi
