"""Filesystem JSON task store with idempotent create."""

from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Optional

from ai_bridge.models import Task, TaskCreate, utc_now_iso
from ai_bridge.state_machine import transition


class TaskStore:
    def __init__(self, root: Path | str) -> None:
        self.root = Path(root)
        self.tasks_dir = self.root / "tasks"
        self.index_path = self.root / "idempotency_index.json"
        self.tasks_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        if not self.index_path.exists():
            self._write_index({})

    def _read_index(self) -> dict[str, str]:
        with self.index_path.open("r", encoding="utf-8") as fh:
            return json.load(fh)

    def _write_index(self, index: dict[str, str]) -> None:
        self.index_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.index_path.with_suffix(".tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(index, fh, indent=2, sort_keys=True)
            fh.write("\n")
        tmp.replace(self.index_path)

    def _task_path(self, task_id: str) -> Path:
        safe = task_id.replace("/", "_")
        return self.tasks_dir / f"{safe}.json"

    def save(self, task: Task) -> Task:
        with self._lock:
            path = self._task_path(task.task_id)
            tmp = path.with_suffix(".tmp")
            payload = task.model_dump(mode="json")
            with tmp.open("w", encoding="utf-8") as fh:
                json.dump(payload, fh, indent=2, sort_keys=True)
                fh.write("\n")
            tmp.replace(path)
            return task

    def get(self, task_id: str) -> Optional[Task]:
        path = self._task_path(task_id)
        if not path.exists():
            return None
        with path.open("r", encoding="utf-8") as fh:
            return Task.model_validate(json.load(fh))

    def get_by_idempotency_key(self, key: str) -> Optional[Task]:
        with self._lock:
            index = self._read_index()
            task_id = index.get(key)
            if not task_id:
                return None
            return self.get(task_id)

    def create_task(self, payload: TaskCreate) -> tuple[Task, bool]:
        with self._lock:
            existing = self.get_by_idempotency_key(payload.idempotency_key)
            if existing is not None:
                return existing, False
            task = Task.from_create(payload)
            index = self._read_index()
            if payload.idempotency_key in index:
                return self.get(index[payload.idempotency_key]), False  # type: ignore[return-value]
            self.save(task)
            index[payload.idempotency_key] = task.task_id
            self._write_index(index)
            return task, True

    def update_status(self, task_id: str, target, **kwargs) -> Task:
        with self._lock:
            task = self.get(task_id)
            if task is None:
                raise KeyError(f"Unknown task_id: {task_id}")
            updated = transition(task, target, **kwargs)
            return self.save(updated)

    def patch(self, task: Task) -> Task:
        with self._lock:
            task.updated_at = utc_now_iso()
            return self.save(task)

    def list_tasks(
        self,
        *,
        owner_subject: str | None = None,
        admin: bool = False,
        status: str | None = None,
        limit: int = 100,
    ) -> list[Task]:
        tasks: list[Task] = []
        for path in sorted(self.tasks_dir.glob("*.json")):
            with path.open("r", encoding="utf-8") as fh:
                task = Task.model_validate(json.load(fh))
            if status and task.status.value != status:
                continue
            if not admin and owner_subject is not None:
                if task.requested_by not in (None, owner_subject):
                    continue
            tasks.append(task)
        return tasks[:limit]
