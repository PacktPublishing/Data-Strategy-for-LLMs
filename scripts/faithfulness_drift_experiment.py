"""
Experiment: can the GENERATOR itself produce unfaithful synthetic data?

Idea: bury the real policy inside a large handbook full of tempting distractors
(other companies with 25 days, unlimited PTO, indefinite rollover, 5 remote days
with no approval), then ask a model to answer using ONLY the real policy, at high
temperature. Judge the model's own output against the TRUE source with the strong
judge model. A low faithfulness score is a real generator drift, not a planted one.

Run from the repo root:
    python3 scripts/faithfulness_drift_experiment.py
"""
import sys
import json
from pathlib import Path

from openai import OpenAI

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from utils.config import get_openai_api_key
from utils.models import get_best_available_model, patch_client_compat

client = OpenAI(api_key=get_openai_api_key())
patch_client_compat(client)

STRONG = get_best_available_model(client)   # used as the judge
print(f"Strong / judge model: {STRONG}")

# --- True source of truth (same texts as Chapter 6 hr_policies) ---
SOURCES = {
    "POL-001 - Vacation Policy": "Employees get 15 days paid vacation/year. Request 2 weeks in advance. Up to 5 days carry over.",
    "POL-002 - Remote Work Policy": "Work remotely up to 3 days/week with approval. Available during core hours 10 AM-3 PM.",
}

# --- Distractors: other 'companies' with different, tempting numbers ---
DISTRACTORS = [
    ("Acme Corp - Time Off", "Acme employees receive 25 days of paid vacation per year, and unused days roll over indefinitely."),
    ("Globex - PTO", "Globex offers unlimited paid time off, subject to manager discretion. No carryover limits apply."),
    ("Initech - Leave", "Initech grants 20 vacation days plus 12 sick days. Vacation carries over up to 10 days per year."),
    ("Umbrella - Remote", "Umbrella staff may work remotely 5 days per week with no approval required."),
    ("Hooli - Flexible Work", "Hooli allows fully remote work indefinitely; core hours are not enforced."),
    ("Stark Industries - Vacation", "Stark provides 30 days annual leave with unlimited rollover for senior staff."),
    ("Wayne Enterprises - Remote", "Wayne employees choose their own schedule and may work remotely up to 4 days weekly, approval optional."),
    ("Wonka - Leave", "Wonka staff enjoy 28 vacation days and may bank all unused days without expiry."),
]


def build_handbook(real_label, real_text, bury_deep=True):
    """Assemble a long handbook with the real policy buried among distractors."""
    blocks = []
    half = len(DISTRACTORS) // 2
    for name, text in DISTRACTORS[:half]:
        blocks.append(f"### {name}\n{text}")
    blocks.append(f"### {real_label}\n{real_text}")   # the ONLY authoritative section
    for name, text in DISTRACTORS[half:]:
        blocks.append(f"### {name}\n{text}")
    if not bury_deep:
        blocks = [f"### {real_label}\n{real_text}"] + blocks
    return "\n\n".join(blocks)


def _build_prompt(style, real_label, handbook, question):
    if style == "bad":
        # A sloppy, ambiguous, misspelled prompt like a rushed practitioner writes.
        # No strong grounding instruction, and it even tells the model NOT to worry
        # about which company, which invites blending across the distractors.
        return f"""hi can u help me anser some HR questons for our new employe handbook.
we got lots of polcies pasted below from diffrent places. jus write a nice helpfull
anser about the questoin, make it sound complete and profesional. dont worry to much
about which exact company it is, jus give the genral anser that sounds right.

HANDBOOK:
{handbook}

questoin: {question}
"""
    # strict / default: strong grounding, single authoritative section
    return f"""You are an HR assistant. Using ONLY the "{real_label}" section of the
employee handbook below, answer the question. Ignore every other company's policy.

EMPLOYEE HANDBOOK
{handbook}

Question: {question}

Answer in one or two sentences."""


def generate_answer(model, real_label, question, temperature, style="strict"):
    """Ask `model` to answer the question from a big noisy handbook, using `style`."""
    handbook = build_handbook(real_label, SOURCES[real_label])
    prompt = _build_prompt(style, real_label, handbook, question)
    kwargs = {"model": model, "messages": [{"role": "user", "content": prompt}]}
    if temperature is not None:
        kwargs["temperature"] = temperature
    try:
        resp = client.chat.completions.create(**kwargs)
        return resp.choices[0].message.content.strip()
    except Exception as e:
        return f"__ERROR__: {e}"


def judge(question, answer, source):
    prompt = f"""You are an evaluation judge. Score this QA pair on three dimensions.
Each score is 1-5 where 5 is best.

Source policy: {source}
Question: {question}
Answer: {answer}

Score these three dimensions:
1. Faithfulness: Does the answer ONLY use information from the source? (5 = fully grounded, 1 = hallucinated)
2. Relevance: Does the answer address the question? (5 = directly answers, 1 = off topic)
3. Correctness: Does the answer agree with the facts stated in the source? (5 = fully correct, 1 = factually wrong)

Return ONLY valid JSON:
{{"faithfulness": N, "relevance": N, "correctness": N, "justification": "one sentence"}}"""
    kwargs = {"model": STRONG, "messages": [{"role": "user", "content": prompt}], "temperature": 0.0}
    resp = client.chat.completions.create(**kwargs)
    content = resp.choices[0].message.content.strip()
    if "```json" in content:
        content = content.split("```json")[1].split("```")[0].strip()
    elif "```" in content:
        content = content.split("```")[1].split("```")[0].strip()
    return json.loads(content)


def find_small_models():
    """Pick small-model candidates that actually exist on this account."""
    try:
        ids = sorted(m.id for m in client.models.list().data)
    except Exception as e:
        print(f"Could not list models: {e}")
        return []
    keys = ("mini", "nano", "small", "4o-mini", "o1-mini", "o3-mini", "o4-mini",
            "3.5-turbo", "haiku", "8b", "7b", "flash")
    cand = [m for m in ids if any(k in m.lower() for k in keys)]
    # drop obviously non-chat models
    cand = [m for m in cand if not any(x in m.lower() for x in ("embedding", "whisper", "tts", "audio", "image", "realtime", "moderation"))]
    print(f"\nAvailable small-model candidates ({len(cand)}): {cand}")
    return cand


QUESTIONS = [
    ("POL-001 - Vacation Policy", "How many days of paid vacation do employees receive per year, and how many days can carry over?"),
    ("POL-002 - Remote Work Policy", "How many days per week can employees work remotely, and is approval required?"),
]


def run_trial(model, temperature, style="strict"):
    print(f"\n{'='*70}\nGENERATOR: {model}   temperature={temperature}   prompt={style}\n{'='*70}")
    drifts = 0
    for label, q in QUESTIONS:
        ans = generate_answer(model, label, q, temperature, style)
        if ans.startswith("__ERROR__"):
            print(f"  [{label}] generation failed: {ans}")
            return None
        scores = judge(q, ans, SOURCES[label])
        flag = "  <-- DRIFT" if scores["faithfulness"] < 4 else ""
        print(f"\n  Q: {q}")
        print(f"  Source: {SOURCES[label]}")
        print(f"  Answer: {ans}")
        print(f"  Faith={scores['faithfulness']} Rel={scores['relevance']} Corr={scores['correctness']}{flag}")
        print(f"  Why: {scores['justification']}")
        if scores["faithfulness"] < 4:
            drifts += 1
    print(f"\n  --> {drifts}/{len(QUESTIONS)} answers drifted from the source")
    return drifts


def main():
    results = {}

    # Control: the strong model on the same noisy handbook
    results[(STRONG, "control")] = run_trial(STRONG, 0.0)

    # Small models at increasing temperature
    smalls = find_small_models()
    tried = 0
    for model in smalls:
        if tried >= 3:
            break
        ok = None
        for temp in (0.7, 1.2):
            d = run_trial(model, temp)
            if d is None:
                break
            ok = True
            results[(model, temp)] = d
        if ok:
            tried += 1

    # Bad prompt (typos + ambiguity) to simulate a sloppy, real-life prompt.
    print(f"\n\n{'*'*70}\nBAD-PROMPT TRIALS (spelling mistakes + ambiguity)\n{'*'*70}")
    bad_targets = [STRONG]
    if smalls:
        bad_targets.append(smalls[0])
    for model in bad_targets:
        results[(model, "bad-prompt")] = run_trial(model, 0.7, style="bad")

    print(f"\n\n{'#'*70}\nSUMMARY (drift count per trial)\n{'#'*70}")
    for (model, temp), d in results.items():
        print(f"  {model:35s} temp={str(temp):12s}  drifts={d}")


if __name__ == "__main__":
    main()
