const KEY = "mochi_studio_collections";

export function saveCollections(collections) {
  try {
    localStorage.setItem(KEY, JSON.stringify(collections));
  } catch {}
}

export function loadCollections() {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}
