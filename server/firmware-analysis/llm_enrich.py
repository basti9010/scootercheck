"""Optional schema-bound LLM enrichment after deterministic decrypt/Ghidra/combo scan.

Requires LLM_API_KEY (or ANTHROPIC_API_KEY / OPENAI_API_KEY). Without key: no-op.
Providers: openai (Chat Completions) | anthropic (Messages API).
Only fills/extends comboSummaries, modeTransitions, inputHints, notes — never invents speeds.
"""
from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from typing import Any

DEFAULT_OPENAI_BASE = "https://api.openai.com/v1"
DEFAULT_ANTHROPIC_BASE = "https://api.anthropic.com"
DEFAULT_OPENAI_MODEL = "gpt-4o-mini"
DEFAULT_ANTHROPIC_MODEL = "claude-haiku-4-5-20251001"
MAX_SNIPPET_CHARS = 14_000
MAX_COMBOS = 12
MAX_TRANSITIONS = 10
MAX_INPUTS = 10

_VALID_KINDS = {"throttle", "brake", "power", "customButton", "dualAnalog", "unknown"}
_VALID_CONF = {"high", "medium", "low"}

# Packed speed immediates + German/English firmware keywords → focus windows in .c
_SPEED_HEX = [
    "0x1400", "0x1600", "0x1700", "0x1900", "0x1e00", "0x2000",
    "0x2300", "0x2319", "0x2800", "0x2d00", "0x3200", "0x6300",
]
_KEYWORD_RE = re.compile(
    r"(speed|limit|throttle|brake|gas|bremse|mode|region|unlock|soft|combo|button|key|adc|pedal)",
    re.IGNORECASE,
)


def llm_configured() -> bool:
    return bool(_api_key())


def llm_provider() -> str:
    """openai | anthropic — auto from LLM_PROVIDER, base URL, or key prefix."""
    explicit = os.environ.get("LLM_PROVIDER", "").strip().lower()
    if explicit in {"openai", "anthropic"}:
        return explicit
    base = os.environ.get("LLM_BASE_URL", "").strip().lower()
    if "anthropic.com" in base:
        return "anthropic"
    key = _api_key()
    if key.startswith("sk-ant-"):
        return "anthropic"
    if os.environ.get("ANTHROPIC_API_KEY", "").strip() and not os.environ.get("OPENAI_API_KEY", "").strip():
        if not os.environ.get("LLM_API_KEY", "").strip() or os.environ.get("LLM_API_KEY", "").strip().startswith("sk-ant-"):
            return "anthropic"
    return "openai"


def _api_key() -> str:
    return (
        os.environ.get("LLM_API_KEY", "").strip()
        or os.environ.get("ANTHROPIC_API_KEY", "").strip()
        or os.environ.get("OPENAI_API_KEY", "").strip()
    )


def _base_url() -> str:
    override = os.environ.get("LLM_BASE_URL", "").strip()
    if override:
        return override.rstrip("/")
    if llm_provider() == "anthropic":
        return DEFAULT_ANTHROPIC_BASE
    return DEFAULT_OPENAI_BASE


def _model() -> str:
    override = os.environ.get("LLM_MODEL", "").strip()
    if override:
        return override
    if llm_provider() == "anthropic":
        return DEFAULT_ANTHROPIC_MODEL
    return DEFAULT_OPENAI_MODEL


def select_decompile_snippet(decompiled_text: str | None, *, max_chars: int = MAX_SNIPPET_CHARS) -> str:
    """Prefer windows around speed immediates / control keywords over raw head truncation."""
    text = decompiled_text or ""
    if not text:
        return ""
    if len(text) <= max_chars:
        return text

    lines = text.splitlines()
    hit_idxs: set[int] = set()
    for i, line in enumerate(lines):
        low = line.lower()
        if any(h in low for h in _SPEED_HEX) or _KEYWORD_RE.search(line):
            hit_idxs.add(i)

    if not hit_idxs:
        return text[:max_chars]

    # Expand ±12 lines around each hit, merge overlapping ranges
    window = 12
    ranges: list[tuple[int, int]] = []
    for i in sorted(hit_idxs):
        a, b = max(0, i - window), min(len(lines), i + window + 1)
        if ranges and a <= ranges[-1][1] + 2:
            ranges[-1] = (ranges[-1][0], max(ranges[-1][1], b))
        else:
            ranges.append((a, b))

    chunks: list[str] = []
    budget = max_chars
    for a, b in ranges:
        block = "\n".join(lines[a:b])
        header = f"\n/* --- lines {a + 1}-{b} --- */\n"
        piece = header + block
        if len(piece) > budget:
            piece = piece[:budget]
            chunks.append(piece)
            break
        chunks.append(piece)
        budget -= len(piece)
        if budget < 400:
            break

    out = "\n".join(chunks).strip()
    return out or text[:max_chars]


def enrich_result(result: dict[str, Any], *, decompiled_text: str | None) -> dict[str, Any]:
    if not llm_configured():
        return result

    snippet = select_decompile_snippet(decompiled_text)
    if not snippet and not result.get("speedLimits"):
        notes = list(result.get("notes") or [])
        notes.append("llm=skipped (no decompile snippet / speeds)")
        result["notes"] = notes
        return result

    payload = {
        "schemaVersion": 1,
        "speedLimits": result.get("speedLimits") or [],
        "existingCombos": result.get("comboSummaries") or [],
        "existingTransitions": result.get("modeTransitions") or [],
        "existingInputs": result.get("inputHints") or [],
        "decompileSnippet": snippet,
        "snippetChars": len(snippet),
    }
    system = (
        "Du bist Firmware-Forensik-Assistent für ScooterCheck (Ninebot/Segway VCU/MCU). "
        "Antworte NUR mit JSON: "
        '{"comboSummaries":[str],"modeTransitions":[{"id","title","trigger","effect","evidence","confidence"}],'
        '"inputHints":[{"id","kind","detail","evidence","confidence"}],"notes":[str]}. '
        "kind ∈ throttle|brake|power|customButton|dualAnalog|unknown. "
        "confidence ∈ high|medium|low. "
        "Keine Speed-km/h-Werte erfinden und keine neuen packed Speeds nennen. "
        "Nur aus Snippet und existingSpeeds ableiten (Tastenfolgen, Moduswechsel, Eingaben). "
        "evidence muss eine kurze Ankerzeile aus dem Snippet zitieren. "
        "Kennzeichne Unsicherheit. Deutsch."
    )
    try:
        raw = _chat(system, json.dumps(payload, ensure_ascii=False))
        data = _extract_json(raw)
    except Exception as e:
        notes = list(result.get("notes") or [])
        notes.append(f"llm=failed:{e}")
        result["notes"] = notes
        return result

    before = _signal_count(result)
    result = _merge_validated(result, data)
    after = _signal_count(result)

    notes = list(result.get("notes") or [])
    if after > before:
        sources = list(result.get("sources") or [])
        if "serverLLM" not in sources:
            sources.append("serverLLM")
        result["sources"] = sources
        quality = dict(result.get("quality") or {})
        quality["llmSchemaValidated"] = True
        quality["summary"] = ((quality.get("summary") or "").rstrip() + " + KI-Hinweise (schema).").strip()
        result["quality"] = quality
        notes.append(f"llm=schema-enriched (+{after - before} Felder, model={_model()})")
    else:
        notes.append("llm=empty (schema ok, keine neuen Felder)")
    result["notes"] = notes
    return result


def _signal_count(result: dict[str, Any]) -> int:
    return (
        len(result.get("comboSummaries") or [])
        + len(result.get("modeTransitions") or [])
        + len(result.get("inputHints") or [])
    )


def _merge_validated(result: dict[str, Any], data: dict[str, Any]) -> dict[str, Any]:
    combos = list(result.get("comboSummaries") or [])
    for c in data.get("comboSummaries") or []:
        if isinstance(c, str):
            c = c.strip()
            if c and c not in combos and len(combos) < MAX_COMBOS:
                combos.append(c)
    result["comboSummaries"] = combos

    transitions = list(result.get("modeTransitions") or [])
    seen_tr = {(str(t.get("title")), str(t.get("trigger")), str(t.get("effect"))) for t in transitions if isinstance(t, dict)}
    for t in data.get("modeTransitions") or []:
        if not isinstance(t, dict) or len(transitions) >= MAX_TRANSITIONS:
            continue
        conf = str(t.get("confidence") or "low").lower()
        if conf not in _VALID_CONF:
            conf = "low"
        title = str(t.get("title") or "KI-Hinweis").strip()[:120]
        trigger = str(t.get("trigger") or "").strip()[:200]
        effect = str(t.get("effect") or "").strip()[:200]
        evidence = str(t.get("evidence") or "LLM schema").strip()[:240]
        if not (title or trigger or effect):
            continue
        key = (title, trigger, effect)
        if key in seen_tr:
            continue
        seen_tr.add(key)
        transitions.append(
            {
                "id": str(t.get("id") or f"llm-tr-{len(transitions)}")[:64],
                "title": title or "KI-Hinweis",
                "trigger": trigger,
                "effect": effect,
                "evidence": evidence,
                "source": "serverLLM",
                "confidence": conf,
            }
        )
    result["modeTransitions"] = transitions

    inputs = list(result.get("inputHints") or [])
    seen_in = {(str(i.get("kind")), str(i.get("detail"))) for i in inputs if isinstance(i, dict)}
    for i in data.get("inputHints") or []:
        if not isinstance(i, dict) or len(inputs) >= MAX_INPUTS:
            continue
        kind = str(i.get("kind") or "unknown")
        if kind not in _VALID_KINDS:
            kind = "unknown"
        conf = str(i.get("confidence") or "low").lower()
        if conf not in _VALID_CONF:
            conf = "low"
        detail = str(i.get("detail") or "").strip()[:240]
        evidence = str(i.get("evidence") or "LLM schema").strip()[:240]
        if not detail:
            continue
        key = (kind, detail)
        if key in seen_in:
            continue
        seen_in.add(key)
        inputs.append(
            {
                "id": str(i.get("id") or f"llm-in-{len(inputs)}")[:64],
                "kind": kind,
                "detail": detail,
                "evidence": evidence,
                "source": "serverLLM",
                "confidence": conf,
            }
        )
    result["inputHints"] = inputs

    notes = list(result.get("notes") or [])
    for n in data.get("notes") or []:
        if isinstance(n, str) and n.strip():
            notes.append(f"llm:{n.strip()[:200]}")
    result["notes"] = notes
    return result


def _chat(system: str, user: str) -> str:
    if llm_provider() == "anthropic":
        return _chat_anthropic(system, user)
    return _chat_openai(system, user)


def _chat_openai(system: str, user: str) -> str:
    body = json.dumps(
        {
            "model": _model(),
            "temperature": 0.1,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        f"{_base_url()}/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {_api_key()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    data = _http_json(req)
    return data["choices"][0]["message"]["content"]


def _chat_anthropic(system: str, user: str) -> str:
    # Messages API — https://docs.anthropic.com/en/api/messages
    body = json.dumps(
        {
            "model": _model(),
            "max_tokens": 2048,
            "temperature": 0.1,
            "system": system + "\n\nAntworte ausschließlich mit einem JSON-Objekt, ohne Markdown.",
            "messages": [{"role": "user", "content": user}],
        }
    ).encode("utf-8")
    base = _base_url()
    # Accept either https://api.anthropic.com or .../v1
    url = base if base.endswith("/v1/messages") else (
        f"{base}/v1/messages" if base.endswith("/v1") else f"{base}/v1/messages"
    )
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "x-api-key": _api_key(),
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    data = _http_json(req)
    parts = data.get("content") or []
    texts = [p.get("text", "") for p in parts if isinstance(p, dict) and p.get("type") == "text"]
    if not texts:
        raise RuntimeError("anthropic response missing text content")
    return "\n".join(texts)


def _http_json(req: urllib.request.Request) -> dict[str, Any]:
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read()[:300]!r}") from e


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:].strip()
    # Tolerate leading prose before first {
    if not text.startswith("{"):
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            text = text[start : end + 1]
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("LLM JSON root must be object")
    return data
