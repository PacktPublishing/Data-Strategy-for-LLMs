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
      - empty output: if a reasoning model burns a small token budget on
        internal reasoning and returns blank content, the shim grows
        ``max_completion_tokens`` and retries until it gets real output

    This lets the book keep ``temperature=0.0`` in its evaluation code (the
    pedagogically-correct choice for deterministic scoring): on a model that
    accepts it, behaviour is unchanged; on a model that rejects it, the call is
    retried without the offending parameters (in a short loop, since the API
    reports them one at a time) instead of raising a 400.

    Idempotent. Returns the same client for convenience.
    """
    completions = client.chat.completions
    if getattr(completions, "_compat_patched", False):
        return client
    _original_create = completions.create

    def _looks_truncated_empty(resp):
        """True if the model returned no text because it hit the token cap.

        Reasoning models spend tokens internally before writing output; if the
        budget is too small they finish with ``finish_reason == "length"`` and
        empty content, which is recoverable by growing the budget. An empty
        answer that finished normally (``"stop"``) is a real answer, not a
        truncation, so we leave it alone. Anything we cannot introspect (e.g. a
        streaming response) is treated as fine.
        """
        try:
            choice = resp.choices[0]
            content = getattr(choice.message, "content", None)
            finish = getattr(choice, "finish_reason", None)
            empty = content is None or (isinstance(content, str) and not content.strip())
            return bool(empty) and finish == "length"
        except Exception:
            return False

    def _create_sanitized(args, attempt):
        # Newer models can reject several parameters at once, but the API reports
        # them one at a time. Retry in a bounded loop, sanitizing whichever
        # parameter the latest error names, so calls that pass both an
        # unsupported ``temperature`` and ``max_tokens`` still recover. Mutates
        # ``attempt`` in place so later retries skip the already-fixed params.
        for _ in range(4):
            try:
                return _original_create(*args, **attempt)
            except Exception as e:
                msg = str(e)
                changed = False
                if "temperature" in msg and "temperature" in attempt:
                    attempt.pop("temperature", None)
                    changed = True
                if "max_tokens" in msg and "max_tokens" in attempt:
                    mt = attempt.pop("max_tokens", None)
                    attempt["max_completion_tokens"] = max(int(mt or 0), 256)
                    changed = True
                if not changed:
                    raise
        return _original_create(*args, **attempt)

    def _safe_create(*args, **kwargs):
        # Two layers of self-healing:
        #  1. Params: newer models reject temperature/max_tokens one at a time,
        #     so _create_sanitized retries, dropping each named param.
        #  2. Empty output: reasoning models can burn the whole token budget on
        #     internal reasoning and return blank content (finish_reason ==
        #     "length"). When that happens we grow max_completion_tokens and try
        #     again, so a too-small cap (e.g. max_tokens=5) heals itself instead
        #     of silently yielding blank answers.
        attempt = dict(kwargs)
        resp = _create_sanitized(args, attempt)
        for _ in range(4):
            if not _looks_truncated_empty(resp):
                return resp
            cap = attempt.get("max_completion_tokens")
            if cap is None:
                return resp
            new_cap = min(int(cap) * 4, 8192)
            if new_cap <= int(cap):
                return resp
            attempt["max_completion_tokens"] = new_cap
            resp = _create_sanitized(args, attempt)
        return resp

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


# ---------------------------------------------------------------------------
# Smallest / cheapest model discovery
#
# There is no OpenAI API that labels a model by size or price, so this ranks by
# NAME MARKERS instead of exact versions. Substrings are used on purpose: a dated
# version dying (e.g. "gpt-3.5-turbo-0125") does not break discovery, because the
# marker "turbo" still matches its successor. Used to demonstrate quality drift
# from a weak generator -- the exact pick does not matter as long as it is weaker
# than the model doing the evaluation.
# ---------------------------------------------------------------------------

# Size markers ordered smallest/cheapest first. Add new ones (e.g. a future
# "pico") at the front; never list exact versions here.
SIZE_MARKERS = ["nano", "mini", "small", "lite", "flash", "haiku", "turbo"]

# Model ids that are not chat/completion models -- never pick these as a generator.
_NON_CHAT = [
    "embedding", "whisper", "tts", "audio", "image", "dall-e", "dalle",
    "moderation", "realtime", "transcribe", "sora", "search",
]


def _is_chat_model(model_id):
    m = model_id.lower()
    return not any(bad in m for bad in _NON_CHAT)


def _smallness_rank(model_id):
    """Lower is smaller/cheaper, based on name markers (not exact versions)."""
    m = model_id.lower()
    for i, marker in enumerate(SIZE_MARKERS):
        if marker in m:
            return i
    return len(SIZE_MARKERS)  # no size marker -> treat as a large model


def _save_cache_key(key, value):
    """Read-modify-write a named value into the shared cache without clobbering
    the keys used by get_best_available_model()."""
    cache = _cache_path()
    try:
        data = {}
        if cache.exists():
            data = json.loads(cache.read_text())
        data.setdefault("keys", {})[key] = {
            "value": value,
            "updated": datetime.now().isoformat(),
        }
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(data, indent=2))
    except Exception:
        pass


def _load_cache_key(key):
    cache = _cache_path()
    try:
        if cache.exists():
            data = json.loads(cache.read_text())
            return data.get("keys", {}).get(key, {}).get("value")
    except Exception:
        pass
    return None


def get_smallest_available_model(client, exclude=None):
    """
    Find the smallest/cheapest available chat model. Self-updating.

    Strategy (mirrors get_best_available_model, but aims low instead of high):
      1. List models live, keep only chat-capable ids
      2. Prefer ids carrying a size marker (nano < mini < small < ... < turbo)
      3. If none are marked, fall back to the OLDEST known family available
         (the tail of the newest-first ranking), which is the cheapest tier
      4. On API failure, use the cached last-good pick
      5. Return None only if discovery fails and there is no cache

    Args:
        client:  An initialized openai.OpenAI client instance.
        exclude: Optional iterable of model ids to skip (e.g. the judge model,
                 so the generator is not the same model doing the scoring).

    Returns:
        str | None: A model id, or None if nothing could be resolved.
    """
    exclude = set(exclude or [])

    try:
        available = [m.id for m in client.models.list() if _is_chat_model(m.id)]
        candidates = [m for m in available if m not in exclude]

        marked = [m for m in candidates if _smallness_rank(m) < len(SIZE_MARKERS)]
        if marked:
            # Smallest marker first; alphabetical tie-break keeps it deterministic
            # and tends to favor older, cheaper families.
            marked.sort(key=lambda m: (_smallness_rank(m), m))
            selected = marked[0]
            _save_cache_key("smallest", selected)
            print(f"Smallest model: {selected}  (live, {len(marked)} small candidates)")
            return selected

        # No size-marked model in the account -> oldest known family is cheapest.
        ranked = _rank_models(set(candidates))
        if ranked:
            selected = ranked[-1]
            _save_cache_key("smallest", selected)
            print(f"Smallest model: {selected}  (live, oldest known family)")
            return selected
        print("  No small-model candidates found in account")
    except Exception as e:
        print(f"  Live discovery failed: {e}")

    cached = _load_cache_key("smallest")
    if cached:
        print(f"Smallest model: {cached}  (cached)")
        return cached

    print("  Could not resolve a small model")
    return None


def get_small_models(client, exclude=None):
    """
    Return a ranked list of small/cheap chat models available on the account.

    Same name-marker heuristics as get_smallest_available_model (smallest first),
    but returns the whole list instead of a single pick, so callers can build a
    multi-model comparison table. Uses substrings, never hardcoded versions, so it
    keeps working as specific dated models retire.

    Args:
        client:  An initialized openai.OpenAI client instance.
        exclude: Optional iterable of model ids to skip.

    Returns:
        list[str]: Small model ids, smallest/cheapest first. Empty on failure.
    """
    exclude = set(exclude or [])
    try:
        available = [m.id for m in client.models.list() if _is_chat_model(m.id)]
        candidates = [m for m in available if m not in exclude]
        marked = [m for m in candidates if _smallness_rank(m) < len(SIZE_MARKERS)]
        marked.sort(key=lambda m: (_smallness_rank(m), m))
        return marked
    except Exception as e:
        print(f"  Live discovery failed: {e}")
        return []
