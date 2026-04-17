import { mount, unmount, trigger_generate } from "./diagram_canvas.mjs";

let mounted = false;

export function init_diagram(containerId, onGenerate) {
  if (mounted) return;

  function tryMount() {
    const el = document.getElementById(containerId);
    if (!el) {
      const observer = new MutationObserver(() => {
        const el = document.getElementById(containerId);
        if (el) { observer.disconnect(); doMount(); }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    } else {
      doMount();
    }
  }

  function doMount() {
    mount(containerId, onGenerate);
    mounted = true;
  }

  tryMount();
}

export function destroy_diagram() {
  unmount();
  mounted = false;
}

export function generate(callback) {
  trigger_generate(callback);
}
