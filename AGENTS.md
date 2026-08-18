# AGENTS

> Tool-neutral instructions for AI coding agents (Claude Code, Windsurf, Cursor, and others) working
> in this repository. This is the code repository for the book *Data Strategy for LLMs*.

## Notebook conventions

### Never hardcode an LLM model name (MANDATORY)

A published book that pins a model (for example `model="gpt-4o-mini"`) ages the moment that model is
renamed, deprecated, or superseded. Every notebook must select the model at runtime:

1. Discover the models the key can see (`client.models.list()`).
2. Prefer a curated priority list, then fall back to the newest `gpt-*` not in the list.
3. Test the candidate with a one-token call before trusting it.
4. Self-heal: skip any model the key cannot actually use and try the next.
5. Degrade gracefully: with no `OPENAI_API_KEY`, skip live-model steps and still run the measurable parts.

Use the shared helper, do not reinvent it:

```python
from utils.notebook_setup import select_and_test_model  # discover + test + self-heal
# or, for install + key + model in one call:
from utils.notebook_setup import setup
client, MODEL = setup(["openai"], pick_model=True)
```

Reference implementation: `utils/notebook_setup.py` (`select_and_test_model`, `best_available_model`).
Live example: `chapter_11/Jupyter_Notebooks/Chapter_11_Financial_Agent_Notebook.ipynb` (Setup cell).

## Why this file exists

Rules that must hold across tools belong in a tool-neutral file, not in per-tool memory (which does
not travel between Claude Code and Windsurf). Behavior that must hold across environments belongs in
code (`utils/`), which runs the same everywhere. Tool-specific rule folders are synced mirrors of
these instructions, not the source of truth.
