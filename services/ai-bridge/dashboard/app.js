const API = (window.AIBRIDGE_API_BASE || "").replace(/\/$/, "");

async function fetchJSON(path) {
  if (!API) return null;
  const token = localStorage.getItem("aibridge_token") || "";
  const res = await fetch(API + path, {
    headers: token ? { Authorization: "Bearer " + token } : {},
  });
  if (!res.ok) throw new Error(String(res.status));
  return res.json();
}

async function refresh() {
  const bridge = document.getElementById("st-bridge");
  const list = document.getElementById("task-list");
  try {
    const health = await fetchJSON("/health");
    if (!health) {
      bridge.textContent = "UNAVAILABLE";
      document.getElementById("st-chatgpt").textContent = "NOT VERIFIED";
      document.getElementById("st-cursor").textContent = "NOT VERIFIED";
      return;
    }
    bridge.textContent = "OK";
    document.getElementById("st-chatgpt").textContent =
      health.chatgpt_connection_verified ? "VERIFIED" : "NOT VERIFIED";
    const tasks = await fetchJSON("/tools/scootercheck_list_tasks");
    // Prefer MCP call shape if present
  } catch (err) {
    bridge.textContent = "UNAVAILABLE";
    list.innerHTML = '<li class="muted">Quelle nicht erreichbar</li>';
  }
}

document.getElementById("btn-refresh").addEventListener("click", refresh);
document.getElementById("task-form").addEventListener("submit", (e) => {
  e.preventDefault();
  const text = document.getElementById("task-text").value.trim();
  if (!text) return;
  alert("Auftrag lokal erfasst (noch keine Live-Ausführung ohne Bridge-Token):\n\n" + text);
});
refresh();
