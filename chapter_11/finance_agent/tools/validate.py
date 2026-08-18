#!/usr/bin/env python3
"""Validate the knowledge index. Standard library only. Non-zero exit on failure."""
import os, re, sys
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT_DIRS = ["rules", "entities", "facts", "decisions", "archive"]
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+\.md)\)")
FM = re.compile(r"\A---\n(.*?)\n---\n", re.S)
CEILING = 2000          # tokens, approximated as words*1.3
REQUIRED = ("name", "description", "last_verified")

def fm(path):
    m = FM.match(open(path, encoding="utf-8").read())
    if not m: return {}
    return {k.strip(): v.strip() for k, v in
            (l.split(":", 1) for l in m.group(1).splitlines() if ":" in l)}

fails = []
idx_path = os.path.join(ROOT, "INDEX.md")
idx = open(idx_path, encoding="utf-8").read()
pointers = [t for _, t in LINK.findall(idx)]

# 1 every pointer resolves
for p in pointers:
    if not os.path.isfile(os.path.join(ROOT, p)):
        fails.append(f"[1] broken pointer: {p}")

# 2 every content file is indexed exactly once
on_disk = [os.path.join(d, f) for d in CONTENT_DIRS
           if os.path.isdir(os.path.join(ROOT, d))
           for f in sorted(os.listdir(os.path.join(ROOT, d))) if f.endswith(".md")]
for f in on_disk:
    n = pointers.count(f)
    if n == 0:   fails.append(f"[2] not indexed: {f}")
    elif n > 1:  fails.append(f"[2] indexed {n}x: {f}")

# 3 size ceiling  4 basename collisions  5 required frontmatter
seen = {}
for f in on_disk:
    full = os.path.join(ROOT, f)
    words = len(open(full, encoding="utf-8").read().split())
    if words * 1.3 > CEILING:
        fails.append(f"[3] over ceiling (~{int(words*1.3)} tok): {f}")
    seen.setdefault(os.path.basename(f), []).append(f)
    meta = fm(full)
    for k in REQUIRED:
        if k not in meta: fails.append(f"[5] missing '{k}': {f}")
for base, group in seen.items():
    if len(group) > 1: fails.append(f"[4] basename collision {base}: {group}")

# 6 no unearned automation claim
if re.search(r"automatically updated", idx, re.I) and "GENERATED" not in idx:
    fails.append("[6] index claims automation it does not perform")

print(f"checked {len(on_disk)} files, {len(pointers)} pointers")
# advisory: staleness. Defaults to the real clock; an optional override
# (FINANCE_AGENT_TODAY=YYYY-MM-DD) lets the book pin a reproducible "as of" date.
today = date.fromisoformat(os.environ["FINANCE_AGENT_TODAY"]) if os.environ.get("FINANCE_AGENT_TODAY") else date.today()
for f in on_disk:
    lv = fm(os.path.join(ROOT, f)).get("last_verified", "")
    try:
        y, m, d = (int(x) for x in lv.split("-"))
        age = (today - date(y, m, d)).days
        if age > 90 and not f.startswith("archive/"):
            print(f"  ADVISORY stale {age}d: {f}")
    except Exception:
        pass
if fails:
    print("\nFAIL:"); [print("  " + x) for x in fails]; sys.exit(1)
print("PASS - all checks green")
