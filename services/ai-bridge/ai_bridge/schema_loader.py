"""Load and validate against schemas/task.schema.json."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schemas" / "task.schema.json"


@lru_cache(maxsize=1)
def load_task_schema() -> dict[str, Any]:
    with SCHEMA_PATH.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def validate_task_dict(data: dict[str, Any]) -> None:
    Draft202012Validator(load_task_schema()).validate(data)
