#!/usr/bin/env bash
# extract-apk.sh — Extract base APK from APKM/XAPK bundles
# For plain .apk input, prints the path unchanged.
# Output: prints the absolute path to the base APK on stdout.
set -euo pipefail

usage() {
  cat <<EOF
Usage: extract-apk.sh <file>

Extract the base APK from an Android application bundle.

Supported formats:
  .apk   Plain APK (passed through unchanged)
  .apkm  APKMirror bundle (ZIP containing base.apk + split APKs)
  .xapk  APKPure/split bundle (ZIP containing APKs + manifest.json)

Output:
  Prints the absolute path to the base APK file on stdout.
  For APKM/XAPK, extracts to <basename>-extract/ in the same directory.
EOF
  exit 0
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

INPUT_FILE="$1"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: File not found: $INPUT_FILE" >&2
  exit 1
fi

INPUT_FILE_ABS=$(realpath "$INPUT_FILE")
INPUT_DIR=$(dirname "$INPUT_FILE_ABS")
BASENAME=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')
ext="${INPUT_FILE##*.}"
ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

case "$ext_lower" in
  apk)
    # Plain APK — pass through
    echo "$INPUT_FILE_ABS"
    ;;

  apkm)
    # APKMirror bundle — ZIP containing base.apk + config.*.apk splits
    EXTRACT_DIR="$INPUT_DIR/${BASENAME}-extract"
    mkdir -p "$EXTRACT_DIR"

    echo "Extracting APKM bundle..." >&2
    unzip -qo "$INPUT_FILE_ABS" -d "$EXTRACT_DIR"

    # Find base.apk (standard name in APKM bundles)
    BASE_APK=""
    if [[ -f "$EXTRACT_DIR/base.apk" ]]; then
      BASE_APK="$EXTRACT_DIR/base.apk"
    else
      # Fallback: look for any APK that isn't a config/split
      for apk in "$EXTRACT_DIR"/*.apk; do
        apk_name=$(basename "$apk")
        if [[ "$apk_name" != config.* ]] && [[ "$apk_name" != split_* ]]; then
          BASE_APK="$apk"
          break
        fi
      done
      # Last resort: just use the largest APK
      if [[ -z "$BASE_APK" ]]; then
        BASE_APK=$(ls -S "$EXTRACT_DIR"/*.apk 2>/dev/null | head -1)
      fi
    fi

    if [[ -z "$BASE_APK" || ! -f "$BASE_APK" ]]; then
      echo "Error: No base APK found in APKM bundle" >&2
      exit 1
    fi

    # Report contents to stderr
    echo "APKM contents:" >&2
    ls -lh "$EXTRACT_DIR"/*.apk 2>/dev/null | while read -r line; do echo "  $line" >&2; done
    if [[ -f "$EXTRACT_DIR/info.json" ]]; then
      echo "  info.json found" >&2
    fi

    echo "$(realpath "$BASE_APK")"
    ;;

  xapk)
    # XAPK bundle — ZIP containing APKs + manifest.json
    EXTRACT_DIR="$INPUT_DIR/${BASENAME}-extract"
    mkdir -p "$EXTRACT_DIR"

    echo "Extracting XAPK bundle..." >&2
    unzip -qo "$INPUT_FILE_ABS" -d "$EXTRACT_DIR"

    # Show manifest if present
    if [[ -f "$EXTRACT_DIR/manifest.json" ]]; then
      echo "XAPK manifest found" >&2
    fi

    # Find base APK — check manifest first, then fall back to naming convention
    BASE_APK=""

    # Try manifest.json for split_apks[].id == "base"
    if [[ -f "$EXTRACT_DIR/manifest.json" ]] && command -v python3 &>/dev/null; then
      BASE_APK_NAME=$(python3 -c "
import json, sys
try:
    m = json.load(open('$EXTRACT_DIR/manifest.json'))
    for s in m.get('split_apks', []):
        if s.get('id') == 'base':
            print(s.get('file', ''))
            break
except: pass
" 2>/dev/null)
      if [[ -n "$BASE_APK_NAME" && -f "$EXTRACT_DIR/$BASE_APK_NAME" ]]; then
        BASE_APK="$EXTRACT_DIR/$BASE_APK_NAME"
      fi
    fi

    # Fallback: look for base.apk or the package-name.apk
    if [[ -z "$BASE_APK" ]]; then
      if [[ -f "$EXTRACT_DIR/base.apk" ]]; then
        BASE_APK="$EXTRACT_DIR/base.apk"
      else
        # Find largest APK
        BASE_APK=$(find "$EXTRACT_DIR" -name "*.apk" -print0 | xargs -0 ls -S 2>/dev/null | head -1)
      fi
    fi

    if [[ -z "$BASE_APK" || ! -f "$BASE_APK" ]]; then
      echo "Error: No base APK found in XAPK bundle" >&2
      exit 1
    fi

    echo "$(realpath "$BASE_APK")"
    ;;

  *)
    echo "Error: Unsupported file type '.$ext_lower'. Expected .apk, .apkm, or .xapk" >&2
    exit 1
    ;;
esac
