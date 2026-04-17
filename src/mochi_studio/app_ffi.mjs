export function get_hash_panel() {
  return window.location.hash.replace("#", "") || "playground";
}

export function set_hash_panel(panel) {
  window.location.hash = panel;
}
