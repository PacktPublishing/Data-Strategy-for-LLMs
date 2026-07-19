# Data Strategy for LLMs - Book-wide setup script (Windows PowerShell)
# Creates a shared environment for all chapters.
#
# The script finds the newest supported Python on your machine (3.10 or
# newer, preferring the latest stable release). If none exists, it installs
# one via winget. It also self-heals: a virtual environment built with an
# unsupported Python is detected and rebuilt automatically.

# --- Params ---
param(
  [switch]$ActivateShell,
  [switch]$RecreateEnv,
  [switch]$CleanDb
)

function Write-Info    { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Success { param([string]$m) Write-Host $m -ForegroundColor Green }
function Write-Err     { param([string]$m) Write-Host $m -ForegroundColor Red }

# --- Supported Python range ---
# Newest first. Update as new stable Python releases prove out with the
# ML stack (torch, chromadb, tiktoken all ship wheels for these).
$PreferredMinors = @(14, 13, 12, 11, 10)
$MinMinor        = 10                    # 3.10 floor: torch >= 2.6 requires it
$WingetTarget    = 'Python.Python.3.14'  # installed when nothing suitable exists

# Resolve script and repository directories
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$RepoRoot  = Split-Path -Path $ScriptDir -Parent
$VenvDir   = Join-Path $RepoRoot 'data_strategy_env'
$ReqFile   = Join-Path $ScriptDir 'requirements.txt'

Write-Info "Setting up Data Strategy for LLMs book environment..."

# --- Python helpers ---

# Returns "3.X" for a python executable, or $null on failure
function Get-PyVersion {
  param([string]$exe)
  try {
    $v = & $exe -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
    if ($v -match '^3\.\d+$') { return $v.Trim() }
  } catch {}
  return $null
}

function Test-VersionSupported {
  param([string]$v)
  if ($v -match '^3\.(\d+)$') { return ([int]$Matches[1] -ge $MinMinor) }
  return $false
}

# Find the newest supported Python via the py launcher, then PATH
function Find-Python {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    foreach ($minor in $PreferredMinors) {
      $exe = $null
      try { $exe = (& py "-3.$minor" -c "import sys; print(sys.executable)" 2>$null) } catch {}
      if ($exe) { return $exe.Trim() }
    }
  }
  # Fall back to plain 'python', but verify its version. (The old script's
  # bug class: accepting whatever python exists without checking.)
  if (Get-Command python -ErrorAction SilentlyContinue) {
    $exe = (Get-Command python).Source
    $v = Get-PyVersion $exe
    if ($v -and (Test-VersionSupported $v)) { return $exe }
  }
  return $null
}

# 1) Locate (or install) a supported Python
Write-Info "Looking for Python 3.$MinMinor or newer (newest preferred)..."
$pythonExe = Find-Python

if (-not $pythonExe) {
  Write-Info "No supported Python found. Attempting install via winget: $WingetTarget"
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id $WingetTarget -e --accept-source-agreements --accept-package-agreements
    # The installer registers the py launcher; PATH updates need a fresh
    # session, so re-scan using the launcher and known install locations.
    $pythonExe = Find-Python
    if (-not $pythonExe) {
      $guess = Join-Path $env:LocalAppData 'Programs\Python\Python314\python.exe'
      if (Test-Path $guess) { $pythonExe = $guess }
    }
  }
  if (-not $pythonExe) {
    Write-Err "Could not find or install a supported Python (3.$MinMinor+)."
    Write-Info "Install the latest Python from https://www.python.org/downloads/ then re-run this script in a NEW PowerShell window."
    exit 1
  }
}

$pyVer = Get-PyVersion $pythonExe
Write-Success "Using Python $pyVer at $pythonExe"

# 2) Create the shared venv, self-healing broken or outdated ones
if ($RecreateEnv.IsPresent -and (Test-Path -Path $VenvDir)) {
  Write-Info "Recreating virtual environment (removing $VenvDir) ..."
  Remove-Item -Recurse -Force $VenvDir
}

$venvPython = Join-Path $VenvDir 'Scripts\python.exe'
if (Test-Path -Path $VenvDir) {
  $venvVer = $null
  if (Test-Path $venvPython) { $venvVer = Get-PyVersion $venvPython }
  if (-not $venvVer) {
    Write-Info "Existing environment is broken (its Python no longer runs). Rebuilding..."
    Remove-Item -Recurse -Force $VenvDir
  } elseif (-not (Test-VersionSupported $venvVer)) {
    Write-Info "Existing environment uses Python $venvVer, which is not supported. Rebuilding with Python $pyVer..."
    Remove-Item -Recurse -Force $VenvDir
  } else {
    Write-Success "Virtual environment already exists at: $VenvDir (Python $venvVer)"
  }
}

if (-not (Test-Path -Path $VenvDir)) {
  Write-Info "Creating shared virtual environment at: $VenvDir"
  & $pythonExe -m venv "$VenvDir"
}

# 3) Install requirements (retry once on a fresh venv if the first pass fails)
if (-not (Test-Path -Path $ReqFile)) {
  Write-Err "requirements.txt not found at $ReqFile"
  exit 1
}

function Install-Requirements {
  & $venvPython -m pip install --upgrade pip | Out-Null
  & $venvPython -m pip install -r "$ReqFile"
  return ($LASTEXITCODE -eq 0)
}

Write-Info "Installing required Python packages from $ReqFile ..."
if (-not (Install-Requirements)) {
  Write-Info "Package installation failed. Rebuilding the environment and retrying once..."
  Remove-Item -Recurse -Force $VenvDir
  & $pythonExe -m venv "$VenvDir"
  if (-not (Install-Requirements)) {
    Write-Err "Package installation failed twice. Check your network connection and re-run this script."
    exit 1
  }
}
Write-Success "All packages installed successfully."

# 4) Smoke test: actually import the key libraries the chapters need
Write-Info "Verifying the environment (importing key packages)..."
$smokeTest = @"
import sys
print(f'  Python {sys.version.split()[0]} at {sys.executable}')
failed = []
for mod in ['openai', 'dotenv', 'chromadb', 'tiktoken', 'torch',
            'transformers', 'peft', 'pandas', 'numpy', 'sklearn',
            'bs4', 'pypdf', 'networkx', 'matplotlib', 'ipykernel']:
    try:
        m = __import__(mod)
        ver = getattr(m, '__version__', '')
        if mod in ('openai', 'chromadb', 'torch', 'transformers'):
            print(f'  {mod} {ver}')
    except Exception as e:
        failed.append(f'{mod} ({e})')
if failed:
    print('  FAILED imports: ' + '; '.join(failed))
    sys.exit(1)
print('  All key packages import correctly.')
"@
& $venvPython -c $smokeTest
if ($LASTEXITCODE -ne 0) {
  Write-Err "Environment verification failed. Re-run with -RecreateEnv; if it persists, please open an issue on the book's GitHub repository."
  exit 1
}
Write-Success "Environment verified."

# 5) Register this venv as a Jupyter kernel (idempotent)
Write-Info "Registering Jupyter kernel: Python (Data Strategy Book)"
try {
  & $venvPython -m jupyter kernelspec uninstall -y data-strategy-book 2>$null | Out-Null
} catch {}
try {
  & $venvPython -m ipykernel install --user --name data-strategy-book --display-name "Python (Data Strategy Book)" | Out-Null
} catch {
  Write-Info "Kernel registration skipped or failed (ipykernel may be missing)."
}

Write-Success "`nData Strategy for LLMs setup complete!"
Write-Info    "Activate with: .\data_strategy_env\Scripts\Activate.ps1"
Write-Info    "Jupyter kernel: Python (Data Strategy Book)"

# 6) Optional: clean shared ChromaDB directory
if ($CleanDb.IsPresent) {
  $DbDir = Join-Path $RepoRoot 'data\chroma_db'
  Write-Info "Cleaning shared ChromaDB directory at: $DbDir"
  if (Test-Path $DbDir) { Remove-Item -Recurse -Force $DbDir }
  Write-Success "ChromaDB directory cleaned."
}

# 7) Prompt for OpenAI API key setup
Write-Info "`n--- API Key Setup ---"
$envFile = Join-Path $RepoRoot '.env'
if (-not (Test-Path -Path $envFile)) {
  Write-Info "Setting up API keys for the book..."
  Write-Info "You'll need an OpenAI API key to run the examples."
  Write-Info "Get your key from: https://platform.openai.com/api-keys"
  Write-Host ""

  $openaiKey = Read-Host "Enter your OpenAI API key (starts with sk-)"

  if ($openaiKey) {
    # Basic format validation (covers both sk- and sk-proj- keys)
    if ($openaiKey -notmatch '^sk-[a-zA-Z0-9_-]{20,}$') {
      Write-Err "Invalid API key format. OpenAI keys should start with 'sk-' followed by 20+ characters."
      Write-Info "Please check your key and try again manually by editing .env file."
    } else {
      # Create .env file from template
      $envExample = Join-Path $RepoRoot '.env.example'
      if (Test-Path -Path $envExample) {
        Copy-Item -Path $envExample -Destination $envFile
        # Replace the placeholder with actual key
        (Get-Content $envFile) -replace 'your-openai-api-key-here', $openaiKey | Set-Content $envFile
      } else {
        # Create .env file directly
        "OPENAI_API_KEY=$openaiKey" | Out-File -FilePath $envFile -Encoding UTF8
      }

      Write-Success "API key saved to .env file!"

      # Test the API key connection
      Write-Info "Testing API key connection..."
      try {
        $testResult = & $venvPython -c @"
import sys
sys.path.insert(0, r'$RepoRoot')
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
"@
        if ($testResult -match "API key is valid") {
          Write-Success ($testResult -join "`n")
        } else {
          Write-Info ($testResult -join "`n")
        }
      } catch {
        Write-Info "API key saved but connection test skipped (could not run test)."
      }
    }
  } else {
    Write-Info "Skipped API key setup. You can add it later to .env file."
    Write-Info "Copy .env.example to .env and add your keys manually."
  }
} else {
  Write-Success ".env file already exists - API keys configured!"
}

# Optionally open a new PowerShell with the venv activated
if ($ActivateShell.IsPresent) {
  Write-Info "Launching a new PowerShell with venv activated... (close that window to exit)"
  $activate = Join-Path $VenvDir 'Scripts\Activate.ps1'
  powershell -NoExit -NoLogo -ExecutionPolicy Bypass -Command ". '$activate'"
}
