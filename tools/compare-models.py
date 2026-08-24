#!/usr/bin/env python3
"""Compare OpenAI models on Uzbek expense categorisation.

Runs the same Uzbek notes the app would produce through several models, using
the *same* system prompt and the same enum-constrained schema, then scores each
model against the expected category and reports token cost.

    export OPENAI_API_KEY=sk-...
    python3 tools/compare-models.py
    python3 tools/compare-models.py gpt-5-nano gpt-5-mini

The system prompt is read out of OpenAICategoryAgent.swift so this can never
drift from what the app actually sends.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
AGENT = os.path.join(HERE, "..", "ExeTrack", "Services", "OpenAICategoryAgent.swift")

DEFAULT_MODELS = ["gpt-5-nano", "gpt-4o-mini", "gpt-5-mini"]
EFFORT = os.environ.get("REASONING_EFFORT", "")

# USD per 1M tokens, input/output. Update if OpenAI changes pricing.
PRICES = {
    "gpt-5-nano":  (0.05, 0.40),
    "gpt-4o-mini": (0.15, 0.60),
    "gpt-5-mini":  (0.25, 2.00),
    "gpt-5":       (1.25, 10.00),
    "gpt-4o":      (2.50, 10.00),
}

# The app's default expense categories.
CATEGORIES = [
    "Groceries", "Restaurants", "Food delivery", "Coffee", "Public transport",
    "Car", "Fuel", "Taxi", "Utilities", "Rent", "Internet", "Health", "Gym",
    "Pharmacy", "Entertainment", "Subscriptions", "Travel", "Shopping", "Electronics",
    "Debt", "Savings",
]

# (note the parser actually produces, amount, expected category)
CASES = [
    ("Korzinka mahsulot",     45000,   "Groceries"),
    ("Taksi",                 15000,   "Taxi"),
    ("Evos lavash",           25000,   "Restaurants"),
    ("Dorixona dori",         50000,   "Pharmacy"),
    ("Benzin",                400000,  "Fuel"),
    ("Internet",              100000,  "Internet"),
    ("Beeline",               30000,   "Internet"),
    ("Kvartira ijarasi",      3000000, "Rent"),
    ("Kino",                  80000,   "Entertainment"),
    ("Uzum quloqchin",        200000,  "Electronics"),
    ("Choyxona tushlik",      35000,   "Restaurants"),
    ("Metro",                 1400,    "Public transport"),
    ("Sportzal oylik obuna",  200000,  "Gym"),
    ("Ovqat buyurtma",        50000,   "Food delivery"),
    ("Mashina",               30000,   "Car"),
    ("Kofe",                  20000,   "Coffee"),
    ("Tushlik",               40000,   "Restaurants"),
    ("Дорихона",              25000,   "Pharmacy"),
    ("Магазин масаллиқ",      50000,   "Groceries"),
    ("Choyxona osh",          45000,   "Restaurants"),
    # Nothing in the list fits these — the agent should decline, not guess.
    ("Qarz",                  1239000, "Debt"),
    ("Qarz berdim Akmalga",   500000,  "Debt"),
    ("Karta o'tkazma",        300000,  "__none_fit__"),
    ("Jamg'armaga qo'ydim",    1000000, "Savings"),
]

PAST_CHOICES = [("Korzinka", "Groceries"), ("Yandex go", "Taxi"), ("Payme", "Internet")]


def system_prompt():
    """Pull the live prompt out of the Swift source."""
    src = open(AGENT, encoding="utf-8").read()
    m = re.search(r'systemPrompt = """\n(.*?)\n    """', src, re.S)
    if not m:
        sys.exit("Could not find systemPrompt in OpenAICategoryAgent.swift")
    return "\n".join(line[4:] if line.startswith("    ") else line
                     for line in m.group(1).split("\n")).replace("\\\n", "")


def schema():
    return {
        "type": "json_schema",
        "json_schema": {
            "name": "category_assignment", "strict": True,
            "schema": {
                "type": "object", "additionalProperties": False, "required": ["results"],
                "properties": {"results": {"type": "array", "items": {
                    "type": "object", "additionalProperties": False,
                    "required": ["index", "category", "confidence", "alternatives"],
                    "properties": {
                        "index": {"type": "integer"},
                        "category": {"type": "string", "enum": CATEGORIES + ["__none_fit__"]},
                        "confidence": {"type": "number"},
                        "alternatives": {"type": "array", "items": {"type": "string", "enum": CATEGORIES}},
                    }}}},
            },
        },
    }


def user_message():
    lines = ["How this user has filed things before:"]
    lines += [f'- "{n}" → {c}' for n, c in PAST_CHOICES]
    lines += ["", "Place each of these:"]
    for i, (note, amount, _) in enumerate(CASES):
        lines.append(f'{i}. "{note}" — {amount:,} so\'m'.replace(",", " "))
    return "\n".join(lines)


def run(model, key):
    payload_body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt()},
            {"role": "user", "content": user_message()},
        ],
        "response_format": schema(),
    }
    # gpt-5* are reasoning models and emit a large hidden reasoning budget by
    # default. Cap it, or a one-line classification takes tens of seconds.
    if model.startswith("gpt-5") and EFFORT:
        payload_body["reasoning_effort"] = EFFORT
    body = json.dumps(payload_body).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    started = time.time()
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            payload = json.loads(r.read())
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:200]
        return None, f"HTTP {e.code}: {detail}", 0, None
    except Exception as e:                                  # noqa: BLE001
        return None, str(e), 0, None

    elapsed = time.time() - started
    results = json.loads(payload["choices"][0]["message"]["content"])["results"]
    by_index = {r["index"]: r for r in results}
    usage = payload.get("usage", {})
    return by_index, None, elapsed, usage


def main():
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        sys.exit("Set OPENAI_API_KEY first:\n  export OPENAI_API_KEY=sk-...")

    models = sys.argv[1:] or DEFAULT_MODELS
    table, meta = {}, {}
    for model in models:
        print(f"running {model} ...", file=sys.stderr)
        got, err, elapsed, usage = run(model, key)
        if err:
            print(f"  {model}: {err}", file=sys.stderr)
            continue
        table[model] = got
        meta[model] = (elapsed, usage)

    if not table:
        sys.exit("No model returned a result.")

    width = max(len(n) for n, _, _ in CASES) + 2
    header = "NOTE".ljust(width) + "EXPECTED".ljust(20) + "".join(m.ljust(20) for m in table)
    print("\n" + header)
    print("-" * len(header))

    scores = {m: 0 for m in table}
    for i, (note, _, expected) in enumerate(CASES):
        row = note.ljust(width) + expected.ljust(20)
        for model in table:
            r = table[model].get(i)
            got = r["category"] if r else "—"
            ok = got == expected
            if ok:
                scores[model] += 1
            row += (("✅ " if ok else "❌ ") + got).ljust(20)
        print(row)

    print("-" * len(header))
    print("ACCURACY".ljust(width + 20) + "".join(
        f"{scores[m]}/{len(CASES)}".ljust(20) for m in table))

    print("\nCost for one run of these 20 notes:")
    for model in table:
        elapsed, usage = meta[model]
        pin, pout = PRICES.get(model, (0, 0))
        cost = usage.get("prompt_tokens", 0) / 1e6 * pin + usage.get("completion_tokens", 0) / 1e6 * pout
        per_1000 = cost / len(CASES) * 1000
        print(f"  {model.ljust(14)} {elapsed:5.1f}s  "
              f"{usage.get('prompt_tokens', 0):>5} in / {usage.get('completion_tokens', 0):>4} out  "
              f"${cost:.5f}   (~${per_1000:.2f} per 1000 expenses)")


if __name__ == "__main__":
    main()
