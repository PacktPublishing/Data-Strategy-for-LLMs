# Windows Development Environment Setup Script
# This script automates the setup process for the 'Data Strategy for LLMs' book project.

# --- Color Functions for Output ---
function Write-Info {
    param([string]$message)
    Write-Host $message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$message)
    Write-Host $message -ForegroundColor Green
}

function Write-Error {
    param([string]$message)
    Write-Host $message -ForegroundColor Red
}

# --- Step 1: Check for Administrator Privileges ---
Write-Info "Checking for Administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script needs to be run as Administrator to install packages. Please re-run PowerShell as Administrator."
    exit 1
}
Write-Success "Running with Administrator privileges."

# --- Step 2: Check for and Install Chocolatey ---
Write-Info "Checking for Chocolatey package manager..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Info "Chocolatey not found. Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Error "Chocolatey installation failed. Please install it manually and re-run this script."
        exit 1
    }
} else {
    Write-Success "Chocolatey is already installed."
}

# --- Step 3: Check for and Install Python 3 ---
Write-Info "Checking for Python 3..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Info "Python 3 not found. Installing Python 3 via Chocolatey..."
    choco install python -y
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Error "Python 3 installation failed. Please try installing it manually."
        exit 1
    }
} else {
    Write-Success "Python 3 is already installed."
}

# --- Step 4: Create a Python Virtual Environment in the Project Root ---

$projectDir = "..\llm-data-book"

Write-Info "Setting up project directory and virtual environment..."

if (-not (Test-Path -Path $projectDir)) {
    New-Item -ItemType Directory -Path $projectDir
    Write-Info "Created project directory: $projectDir"
}

# Copy requirements.txt from the current directory
Copy-Item -Path "requirements.txt" -Destination $projectDir

# Navigate to the project directory
Set-Location $projectDir

if (-not (Test-Path -Path "venv")) {
    python -m venv venv
    Write-Info "Created virtual environment in '$projectDir\venv'"
} else {
    Write-Success "Virtual environment already exists."
}

# --- Step 5: Activate Virtual Environment and Install Packages ---
Write-Info "Activating virtual environment and installing packages..."

# Activate the virtual environment
.\venv\Scripts\Activate.ps1

# Installing required Python packages
Write-Info "Installing required Python packages from requirements.txt..."

pip install -r requirements.txt

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install Python packages. Please check requirements.txt and your internet connection."
    deactivate
    exit 1
}

Write-Success "All packages installed successfully."

# --- Final Instructions ---
deactivate
Write-Success "\nSetup complete!"
Write-Info "To get started, navigate to the project directory and activate the virtual environment:"
Write-Info "  cd $projectDir"
Write-Info "  .\venv\Scripts\Activate.ps1"
