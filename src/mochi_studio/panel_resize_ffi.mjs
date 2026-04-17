export function init_resize(containerId) {
  if (!setup(containerId)) {
    const observer = new MutationObserver(() => {
      if (setup(containerId)) observer.disconnect();
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }
}

function setup(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return false;

  container.querySelectorAll("[data-resize-handle]").forEach((handle) => {
    const side = handle.getAttribute("data-resize-handle");

    handle.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const panel = container.querySelector(`[data-panel="${side}"]`);
      if (!panel) return;

      const startX    = e.clientX;
      const startWidth = panel.offsetWidth;

      handle.style.background = "#6366f1";
      document.body.style.cursor = "col-resize";
      document.body.style.userSelect = "none";

      const onMove = (e) => {
        const delta = side === "left"
          ? e.clientX - startX
          : startX - e.clientX;
        const newWidth = Math.max(140, Math.min(480, startWidth + delta));
        panel.style.width = newWidth + "px";
        panel.style.flexBasis = newWidth + "px";
      };

      const onUp = () => {
        handle.style.background = "";
        document.body.style.cursor = "";
        document.body.style.userSelect = "";
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
      };

      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    });
  });
  return true;
}
