// drag_ffi.mjs — node drag handling (zoom-aware)

export function startNodeDrag(nodeId, startMouseX, startMouseY, zoom, onMove, onEnd) {
  let lastX = startMouseX;
  let lastY = startMouseY;

  function onMouseMove(e) {
    // Divide by zoom so node moves with cursor in canvas space
    const dx = Math.round((e.clientX - lastX) / zoom);
    const dy = Math.round((e.clientY - lastY) / zoom);
    lastX = e.clientX;
    lastY = e.clientY;
    onMove(nodeId, dx, dy);
  }

  function onMouseUp() {
    document.removeEventListener("mousemove", onMouseMove);
    document.removeEventListener("mouseup", onMouseUp);
    onEnd(nodeId);
  }

  document.addEventListener("mousemove", onMouseMove);
  document.addEventListener("mouseup", onMouseUp);
}
