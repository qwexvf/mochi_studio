// FFI for URL-based sharing

export function copyShareLink(query, variables) {
  const payload = btoa(JSON.stringify({ query, variables }));
  const url = `${location.origin}${location.pathname}#share=${payload}`;
  navigator.clipboard.writeText(url).catch(() => {
    prompt("Copy this link:", url);
  });
}

export function readUrl() {
  const hash = location.hash;
  const match = hash.match(/share=([^&]+)/);
  if (!match) return { 0: "None", _ :"None" };
  try {
    const { query, variables } = JSON.parse(atob(match[1]));
    return { 0: "Some", 1: [query, variables] };
  } catch {
    return { 0: "None" };
  }
}
