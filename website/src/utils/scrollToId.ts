export function scrollToId(id: string) {
  const el = document.getElementById(id);
  if (!el) return false;
  el.scrollIntoView({ behavior: "smooth", block: "start" });
  history.replaceState(null, "", `#${id}`);
  return true;
}

export function hashId(href: string) {
  const i = href.indexOf("#");
  return i >= 0 ? href.slice(i + 1) : "";
}
