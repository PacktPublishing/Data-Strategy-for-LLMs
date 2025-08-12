# Chapter 1 — Environment Setup and Notebooks

This chapter ships with self-contained setup scripts and a dedicated Python virtual environment so you can run the notebooks reproducibly.

## What gets created
- Virtual environment: `chapter_01/venv_chapter_01`
- Requirements are installed from: `chapter_01/setup/requirements.txt`
- Jupyter kernel is registered as: `Python (Chapter 1)` (internal name: `chapter-01`)

## Run the setup

macOS/Linux:
```bash
bash chapter_01/setup/chapter_01_setup.sh
```

Windows (PowerShell):
```powershell
powershell -ExecutionPolicy Bypass -File chapter_01/setup/chapter_01_setup.ps1
```

## Smart auto-activation (default)
- If you run the script from an interactive terminal (not CI/notebook), it will automatically open a new shell with the environment activated.
- To force activation explicitly:
  - macOS/Linux: `bash chapter_01/setup/chapter_01_setup.sh --activate-shell`
  - Windows: `powershell -ExecutionPolicy Bypass -File chapter_01/setup/chapter_01_setup.ps1 -ActivateShell`
- To skip activation:
  - macOS/Linux: `bash chapter_01/setup/chapter_01_setup.sh --no-activate`
  - Windows: run without `-ActivateShell` (default).

Manual activation (if needed):
- macOS/Linux: `source chapter_01/venv_chapter_01/bin/activate`
- Windows (PowerShell): `.\\chapter_01\\venv_chapter_01\\Scripts\\Activate.ps1`

## Using the environment in notebooks
The setup scripts register the environment as a Jupyter kernel named `Python (Chapter 1)`.

- In VS Code: click “Select Kernel” (top-right) → choose `Python (Chapter 1)`.
- In JupyterLab: Kernel → Change Kernel → `Python (Chapter 1)`.

### Troubleshooting: Kernel not showing up
- In VS Code, the Jupyter extension caches kernels. Use Command Palette → **Developer: Reload Window**, then reopen the notebook and select `Python (Chapter 1)`.
- Ensure the kernelspec exists at `~/Library/Jupyter/kernels/chapter-01/kernel.json` (macOS). It should point to `chapter_01/venv_chapter_01/bin/python`.
- If launching Jupyter from terminal, install Jupyter in the venv and launch via:
  - `chapter_01/venv_chapter_01/bin/python -m pip install jupyterlab`
  - `chapter_01/venv_chapter_01/bin/jupyter lab`

Quick verification cell inside a notebook:
```python
import sys, pkgutil
print(sys.executable)
print("in venv_chapter_01:", "venv_chapter_01" in sys.executable)
for m in ["openai", "chromadb"]:
    print(m, "OK" if pkgutil.find_loader(m) else "MISSING")
```

## Notebooks
- `chapter_01/Jupyter_Notebooks/Chapter_1_Setup_Advanced.ipynb`
- `chapter_01/Jupyter_Notebooks/Chapter_1_Step_By_Step.ipynb`

We recommend selecting the `Python (Chapter 1)` kernel before running cells for a clean, reproducible environment.
