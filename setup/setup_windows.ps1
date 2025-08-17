# Data Strategy for LLMs - Book-wide setup script (Windows PowerShell)
# Creates a shared environment for all chapters

# --- Params ---
param(
  [switch]$ActivateShell
)

function Write-Info    { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Success { param([string]$m) Write-Host $m -ForegroundColor Green }
function Write-Error   { param([string]$m) Write-Host $m -ForegroundColor Red }

# Resolve script and repository directories
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$RepoRoot  = Split-Path -Path $ScriptDir -Parent
$VenvDir   = Join-Path $RepoRoot 'data_strategy_env'
$ReqFile   = Join-Path $ScriptDir 'requirements.txt'

Write-Info "Setting up Data Strategy for LLMs book environment..."

# 1) Resolve required Python 3.12 interpreter
Write-Info "Resolving Python (require 3.12) ..."
$py = $null
$pyver = $null

if (Get-Command py -ErrorAction SilentlyContinue) {
    $versionCheck = py -3.12 --version 2>&1
    if ($versionCheck -match "Python 3\.12") {
		# Windows Python launcher supports explicit 3.12 selection
		$py = 'py'
		$pyver = '-3.12'
    }
}

if (-not $py) {
	# Fallback to 'python' but verify version
	$versionCheck = python --version 2>&1
    if ($versionCheck -match "Python 3\.12") {
		$py = 'python'
		$pyver = ''
    }
}

if (-not $py) {
  Write-Error "Python 3.12 not found. Please install Python 3.12 (e.g., from python.org or via the Python launcher) and re-run."
  Write-Info  "If you have Chocolatey, you can try: choco install python --version=3.12.x"
  exit 1
}

# 2) Create shared venv for entire book
if (-not (Test-Path -Path $VenvDir)) {
  Write-Info "Creating shared virtual environment at: $VenvDir"
  & $py $py_ver -m venv "$VenvDir"
} else {
  Write-Success "Virtual environment already exists at: $VenvDir"
}

# 3) Activate and install requirements
. "$VenvDir\Scripts\Activate.ps1"

Write-Info "Installing required Python packages from $ReqFile ..."
if (Test-Path -Path $ReqFile) {
  python -m pip install --upgrade pip | Out-Null
  pip install -r "$ReqFile"
} else {
  Write-Error "requirements.txt not found at $ReqFile"
  deactivate
  exit 1
}

Write-Success "All packages installed successfully."

# 4) Register this venv as a Jupyter kernel
Write-Info "Registering Jupyter kernel: Python (Data Strategy Book)"
try {
  & "$VenvDir\Scripts\python.exe" -m ipykernel install --user --name data-strategy-book --display-name "Python (Data Strategy Book)" | Out-Null
} catch {
  Write-Info "Kernel registration skipped or failed (ipykernel may be missing)."
}

deactivate

Write-Success "`nData Strategy for LLMs setup complete!"
Write-Info    "Activate with: .\\data_strategy_env\\Scripts\\Activate.ps1"
Write-Info    "Jupyter kernel: Python (Data Strategy Book)"

# 5) Prompt for OpenAI API key setup
Write-Info "`n--- API Key Setup ---"
$envFile = Join-Path $RepoRoot '.env'
if (-not (Test-Path -Path $envFile)) {
  Write-Info "Setting up API keys for the book..."
  Write-Info "You'll need an OpenAI API key to run the examples."
  Write-Info "Get your key from: https://platform.openai.com/api-keys"
  Write-Host ""
  
  $openaiKey = Read-Host "Enter your OpenAI API key (starts with sk-)"
  
  if ($openaiKey) {
    # Basic format validation
    if ($openaiKey -notmatch '^sk-[a-zA-Z0-9]{48,}$') {
      Write-Error "Invalid API key format. OpenAI keys should start with 'sk-' followed by 48+ characters."
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
      . "$VenvDir\Scripts\Activate.ps1"
      
      try {
        $testResult = & "$VenvDir\Scripts\python.exe" -c @"
import os
import sys
sys.path.insert(0, '$RepoRoot')
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
          Write-Success $testResult
        } else {
          Write-Info $testResult
        }
      } catch {
        Write-Info "API key saved but connection test skipped (could not run test)."
      }
      
      deactivate
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
  $activate = Join-Path $VenvDir 'Scripts/Activate.ps1'
  powershell -NoExit -NoLogo -ExecutionPolicy Bypass -Command ". '$activate'"
}
