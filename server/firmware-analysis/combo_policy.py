"""Anti-hallucination policy for unlock/combo claims.

Physical button sequences may only appear in comboSummaries when explicitly
validated (live vehicle test or a line marked Belegt:/Validiert:). Speed pairs,
board pinouts, YARA, string matches, and LLM guesses must NOT invent
Gas/Bremse/Power sequences.
"""
from __future__ import annotations

import re
from typing import Any

_VALIDATED_PREFIXES = (
    "live-kombination",
    "live-vergleich",
    "validiert:",
    "belegt:",
)

_SPECULATIVE_MARKERS = re.compile(
    r"(gas\s*\+|bremse\s*\+|power\s*ein|vermutet|häufig gas|board-heuristik|"
    r"panic-heuristik|aktivierung offen|live-test nötig|tastenkombi|"
    r"einschalt-kombi|custom-button oder reboot)",
    re.IGNORECASE,
)


def is_validated_combo(line: str) -> bool:
    t = (line or "").strip().lower()
    if not t:
        return False
    return any(t.startswith(p) for p in _VALIDATED_PREFIXES)


def is_speculative_combo(line: str) -> bool:
    t = (line or "").strip()
    if not t:
        return False
    if is_validated_combo(t):
        return False
    return bool(_SPECULATIVE_MARKERS.search(t))


def sanitize_combo_summaries(combos: list[str] | None) -> list[str]:
    """Keep only validated combo lines; drop speculative button guesses."""
    out: list[str] = []
    seen: set[str] = set()
    for c in combos or []:
        if not isinstance(c, str):
            continue
        line = c.strip()
        if not line or line in seen:
            continue
        if is_speculative_combo(line):
            continue
        if not is_validated_combo(line):
            # Non-button factual lines that somehow landed here are also dropped
            # from comboSummaries (they belong in notes / YARA / speeds).
            continue
        seen.add(line)
        out.append(line)
    return out


def sanitize_transition_trigger(trigger: str | None) -> str:
    """Replace invented button triggers with an explicit unbelegt marker."""
    t = (trigger or "").strip()
    if not t:
        return "Aus Code nicht als Tastenfolge belegt"
    if is_validated_combo(t) or t.lower().startswith("belegt:"):
        return t
    if _SPECULATIVE_MARKERS.search(t) or "gas" in t.lower() or "bremse" in t.lower():
        return "Aus Code nicht als Tastenfolge belegt"
    if "modellabhängig" in t.lower() or "vermut" in t.lower():
        return "Aus Code nicht als Tastenfolge belegt"
    return t


def sanitize_result_combos(result: dict[str, Any]) -> dict[str, Any]:
    """Final gate before API response / persistence."""
    result["comboSummaries"] = sanitize_combo_summaries(result.get("comboSummaries"))
    transitions = []
    for t in result.get("modeTransitions") or []:
        if not isinstance(t, dict):
            continue
        nt = dict(t)
        nt["trigger"] = sanitize_transition_trigger(nt.get("trigger"))
        # Drop transitions whose only purpose was a speculative power combo
        title = str(nt.get("title") or "").lower()
        if "einschalt-kombi" in title and "vermut" in title:
            continue
        if "einschalt-kombi (slice" in title or "einschalt-kombi (slice/pinout)" in title:
            continue
        if title.startswith("einschalt-kombi"):
            continue
        transitions.append(nt)
    result["modeTransitions"] = transitions

    # Board pinout may stay for forensics, but never carry a default button recipe
    board = result.get("boardPinout")
    if isinstance(board, dict) and "defaultComboHypothesis" in board:
        board = dict(board)
        board.pop("defaultComboHypothesis", None)
        result["boardPinout"] = board
    return result
