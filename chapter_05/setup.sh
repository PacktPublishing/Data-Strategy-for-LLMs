#!/usr/bin/env bash
set -euo pipefail

# Chapter 5 setup script (macOS/Linux)
# Creates a local venv, installs requirements, and prints versions.

VENV_DIR=".venv-ch5"
REQ_FILE="requirements.txt"

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"
CH5_DIR="$(dirname "$SCRIPT_DIR")"

python3 -m venv "$CH5_DIR/$VENV_DIR"
source "$CH5_DIR/$VENV_DIR/bin/activate"

python -m pip install --upgrade pip >/dev/null
python -m pip install -r "$SCRIPT_DIR/$REQ_FILE" -q

python - << 'PY'
import sys, os, pkgutil
print("Chapter 5 environment setup complete.\n")
print("Python:", sys.version.split()[0])
mods = ["chromadb","tiktoken","requests","beautifulsoup4","pypdf","wikipediaapi","Bio","reportlab"]
for m in mods:
    found = pkgutil.find_loader(m) is not None
    print(f"- {m}: {'OK' if found else 'MISSING'}")
PY

# Generate sample PDF for the figure/caption demo (idempotent)
PDF_SCRIPT="$CH5_DIR/chapter5/data/pdfs/make_sample_pdf.py"
if [ -f "$PDF_SCRIPT" ]; then
  echo "\nGenerating sample PDF for Chapter 5 multi-modal demo..."
  python "$PDF_SCRIPT" >/dev/null 2>&1 || true
  if [ -f "$CH5_DIR/chapter5/data/pdfs/sample_report_with_figure.pdf" ]; then
    echo "Sample PDF created: chapter5/data/pdfs/sample_report_with_figure.pdf"
  else
    echo "Sample PDF generation skipped (reportlab unavailable or other issue)."
  fi
fi

echo "\nActivate with: source $CH5_DIR/$VENV_DIR/bin/activate"
echo "Run validate: python $SCRIPT_DIR/validate_setup.py"
