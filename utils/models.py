"""
Self-updating OpenAI model discovery.

Every notebook in this book calls get_best_available_model() instead of
hardcoding a model name. The function:

  1. Queries the OpenAI API for available models
    2. Ranks a curated set of budget models, never falling back to premium models
  3. Saves the result to data/last_known_models.json
    4. On discovery failure, revalidates budget candidates from the cache
    5. Stops if no eligible model can be verified

Usage (in any notebook):
    from utils.models import get_best_available_model
    MODEL = get_best_available_model(client)
"""

import json
import re
from pathlib import Path
from datetime import date, datetime


MODEL_PRIORITY = [
    "gpt-6-luna", "gpt-5.4-nano", "gpt-5-nano",
    "gpt-5-mini", "gpt-5.4-mini", "gpt-5.6-luna",
]


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


def _list_model_ids(client):
    """Model ids from ``client.models.list()``, minus models past their shutdown date.

    OpenAI keeps a retired model in the list after it stops answering (for
    example gpt-3.5-turbo-1106, shut down 2026-09-28, still listed in October
    2026 and returning 404 "has been deprecated"). Each entry carries an
    optional ``shutdown_date`` (YYYY-MM-DD, or null when no shutdown is
    announced), so anything dated today or earlier is dropped here. Models with
    a future shutdown date are kept; they still work until that day.
    """
    today = date.today().isoformat()
    ids = set()
    for m in client.models.list():
        shutdown = getattr(m, "shutdown_date", None) or (getattr(m, "model_extra", None) or {}).get("shutdown_date")
        if shutdown and str(shutdown)[:10] <= today:
            continue
        ids.add(m.id)
    return ids


def _rank_models(available_ids, preferred=None):
    """Rank approved budget aliases and dated snapshots; omit unpriced models."""
    families = list(dict.fromkeys(
        [model for model in (preferred or []) if model in MODEL_PRIORITY]
        + MODEL_PRIORITY
    ))
    ranked = []
    for family in families:
        if family in available_ids:
            ranked.append(family)
        ranked.extend(sorted(
            (model for model in available_ids
             if re.fullmatch(re.escape(family) + r"-\d{4}-\d{2}-\d{2}", model)),
            reverse=True,
        ))
    return ranked


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


def _model_responds(client, model_id):
    """Probe a model with a tiny call. True if it answers without raising.

    A model can appear in ``client.models.list()`` yet reject a real request:
    it may have just been deprecated, not be enabled for this account, or be
    region-gated. Listing is not the same as access. We only trust a model we
    can actually invoke. An empty-but-valid reply (some reasoning models spend
    the whole tiny budget thinking) still counts as responding -- only an
    exception means "not usable".
    """
    for params in ({"max_tokens": 1}, {"max_completion_tokens": 1}):
        try:
            client.chat.completions.create(
                model=model_id,
                messages=[{"role": "user", "content": "ping"}],
                **params,
            )
            return True
        except Exception:
            continue
    return False


def get_best_available_model(client, verify=True, max_probes=6, preferred=None):
    """
    Discover an approved low-cost model without escalating to premium models.

    Args:
        client:     An initialized openai.OpenAI client instance.
        verify:     When True (default), probe candidates in rank order and
                    return the first that actually answers, so a model that is
                    listed but not invocable (e.g. just deprecated) is skipped
                    instead of being handed back and crashing the notebook on
                    the next call. Set False for the old list-only behaviour.
        max_probes: Maximum number of budget candidates to test before stopping.
        preferred: Optional ordering of approved budget model families.

    Returns:
        str: A discovered budget model ID.

    Raises:
        RuntimeError: No eligible model is available or passes verification.
    """
    try:
        available = _list_model_ids(client)
        origin = "live"
    except Exception as e:
        print(f"  Live discovery failed: {e}")
        cached_ranked, cached_selected, cached_date = _load_cache()
        available = set(cached_ranked)
        if cached_selected:
            available.add(cached_selected)
        origin = f"cached from {cached_date}"

    ranked = _rank_models(available, preferred=preferred)
    candidates = ranked[:max(0, max_probes)] if verify else ranked[:1]
    for candidate in candidates:
        if not verify or _model_responds(client, candidate):
            _save_cache(ranked, candidate)
            print(f"Selected budget model: {candidate}  ({origin})")
            return candidate
    raise RuntimeError(
        "No usable budget chat model found. Check API credit and model access. "
        "Premium and unpriced models are intentionally excluded; "
        "no unverified bootstrap model will be used."
    )


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
    1. List models live, keep only approved budget chat ids
      2. Prefer ids carrying a size marker (nano < mini < small < ... < turbo)
        3. Never broaden to premium or unpriced families
        4. On API failure, revalidate an eligible cached pick
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
        available = _rank_models(_list_model_ids(client))
        candidates = [m for m in available if m not in exclude]

        marked = [m for m in candidates if _smallness_rank(m) < len(SIZE_MARKERS)]
        if marked:
            # Smallest marker first; alphabetical tie-break keeps it deterministic
            # and tends to favor older, cheaper families.
            marked.sort(key=lambda m: (_smallness_rank(m), m))
            for selected in marked[:6]:
                if _model_responds(client, selected):
                    _save_cache_key("smallest", selected)
                    print(f"Smallest model: {selected}  (live, {len(marked)} small candidates)")
                    return selected

        if not marked:
            for selected in candidates[:6]:
                if _model_responds(client, selected):
                    _save_cache_key("smallest", selected)
                    print(f"Smallest model: {selected}  (live, budget family)")
                    return selected
        print("  No small-model candidates found in account")
    except Exception as e:
        print(f"  Live discovery failed: {e}")

    cached = _load_cache_key("smallest")
    if cached and cached not in exclude and _rank_models({cached}) and _model_responds(client, cached):
        print(f"Smallest model: {cached}  (cached)")
        return cached

    print("  Could not resolve a small model")
    return None


def get_small_models(client, exclude=None, verify=True):
    """
    Return a ranked list of small/cheap chat models available on the account.

    Same name-marker heuristics as get_smallest_available_model (smallest first),
    but returns the whole list instead of a single pick, so callers can build a
    multi-model comparison table. Uses substrings, never hardcoded versions, so it
    keeps working as specific dated models retire.

    Args:
        client:  An initialized openai.OpenAI client instance.
        exclude: Optional iterable of model ids to skip.
        verify:  When True (default), keep only models that answer a one-token
                 probe, the same check get_best_available_model uses, so a
                 listed-but-retired model never reaches the caller's loop.

    Returns:
        list[str]: Small model ids, smallest/cheapest first. Empty on failure.
    """
    exclude = set(exclude or [])
    try:
        available = _rank_models(_list_model_ids(client))
        candidates = [m for m in available if m not in exclude]
        marked = [m for m in candidates if _smallness_rank(m) < len(SIZE_MARKERS)]
        marked.sort(key=lambda m: (_smallness_rank(m), m))
        if verify:
            marked = [m for m in marked if _model_responds(client, m)]
        return marked
    except Exception as e:
        print(f"  Live discovery failed: {e}")
        return []
