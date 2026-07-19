#!/usr/bin/env bash
set -euo pipefail

# Data Strategy for LLMs - Book-wide setup script (macOS/Linux)
# Creates a shared environment for all chapters.
#
# The script finds the newest supported Python on your machine (3.10 or
# newer, preferring the latest stable release). If none exists, it installs
# one via Homebrew on macOS. It also self-heals: a virtual environment
# built with an unsupported Python (for example the macOS system 3.9) is
# detected and rebuilt automatically.

# --- Color helpers ---
echo_info()    { echo -e "\033[1;34m$1\033[0m"; }
echo_success() { echo -e "\033[1;32m$1\033[0m"; }
echo_error()   { echo -e "\033[1;31m$1\033[0m"; }

# --- Supported Python range ---
# Newest first. Update this list as new stable Python releases prove out
# with the ML stack (torch, chromadb, tiktoken all ship wheels for these).
PREFERRED_MINORS="14 13 12 11 10"
MIN_MINOR=10                # 3.10 floor: torch >= 2.6 requires it
BREW_TARGET="python@3.14"   # what we install when nothing suitable exists

# --- Args / Defaults ---
ACTIVATE_SHELL=0
FORCE_NO_ACTIVATE=0
RECREATE_ENV=0
CLEAN_DB=0

for arg in "$@"; do
  case "$arg" in
    --activate-shell) ACTIVATE_SHELL=1 ;;
    --no-activate)    FORCE_NO_ACTIVATE=1 ;;
    --recreate-env)   RECREATE_ENV=1 ;;
    --clean-db)       CLEAN_DB=1 ;;
    *) ;;
  esac
done

# Ensure we run relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$REPO_ROOT/data_strategy_env"
REQ_FILE="$SCRIPT_DIR/requirements.txt"

echo_info "Setting up Data Strategy for LLMs book environment..."

# --- Python helpers ---

# Print "3.X" for a python binary, empty on failure
py_version_of() {
  "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true
}

# Is version "3.X" inside our supported range?
version_supported() {
  local v="$1"
  case "$v" in
    3.*) [ "${v#3.}" -ge "$MIN_MINOR" ] 2>/dev/null ;;
    *)   return 1 ;;
  esac
}

# Find the newest supported Python. Checks PATH first, then Homebrew kegs
# (which are not always linked into PATH). Sets PY_BIN on success.
find_python() {
  PY_BIN=""
  local minor candidate keg
  for minor in $PREFERRED_MINORS; do
    # PATH lookup
    candidate="$(command -v "python3.$minor" 2>/dev/null || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      PY_BIN="$candidate"
      return 0
    fi
    # Homebrew keg lookup (macOS; handles unlinked installs)
    if command -v brew &>/dev/null; then
      keg="$(brew --prefix "python@3.$minor" 2>/dev/null || true)"
      if [ -n "$keg" ] && [ -x "$keg/bin/python3.$minor" ]; then
        PY_BIN="$keg/bin/python3.$minor"
        return 0
      fi
    fi
  done
  # Last resort: a generic python3, but only if its version is supported.
  # This is the check the old script skipped, which is how the macOS
  # system Python 3.9 ended up in the environment.
  candidate="$(command -v python3 2>/dev/null || true)"
  if [ -n "$candidate" ]; then
    local v
    v="$(py_version_of "$candidate")"
    if version_supported "$v"; then
      PY_BIN="$candidate"
      return 0
    fi
  fi
  return 1
}

# 1) Locate (or install) a supported Python
echo_info "Looking for Python 3.$MIN_MINOR or newer (newest preferred)..."
if ! find_python; then
  SYS_PY_VER="$(py_version_of "$(command -v python3 2>/dev/null || echo /usr/bin/python3)")"
  [ -n "$SYS_PY_VER" ] && echo_info "Found only Python $SYS_PY_VER, which this book's ML stack does not support."
  if [ "$(uname -s)" = "Darwin" ]; then
    echo_info "Installing $BREW_TARGET via Homebrew..."
    if ! command -v brew &>/dev/null; then
      echo_info "Homebrew not found. Installing Homebrew first..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # Make brew visible in this shell (Apple Silicon and Intel paths)
      eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || eval "$(/usr/local/bin/brew shellenv 2>/dev/null)" || true
    fi
    brew install "$BREW_TARGET"
    if ! find_python; then
      echo_error "Installed $BREW_TARGET but still cannot locate it. Try opening a new terminal and re-running this script."
      exit 1
    fi
  else
    echo_error "No supported Python found. Please install Python 3.12 or newer, e.g.:"
    echo_error "  Ubuntu/Debian: sudo apt install python3.12 python3.12-venv"
    echo_error "  Fedora:        sudo dnf install python3.12"
    exit 1
  fi
fi
PY_VER="$(py_version_of "$PY_BIN")"
echo_success "Using Python $PY_VER at $PY_BIN"

# 2) Create the shared venv, self-healing broken or outdated ones
if [ "$RECREATE_ENV" -eq 1 ] && [ -d "$VENV_DIR" ]; then
  echo_info "Recreating virtual environment (removing $VENV_DIR) ..."
  rm -rf "$VENV_DIR"
fi

if [ -d "$VENV_DIR" ]; then
  VENV_VER="$(py_version_of "$VENV_DIR/bin/python")"
  if [ -z "$VENV_VER" ]; then
    echo_info "Existing environment is broken (its Python no longer runs). Rebuilding..."
    rm -rf "$VENV_DIR"
  elif ! version_supported "$VENV_VER"; then
    echo_info "Existing environment uses Python $VENV_VER, which is not supported. Rebuilding with Python $PY_VER..."
    rm -rf "$VENV_DIR"
  else
    echo_success "Virtual environment already exists at: $VENV_DIR (Python $VENV_VER)"
  fi
fi

if [ ! -d "$VENV_DIR" ]; then
  echo_info "Creating shared virtual environment at: $VENV_DIR"
  "$PY_BIN" -m venv "$VENV_DIR"
fi

# 3) Install requirements (retry once on a fresh venv if the first pass fails)
if [ ! -f "$REQ_FILE" ]; then
  echo_error "requirements.txt not found at $REQ_FILE"
  exit 1
fi

install_requirements() {
  "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
  "$VENV_DIR/bin/pip" install -r "$REQ_FILE"
}

echo_info "Installing required Python packages from $REQ_FILE ..."
if ! install_requirements; then
  echo_info "Package installation failed. Rebuilding the environment and retrying once..."
  rm -rf "$VENV_DIR"
  "$PY_BIN" -m venv "$VENV_DIR"
  if ! install_requirements; then
    echo_error "Package installation failed twice. Check your network connection and re-run this script."
    exit 1
  fi
fi
echo_success "All packages installed successfully."

# 4) Smoke test: actually import the key libraries the chapters need
echo_info "Verifying the environment (importing key packages)..."
if "$VENV_DIR/bin/python" - <<'PY'
import sys
print(f"  Python {sys.version.split()[0]} at {sys.executable}")
failed = []
for mod in ["openai", "dotenv", "chromadb", "tiktoken", "torch",
            "transformers", "peft", "pandas", "numpy", "sklearn",
            "bs4", "pypdf", "networkx", "matplotlib", "ipykernel"]:
    try:
        m = __import__(mod)
        ver = getattr(m, "__version__", "")
        if mod in ("openai", "chromadb", "torch", "transformers"):
            print(f"  {mod} {ver}")
    except Exception as e:
        failed.append(f"{mod} ({e})")
if failed:
    print("  FAILED imports: " + "; ".join(failed))
    sys.exit(1)
print("  All key packages import correctly.")
PY
then
  echo_success "Environment verified."
else
  echo_error "Environment verification failed. Re-run with --recreate-env; if it persists, please open an issue on the book's GitHub repository."
  exit 1
fi

# 5) Register this venv as a Jupyter kernel (idempotent)
echo_info "Registering Jupyter kernel: Python (Data Strategy Book)"
"$VENV_DIR/bin/jupyter" kernelspec uninstall -y data-strategy-book >/dev/null 2>&1 || true
"$VENV_DIR/bin/python" -m ipykernel install --user --name data-strategy-book --display-name "Python (Data Strategy Book)" >/dev/null 2>&1 || true

echo_success "\nData Strategy for LLMs setup complete!"
echo_info   "Activate with: source data_strategy_env/bin/activate"
echo_info   "Jupyter kernel: Python (Data Strategy Book)"

# 6) Optional: clean shared ChromaDB directory
if [ "$CLEAN_DB" -eq 1 ]; then
  DB_DIR="$REPO_ROOT/data/chroma_db"
  echo_info "Cleaning shared ChromaDB directory at: $DB_DIR"
  rm -rf "$DB_DIR"
  echo_success "ChromaDB directory cleaned."
fi

# 7) Prompt for OpenAI API key setup
echo_info "\n--- API Key Setup ---"
if [ ! -f "$REPO_ROOT/.env" ]; then
  echo_info "Setting up API keys for the book..."
  echo_info "You'll need an OpenAI API key to run the examples."
  echo_info "Get your key from: https://platform.openai.com/api-keys"
  echo ""

  read -p "Enter your OpenAI API key (starts with sk-): " openai_key

  if [ -n "$openai_key" ]; then
    # Basic format validation (covers both sk- and sk-proj- keys)
    if [[ ! "$openai_key" =~ ^sk-[a-zA-Z0-9_-]{20,}$ ]]; then
      echo_error "Invalid API key format. OpenAI keys should start with 'sk-' followed by 20+ characters."
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
      "$VENV_DIR/bin/python" -c "
import sys
sys.path.insert(0, '$REPO_ROOT')
try:
    from utils.config import get_openai_api_key
    import openai

    api_key = get_openai_api_key()
    client = openai.OpenAI(api_key=api_key)

    # Test with a minimal API call
    response = client.models.list()
    print('API key is valid and connection successful!')
    print(f'Available models: {len(response.data)} models found')

except ImportError as e:
    print(f'Could not import required modules: {e}')
    print('API key saved but could not test connection.')
except Exception as e:
    print(f'API key test failed: {e}')
    print('Please check your API key and billing status at https://platform.openai.com/')
    print('Make sure you have credits available in your OpenAI account.')
" 2>/dev/null || echo_info "API key saved but connection test skipped."
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
