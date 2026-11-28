"""SQLite-backed task store with JSON migration and ownership checks."""

from __future__ import annotations

import json
import sqlite3
import threading
from pathlib import Path
from typing import Any, Optional

from ai_bridge.models import Task, TaskCreate, TaskStatus, utc_now_iso
from ai_bridge.state_machine import transition


SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
  task_id TEXT PRIMARY KEY,
  idempotency_key TEXT NOT NULL UNIQUE,
  owner_subject TEXT,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,
  cursor_agent_id TEXT,
  cursor_run_id TEXT,
  github_pr_url TEXT,
  branch_name TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_sync_at TEXT,
  error_message TEXT
);
CREATE TABLE IF NOT EXISTS audit_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT,
  actor TEXT,
  action TEXT NOT NULL,
  detail_json TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON tasks(owner_subject);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
"""


class SqliteTaskStore:
    """Atomic task persistence. Prefer this over filesystem JSON for v2."""

    def __init__(self, db_path: Path | str) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        # Orchestrator writes reports under store.root / "reports"
        self.root = self.db_path.parent
        self._lock = threading.RLock()
        with self._connect() as conn:
            conn.executescript(SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA foreign_keys=ON;")
        return conn

    def migrate_from_json(self, json_root: Path) -> int:
        """Import tasks/*.json + idempotency_index without deleting sources."""
        tasks_dir = Path(json_root) / "tasks"
        if not tasks_dir.is_dir():
            return 0
        imported = 0
        for path in sorted(tasks_dir.glob("*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            task = Task.model_validate(data)
            existing = self.get(task.task_id)
            if existing is None:
                self._upsert(task)
                imported += 1
        return imported

    def _row_to_task(self, row: sqlite3.Row) -> Task:
        payload = json.loads(row["payload_json"])
        # Overlay columns that may be newer than payload snapshot
        payload["status"] = row["status"]
        payload["cursor_agent_id"] = row["cursor_agent_id"]
        payload["cursor_run_id"] = row["cursor_run_id"]
        payload["updated_at"] = row["updated_at"]
        if row["error_message"] is not None:
            payload["error_message"] = row["error_message"]
        if row["github_pr_url"]:
            payload["github_pr_url"] = row["github_pr_url"]
        if row["branch_name"]:
            payload["branch_name"] = row["branch_name"]
        if row["last_sync_at"]:
            payload["last_sync_at"] = row["last_sync_at"]
        if row["owner_subject"] and not payload.get("requested_by"):
            payload["requested_by"] = row["owner_subject"]
        return Task.model_validate(payload)

    def _upsert(self, task: Task) -> None:
        payload = task.model_dump(mode="json")
        with self._lock:
            with self._connect() as conn:
                conn.execute(
                    """
                    INSERT INTO tasks (
                      task_id, idempotency_key, owner_subject, payload_json, status,
                      cursor_agent_id, cursor_run_id, github_pr_url, branch_name,
                      created_at, updated_at, last_sync_at, error_message
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(task_id) DO UPDATE SET
                      payload_json=excluded.payload_json,
                      status=excluded.status,
                      cursor_agent_id=excluded.cursor_agent_id,
                      cursor_run_id=excluded.cursor_run_id,
                      github_pr_url=excluded.github_pr_url,
                      branch_name=excluded.branch_name,
                      updated_at=excluded.updated_at,
                      last_sync_at=excluded.last_sync_at,
                      error_message=excluded.error_message,
                      owner_subject=COALESCE(excluded.owner_subject, tasks.owner_subject)
                    """,
                    (
                        task.task_id,
                        task.idempotency_key,
                        task.requested_by,
                        json.dumps(payload, sort_keys=True),
                        task.status.value if isinstance(task.status, TaskStatus) else str(task.status),
                        task.cursor_agent_id,
                        task.cursor_run_id,
                        getattr(task, "github_pr_url", None),
                        getattr(task, "branch_name", None),
                        task.created_at,
                        task.updated_at,
                        getattr(task, "last_sync_at", None),
                        task.error_message,
                    ),
                )
                conn.commit()

    def save(self, task: Task) -> Task:
        self._upsert(task)
        return task

    def get(self, task_id: str) -> Optional[Task]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM tasks WHERE task_id = ?", (task_id,)).fetchone()
        return self._row_to_task(row) if row else None

    def get_by_idempotency_key(self, key: str) -> Optional[Task]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM tasks WHERE idempotency_key = ?", (key,)
            ).fetchone()
        return self._row_to_task(row) if row else None

    def create_task(self, payload: TaskCreate) -> tuple[Task, bool]:
        with self._lock:
            existing = self.get_by_idempotency_key(payload.idempotency_key)
            if existing is not None:
                return existing, False
            task = Task.from_create(payload)
            try:
                self._upsert(task)
            except sqlite3.IntegrityError:
                # concurrent create with same idempotency key
                again = self.get_by_idempotency_key(payload.idempotency_key)
                if again:
                    return again, False
                raise
            self.audit(task.task_id, payload.requested_by or "system", "task_created", {})
            return task, True

    def update_status(self, task_id: str, target: TaskStatus, **kwargs) -> Task:
        task = self.get(task_id)
        if task is None:
            raise KeyError(f"Unknown task_id: {task_id}")
        updated = transition(task, target, **kwargs)
        self.save(updated)
        return updated

    def patch(self, task: Task) -> Task:
        data = task.model_dump()
        data["updated_at"] = utc_now_iso()
        updated = Task.model_validate(data)
        self.save(updated)
        return updated

    def list_tasks(
        self,
        *,
        owner_subject: str | None = None,
        admin: bool = False,
        status: str | None = None,
        limit: int = 100,
    ) -> list[Task]:
        sql = "SELECT * FROM tasks"
        clauses: list[str] = []
        args: list[Any] = []
        if not admin:
            clauses.append("owner_subject = ?")
            args.append(owner_subject or "")
        if status:
            clauses.append("status = ?")
            args.append(status)
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY created_at DESC LIMIT ?"
        args.append(limit)
        with self._connect() as conn:
            rows = conn.execute(sql, args).fetchall()
        return [self._row_to_task(r) for r in rows]

    def audit(self, task_id: str | None, actor: str | None, action: str, detail: dict) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO audit_events (task_id, actor, action, detail_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    task_id,
                    actor,
                    action,
                    json.dumps(detail, sort_keys=True),
                    utc_now_iso(),
                ),
            )
            conn.commit()
