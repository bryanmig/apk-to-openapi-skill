#!/usr/bin/env bash
# prepare.sh — One-shot pipeline: deps → extract → decompile → scan
# Runs all mechanical steps and outputs a structured report.
#
# Usage: prepare.sh <apk|apkm|xapk>
# Output: Structured report on stdout with paths and scan results.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: prepare.sh <apk|apkm|xapk>"
  echo ""
  echo "Runs the full decompile + scan pipeline in one command."
  echo "Outputs a structured report for Claude to parse."
  exit 0
fi

INPUT="$1"
if [[ ! -f "$INPUT" ]]; then
  echo "Error: File not found: $INPUT" >&2
  exit 1
fi

INPUT_ABS=$(realpath "$INPUT")
BASENAME=$(basename "$INPUT" | sed 's/\.[^.]*$//')
WORK_DIR=$(pwd)
CLEANUP_DIRS=()
INPUT_EXT=$(echo "${INPUT_ABS##*.}" | tr '[:upper:]' '[:lower:]')

# ─── Step 1: Check dependencies ─────────────────────────────────────
echo ">>> Checking dependencies..."
DEP_OUTPUT=$(bash "$SCRIPT_DIR/check-deps.sh" 2>&1) || {
  echo "$DEP_OUTPUT"
  echo ""
  echo "ERROR: Missing required dependencies. Install with:"
  echo "  bash $SCRIPT_DIR/install-dep.sh <name>"
  exit 1
}
echo "All dependencies OK."
echo ""

# ─── Step 2: Extract base APK ───────────────────────────────────────
echo ">>> Extracting base APK..."
BASE_APK=$(bash "$SCRIPT_DIR/extract-apk.sh" "$INPUT_ABS")
echo "Base APK: $BASE_APK"
# Track extract directory if one was created (APKM/XAPK bundles)
if [[ "$INPUT_EXT" == "apkm" || "$INPUT_EXT" == "xapk" ]]; then
  EXTRACT_DIR="$(dirname "$INPUT_ABS")/${BASENAME}-extract"
  [[ -d "$EXTRACT_DIR" ]] && CLEANUP_DIRS+=("$EXTRACT_DIR")
fi
echo ""

# ─── Step 3: Decompile with jadx ────────────────────────────────────
DECOMPILED_DIR="$WORK_DIR/${BASENAME}-decompiled"
CLEANUP_DIRS+=("$DECOMPILED_DIR")
if [[ -d "$DECOMPILED_DIR/sources" ]]; then
  echo ">>> Skipping jadx decompilation (already exists: $DECOMPILED_DIR)"
else
  echo ">>> Decompiling with jadx (this may take several minutes)..."
  jadx -d "$DECOMPILED_DIR" --show-bad-code "$BASE_APK" 2>&1 || true
fi
echo ""

# ─── Step 4: Detect & decompile Hermes ──────────────────────────────
echo ">>> Detecting Hermes bytecode..."
HERMES_RESULT=$(bash "$SCRIPT_DIR/detect-hermes.sh" "$DECOMPILED_DIR" 2>/dev/null || echo "NONE")
JS_FILE="NONE"

if [[ "$HERMES_RESULT" == HERMES:* ]]; then
  BUNDLE_PATH="${HERMES_RESULT#HERMES:}"
  JS_DIR="$WORK_DIR/${BASENAME}-decompiled-js"
  JS_FILE="$JS_DIR/index.js"
  CLEANUP_DIRS+=("$JS_DIR")

  if [[ -f "$JS_FILE" ]]; then
    echo ">>> Skipping Hermes decompilation (already exists: $JS_FILE)"
  else
    # Find hbc-decompiler (check plugin venv first, then system PATH)
    VENV_DIR="$PLUGIN_ROOT/.venv"
    if [[ -f "$VENV_DIR/bin/hbc-decompiler" ]]; then
      HBC="$VENV_DIR/bin/hbc-decompiler"
    elif command -v hbc-decompiler &>/dev/null; then
      HBC="hbc-decompiler"
    else
      echo "ERROR: hbc-decompiler not found. Install with:" >&2
      echo "  bash $SCRIPT_DIR/install-dep.sh hermes-dec" >&2
      exit 1
    fi

    mkdir -p "$JS_DIR"
    echo ">>> Decompiling Hermes bytecode..."
    "$HBC" "$BUNDLE_PATH" "$JS_FILE" 2>&1 || true
  fi
elif [[ "$HERMES_RESULT" == PLAINJS:* ]]; then
  JS_FILE="${HERMES_RESULT#PLAINJS:}"
  echo ">>> Plain JavaScript bundle found: $JS_FILE"
else
  echo ">>> No JavaScript bundle detected (native-only app)"
fi
echo ""

# ─── Step 5: Scan native code ───────────────────────────────────────
SOURCES_DIR="$DECOMPILED_DIR/sources"
MANIFEST="$DECOMPILED_DIR/resources/AndroidManifest.xml"

echo ""
echo "========================================"
echo "REPORT"
echo "========================================"
echo "DECOMPILED_DIR=$DECOMPILED_DIR"
echo "MANIFEST=$MANIFEST"
echo "JS_FILE=$JS_FILE"
echo ""

if [[ ! -d "$SOURCES_DIR" ]]; then
  echo "WARNING: No sources directory found at $SOURCES_DIR"
  echo "jadx may have failed. Check the decompiled directory."
  echo ""
  echo "--- CLEANUP ---"
  for dir in "${CLEANUP_DIRS[@]}"; do
    [[ -d "$dir" ]] && echo "$dir"
  done
  echo ""
  echo "========================================"
  echo "DONE"
  echo "========================================"
  exit 0
fi

# ── Retrofit API files ──
echo "--- API_FILES ---"
grep -rl '@GET\|@POST\|@PUT\|@DELETE\|@PATCH\|@HEAD' "$SOURCES_DIR" 2>/dev/null | head -100 || echo "(none)"
echo ""

# ── Volley request files ──
echo "--- VOLLEY_FILES ---"
grep -rl 'StringRequest\|JsonObjectRequest\|JsonArrayRequest\|RequestQueue' "$SOURCES_DIR" 2>/dev/null | head -30 || echo "(none)"
echo ""

# ── Raw OkHttp usage ──
echo "--- OKHTTP_FILES ---"
grep -rl 'Request\.Builder\|OkHttpClient\|\.newCall(' "$SOURCES_DIR" 2>/dev/null | head -30 || echo "(none)"
echo ""

# ── Ktor client usage ──
echo "--- KTOR_FILES ---"
grep -rl 'HttpClient\|client\.get\|client\.post\|client\.put\|client\.delete' "$SOURCES_DIR" 2>/dev/null | head -30 || echo "(none)"
echo ""

# ── Model/DTO classes ──
echo "--- MODEL_FILES ---"
grep -rl '@SerializedName\|@Json(\|@Serializable\|@JsonProperty' "$SOURCES_DIR" 2>/dev/null | head -50 || echo "(none)"
echo ""

# ── Base URL configuration ──
echo "--- BASE_URLS ---"
grep -rn 'BASE_URL\|API_URL\|baseUrl\|api_base\|\.baseUrl(' "$SOURCES_DIR" 2>/dev/null | head -15 || echo "(none)"
echo ""

# ── Auth patterns ──
echo "--- AUTH_PATTERNS ---"
grep -rn 'Authorization\|Bearer\|addHeader.*[Aa]uth\|Interceptor\|@Header(' "$SOURCES_DIR" 2>/dev/null | head -15 || echo "(none)"
echo ""

# ── GraphQL (Apollo / graphql-java) ──
echo "--- GRAPHQL_FILES ---"
grep -rl 'ApolloClient\|@GraphQL\|graphql\|\.query(\|\.mutate(' "$SOURCES_DIR" 2>/dev/null | head -20 || echo "(none)"
echo ""

echo "--- CLEANUP ---"
for dir in "${CLEANUP_DIRS[@]}"; do
  [[ -d "$dir" ]] && echo "$dir"
done
echo ""
echo "========================================"
echo "DONE"
echo "========================================"
