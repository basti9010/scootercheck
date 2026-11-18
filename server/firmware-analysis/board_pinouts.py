"""Investigative board / pinout knowledge for ScooterCheck combo forensics.

These maps are NOT manufacturer schematics. They encode community/field
heuristics for common Ninebot/Segway VCU layouts so backward-slices and
input probes can label GPIO/ADC hits as Gas/Bremse/Power candidates.
Always treat results as unconfirmed until a live comparison test.
"""
from __future__ import annotations

from typing import Any

# role: throttle | brake | power | customButton | sense
BoardPin = dict[str, Any]

# AT32 / STM32-style absolute addresses often seen as peripheral bases in blobs.
# Values are heuristic windows — matching is by address proximity in the image map.
_BOARDS: list[dict[str, Any]] = [
    {
        "id": "zt3-vcu-at32",
        "models": ["zt3", "zt3pro"],
        "boards": ["zt3_vcu_at32", "at32"],
        "controllerTypes": ["VCU"],
        "mcuFamily": "AT32",
        "notes": "ZT3 VCU AT32 — Pin-/Addr-Heuristik für Gas/Bremse/Power/Panic; keine belegte Tastenfolge.",
        "defaultComboHypothesis": "",
        "panicHypothesis": "",
        "pins": [
            {
                "id": "throttle-adc",
                "role": "throttle",
                "label": "Gas (ADC)",
                "addrHints": [0x40012400, 0x40013C00],  # ADC1/ADC-ish windows
                "stringHints": ["throttle", "gas", "accel", "adc"],
            },
            {
                "id": "brake-adc",
                "role": "brake",
                "label": "Bremse (ADC)",
                "addrHints": [0x40012800, 0x40013C00],
                "stringHints": ["brake", "bremse", "lever"],
            },
            {
                "id": "power-gpio",
                "role": "power",
                "label": "Power / Boot-GPIO",
                "addrHints": [0x40010800, 0x40010C00, 0x40011000],  # GPIOA/B/C-ish
                "stringHints": ["power", "boot", "startup", "key"],
            },
            {
                "id": "panic-gpio",
                "role": "customButton",
                "label": "Panic / Custom-Taste",
                "addrHints": [0x40011000, 0x40011400],
                "stringHints": ["panic", "custom", "button", "softunlock"],
            },
        ],
    },
    {
        "id": "g3-vcu",
        "models": ["g3", "maxg3", "max-g3"],
        "boards": ["g3_vcu", "g3"],
        "controllerTypes": ["VCU", "MCU"],
        "mcuFamily": "STM32/AT32",
        "notes": "G3-Familie — oft Panicbutton-CFW; Pin-/Addr-Heuristik ohne belegte Unlock-Tastenfolge.",
        "defaultComboHypothesis": "",
        "panicHypothesis": "",
        "pins": [
            {
                "id": "throttle-adc",
                "role": "throttle",
                "label": "Gas (ADC)",
                "addrHints": [0x40012400, 0x40012000],
                "stringHints": ["throttle", "gas", "adc"],
            },
            {
                "id": "brake-adc",
                "role": "brake",
                "label": "Bremse (ADC)",
                "addrHints": [0x40012800, 0x40012000],
                "stringHints": ["brake", "bremse"],
            },
            {
                "id": "power-gpio",
                "role": "power",
                "label": "Power / Boot",
                "addrHints": [0x40010800, 0x40010C00],
                "stringHints": ["power", "boot", "key"],
            },
            {
                "id": "panic-gpio",
                "role": "customButton",
                "label": "Panic-Taste",
                "addrHints": [0x40011000],
                "stringHints": ["panic", "button", "custom"],
            },
        ],
    },
    {
        "id": "f3-vcu",
        "models": ["f3", "f3pro", "f3_pro"],
        "boards": ["f3_vcu", "f3"],
        "controllerTypes": ["VCU"],
        "mcuFamily": "STM32/AT32",
        "notes": "F3/F3 Pro — Pinout heuristisch; keine belegte Unlock-Tastenfolge aus Board-Wissen.",
        "defaultComboHypothesis": "",
        "panicHypothesis": "",
        "pins": [
            {
                "id": "throttle-adc",
                "role": "throttle",
                "label": "Gas (ADC)",
                "addrHints": [0x40012400],
                "stringHints": ["throttle", "gas", "adc"],
            },
            {
                "id": "brake-adc",
                "role": "brake",
                "label": "Bremse (ADC)",
                "addrHints": [0x40012800],
                "stringHints": ["brake", "bremse"],
            },
            {
                "id": "power-gpio",
                "role": "power",
                "label": "Power / Boot",
                "addrHints": [0x40010800, 0x40010C00],
                "stringHints": ["power", "boot"],
            },
        ],
    },
]


def resolve_board(
    *,
    models: list[str] | None = None,
    controller_type: str | None = None,
    display_name: str | None = None,
    filename: str | None = None,
) -> dict[str, Any] | None:
    blob = " ".join(
        [
            " ".join(models or []),
            controller_type or "",
            display_name or "",
            filename or "",
        ]
    ).lower()
    best: dict[str, Any] | None = None
    best_score = 0
    for b in _BOARDS:
        score = 0
        for m in b.get("models") or []:
            if m.lower() in blob:
                score += 3
        for board in b.get("boards") or []:
            if board.lower() in blob:
                score += 2
        if (controller_type or "").upper() in {c.upper() for c in (b.get("controllerTypes") or [])}:
            score += 1
        if "at32" in blob and b.get("mcuFamily") == "AT32":
            score += 1
        if score > best_score:
            best_score = score
            best = b
    return best if best_score > 0 else None


def list_boards() -> list[dict[str, Any]]:
    return [
        {
            "id": b["id"],
            "models": b.get("models"),
            "mcuFamily": b.get("mcuFamily"),
            "notes": b.get("notes"),
            "defaultComboHypothesis": b.get("defaultComboHypothesis"),
        }
        for b in _BOARDS
    ]


def label_addr(board: dict[str, Any] | None, addr: int, *, window: int = 0x1000) -> list[dict[str, Any]]:
    if not board:
        return []
    hits: list[dict[str, Any]] = []
    for pin in board.get("pins") or []:
        for hint in pin.get("addrHints") or []:
            if abs(int(hint) - addr) <= window or (int(hint) & ~0xFFF) == (addr & ~0xFFF):
                hits.append(
                    {
                        "pinId": pin.get("id"),
                        "role": pin.get("role"),
                        "label": pin.get("label"),
                        "hintAddr": f"{int(hint):#x}",
                        "matchedAddr": f"{addr:#x}",
                    }
                )
                break
    return hits


def string_roles(board: dict[str, Any] | None, text: str) -> list[str]:
    if not board or not text:
        return []
    low = text.lower()
    roles: list[str] = []
    for pin in board.get("pins") or []:
        for h in pin.get("stringHints") or []:
            if h.lower() in low:
                roles.append(str(pin.get("role")))
                break
    return sorted(set(roles))
