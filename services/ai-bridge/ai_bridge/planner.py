"""Task Planner stub — deterministic plan without LLM calls."""

from __future__ import annotations

from ai_bridge.models import Task, TaskPriority


class TaskPlanner:
    DEFAULT_AGENTS = ("implementer", "tester")

    def plan(self, task: Task) -> dict:
        agents = list(task.assigned_agents) or list(self.DEFAULT_AGENTS)
        if task.priority in (TaskPriority.P0, TaskPriority.P1) and "reviewer" not in agents:
            agents.append("reviewer")

        steps = [
            {"id": "validate", "title": "Validate requirements and repo context", "agent": agents[0]},
            {"id": "implement", "title": "Implement changes on a feature branch", "agent": agents[0]},
            {
                "id": "test",
                "title": "Run automated tests / checks",
                "agent": agents[1] if len(agents) > 1 else agents[0],
            },
        ]
        if "reviewer" in agents:
            steps.append({"id": "review", "title": "Human/agent review gate", "agent": "reviewer"})

        prompt = self._build_prompt(task, steps)
        return {
            "planner": "stub-v1",
            "agents": agents,
            "steps": steps,
            "cursor_prompt": prompt,
            "notes": "Deterministic stub plan. Replace with LLM/MCP planner in later etappes.",
        }

    def _build_prompt(self, task: Task, steps: list[dict]) -> str:
        reqs = "\n".join(f"- {r}" for r in task.requirements) or "- (none listed)"
        ac = "\n".join(f"- {c}" for c in task.acceptance_criteria) or "- (none listed)"
        step_lines = "\n".join(f"{i+1}. {s['title']}" for i, s in enumerate(steps))
        return (
            f"# Task: {task.title}\n\n"
            f"{task.description}\n\n"
            f"Repository: {task.repository}\n"
            f"Base branch: {task.base_branch}\n"
            f"Priority: {task.priority.value}\n\n"
            f"## Requirements\n{reqs}\n\n"
            f"## Acceptance criteria\n{ac}\n\n"
            f"## Plan\n{step_lines}\n"
        )
