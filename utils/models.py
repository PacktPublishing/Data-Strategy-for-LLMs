"""
Self-updating OpenAI model discovery.

Every notebook in this book calls get_best_available_model() instead of
hardcoding a model name. The function:

  1. Queries the OpenAI API for available models
  2. Ranks them by newest family first
  3. Saves the result to data/last_known_models.json
  4. On API failure, falls back to the cache from the last successful run
  5. After one successful call, no hardcoded name is ever used again

Usage (in any notebook):
    from utils.models import get_best_available_model
    MODEL = get_best_available_model(client)
"""

import json
from pathlib import Path
from datetime import datetime


# Model families ordered newest first. Add new families at the top.
MODEL_PRIORITY = [
    "gpt-5.5", "gpt-5.5-mini",              # 5.5 family (May 2026)
    "gpt-5.4-mini", "gpt-5.4",              # 5.4 family (Mar 2026)
    "gpt-5.3",                                # 5.3 family (Mar 2026)
    "o4-mini", "o4",                          # reasoning family (2025)
    "gpt-4.1-mini", "gpt-4.1",              # 4.1 family (2025)
    "gpt-4o-mini", "gpt-4o",                # 4o family (2024)
]

# Patterns for discovering models not yet in the priority list
DISCOVERY_PATTERNS = ["gpt-5", "gpt-6", "gpt-7", "o5", "o4", "gpt-4.1", "gpt-4o"]

# Bootstrap seed -- only used on the very first run if the API also fails.
_BOOTSTRAP_MODEL = "gpt-5.5"


def patch_client_compat(client):
    """Make ``client.chat.completions.create`` tolerant of newer-model parameter rules.

    Newer OpenAI models (e.g. the GPT-5 family) reject parameters that older
    models accept, which otherwise breaks example code that hardcodes them:

      - ``temperature``: only the default (1) is allowed -> the shim drops it
      - ``max_tokens``:  not supported -> the shim switches to
        ``max_completion_tokens`` (with headroom, since reasoning models spend
        tokens internally before producing output)

    This lets the book keep ``temperature=0.0`` in its evaluation code (the
    pedagogically-correct choice for deterministic scoring): on a model that
    accepts it, behaviour is unchanged; on a model that rejects it, the call is
    retried once without the offending parameter instead of raising a 400.

    Idempotent. Returns the same client for convenience.
    """
    completions = client.chat.completions
    if getattr(completions, "_compat_patched", False):
        return client
    _original_create = completions.create

    def _safe_create(*args, **kwargs):
        try:
            return _original_create(*args, **kwargs)
        except Exception as e:
            msg = str(e)
            retry = dict(kwargs)
            changed = False
            if "temperature" in msg and "temperature" in retry:
                retry.pop("temperature", None)
                changed = True
            if "max_tokens" in msg and "max_tokens" in retry:
                mt = retry.pop("max_tokens", None)
                retry["max_completion_tokens"] = max(int(mt or 0), 256)
                changed = True
            if changed:
                return _original_create(*args, **retry)
            raise

    completions.create = _safe_create
    completions._compat_patched = True
    return client


def _find_repo_root():
    """Walk up from cwd until we find the utils/ directory."""
    for p in [Path.cwd()] + list(Path.cwd().parents):
        if (p / "utils").is_dir():
            return p
    return Path.cwd()


def _cache_path():
    return _find_repo_root() / "data" / "last_known_models.json"


def _rank_models(available_ids):
    """From a set of model IDs, return a ranked list (best first)."""
    ranked = [m for m in MODEL_PRIORITY if m in available_ids]
    discovered = sorted(
        [m for m in available_ids
         if any(p in m for p in DISCOVERY_PATTERNS) and m not in ranked],
        reverse=True,
    )
    return ranked + discovered


def _save_cache(ranked, selected):
    cache = _cache_path()
    try:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps({
            "updated": datetime.now().isoformat(),
            "selected": selected,
            "ranked": ranked,
        }, indent=2))
    except Exception:
        pass


def _load_cache():
    cache = _cache_path()
    try:
        if cache.exists():
            data = json.loads(cache.read_text())
            return data.get("ranked", []), data.get("selected"), data.get("updated")
    except Exception:
        pass
    return [], None, None


def get_best_available_model(client):
    """
    Find the best available OpenAI model. Fully self-updating.

    Args:
        client: An initialized openai.OpenAI client instance.

    Returns:
        str: The model ID to use (e.g. "gpt-5.5", "o4-mini").
    """
    # Step 1: Live discovery
    try:
        available = {m.id for m in client.models.list()}
        ranked = _rank_models(available)
        if ranked:
            selected = ranked[0]
            _save_cache(ranked, selected)
            print(f"Selected model: {selected}  (live, {len(ranked)} candidates)")
            return selected
        print("  No known model families found in account")
    except Exception as e:
        print(f"  Live discovery failed: {e}")

    # Step 2: Cache from last successful connection
    cached_ranked, cached_selected, cached_date = _load_cache()
    if cached_selected:
        print(f"Selected model: {cached_selected}  (cached from {cached_date})")
        return cached_selected

    # Step 3: Bootstrap seed (first run + API failure). Written to cache immediately.
    print(f"Selected model: {_BOOTSTRAP_MODEL}  (bootstrap seed, first run)")
    _save_cache([_BOOTSTRAP_MODEL], _BOOTSTRAP_MODEL)
    return _BOOTSTRAP_MODEL
