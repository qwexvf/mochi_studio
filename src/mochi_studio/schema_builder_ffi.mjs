// schema_builder_ffi.mjs — canvas pan drag handling + zoom + keyboard

export function startCanvasPan(startMouseX, startMouseY, onMove, onEnd) {
  let lastX = startMouseX;
  let lastY = startMouseY;

  function onMouseMove(e) {
    const dx = e.clientX - lastX;
    const dy = e.clientY - lastY;
    lastX = e.clientX;
    lastY = e.clientY;
    onMove(dx, dy);
  }

  function onMouseUp() {
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
    onEnd();
  }

  document.addEventListener("mousemove", onMouseMove);
  document.addEventListener("mouseup", onMouseUp);
}

export function listenWheel(canvasId, callback) {
  const el = document.getElementById(canvasId);
  if (!el) return;
  el.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      const rect = el.getBoundingClientRect();
      callback(e.deltaY, e.clientX, e.clientY, rect.x, rect.y, rect.width, rect.height);
    },
    { passive: false },
  );
}

export function getCanvasRect(canvasId) {
  const el = document.getElementById(canvasId);
  if (!el) return { x: 0, y: 0, width: 800, height: 600 };
  return el.getBoundingClientRect();
}

export function getCanvasSize(canvasId) {
  const el = document.getElementById(canvasId);
  if (!el) return [800, 600];
  const rect = el.getBoundingClientRect();
  return [rect.width, rect.height];
}

export function listenKeyboard(onDelete, onEscape) {
  function onKeyDown(e) {
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return;
    if (e.key === "Delete" || e.key === "Backspace") {
      e.preventDefault();
      onDelete();
    } else if (e.key === "Escape") {
      onEscape();
    }
  }
  document.addEventListener("keydown", onKeyDown);
}

export function copyToClipboard(text) {
  navigator.clipboard.writeText(text).catch(() => {});
}

export async function writeToProject(projectPath, files, callback) {
  // Convert Gleam list of tuples to JS array of objects
  const fileList = [];
  let cur = files;
  while (cur.hasOwnProperty("head")) {
    const [path, content] = cur.head;
    fileList.push({ path, content });
    cur = cur.tail;
  }
  try {
    const resp = await fetch("http://localhost:4000/api/write", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ project_path: projectPath, files: fileList }),
    });
    const data = await resp.json();
    const written = data.written ?? [];
    callback(true, written.join(", ") || "done");
  } catch (e) {
    callback(false, String(e));
  }
}
