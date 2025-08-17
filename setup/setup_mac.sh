#!/usr/bin/env bash
set -euo pipefail

# Data Strategy for LLMs - Book-wide setup script (macOS/Linux)
# Creates a shared environment for all chapters

# --- Color helpers ---
echo_info()    { echo -e "\033[1;34m$1\033[0m"; }
echo_success() { echo -e "\033[1;32m$1\033[0m"; }
echo_error()   { echo -e "\033[1;31m$1\033[0m"; }

# --- Args / Defaults ---
ACTIVATE_SHELL=0
FORCE_NO_ACTIVATE=0
RECREATE_ENV=0
CLEAN_DB=0

for arg in "$@"; do
  case "$arg" in
    --activate-shell)
      ACTIVATE_SHELL=1
      ;;
    --no-activate)
      FORCE_NO_ACTIVATE=1
      ;;
    --recreate-env)
      RECREATE_ENV=1
      ;;
    --clean-db)
      CLEAN_DB=1
      ;;
    *)
      ;;
  esac
done

# Ensure we run relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$REPO_ROOT/data_strategy_env"
REQ_FILE="$SCRIPT_DIR/requirements.txt"

echo_info "Setting up Data Strategy for LLMs book environment..."

# 1) Check Homebrew and Python (prefer 3.12)
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

# 2) Optionally recreate env, then create shared venv for entire book
if [ "$RECREATE_ENV" -eq 1 ] && [ -d "$VENV_DIR" ]; then
  echo_info "Recreating virtual environment (removing $VENV_DIR) ..."
  rm -rf "$VENV_DIR"
fi

if [ ! -d "$VENV_DIR" ]; then
  echo_info "Creating shared virtual environment at: $VENV_DIR"
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

# 4) Register this venv as a Jupyter kernel (idempotent)
echo_info "Registering Jupyter kernel: Python (Data Strategy Book)"
# Try to remove any existing kernelspec with the same name to avoid dupes
jupyter kernelspec uninstall -y data-strategy-book >/dev/null 2>&1 || true
python -m ipykernel install --user --name data-strategy-book --display-name "Python (Data Strategy Book)" >/dev/null 2>&1 || true

deactivate

echo_success "\nData Strategy for LLMs setup complete!"
echo_info   "Activate with: source data_strategy_env/bin/activate"
echo_info   "Jupyter kernel: Python (Data Strategy Book)"

# 5) Optional: clean shared ChromaDB directory
if [ "$CLEAN_DB" -eq 1 ]; then
  DB_DIR="$REPO_ROOT/data/chroma_db"
  echo_info "Cleaning shared ChromaDB directory at: $DB_DIR"
  rm -rf "$DB_DIR"
  echo_success "ChromaDB directory cleaned."
fi

# 6) Prompt for OpenAI API key setup
echo_info "\n--- API Key Setup ---"
if [ ! -f "$REPO_ROOT/.env" ]; then
  echo_info "Setting up API keys for the book..."
  echo_info "You'll need an OpenAI API key to run the examples."
  echo_info "Get your key from: https://platform.openai.com/api-keys"
  echo ""
  
  read -p "Enter your OpenAI API key (starts with sk-): " openai_key
  
  if [ -n "$openai_key" ]; then
    # Basic format validation
    if [[ ! "$openai_key" =~ ^sk-[a-zA-Z0-9]{48,}$ ]]; then
      echo_error "Invalid API key format. OpenAI keys should start with 'sk-' followed by 48+ characters."
      echo_info "Please check your key and try again manually by editing .env file."
    else
      # Create .env file from template
      if [ -f "$REPO_ROOT/.env.example" ]; then
        cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
        # Replace the placeholder with actual key
        sed -i.bak "s/your-openai-api-key-here/$openai_key/" "$REPO_ROOT/.env"
        rm "$REPO_ROOT/.env.bak" 2>/dev/null || true
      else
        # Create .env file directly
        echo "OPENAI_API_KEY=$openai_key" > "$REPO_ROOT/.env"
      fi
      
      echo_success "API key saved to .env file!"
      
      # Test the API key connection
      echo_info "Testing API key connection..."
      # shellcheck disable=SC1090
      source "$VENV_DIR/bin/activate"
      
      python3 -c "
import os
import sys
sys.path.insert(0, '$REPO_ROOT')
try:
    from utils.config import get_openai_api_key
    import openai
    
    api_key = get_openai_api_key()
    client = openai.OpenAI(api_key=api_key)
    
    # Test with a minimal API call
    response = client.models.list()
    print('✅ API key is valid and connection successful!')
    print(f'Available models: {len(response.data)} models found')
    
except ImportError as e:
    print(f'⚠️  Could not import required modules: {e}')
    print('API key saved but could not test connection.')
except Exception as e:
    print(f'❌ API key test failed: {e}')
    print('Please check your API key and billing status at https://platform.openai.com/')
    print('Make sure you have credits available in your OpenAI account.')
" 2>/dev/null || echo_info "API key saved but connection test skipped (openai package not available yet)."
      
      deactivate
    fi
  else
    echo_info "Skipped API key setup. You can add it later to .env file."
    echo_info "Copy .env.example to .env and add your keys manually."
  fi
else
  echo_success ".env file already exists - API keys configured!"
fi

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
