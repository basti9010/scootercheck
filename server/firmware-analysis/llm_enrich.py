"""Optional schema-bound LLM enrichment after deterministic decrypt/Ghidra/combo scan.

Requires LLM_API_KEY (OpenAI-compatible). Without key: no-op.
Only fills/extends comboSummaries, modeTransitions, inputHints, notes — never invents speeds.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

LLM_API_KEY = os.environ.get("LLM_API_KEY", "").strip() or os.environ.get("OPENAI_API_KEY", "").strip()
LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1").rstrip("/")
LLM_MODEL = os.environ.get("LLM_MODEL", "gpt-4o-mini").strip()


def llm_configured() -> bool:
    return bool(LLM_API_KEY)


def enrich_result(result: dict[str, Any], *, decompiled_text: str | None) -> dict[str, Any]:
    if not llm_configured():
        return result
    snippet = (decompiled_text or "")[:12000]
    if not snippet and not result.get("speedLimits"):
        return result

    payload = {
        "schemaVersion": 1,
        "speedLimits": result.get("speedLimits") or [],
        "existingCombos": result.get("comboSummaries") or [],
        "existingTransitions": result.get("modeTransitions") or [],
        "existingInputs": result.get("inputHints") or [],
        "decompileSnippet": snippet,
    }
    system = (
        "Du bist Firmware-Forensik-Assistent für ScooterCheck. "
        "Antworte NUR mit JSON: "
        '{"comboSummaries":[str],"modeTransitions":[{"id","title","trigger","effect","evidence","confidence"}],'
        '"inputHints":[{"id","kind","detail","evidence","confidence"}],"notes":[str]}. '
        "kind ∈ throttle|brake|power|customButton|dualAnalog|unknown. "
        "confidence ∈ high|medium|low. "
        "Keine Speed-Werte erfinden. Nur aus Snippet/bestehenden Speeds ableiten. "
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

    combos = list(result.get("comboSummaries") or [])
    for c in data.get("comboSummaries") or []:
        if isinstance(c, str) and c and c not in combos:
            combos.append(c)
    result["comboSummaries"] = combos

    transitions = list(result.get("modeTransitions") or [])
    for t in data.get("modeTransitions") or []:
        if not isinstance(t, dict):
            continue
        t = {
            "id": str(t.get("id") or f"llm-tr-{len(transitions)}"),
            "title": str(t.get("title") or "KI-Hinweis"),
            "trigger": str(t.get("trigger") or ""),
            "effect": str(t.get("effect") or ""),
            "evidence": str(t.get("evidence") or "LLM schema"),
            "source": "serverLLM",
            "confidence": str(t.get("confidence") or "low"),
        }
        transitions.append(t)
    result["modeTransitions"] = transitions

    inputs = list(result.get("inputHints") or [])
    for i in data.get("inputHints") or []:
        if not isinstance(i, dict):
            continue
        inputs.append(
            {
                "id": str(i.get("id") or f"llm-in-{len(inputs)}"),
                "kind": str(i.get("kind") or "unknown"),
                "detail": str(i.get("detail") or ""),
                "evidence": str(i.get("evidence") or "LLM schema"),
                "source": "serverLLM",
                "confidence": str(i.get("confidence") or "low"),
            }
        )
    result["inputHints"] = inputs

    notes = list(result.get("notes") or [])
    for n in data.get("notes") or []:
        if isinstance(n, str) and n:
            notes.append(f"llm:{n}")
    notes.append("llm=schema-enriched")
    result["notes"] = notes

    sources = list(result.get("sources") or [])
    if "serverLLM" not in sources:
        sources.append("serverLLM")
    result["sources"] = sources
    quality = dict(result.get("quality") or {})
    quality["llmSchemaValidated"] = True
    quality["summary"] = (quality.get("summary") or "") + " + KI-Hinweise (schema)."
    result["quality"] = quality
    return result


def _chat(system: str, user: str) -> str:
    body = json.dumps(
        {
            "model": LLM_MODEL,
            "temperature": 0.1,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        f"{LLM_BASE_URL}/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {LLM_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read()[:300]!r}") from e
    return data["choices"][0]["message"]["content"]


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:].strip()
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("LLM JSON root must be object")
    return data
