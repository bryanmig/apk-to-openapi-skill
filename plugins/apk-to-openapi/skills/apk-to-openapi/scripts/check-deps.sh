#!/usr/bin/env bash
# check-deps.sh — Verify all dependencies for APK-to-OpenAPI extraction
set -euo pipefail

REQUIRED_JAVA_MAJOR=17
errors=0
missing_required=()
missing_optional=()

echo "=== APK-to-OpenAPI: Dependency Check ==="
echo

# --- Java ---
java_found=false
if command -v java &>/dev/null; then
  java_version_output=$(java -version 2>&1 || true)
  java_first_line=$(echo "$java_version_output" | head -1)
  # Extract major version, handling both "17.0.x" and "1.8.x" formats
  java_version=$(echo "$java_first_line" | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
  if [[ "$java_version" == "1" ]]; then
    java_version=$(echo "$java_first_line" | sed -n 's/.*"1\.\([0-9]*\)\..*/\1/p')
  fi

  if [[ -n "$java_version" ]] && (( java_version >= REQUIRED_JAVA_MAJOR )); then
    echo "[OK] Java $java_version"
    java_found=true
  elif [[ -n "$java_version" ]]; then
    echo "[WARN] Java $java_version detected (need $REQUIRED_JAVA_MAJOR+)"
  fi
fi

if [[ "$java_found" == false ]]; then
  # macOS stub at /usr/bin/java may exist but not have a real JDK
  echo "[MISSING] Java (JDK $REQUIRED_JAVA_MAJOR+ required)"
  errors=$((errors + 1))
  missing_required+=("java")
fi

# --- jadx ---
if command -v jadx &>/dev/null; then
  jadx_version=$(jadx --version 2>/dev/null || echo "unknown")
  echo "[OK] jadx $jadx_version"
else
  echo "[MISSING] jadx"
  errors=$((errors + 1))
  missing_required+=("jadx")
fi

# --- Python 3 ---
PYTHON_CMD=""
if command -v python3 &>/dev/null; then
  PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
  py_ver=$(python --version 2>&1 | sed -n 's/Python \([0-9]*\).*/\1/p')
  if [[ "$py_ver" == "3" ]]; then
    PYTHON_CMD="python"
  fi
fi

if [[ -n "$PYTHON_CMD" ]]; then
  py_full=$($PYTHON_CMD --version 2>&1)
  echo "[OK] $py_full"
else
  echo "[MISSING] Python 3"
  errors=$((errors + 1))
  missing_required+=("python3")
fi

# --- hermes-dec ---
# Check in venv first, then system PATH
HERMES_DEC_CMD=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"

if [[ -f "$VENV_DIR/bin/hbc-decompiler" ]]; then
  HERMES_DEC_CMD="$VENV_DIR/bin/hbc-decompiler"
  echo "[OK] hermes-dec (venv: $VENV_DIR)"
elif command -v hbc-decompiler &>/dev/null; then
  HERMES_DEC_CMD="hbc-decompiler"
  echo "[OK] hermes-dec (system)"
else
  echo "[MISSING] hermes-dec (Hermes bytecode decompiler)"
  errors=$((errors + 1))
  missing_required+=("hermes-dec")
fi

# --- Optional: npx / redocly (for OpenAPI validation) ---
if command -v npx &>/dev/null; then
  echo "[OK] npx (for OpenAPI validation)"
else
  echo "[MISSING] npx (optional — for OpenAPI spec validation)"
  missing_optional+=("npx")
fi

# --- Machine-readable summary ---
echo
if [[ ${#missing_required[@]} -gt 0 ]]; then
  for dep in "${missing_required[@]}"; do
    echo "INSTALL_REQUIRED:$dep"
  done
fi
if [[ ${#missing_optional[@]} -gt 0 ]]; then
  for dep in "${missing_optional[@]}"; do
    echo "INSTALL_OPTIONAL:$dep"
  done
fi

echo
if (( errors > 0 )); then
  echo "*** ${#missing_required[@]} required dependency/ies missing. ***"
  echo "Run: bash $(dirname "$0")/install-dep.sh <name>"
  exit 1
else
  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    echo "Required dependencies OK. ${#missing_optional[@]} optional dependency/ies missing."
  else
    echo "All dependencies installed. Ready to extract APIs."
  fi
  exit 0
fi
