export async function executeGraphQL(endpoint, body, callback) {
  try {
    const resp = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body,
    });
    const text = await resp.text();
    if (!resp.ok) {
      callback(false, `HTTP ${resp.status}: ${text}`);
    } else {
      callback(true, text);
    }
  } catch (e) {
    callback(false, String(e));
  }
}

export function prettyPrint(jsonStr) {
  try {
    return JSON.stringify(JSON.parse(jsonStr), null, 2);
  } catch {
    return jsonStr;
  }
}
