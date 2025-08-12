#!/usr/bin/env python3
"""
Chapter 5 setup validator.
- Detects local vs Google Colab
- Verifies package imports
- Checks .env presence
- Prints suggested base directories (including Google Drive when in Colab)
"""
from __future__ import annotations
import os
import sys
import pkgutil
from pathlib import Path


def in_colab() -> bool:
    try:
        import google.colab  # type: ignore
        return True
    except Exception:
        return False


def print_env_report() -> None:
    print("Chapter 5 environment check")
    print("Python:", sys.version.split()[0])
    mods = [
        ("chromadb", "chromadb"),
        ("tiktoken", "tiktoken"),
        ("requests", "requests"),
        ("beautifulsoup4", "bs4"),
        ("pypdf", "pypdf"),
        ("wikipedia-api", "wikipediaapi"),
        ("biopython", "Bio"),
    ]
    for label, mod in mods:
        found = pkgutil.find_loader(mod) is not None
        print(f"- {label:<16}: {'OK' if found else 'MISSING'}")

    # .env presence
    env_path = Path(__file__).with_name(".env")
    has_env = env_path.exists()
    print(f"- .env present     : {'YES' if has_env else 'NO'}")
    if not has_env:
        ex = Path(__file__).with_name(".env.example")
        if ex.exists():
            print(f"  Hint: copy {ex.name} to .env and fill keys as needed")

    # Location suggestions
    if in_colab():
        print("\nDetected Google Colab environment.")
        print("To persist artifacts, mount Google Drive and use:")
        print("  /content/drive/MyDrive/data-strategy-book/27July2025/chapter5/")
        print("Suggested directories:")
        print("- DB path      : /content/drive/MyDrive/.../ch5_db")
        print("- Traces path  : /content/drive/MyDrive/.../chapter5/traces/advanced_rag.jsonl")
        print("- Data path    : /content/drive/MyDrive/.../chapter5/data/")
    else:
        base = Path(__file__).resolve().parents[1]
        print("\nLocal environment detected.")
        print("Repository base:", base)
        print("Suggested directories:")
        print(f"- DB path      : {base/'ch5_db'}")
        print(f"- Traces path  : {base/'chapter5'/'traces'/'advanced_rag.jsonl'}")
        print(f"- Data path    : {base/'chapter5'/'data'}")


if __name__ == "__main__":
    print_env_report()
