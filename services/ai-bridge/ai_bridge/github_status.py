"""Read-only GitHub status helpers (optional GITHUB_TOKEN / GH_TOKEN)."""

from __future__ import annotations

import os
from typing import Any

import httpx

from mcp.security import untrusted_external_text


def _token() -> str | None:
    return (os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or "").strip() or None


def fetch_open_pulls(owner: str, repo: str, *, limit: int = 10) -> dict[str, Any]:
    token = _token()
    if not token:
        return {"available": False, "reason": "GITHUB_TOKEN unset", "pulls": []}
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    url = f"https://api.github.com/repos/{owner}/{repo}/pulls"
    with httpx.Client(timeout=20.0) as client:
        resp = client.get(url, headers=headers, params={"state": "open", "per_page": limit})
        if resp.status_code >= 400:
            return {"available": False, "reason": f"http_{resp.status_code}", "pulls": []}
        items = resp.json()
    pulls = [
        {
            "number": p.get("number"),
            "title": p.get("title"),
            "html_url": p.get("html_url"),
            "head": (p.get("head") or {}).get("ref"),
            "draft": p.get("draft"),
        }
        for p in items
    ]
    return {"available": True, "pulls": pulls}


def fetch_workflow_runs(owner: str, repo: str, *, branch: str | None = None) -> dict[str, Any]:
    token = _token()
    if not token:
        return {
            "available": False,
            "reason": "GITHUB_TOKEN unset",
            "log": untrusted_external_text("github", "CI unavailable: no token"),
        }
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    params: dict[str, Any] = {"per_page": 5}
    if branch:
        params["branch"] = branch
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runs"
    with httpx.Client(timeout=20.0) as client:
        resp = client.get(url, headers=headers, params=params)
        if resp.status_code >= 400:
            return {
                "available": False,
                "reason": f"http_{resp.status_code}",
                "log": untrusted_external_text("github", f"CI fetch failed HTTP {resp.status_code}"),
            }
        data = resp.json()
    runs = []
    for r in data.get("workflow_runs") or []:
        runs.append(
            {
                "id": r.get("id"),
                "name": r.get("name"),
                "status": r.get("status"),
                "conclusion": r.get("conclusion"),
                "html_url": r.get("html_url"),
                "head_sha": (r.get("head_sha") or "")[:12],
            }
        )
    excerpt = "\n".join(
        f"{x['name']}: {x['status']}/{x['conclusion']}" for x in runs
    ) or "no runs"
    return {
        "available": True,
        "runs": runs,
        "log": untrusted_external_text("github", excerpt),
    }
