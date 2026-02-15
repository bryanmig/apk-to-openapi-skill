#!/usr/bin/env bash
# install-dep.sh — Install a dependency for APK-to-OpenAPI extraction
# Usage: install-dep.sh <dependency>
# Dependencies: java, jadx, hermes-dec
#
# Exit codes:
#   0 — installed successfully
#   1 — installation failed
#   2 — requires manual action
set -euo pipefail

usage() {
  cat <<EOF
Usage: install-dep.sh <dependency>

Install a dependency for APK-to-OpenAPI extraction.

Available dependencies:
  java         Java JDK 17+
  jadx         jadx decompiler
  hermes-dec   Hermes bytecode decompiler (Python package)

The script detects your OS and package manager, then installs
using the best available method (brew, user-local, or venv).
EOF
  exit 0
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

DEP="$1"

# --- Detect environment ---
OS="unknown"
PKG_MANAGER="none"
HAS_SUDO=false

case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="macos" ;;
esac

if command -v brew &>/dev/null; then
  PKG_MANAGER="brew"
elif command -v apt-get &>/dev/null; then
  PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
  PKG_MANAGER="dnf"
elif command -v pacman &>/dev/null; then
  PKG_MANAGER="pacman"
fi

if command -v sudo &>/dev/null; then
  HAS_SUDO=true
fi

info()   { echo "[INFO] $*"; }
ok()     { echo "[OK] $*"; }
fail()   { echo "[FAIL] $*" >&2; }
manual() { echo "[MANUAL] $*" >&2; exit 2; }

pkg_install() {
  local pkg="$1"
  case "$PKG_MANAGER" in
    brew)   info "Installing $pkg via Homebrew..."; brew install "$pkg" ;;
    apt)
      if [[ "$HAS_SUDO" == true ]]; then
        info "Installing $pkg via apt..."
        sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
      else
        manual "Run: sudo apt-get install $pkg"
      fi
      ;;
    dnf)
      if [[ "$HAS_SUDO" == true ]]; then
        sudo dnf install -y "$pkg"
      else
        manual "Run: sudo dnf install $pkg"
      fi
      ;;
    pacman)
      if [[ "$HAS_SUDO" == true ]]; then
        sudo pacman -S --noconfirm "$pkg"
      else
        manual "Run: sudo pacman -S $pkg"
      fi
      ;;
    *) manual "No supported package manager found. Install $pkg manually." ;;
  esac
}

download() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -fsSL -o "$dest" "$url"
  elif command -v wget &>/dev/null; then
    wget -q -O "$dest" "$url"
  else
    fail "Neither curl nor wget available."
    return 1
  fi
}

gh_latest_tag() {
  local repo="$1"
  local url="https://api.github.com/repos/$repo/releases/latest"
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
  elif command -v wget &>/dev/null; then
    wget -q -O - "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
  fi
}

add_to_profile() {
  local line="$1"
  local profile=""
  if [[ -f "$HOME/.zshrc" ]]; then
    profile="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    profile="$HOME/.bashrc"
  elif [[ -f "$HOME/.profile" ]]; then
    profile="$HOME/.profile"
  fi

  if [[ -n "$profile" ]]; then
    if ! grep -qF "$line" "$profile" 2>/dev/null; then
      echo "$line" >> "$profile"
      info "Added to $profile: $line"
    fi
  else
    info "Add this to your shell profile: $line"
  fi
}

# =====================================================================
# Dependency installers
# =====================================================================

install_java() {
  if command -v java &>/dev/null; then
    local ver
    ver=$(java -version 2>&1 | head -1 | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
    if [[ -n "$ver" ]] && (( ver >= 17 )); then
      ok "Java $ver already installed"
      return 0
    fi
  fi

  info "Installing Java JDK 17+..."
  case "$PKG_MANAGER" in
    brew)    brew install openjdk@17 ;;
    apt)     pkg_install "openjdk-17-jdk" ;;
    dnf)     pkg_install "java-17-openjdk-devel" ;;
    pacman)  pkg_install "jdk17-openjdk" ;;
    *)       manual "Install Java JDK 17+ from https://adoptium.net/" ;;
  esac

  if command -v java &>/dev/null; then
    ok "Java installed: $(java -version 2>&1 | head -1)"
  else
    # Homebrew keg-only: need to add to PATH
    if [[ "$PKG_MANAGER" == "brew" ]]; then
      local jdk_path="/opt/homebrew/opt/openjdk@17/bin"
      [[ ! -d "$jdk_path" ]] && jdk_path="/usr/local/opt/openjdk@17/bin"
      if [[ -d "$jdk_path" ]]; then
        export PATH="$jdk_path:$PATH"
        add_to_profile "export PATH=\"$jdk_path:\$PATH\""
        ok "Java installed (added $jdk_path to PATH)"
      else
        fail "Java installed but not on PATH. Check brew info openjdk@17."
        exit 1
      fi
    else
      fail "Java installation may have failed."
      exit 1
    fi
  fi
}

install_jadx() {
  if command -v jadx &>/dev/null; then
    ok "jadx already installed: $(jadx --version 2>/dev/null || echo 'unknown')"
    return 0
  fi

  if [[ "$PKG_MANAGER" == "brew" ]]; then
    info "Installing jadx via Homebrew..."
    brew install jadx
    ok "jadx installed via Homebrew"
    return 0
  fi

  # User-local install from GitHub releases
  info "Installing jadx from GitHub releases..."
  local tag
  tag=$(gh_latest_tag "skylot/jadx")
  if [[ -z "$tag" ]]; then
    fail "Could not determine latest jadx version."
    manual "Download from https://github.com/skylot/jadx/releases/latest"
  fi

  local version="${tag#v}"
  local url="https://github.com/skylot/jadx/releases/download/${tag}/jadx-${version}.zip"
  local tmp_zip
  tmp_zip=$(mktemp /tmp/jadx-XXXXXX.zip)

  info "Downloading jadx $version..."
  download "$url" "$tmp_zip"

  local install_dir="$HOME/.local/share/jadx"
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  unzip -qo "$tmp_zip" -d "$install_dir"
  rm -f "$tmp_zip"
  chmod +x "$install_dir/bin/jadx" "$install_dir/bin/jadx-gui" 2>/dev/null || true

  mkdir -p "$HOME/.local/bin"
  ln -sf "$install_dir/bin/jadx" "$HOME/.local/bin/jadx"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'

  ok "jadx $version installed to $install_dir"
}

install_hermes_dec() {
  # Determine project root for venv location
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local project_dir
  project_dir="$(cd "$script_dir/../../.." && pwd)"
  local venv_dir="$project_dir/.venv"

  # Check if already available
  if [[ -f "$venv_dir/bin/hbc-decompiler" ]]; then
    ok "hermes-dec already installed in venv: $venv_dir"
    return 0
  fi
  if command -v hbc-decompiler &>/dev/null; then
    ok "hermes-dec already installed (system)"
    return 0
  fi

  # Find Python 3
  local python_cmd=""
  if command -v python3 &>/dev/null; then
    python_cmd="python3"
  elif command -v python &>/dev/null; then
    local py_ver
    py_ver=$(python --version 2>&1 | sed -n 's/Python \([0-9]*\).*/\1/p')
    if [[ "$py_ver" == "3" ]]; then
      python_cmd="python"
    fi
  fi

  if [[ -z "$python_cmd" ]]; then
    fail "Python 3 is required to install hermes-dec."
    manual "Install Python 3 first, then re-run this script."
  fi

  info "Creating Python venv at $venv_dir..."
  $python_cmd -m venv "$venv_dir" 2>/dev/null || {
    # Some systems need ensurepip
    $python_cmd -m venv --without-pip "$venv_dir"
    "$venv_dir/bin/$python_cmd" -m ensurepip 2>/dev/null || true
  }

  info "Installing hermes-dec in venv..."
  "$venv_dir/bin/pip" install hermes-dec 2>&1

  if [[ -f "$venv_dir/bin/hbc-decompiler" ]]; then
    ok "hermes-dec installed in venv: $venv_dir"
    info "Use: $venv_dir/bin/hbc-decompiler <input> <output>"
  else
    fail "hermes-dec installation failed."
    info "Try manually: $venv_dir/bin/pip install hermes-dec"
    exit 1
  fi
}

# =====================================================================
# Dispatch
# =====================================================================

case "$DEP" in
  java)        install_java ;;
  jadx)        install_jadx ;;
  hermes-dec)  install_hermes_dec ;;
  *)
    echo "Error: Unknown dependency '$DEP'" >&2
    echo "Available: java, jadx, hermes-dec" >&2
    exit 1
    ;;
esac
