# Chapter 1 setup script (Windows PowerShell)
# Creates a local venv inside chapter_01 and installs requirements.

function Write-Info    { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Success { param([string]$m) Write-Host $m -ForegroundColor Green }
function Write-Error   { param([string]$m) Write-Host $m -ForegroundColor Red }

# --- Params ---
param(
  [switch]$ActivateShell
)

# Resolve script and chapter_01 directories
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$Ch1Dir    = Split-Path -Path $ScriptDir -Parent
$VenvDir   = Join-Path $Ch1Dir 'venv_chapter_01'
$ReqFile   = Join-Path $ScriptDir 'requirements.txt'

<# 1) Resolve preferred Python 3.12 interpreter #>
Write-Info "Resolving Python (prefer 3.12) ..."
$py312 = $null

if (Get-Command py -ErrorAction SilentlyContinue) {
  # Windows Python launcher supports explicit 3.12 selection
  $py312 = 'py -3.12'
}
elseif (Get-Command python -ErrorAction SilentlyContinue) {
  # Fallback to 'python' but verify version
  try {
    $ver = (& python -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
    if ($ver -eq '3.12') { $py312 = 'python' }
  } catch {}
}

if (-not $py312) {
  Write-Error "Python 3.12 not found. Please install Python 3.12 (e.g., from python.org or via the Python launcher) and re-run."
  Write-Info  "If you have Chocolatey, you can try: choco install python --version=3.12.x"
  exit 1
}

# 2) Create venv in chapter_01
if (-not (Test-Path -Path $VenvDir)) {
  Write-Info "Creating virtual environment at: $VenvDir"
  & $py312 -m venv "$VenvDir"
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
Write-Info "Registering Jupyter kernel: Python (Chapter 1)"
try {
  & "$VenvDir\Scripts\python.exe" -m ipykernel install --user --name chapter-01 --display-name "Python (Chapter 1)" | Out-Null
} catch {
  Write-Info "Kernel registration skipped or failed (ipykernel may be missing)."
}

deactivate

Write-Success "`nChapter 1 setup complete!"
Write-Info    "Activate with: .\\chapter_01\\venv_chapter_01\\Scripts\\Activate.ps1"

# Optionally open a new PowerShell with the venv activated
if ($ActivateShell.IsPresent) {
  Write-Info "Launching a new PowerShell with venv activated... (close that window to exit)"
  $activate = Join-Path $VenvDir 'Scripts/Activate.ps1'
  powershell -NoExit -NoLogo -ExecutionPolicy Bypass -Command ". '$activate'"
}
