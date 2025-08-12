# Chapter 5 setup script (Windows PowerShell)
# Creates a local venv, installs requirements, and prints versions.

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ch5Dir = Split-Path -Parent $scriptDir
$venvDir = Join-Path $ch5Dir '.venv-ch5'
$reqFile = Join-Path $scriptDir 'requirements.txt'

python -m venv $venvDir

$activate = Join-Path $venvDir 'Scripts\Activate.ps1'
. $activate

python -m pip install --upgrade pip | Out-Null
python -m pip install -r $reqFile -q

python - << 'PY'
import sys, pkgutil
print('Chapter 5 environment setup complete.\n')
print('Python:', sys.version.split()[0])
mods = ['chromadb','tiktoken','requests','bs4','pypdf','wikipediaapi','Bio','reportlab']
for m in mods:
    found = pkgutil.find_loader(m) is not None
    print(f'- {m}: {"OK" if found else "MISSING"}')
PY

# Generate sample PDF for the figure/caption demo (idempotent)
$pdfScript = Join-Path $ch5Dir 'chapter5/data/pdfs/make_sample_pdf.py'
if (Test-Path $pdfScript) {
  Write-Host "`nGenerating sample PDF for Chapter 5 multi-modal demo..."
  try {
    python $pdfScript | Out-Null
  } catch {}
  $pdfOut = Join-Path $ch5Dir 'chapter5/data/pdfs/sample_report_with_figure.pdf'
  if (Test-Path $pdfOut) {
    Write-Host "Sample PDF created: chapter5/data/pdfs/sample_report_with_figure.pdf"
  } else {
    Write-Host "Sample PDF generation skipped (reportlab unavailable or other issue)."
  }
}

Write-Host "`nActivate with: `" $activate
Write-Host "Run validate: python" (Join-Path $scriptDir 'validate_setup.py')
