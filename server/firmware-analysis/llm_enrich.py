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
    key = _api_key()
    if not key:
        return False
    # OAuth / Claude Code setup tokens — not usable as Console API keys.
    if key.startswith("sk-ant-oat") or key.startswith("eyJ"):
        return False
    return True


def llm_key_status() -> dict[str, str | bool]:
    """Diagnostics for /health — never includes the secret."""
    key = _api_key()
    if not key:
        return {"present": False, "usable": False, "kind": "missing"}
    if key.startswith("sk-ant-api"):
        return {"present": True, "usable": True, "kind": "anthropic-api"}
    if key.startswith("sk-ant-usr"):
        # Newer Claude Console personal API keys (valid with x-api-key / Bearer).
        return {"present": True, "usable": True, "kind": "anthropic-usr"}
    if key.startswith("sk-ant-oat"):
        return {
            "present": True,
            "usable": False,
            "kind": "anthropic-oauth",
            "hint": "sk-ant-oat ist ein OAuth/Setup-Token — bitte API-Schlüssel (sk-ant-usr / sk-ant-api) verwenden",
        }
    if key.startswith("sk-ant-"):
        return {"present": True, "usable": True, "kind": "anthropic-other"}
    if key.startswith("sk-"):
        return {"present": True, "usable": True, "kind": "openai-ish"}
    return {"present": True, "usable": True, "kind": "other"}


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
    raw = (
        os.environ.get("LLM_API_KEY", "").strip()
        or os.environ.get("ANTHROPIC_API_KEY", "").strip()
        or os.environ.get("OPENAI_API_KEY", "").strip()
    )
    # Hetzner console DE keyboard often turns '-' into 'ß' when pasting.
    return raw.replace("ß", "-").replace(" ", "")


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


def enrich_result(
    result: dict[str, Any],
    *,
    decompiled_text: str | None,
    limit_c_text: str | None = None,
) -> dict[str, Any]:
    status = llm_key_status()
    if status.get("kind") == "anthropic-oauth":
        notes = list(result.get("notes") or [])
        notes.append(f"llm=skipped ({status.get('hint')})")
        result["notes"] = notes
        return result
    if not llm_configured():
        return result

    # Prefer focused limit-function decompile over full dump when available.
    focused = (limit_c_text or "").strip()
    if focused and len(focused) > 80:
        snippet = focused
        snippet_kind = "limits.c"
    else:
        snippet = select_decompile_snippet(decompiled_text)
        snippet_kind = "full.c"
    if not snippet and not result.get("speedLimits"):
        notes = list(result.get("notes") or [])
        notes.append("llm=skipped (no decompile snippet / speeds)")
        result["notes"] = notes
        return result

    # Keep request/response small — large snippets often truncate mid-JSON (max_tokens).
    speeds_compact = [
        {"kmh": s.get("kmh"), "role": s.get("role"), "source": s.get("source")}
        for s in (result.get("speedLimits") or [])[:20]
        if isinstance(s, dict)
    ]
    snippet_for_llm = snippet[:10_000]
    payload = {
        "schemaVersion": 1,
        "speedLimits": speeds_compact,
        "existingCombos": (result.get("comboSummaries") or [])[:8],
        "existingTransitions": [
            {k: t.get(k) for k in ("title", "trigger", "effect")}
            for t in (result.get("modeTransitions") or [])[:6]
            if isinstance(t, dict)
        ],
        "existingInputs": [
            {k: i.get(k) for k in ("kind", "detail")}
            for i in (result.get("inputHints") or [])[:6]
            if isinstance(i, dict)
        ],
        "decompileSnippet": snippet_for_llm,
        "snippetKind": snippet_kind,
        "snippetChars": len(snippet_for_llm),
        "boardPinout": result.get("boardPinout"),
        "limitSliceRoles": result.get("limitSlices") and [
            r for s in (result.get("limitSlices") or [])[:6] for r in (s.get("pinLabels") or [])
        ][:12],
    }
    system = (
        "Du bist Firmware-Forensik-Assistent für ScooterCheck (Ninebot/Segway VCU/MCU). "
        "Antworte NUR mit einem kompakten JSON-Objekt (kein Markdown, keine Prosa). "
        "Schema: "
        '{"comboSummaries":[str≤120],"modeTransitions":[{"id","title","trigger","effect","evidence","confidence"}],'
        '"inputHints":[{"id","kind","detail","evidence","confidence"}],"notes":[str≤120]}. '
        "Limits: ≤4 comboSummaries, ≤4 modeTransitions, ≤4 inputHints, ≤3 notes. "
        "evidence ≤80 Zeichen. kind ∈ throttle|brake|power|customButton|dualAnalog|unknown. "
        "confidence ∈ high|medium|low. "
        "Keine Speed-km/h-Werte erfinden. Nur Tastenfolgen/Moduswechsel/Eingaben aus Snippet. Deutsch."
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
            "max_tokens": 4096,
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
    key = _api_key()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            # Prefer Bearer (current docs); keep x-api-key for compatibility.
            "Authorization": f"Bearer {key}",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    data = _http_json(req)
    stop = data.get("stop_reason")
    parts = data.get("content") or []
    texts = [p.get("text", "") for p in parts if isinstance(p, dict) and p.get("type") == "text"]
    if not texts:
        raise RuntimeError("anthropic response missing text content")
    text = "\n".join(texts)
    # stop_reason == max_tokens → truncated; _extract_json tries repair.
    _ = stop
    return text


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
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        repaired = _repair_truncated_json(text)
        data = json.loads(repaired)
    if not isinstance(data, dict):
        raise ValueError("LLM JSON root must be object")
    return data


def _repair_truncated_json(text: str) -> str:
    """Best-effort close of truncated model JSON (cut mid-string / mid-array)."""
    s = text.strip()
    if not s.startswith("{"):
        start = s.find("{")
        if start < 0:
            raise ValueError("no JSON object in LLM output")
        s = s[start:]

    # If truncated inside a string, close it.
    in_str = False
    escape = False
    for ch in s:
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
    if in_str:
        s += '"'

    # Drop trailing incomplete key/value junk after last complete comma-separated item.
    # Prefer cutting back to a safe terminator, then close brackets.
    for cut in range(len(s), max(len(s) - 400, 0), -1):
        candidate = s[:cut].rstrip()
        if candidate.endswith((",", ":")):
            candidate = candidate[:-1].rstrip()
        # Close open braces/brackets
        stack: list[str] = []
        in_str = False
        escape = False
        balanced = True
        for ch in candidate:
            if in_str:
                if escape:
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
            elif ch in "{[":
                stack.append(ch)
            elif ch == "}":
                if not stack or stack[-1] != "{":
                    balanced = False
                    break
                stack.pop()
            elif ch == "]":
                if not stack or stack[-1] != "[":
                    balanced = False
                    break
                stack.pop()
        if not balanced or in_str:
            continue
        closers = "".join("}" if c == "{" else "]" for c in reversed(stack))
        try:
            data = json.loads(candidate + closers)
            if isinstance(data, dict):
                return candidate + closers
        except json.JSONDecodeError:
            continue
    raise ValueError("could not repair truncated LLM JSON")
