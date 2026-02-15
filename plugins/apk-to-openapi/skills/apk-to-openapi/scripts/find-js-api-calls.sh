#!/usr/bin/env bash
# find-js-api-calls.sh — Search decompiled Hermes JS for API endpoints
# Usage: find-js-api-calls.sh <index.js>
#
# Searches hermes-dec output for API class definitions, endpoint methods,
# HTTP calls, base URLs, and authentication patterns.
set -euo pipefail

usage() {
  cat <<EOF
Usage: find-js-api-calls.sh <index.js> [OPTIONS]

Search decompiled Hermes JavaScript for API endpoint patterns.

Arguments:
  <index.js>        Path to the decompiled JS file (hermes-dec output)

Options:
  --methods         Search only for API method registry
  --http            Search only for HTTP method calls (get/post/put/delete/patch)
  --config          Search only for base URL and configuration
  --auth            Search only for authentication patterns
  --endpoints       Search only for endpoint path strings
  --all             Search all patterns (default)
  -h, --help        Show this help message

Output:
  Results are printed as sections with line numbers for easy navigation.
  Use these results to guide manual reading of the decompiled JS for full endpoint details.
EOF
  exit 0
}

JS_FILE=""
SEARCH_METHODS=false
SEARCH_HTTP=false
SEARCH_CONFIG=false
SEARCH_AUTH=false
SEARCH_ENDPOINTS=false
SEARCH_ALL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --methods)    SEARCH_METHODS=true;   SEARCH_ALL=false; shift ;;
    --http)       SEARCH_HTTP=true;      SEARCH_ALL=false; shift ;;
    --config)     SEARCH_CONFIG=true;    SEARCH_ALL=false; shift ;;
    --auth)       SEARCH_AUTH=true;      SEARCH_ALL=false; shift ;;
    --endpoints)  SEARCH_ENDPOINTS=true; SEARCH_ALL=false; shift ;;
    --all)        SEARCH_ALL=true; shift ;;
    -h|--help)    usage ;;
    -*)           echo "Error: Unknown option $1" >&2; usage ;;
    *)            JS_FILE="$1"; shift ;;
  esac
done

if [[ -z "$JS_FILE" ]]; then
  echo "Error: No JavaScript file specified." >&2
  usage
fi

if [[ ! -f "$JS_FILE" ]]; then
  echo "Error: File not found: $JS_FILE" >&2
  exit 1
fi

FILE_SIZE=$(wc -c < "$JS_FILE" | tr -d ' ')
LINE_COUNT=$(wc -l < "$JS_FILE" | tr -d ' ')
echo "Searching: $JS_FILE ($LINE_COUNT lines, $FILE_SIZE bytes)"
echo

section() {
  echo
  echo "==== $1 ===="
  echo
}

# --- API Class Definitions ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_METHODS" == true ]]; then
  section "API Class Definitions"
  echo "Looking for API/service class definitions..."
  grep -n '// Original name: Api[, ]' "$JS_FILE" 2>/dev/null || echo "(none found)"
  grep -n '// Original name: .*[Ss]ervice[, ]' "$JS_FILE" 2>/dev/null | head -20 || true
  grep -n '// Original name: .*[Cc]lient[, ]' "$JS_FILE" 2>/dev/null | head -20 || true

  section "API Method Registry (method name assignments)"
  # Find the API class line number, then search for method assignments nearby
  API_LINE=$(grep -n '// Original name: Api[, ]' "$JS_FILE" 2>/dev/null | head -1 | cut -d: -f1)
  if [[ -n "$API_LINE" ]]; then
    echo "API class found at line $API_LINE. Searching nearby method assignments (within 1000 lines)..."
    START=$((API_LINE > 0 ? API_LINE : 1))
    END=$((API_LINE + 1000))
    sed -n "${START},${END}p" "$JS_FILE" | grep -n "r[0-9]*\['[a-zA-Z]*'\] = r[0-9]" | \
      awk -v offset="$((START - 1))" -F: '{printf "%d:%s\n", $1 + offset, $2}'
  else
    echo "No 'Api' class found. Showing all method binding patterns (may include non-API)..."
    grep -n "r[0-9]*\['[a-zA-Z]*'\] = r[0-9]" "$JS_FILE" 2>/dev/null | head -100 || echo "(none found)"
  fi

  section "Named API Functions"
  echo "Looking for API function implementations..."
  grep -n '// Original name: _\?get[A-Z]' "$JS_FILE" 2>/dev/null | head -50 || true
  grep -n '// Original name: _\?post[A-Z]\|_\?create[A-Z]\|_\?register[A-Z]\|_\?login' "$JS_FILE" 2>/dev/null | head -50 || true
  grep -n '// Original name: _\?update[A-Z]\|_\?patch[A-Z]' "$JS_FILE" 2>/dev/null | head -50 || true
  grep -n '// Original name: _\?delete[A-Z]\|_\?remove[A-Z]' "$JS_FILE" 2>/dev/null | head -50 || true
fi

# --- HTTP Method Calls ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_HTTP" == true ]]; then
  section "HTTP Method Calls"
  echo "Looking for apisauce/axios HTTP method calls..."

  echo
  echo "--- .get calls ---"
  grep -n '\.get;' "$JS_FILE" 2>/dev/null | grep 'r[0-9]' | head -30 || echo "(none)"

  echo
  echo "--- .post calls ---"
  grep -n '\.post;' "$JS_FILE" 2>/dev/null | grep 'r[0-9]' | head -30 || echo "(none)"

  echo
  echo "--- .put calls ---"
  grep -n '\.put;' "$JS_FILE" 2>/dev/null | grep 'r[0-9]' | head -30 || echo "(none)"

  echo
  echo "--- .patch calls ---"
  grep -n '\.patch;' "$JS_FILE" 2>/dev/null | grep 'r[0-9]' | head -30 || echo "(none)"

  echo
  echo "--- .delete calls ---"
  grep -n '\.delete;' "$JS_FILE" 2>/dev/null | grep 'r[0-9]' | head -30 || echo "(none)"

  section "Apisauce/Axios Usage"
  grep -n '\.apisauce' "$JS_FILE" 2>/dev/null | head -30 || echo "(none)"
  grep -n 'apisauce.*create\|axios.*create' "$JS_FILE" 2>/dev/null | head -10 || true

  section "Fetch API Usage"
  grep -n '\bfetch(' "$JS_FILE" 2>/dev/null | head -20 || echo "(none)"
fi

# --- Base URL / Config ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_CONFIG" == true ]]; then
  section "Base URL & Configuration"
  grep -n 'baseURL\|base_url\|BASE_URL' "$JS_FILE" 2>/dev/null | head -20 || echo "(none)"
  grep -n "config\.url\|config\.timeout" "$JS_FILE" 2>/dev/null | head -20 || true

  echo
  echo "--- Hardcoded URLs ---"
  grep -n "https\?://[a-zA-Z0-9]" "$JS_FILE" 2>/dev/null | grep -v 'node_modules\|react-native\|facebook\|github\|google\|sentry\|amplitude' | head -30 || echo "(none)"
fi

# --- Authentication ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_AUTH" == true ]]; then
  section "Authentication Patterns"
  grep -n 'Authorization\|setHeader.*[Aa]uth\|Bearer\|Basic ' "$JS_FILE" 2>/dev/null | head -20 || echo "(none)"
  grep -n 'api[_-]\?[Kk]ey\|access[_-]\?[Tt]oken\|auth[_-]\?[Tt]oken' "$JS_FILE" 2>/dev/null | head -20 || true
fi

# --- Endpoint Path Strings ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_ENDPOINTS" == true ]]; then
  section "Endpoint Path Strings"
  echo "Looking for string literals that look like API paths..."
  # Match strings like 'users', 'frames/123/messages', etc.
  # These are typically assigned to a register right before a .bind() call
  grep -n "r[0-9]* = '[a-z_]*/*[a-z_]*'" "$JS_FILE" 2>/dev/null \
    | grep -v "r[0-9]* = '[a-z]'" \
    | grep -v 'function\|return\|undefined\|null\|true\|false\|string\|number\|object' \
    | head -100 || echo "(none)"

  echo
  echo "--- Template literal paths (with interpolation) ---"
  grep -n "frames/.*/" "$JS_FILE" 2>/dev/null | head -30 || true
  grep -n "users/\|user/\|sessions/\|albums/" "$JS_FILE" 2>/dev/null | head -30 || true
fi

echo
echo "=== Search complete ==="
echo
echo "Next steps:"
echo "  1. Read the API class definition section to find the method registry"
echo "  2. Use the method names to search for their implementations"
echo "  3. In each implementation, find the HTTP method (.get/.post etc.) and endpoint path"
echo "  4. Note request body structure and query parameters"
