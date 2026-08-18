"""Shared notebook setup for the *Data Strategy for LLMs* book.

ONE source of truth for per-notebook environment setup, so the chapters
cannot drift apart again (the drift is what caused Chapter 9 to fail with
`ModuleNotFoundError: pandas` while other chapters worked).

What it guarantees for every chapter / every reader:
  1. Packages install into the RUNNING kernel (via ``sys.executable -m pip``),
     not whatever ``pip`` the shell happens to resolve. This is the fix for
     the classic "I ran ``!pip install`` but ``import`` still fails" trap.
  2. The OpenAI API key loads the same way book-wide: ``utils.config`` reads
     the repo-root ``.env``; on Colab (or any env with no ``.env``) it prompts.
  3. Helpful, consistent messages instead of a silent placeholder key.

Usage in a chapter's FIRST code cell
------------------------------------
OpenAI chapter (most chapters)::

    from utils.notebook_setup import setup
    client, BASE_MODEL = setup(["openai", "pandas", "numpy"])

Data-only chapter (no OpenAI, e.g. Chapter 2)::

    from utils.notebook_setup import setup
    setup(["requests", "beautifulsoup4", "pandas"], need_openai=False)

Pick the best available model automatically (e.g. evaluation chapters)::

    client, BASE_MODEL = setup(["openai", "pandas"], pick_model=True)

Note: the importing cell still needs ``utils`` on ``sys.path``. The helper
adds the repo root itself, but the very first ``import`` works as long as the
notebook is run from inside the repo (the normal case) or on Colab after the
repo is cloned. If ``from utils.notebook_setup import setup`` itself fails,
run this one-liner first::

    import sys, pathlib; sys.path.insert(0, str(next(p for p in [pathlib.Path.cwd(), *pathlib.Path.cwd().parents] if (p/'utils').is_dir())))
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def _install_one(pkg: str) -> bool:
    """Install a single package into the running kernel's Python, with fallbacks."""
    for cmd in (
        [sys.executable, "-m", "pip", "install", pkg, "--quiet"],
        [sys.executable, "-m", "pip", "install", pkg, "--user", "--quiet"],
        [sys.executable, "-m", "pip", "install", pkg, "--break-system-packages", "--quiet"],
    ):
        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            return True
        except subprocess.CalledProcessError:
            continue
    return False


def quiet_warnings() -> None:
    """Silence noisy library warnings so they never reach a reader's output.

    Warnings (and some library banners) can print local file paths, deprecation
    notices, and tokenizer chatter that clutter the notebook and occasionally leak
    a local folder name. We turn them off book-wide.
    """
    import warnings
    warnings.filterwarnings("ignore")
    os.environ.setdefault("PYTHONWARNINGS", "ignore")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")  # quiets HF tokenizers banner
    os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")


def install_packages(packages) -> bool:
    """Install each package into the running kernel. Returns True if all succeeded."""
    failed = [pkg for pkg in packages if not _install_one(pkg)]
    if failed:
        print(f"WARNING: could not install {failed}. Restart the kernel and re-run this cell.")
    return not failed


def get_repo_root() -> Path:
    """Find the repository root by walking up for the utils/ package."""
    for p in [Path.cwd()] + list(Path.cwd().parents):
        if (p / "utils" / "config.py").exists():
            return p
    return Path(__file__).resolve().parent.parent


def load_openai_key() -> str:
    """Load the OpenAI key the book-wide way (utils.config), prompting as a fallback."""
    root = get_repo_root()
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))
    try:
        from utils.config import get_openai_api_key
        return get_openai_api_key()
    except Exception:
        key = os.getenv("OPENAI_API_KEY")
        if not key:
            import getpass
            key = getpass.getpass("Enter your OpenAI API key: ")
        return key


def best_available_model(
    client,
    preferred=("gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"),
) -> str:
    """Pick the best currently-available model instead of hardcoding a stale one."""
    try:
        available = {m.id for m in client.models.list()}
        for model in preferred:
            if model in available:
                print(f"Selected model: {model}")
                return model
        gpt = sorted((m for m in available if m.startswith("gpt-")), reverse=True)
        if gpt:
            print(f"Selected model: {gpt[0]}")
            return gpt[0]
    except Exception as e:
        print(f"Could not list models: {e}")
    print("Fallback model: gpt-3.5-turbo")
    return "gpt-3.5-turbo"


def select_and_test_model(
    client,
    preferred=("gpt-4o", "gpt-4.1", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"),
) -> str:
    """Discover the latest valid model at runtime, TEST it, and self-heal.

    Like ``best_available_model`` but proves the choice with a one-token call and
    falls back to the next candidate if the key cannot actually use it. Never
    hardcode a model name (see the notebook-model self-heal rule).
    """
    available = {m.id for m in client.models.list()}
    ordered = [m for m in preferred if m in available]
    ordered += sorted(
        (m for m in available if m.startswith("gpt-") and m not in ordered), reverse=True
    )
    for name in ordered:
        try:
            client.chat.completions.create(
                model=name, messages=[{"role": "user", "content": "ping"}], max_tokens=1
            )
            print(f"Selected and tested model: {name}")
            return name
        except Exception as err:
            print(f"Skipping {name} ({type(err).__name__})")
    raise RuntimeError("No usable chat model found for this API key.")


def setup(packages=("openai",), need_openai: bool = True, pick_model: bool = False):
    """Install packages into the kernel, load the API key, and return ``(client, model)``.

    Returns ``(None, None)`` when ``need_openai`` is False (data-only chapters).
    When ``pick_model`` is True the model is discovered from the API; otherwise it
    is taken from ``BASE_MODEL`` (default ``gpt-4o-mini``).
    """
    quiet_warnings()
    install_packages(list(packages))
    if not need_openai:
        print("Setup complete.")
        return None, None

    api_key = load_openai_key()
    os.environ["OPENAI_API_KEY"] = api_key
    from openai import OpenAI

    client = OpenAI(api_key=api_key)
    # Tolerate newer-model parameter rules (temperature/max_tokens) across model generations.
    try:
        from utils.models import patch_client_compat
        patch_client_compat(client)
    except Exception:
        pass
    model = best_available_model(client) if pick_model else os.getenv("BASE_MODEL", "gpt-4o-mini")
    print("Setup complete.")
    return client, model
