#!/usr/bin/env bash
set -euo pipefail

# Chapter 1 setup script (macOS/Linux)
# Creates a local venv inside chapter_01 and installs requirements.

# --- Color helpers ---
echo_info()    { echo -e "\033[1;34m$1\033[0m"; }
echo_success() { echo -e "\033[1;32m$1\033[0m"; }
echo_error()   { echo -e "\033[1;31m$1\033[0m"; }

# --- Args / Defaults ---
ACTIVATE_SHELL=0
FORCE_NO_ACTIVATE=0
if [[ "${1:-}" == "--activate-shell" ]]; then
  ACTIVATE_SHELL=1
elif [[ "${1:-}" == "--no-activate" ]]; then
  FORCE_NO_ACTIVATE=1
fi

# Ensure we run relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH1_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$CH1_DIR/venv_chapter_01"
REQ_FILE="$SCRIPT_DIR/requirements.txt"

# 1) Check Homebrew and Python (best effort)
echo_info "Checking for Homebrew..."
if ! command -v brew &>/dev/null; then
  echo_info "Homebrew not found. Attempting to install..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
else
  echo_success "Homebrew is already installed."
fi

echo_info "Checking for Python (prefer 3.12)..."
if ! command -v python3 &>/dev/null && ! command -v python3.12 &>/dev/null && [ ! -x "/opt/homebrew/opt/python@3.12/bin/python3.12" ]; then
  echo_info "Python 3 not found. Attempting to install Python 3.12 via Homebrew..."
  brew install python@3.12 || true
else
  echo_success "Python is available."
fi

# 2) Create venv in chapter_01
if [ ! -d "$VENV_DIR" ]; then
  echo_info "Creating virtual environment at: $VENV_DIR"
  # Resolve preferred Python 3.12 binary
  if command -v python3.12 &>/dev/null; then
    PY_BIN="$(command -v python3.12)"
  elif [ -x "/opt/homebrew/opt/python@3.12/bin/python3.12" ]; then
    PY_BIN="/opt/homebrew/opt/python@3.12/bin/python3.12"
  elif command -v python3 &>/dev/null; then
    PY_BIN="$(command -v python3)"
  else
    echo_error "No suitable python found. Please install Python 3.12."
    exit 1
  fi
  "$PY_BIN" -m venv "$VENV_DIR"
else
  echo_success "Virtual environment already exists at: $VENV_DIR"
fi

# 3) Activate and install requirements
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

echo_info "Installing required Python packages from $REQ_FILE ..."
if [ -f "$REQ_FILE" ]; then
  python -m pip install --upgrade pip >/dev/null
  pip install -r "$REQ_FILE"
else
  echo_error "requirements.txt not found at $REQ_FILE"
  deactivate || true
  exit 1
fi

echo_success "All packages installed successfully."

# 4) Register this venv as a Jupyter kernel
echo_info "Registering Jupyter kernel: Python (Chapter 1)"
python -m ipykernel install --user --name chapter-01 --display-name "Python (Chapter 1)" >/dev/null 2>&1 || true

deactivate

echo_success "\nChapter 1 setup complete!"
echo_info   "Activate with: source chapter_01/venv_chapter_01/bin/activate"

# Smart auto-activation: interactive TTY and not CI/notebook, unless overridden
if [[ "$FORCE_NO_ACTIVATE" == "0" ]]; then
  if [[ "$ACTIVATE_SHELL" == "1" ]]; then
    echo_info "Launching a new shell with venv activated... (exit to return)"
    exec "$SHELL" -i -c "source '$VENV_DIR/bin/activate'; exec '$SHELL' -i"
  else
    # Heuristics: interactive TTY and not CI
    if [[ -t 1 && -n "${PS1:-}" && -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" ]]; then
      echo_info "Interactive terminal detected. Auto-activating a new shell... (exit to return)"
      exec "$SHELL" -i -c "source '$VENV_DIR/bin/activate'; exec '$SHELL' -i"
    else
      echo_info "Non-interactive or CI detected. Skipping auto-activation."
    fi
  fi
fi
