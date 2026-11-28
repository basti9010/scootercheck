/**
 * ScooterCheck Development Center — mobile SPA (iPhone Safari).
 * Auth: localStorage key `aibridge_token` only (never Cursor API keys).
 * APIs (relative): /health, /api/v1/status, /api/v1/tasks, /api/v1/tasks/{id}
 * Mutations: POST create / approve / start
 * Report: GET /api/v1/tasks/{id}/report
 */

const TOKEN_KEY = "aibridge_token";
const UNKNOWN = "UNKNOWN";
const NOT_VERIFIED = "NOT VERIFIED";

const state = {
  route: { name: "home" },
  status: null,
  health: null,
  tasks: null,
  task: null,
  report: null,
  busy: false,
  error: null,
};

const $ = (sel, root = document) => root.querySelector(sel);
const main = $("#main");
const pageTag = $("#page-tag");
const btnBack = $("#btn-back");
const tabbar = $("#tabbar");
const toastEl = $("#toast");
const tokenDialog = $("#token-dialog");
const tokenInput = $("#token-input");

/* ---------- routing ---------- */

function parseHash() {
  const raw = (location.hash || "#/").replace(/^#/, "") || "/";
  const path = raw.startsWith("/") ? raw : `/${raw}`;
  const parts = path.split("/").filter(Boolean);

  if (parts.length === 0) return { name: "home" };
  if (parts[0] === "new") return { name: "new" };
  if (parts[0] === "tasks") return { name: "tasks" };
  if (parts[0] === "task" && parts[1]) {
    if (parts[2] === "report") return { name: "report", id: decodeURIComponent(parts[1]) };
    return { name: "detail", id: decodeURIComponent(parts[1]) };
  }
  return { name: "home" };
}

function navigate(hash) {
  const next = hash.startsWith("#") ? hash : `#${hash}`;
  if (location.hash === next) {
    onRoute();
    return;
  }
  location.hash = next;
}

function setChrome(route) {
  const deep = route.name === "detail" || route.name === "report";
  btnBack.classList.toggle("hidden", !deep);

  const tags = {
    home: "Development Center",
    new: "Neuer Auftrag",
    tasks: "Aufgaben",
    detail: "Task-Detail",
    report: "Report",
  };
  pageTag.textContent = tags[route.name] || "Development Center";

  tabbar.querySelectorAll(".tab").forEach((tab) => {
    const r = tab.dataset.route;
    const active =
      (r === "home" && route.name === "home") ||
      (r === "new" && route.name === "new") ||
      (r === "tasks" && (route.name === "tasks" || route.name === "detail" || route.name === "report"));
    tab.classList.toggle("active", active);
  });
}

/* ---------- API ---------- */

function getToken() {
  return (localStorage.getItem(TOKEN_KEY) || "").trim();
}

function authHeaders(extra = {}) {
  const headers = { Accept: "application/json", ...extra };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    headers: authHeaders(options.headers || {}),
  });
  const text = await res.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { raw: text };
    }
  }
  if (!res.ok) {
    const detail = data && data.detail;
    const msg =
      (typeof detail === "string" && detail) ||
      (data && (data.message || data.error)) ||
      `HTTP ${res.status}`;
    const err = new Error(typeof msg === "string" ? msg : JSON.stringify(msg));
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function pick(obj, keys, fallback = UNKNOWN) {
  if (!obj || typeof obj !== "object") return fallback;
  for (const k of keys) {
    if (obj[k] !== undefined && obj[k] !== null && obj[k] !== "") return obj[k];
  }
  return fallback;
}

function boolLabel(val, yes = "OK", no = NOT_VERIFIED, missing = UNKNOWN) {
  if (val === true || val === "true" || val === 1) return yes;
  if (val === false || val === "false" || val === 0) return no;
  return missing;
}

function statusClass(label) {
  const s = String(label || "").toUpperCase();
  if (["OK", "VERIFIED", "COMPLETED", "RUNNING", "QUEUED", "LIVE_READY"].includes(s)) return "ok";
  if (
    ["FAILED", "CANCELLED", "BLOCKED", "UNAVAILABLE", "ERROR", "BLOCKED_MISSING_CREDENTIAL"].includes(
      s
    )
  )
    return "bad";
  if (["WAITING_FOR_APPROVAL", "REVIEW", "TESTING", "PLANNED", "VALIDATING"].includes(s))
    return "warn";
  if ([UNKNOWN, NOT_VERIFIED, "NOT CONNECTED"].includes(s)) return "muted";
  return "";
}

function normalizeTasks(payload) {
  if (!payload) return null;
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload.tasks)) return payload.tasks;
  if (Array.isArray(payload.recent_tasks)) return payload.recent_tasks;
  if (Array.isArray(payload.items)) return payload.items;
  return null;
}

function taskId(t) {
  return pick(t, ["task_id", "id", "uuid"], "");
}

function taskTitle(t) {
  return pick(t, ["title", "name", "summary", "description"], UNKNOWN);
}

function taskStatus(t) {
  return pick(t, ["status", "state"], UNKNOWN);
}

function truncate(str, n = 80) {
  const s = String(str || "").trim();
  if (s.length <= n) return s;
  return `${s.slice(0, n - 1)}…`;
}

function firstLineTitle(text) {
  const line = String(text || "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .find(Boolean);
  if (!line) return "Untitled task";
  return truncate(line, 120);
}

/* ---------- UI helpers ---------- */

let toastTimer = null;
function toast(msg) {
  toastEl.textContent = msg;
  toastEl.classList.remove("hidden");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.classList.add("hidden"), 2800);
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function cell(label, value) {
  const cls = statusClass(value);
  return `<div class="status-cell"><dt>${escapeHtml(label)}</dt><dd class="${cls}">${escapeHtml(value)}</dd></div>`;
}

function bindTaskRows() {
  main.querySelectorAll("[data-task-id]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.getAttribute("data-task-id");
      if (id) navigate(`#/task/${encodeURIComponent(id)}`);
    });
  });
}

function taskListHtml(tasks, emptyHint) {
  if (tasks === null) {
    return `<li class="empty">${state.error ? "Quelle nicht erreichbar" : emptyHint || "Lade…"}</li>`;
  }
  if (!tasks.length) return `<li class="empty">Keine Tasks</li>`;
  return tasks
    .map((t) => {
      const id = taskId(t);
      const st = taskStatus(t);
      return `<li>
        <button type="button" class="task-row" data-task-id="${escapeHtml(id)}">
          <div class="meta">
            <div class="title">${escapeHtml(truncate(taskTitle(t), 72))}</div>
            <div class="sub">${escapeHtml(pick(t, ["updated_at", "created_at"], id || UNKNOWN))}</div>
          </div>
          <span class="badge ${statusClass(st)}">${escapeHtml(st)}</span>
        </button>
      </li>`;
    })
    .join("");
}

/* ---------- views ---------- */

function renderHome() {
  const health = state.health;
  const status = state.status;
  const cursor = status && status.cursor;

  const bridge = health
    ? boolLabel(health.ok ?? true, "OK", "UNAVAILABLE", UNKNOWN)
    : status
      ? pick(status, ["bridge"], UNKNOWN).toString().toUpperCase() === "OK"
        ? "OK"
        : pick(status, ["bridge"], UNKNOWN)
      : state.error
        ? "UNAVAILABLE"
        : UNKNOWN;

  const cursorLive = health
    ? boolLabel(
        health.CURSOR_API_LIVE_VERIFIED ?? health.cursor_api_live_verified,
        "VERIFIED",
        NOT_VERIFIED,
        NOT_VERIFIED
      )
    : cursor
      ? boolLabel(cursor.CURSOR_API_LIVE_VERIFIED, "VERIFIED", NOT_VERIFIED, NOT_VERIFIED)
      : NOT_VERIFIED;

  const chatgpt = boolLabel(
    (health && health.chatgpt_connection_verified) ??
      (status && status.chatgpt_connection_verified),
    "VERIFIED",
    NOT_VERIFIED,
    NOT_VERIFIED
  );

  const deploy = status ? pick(status, ["production_deploy", "deployment", "deploy_status"], UNKNOWN) : UNKNOWN;

  const mode = health
    ? pick(health, ["client_mode", "mode"], UNKNOWN)
    : cursor
      ? pick(cursor, ["mode", "status"], UNKNOWN)
      : UNKNOWN;

  let openCount = UNKNOWN;
  if (status && Array.isArray(status.active_tasks)) openCount = String(status.active_tasks.length);
  else if (status && status.open_tasks !== undefined) openCount = String(status.open_tasks);

  const listSource =
    state.tasks ||
    (status && (status.recent_tasks || status.active_tasks)) ||
    null;

  const pulls = (status && status.pull_requests && status.pull_requests.pulls) || [];
  const ciRuns = (status && status.ci && status.ci.runs) || [];
  const pullHtml = pulls.length
    ? pulls
        .slice(0, 5)
        .map(
          (p) =>
            `<li><a class="link" href="${escapeHtml(p.html_url || "#")}" target="_blank" rel="noopener">#${escapeHtml(
              String(p.number || "")
            )} ${escapeHtml(truncate(p.title || "", 48))}</a></li>`
        )
        .join("")
    : `<li class="empty">Keine offenen PRs / nicht geladen</li>`;
  const ciHtml = ciRuns.length
    ? ciRuns
        .slice(0, 5)
        .map(
          (r) =>
            `<li><span class="badge ${statusClass(r.conclusion || r.status)}">${escapeHtml(
              String(r.conclusion || r.status || UNKNOWN)
            )}</span> ${escapeHtml(truncate(r.name || r.display_title || "", 40))}</li>`
        )
        .join("")
    : `<li class="empty">CI unbekannt</li>`;

  main.innerHTML = `
    <section class="panel">
      <h1>Status</h1>
      <p class="lede">Nur Live-Daten. Fehlende Werte bleiben ${UNKNOWN} / ${NOT_VERIFIED}.</p>
      <dl class="status-grid">
        ${cell("Bridge", bridge)}
        ${cell("Cursor Live", cursorLive)}
        ${cell("ChatGPT", chatgpt)}
        ${cell("Deployment", deploy)}
        ${cell("Client-Modus", mode)}
        ${cell("Offene Tasks", openCount)}
      </dl>
      <div class="actions pair" style="margin-top:1rem">
        <button type="button" class="btn primary" id="btn-refresh">Aktualisieren</button>
        <button type="button" class="btn" id="btn-go-new">Neuer Auftrag</button>
      </div>
    </section>
    <section class="panel">
      <h2>Aktuelle Tasks</h2>
      <ul class="task-list">${taskListHtml(listSource ? listSource.slice(0, 8) : null)}</ul>
      <div class="actions">
        <button type="button" class="btn ghost" id="btn-all-tasks">Alle Tasks</button>
      </div>
    </section>
    <section class="panel">
      <h2>Pull Requests</h2>
      <ul class="plain-list">${pullHtml}</ul>
    </section>
    <section class="panel">
      <h2>CI</h2>
      <ul class="plain-list">${ciHtml}</ul>
    </section>
  `;

  $("#btn-refresh")?.addEventListener("click", () => loadHome(true));
  $("#btn-go-new")?.addEventListener("click", () => navigate("#/new"));
  $("#btn-all-tasks")?.addEventListener("click", () => navigate("#/tasks"));
  bindTaskRows();
}

function renderNew() {
  main.innerHTML = `
    <section class="panel">
      <h1>Neuer Auftrag</h1>
      <p class="lede">Beschreibe die Änderung. Ein Tippen → erstellen.</p>
      <form id="new-form">
        <label class="field">
          <span>Aufgabe</span>
          <textarea class="large" id="task-text" required maxlength="8000"
            placeholder="z. B. Verbessere die Radar-Karte für iPhone Safari…"></textarea>
        </label>
        <div class="actions">
          <button type="submit" class="btn primary" id="btn-create" ${state.busy ? "disabled" : ""}>
            ${state.busy ? "Wird erstellt…" : "Auftrag erstellen"}
          </button>
        </div>
      </form>
    </section>
  `;

  $("#new-form")?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const text = ($("#task-text")?.value || "").trim();
    if (!text) return;
    if (!getToken()) {
      toast("Bridge-Token fehlt");
      openTokenSheet();
      return;
    }
    state.busy = true;
    renderNew();
    try {
      const body = {
        title: firstLineTitle(text),
        description: text,
        repository: "https://github.com/basti9010/scootercheck",
        base_branch: "cursor/ai-bridge-v2-b100",
        priority: "P2",
        approval_required: true,
        idempotency_key: crypto.randomUUID(),
      };
      const data = await api("/api/v1/tasks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const created = data?.task || data;
      const id = taskId(created);
      toast("Auftrag erstellt");
      if (id) navigate(`#/task/${encodeURIComponent(id)}`);
      else navigate("#/tasks");
    } catch (err) {
      toast(err.message || "Erstellen fehlgeschlagen");
      state.busy = false;
      renderNew();
      const ta = $("#task-text");
      if (ta) ta.value = text;
    } finally {
      state.busy = false;
    }
  });
}

function renderTasks() {
  main.innerHTML = `
    <section class="panel">
      <h1>Tasks</h1>
      <p class="lede">Tippe einen Eintrag für Details.</p>
      <ul class="task-list">${taskListHtml(state.tasks)}</ul>
      <div class="actions pair">
        <button type="button" class="btn" id="btn-refresh-tasks">Aktualisieren</button>
        <button type="button" class="btn primary" id="btn-new-from-list">Neu</button>
      </div>
    </section>
  `;

  $("#btn-refresh-tasks")?.addEventListener("click", () => loadTasks(true));
  $("#btn-new-from-list")?.addEventListener("click", () => navigate("#/new"));
  bindTaskRows();
}

function renderDetail() {
  const t = state.task;
  if (!t) {
    main.innerHTML = `<p class="loading">${escapeHtml(state.error || "Lade Task…")}</p>`;
    return;
  }

  const id = taskId(t);
  const st = taskStatus(t);
  const approval = pick(t, ["approval_status"], UNKNOWN);
  const desc = pick(t, ["description"], UNKNOWN);
  const reportPath = pick(t, ["report_path"], "");
  const errMsg = pick(t, ["error_message", "error"], "");
  const stUp = String(st).toUpperCase();
  const canAnalyze = stUp === "CREATED";
  const canApprove = stUp === "WAITING_FOR_APPROVAL";
  const canStart = stUp === "QUEUED";
  const canCancel = !["COMPLETED", "CANCELLED"].includes(stUp);
  const agentId = pick(t, ["cursor_agent_id"], "");
  const runId = pick(t, ["cursor_run_id"], "");
  const branch = pick(t, ["branch_name", "base_branch"], UNKNOWN);
  const prUrl = pick(t, ["github_pr_url"], "");
  const lastSync = pick(t, ["last_sync_at", "updated_at"], UNKNOWN);
  const started = pick(t, ["created_at"], UNKNOWN);

  main.innerHTML = `
    <section class="panel">
      <h1>${escapeHtml(truncate(taskTitle(t), 90))}</h1>
      <div class="detail-block">
        <div class="label">Status</div>
        <div class="value ${statusClass(st)}">${escapeHtml(st)}</div>
      </div>
      <div class="detail-block">
        <div class="label">Task-ID</div>
        <div class="value">${escapeHtml(id || UNKNOWN)}</div>
      </div>
      <div class="detail-block">
        <div class="label">Cursor-Agent-ID</div>
        <div class="value">${escapeHtml(agentId || "—")}</div>
      </div>
      <div class="detail-block">
        <div class="label">Cursor-Run-ID</div>
        <div class="value">${escapeHtml(runId || "—")}</div>
      </div>
      <div class="detail-block">
        <div class="label">Start / Sync</div>
        <div class="value">${escapeHtml(started)} · ${escapeHtml(lastSync)}</div>
      </div>
      <div class="detail-block">
        <div class="label">Branch</div>
        <div class="value">${escapeHtml(branch)}</div>
      </div>
      <div class="detail-block">
        <div class="label">Pull Request</div>
        <div class="value">${
          prUrl && prUrl !== UNKNOWN
            ? `<a class="link" href="${escapeHtml(prUrl)}" target="_blank" rel="noopener">${escapeHtml(prUrl)}</a>`
            : "—"
        }</div>
      </div>
      <div class="detail-block">
        <div class="label">Freigabe</div>
        <div class="value">${escapeHtml(approval)}</div>
      </div>
      <div class="detail-block">
        <div class="label">Auftrag</div>
        <div class="value">${escapeHtml(desc)}</div>
      </div>
      ${
        errMsg && errMsg !== UNKNOWN
          ? `<div class="detail-block"><div class="label">Fehler</div><div class="value bad">${escapeHtml(errMsg)}</div></div>`
          : ""
      }
      <div class="actions">
        <button type="button" class="btn" id="btn-analyze" ${!canAnalyze || state.busy ? "disabled" : ""}>
          Analysieren
        </button>
        <button type="button" class="btn primary" id="btn-approve" ${!canApprove || state.busy ? "disabled" : ""}>
          Freigeben
        </button>
        <button type="button" class="btn" id="btn-start" ${!canStart || state.busy ? "disabled" : ""}>
          Agent starten
        </button>
        <button type="button" class="btn" id="btn-report" ${!id ? "disabled" : ""}>
          Report
        </button>
        <button type="button" class="btn ghost" id="btn-cancel" ${!canCancel || state.busy ? "disabled" : ""}>
          Abbrechen
        </button>
        <button type="button" class="btn ghost" id="btn-refresh-detail">Aktualisieren</button>
      </div>
    </section>
  `;

  $("#btn-refresh-detail")?.addEventListener("click", () => loadDetail(id, true));
  $("#btn-report")?.addEventListener("click", () => {
    if (id) navigate(`#/task/${encodeURIComponent(id)}/report`);
  });
  $("#btn-analyze")?.addEventListener("click", () => mutateTask(id, "analyze"));
  $("#btn-approve")?.addEventListener("click", () => {
    if (!confirm("Aufgabe wirklich freigeben?")) return;
    mutateTask(id, "approve");
  });
  $("#btn-start")?.addEventListener("click", () => {
    if (!confirm("Cursor-Agent wirklich starten?")) return;
    mutateTask(id, "start");
  });
  $("#btn-cancel")?.addEventListener("click", () => {
    if (!confirm("Aufgabe abbrechen?")) return;
    mutateTask(id, "cancel");
  });
}

function renderReport() {
  const t = state.task;
  const reportPayload = state.report;

  if (!t && !reportPayload) {
    main.innerHTML = `<p class="loading">${escapeHtml(state.error || "Lade Report…")}</p>`;
    return;
  }

  const id = (t && taskId(t)) || (reportPayload && reportPayload.task_id) || state.route.id || "";
  const title = t ? taskTitle(t) : id || UNKNOWN;

  let body = UNKNOWN;
  const report =
    reportPayload?.report ??
    t?.report ??
    t?.report_text ??
    t?.report_body ??
    null;

  if (report === null || report === undefined || report === "") {
    body = reportPayload?.summary || UNKNOWN;
  } else if (typeof report === "object") {
    body = JSON.stringify(report, null, 2);
  } else {
    body = String(report);
  }

  main.innerHTML = `
    <section class="panel">
      <h1>Report</h1>
      <p class="lede">${escapeHtml(truncate(title, 72))} · ${escapeHtml(id || UNKNOWN)}</p>
      <div class="report-box">${escapeHtml(body)}</div>
      <div class="actions pair" style="margin-top:1rem">
        <button type="button" class="btn" id="btn-back-detail">Zur Task</button>
        <button type="button" class="btn ghost" id="btn-refresh-report">Aktualisieren</button>
      </div>
    </section>
  `;

  $("#btn-back-detail")?.addEventListener("click", () => {
    if (id) navigate(`#/task/${encodeURIComponent(id)}`);
  });
  $("#btn-refresh-report")?.addEventListener("click", async () => {
    await loadDetail(id, true);
    await loadReport(id, true);
    renderReport();
  });
}

async function mutateTask(id, action) {
  if (!id) return;
  if (!getToken()) {
    toast("Bridge-Token fehlt");
    openTokenSheet();
    return;
  }
  state.busy = true;
  renderDetail();
  try {
    const data = await api(`/api/v1/tasks/${encodeURIComponent(id)}/${action}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    if (action === "start") {
      // start returns orchestration report; refresh task afterward
      state.report = data;
      await loadDetail(id, true);
    } else {
      state.task = data?.task || data;
    }
    const labels = {
      analyze: "Analysiert",
      approve: "Freigegeben",
      start: "Gestartet",
      cancel: "Abgebrochen",
    };
    toast(labels[action] || "OK");
  } catch (err) {
    toast(err.message || "Aktion fehlgeschlagen");
  } finally {
    state.busy = false;
    if (state.route.name === "detail") renderDetail();
  }
}

/* ---------- data loaders ---------- */

async function loadHome(force) {
  state.error = null;
  if (force) {
    state.health = null;
    state.status = null;
    state.tasks = null;
    renderHome();
  }

  const results = await Promise.allSettled([
    api("/health"),
    api("/api/v1/status"),
    api("/api/v1/tasks"),
  ]);

  if (results[0].status === "fulfilled") state.health = results[0].value;
  else {
    state.health = null;
    state.error = results[0].reason?.message || "health failed";
  }

  if (results[1].status === "fulfilled") state.status = results[1].value;
  else state.status = null;

  if (results[2].status === "fulfilled") state.tasks = normalizeTasks(results[2].value) || [];
  else if (state.status) state.tasks = normalizeTasks(state.status);
  else state.tasks = null;

  if (state.route.name === "home") renderHome();
}

async function loadTasks(force) {
  if (force) {
    state.tasks = null;
    renderTasks();
  }
  try {
    const data = await api("/api/v1/tasks");
    state.tasks = normalizeTasks(data) || [];
    state.error = null;
  } catch (err) {
    state.tasks = null;
    state.error = err.message;
  }
  if (state.route.name === "tasks") renderTasks();
}

async function loadDetail(id, force) {
  if (!id) return;
  if (force || !state.task || taskId(state.task) !== id) {
    state.task = null;
    if (state.route.name === "detail") renderDetail();
  }
  try {
    const data = await api(`/api/v1/tasks/${encodeURIComponent(id)}`);
    state.task = data?.task || data;
    state.error = null;
  } catch (err) {
    state.task = null;
    state.error = err.message || "Task nicht gefunden";
  }
  if (state.route.name === "detail") renderDetail();
}

async function loadReport(id, force) {
  if (!id) return;
  if (force) state.report = null;
  try {
    state.report = await api(`/api/v1/tasks/${encodeURIComponent(id)}/report`);
    state.error = null;
  } catch (err) {
    state.report = null;
    state.error = err.message || "Report nicht verfügbar";
  }
}

/* ---------- token sheet ---------- */

function openTokenSheet() {
  tokenInput.value = getToken();
  if (typeof tokenDialog.showModal === "function") tokenDialog.showModal();
  else tokenDialog.setAttribute("open", "");
}

$("#btn-token")?.addEventListener("click", openTokenSheet);

$("#token-form")?.addEventListener("submit", (e) => {
  const submitter = e.submitter;
  const value = submitter?.value || "save";
  if (value === "save") {
    const v = tokenInput.value.trim();
    if (v) localStorage.setItem(TOKEN_KEY, v);
    else localStorage.removeItem(TOKEN_KEY);
    toast(v ? "Token gespeichert" : "Token entfernt");
  }
});

$("#btn-clear-token")?.addEventListener("click", () => {
  localStorage.removeItem(TOKEN_KEY);
  tokenInput.value = "";
  toast("Token gelöscht");
  tokenDialog.close?.();
});

/* ---------- chrome events ---------- */

btnBack?.addEventListener("click", () => {
  const r = state.route;
  if (r.name === "report" && r.id) navigate(`#/task/${encodeURIComponent(r.id)}`);
  else if (r.name === "detail") navigate("#/tasks");
  else history.back();
});

tabbar?.addEventListener("click", (e) => {
  const tab = e.target.closest(".tab");
  if (!tab) return;
  const route = tab.dataset.route;
  if (route === "home") navigate("#/");
  else if (route === "new") navigate("#/new");
  else if (route === "tasks") navigate("#/tasks");
});

async function onRoute() {
  state.route = parseHash();
  setChrome(state.route);

  if (state.route.name === "home") {
    renderHome();
    await loadHome(false);
  } else if (state.route.name === "new") {
    renderNew();
  } else if (state.route.name === "tasks") {
    renderTasks();
    await loadTasks(false);
  } else if (state.route.name === "detail") {
    renderDetail();
    await loadDetail(state.route.id, false);
  } else if (state.route.name === "report") {
    renderReport();
    await Promise.all([loadDetail(state.route.id, false), loadReport(state.route.id, false)]);
    renderReport();
  }
}

window.addEventListener("hashchange", onRoute);

if (!location.hash || location.hash === "#") {
  location.replace("#/");
} else {
  onRoute();
}
