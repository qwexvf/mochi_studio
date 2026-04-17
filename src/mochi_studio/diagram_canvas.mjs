import {
  createSignal,
  createEffect,
  createUniqueId,
  For,
} from "solid-js";
import { render } from "solid-js/web";
import h from "solid-js/h";

// ── Constants ─────────────────────────────────────────────────────────────────

const KIND_COLOR = {
  Object:      "#6366f1",
  InputObject: "#10b981",
  Enum:        "#f59e0b",
  Union:       "#ec4899",
};

const CARD_W      = 260;
const HEADER_H    = 40;
const FIELD_H     = 32;
const FOOTER_H    = 30;

function cardHeight(node) {
  return HEADER_H + node.fields.length * FIELD_H + FOOTER_H;
}

// ── Shared state ──────────────────────────────────────────────────────────────

let _currentNodes = [];

// ── Helpers ───────────────────────────────────────────────────────────────────

function newNode(kind) {
  return {
    id: createUniqueId(),
    name: "NewType",
    kind,
    fields: [],
    x: 260 + Math.floor(Math.random() * 400),
    y: 160 + Math.floor(Math.random() * 300),
  };
}

function newField() {
  return { name: "field", field_type: "String", non_null: false };
}

function updateNodes(setNodes, updater) {
  setNodes((prev) => {
    const next = updater(prev);
    _currentNodes = next;
    return next;
  });
}

// ── SVG helpers (createElementNS required for correct SVG rendering) ──────────

const SVG_NS = "http://www.w3.org/2000/svg";

function svgEl(tag, attrs = {}, children = []) {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  for (const child of children) if (child) el.appendChild(child);
  return el;
}

// ── SVG edges ─────────────────────────────────────────────────────────────────

function SvgEdges(props) {
  let svgRef;

  createEffect(() => {
    const nodes = props.nodes;
    if (!svgRef) return;

    // Clear previous edges (keep defs)
    while (svgRef.lastChild && svgRef.lastChild.tagName !== "defs")
      svgRef.removeChild(svgRef.lastChild);

    const nameToNode = Object.fromEntries(nodes.map((n) => [n.name, n]));

    nodes.forEach((srcNode) => {
      srcNode.fields.forEach((field, fieldIdx) => {
        const base = field.field_type.replace(/[\[\]!]/g, "").trim();
        const tgt  = nameToNode[base];
        if (!tgt || tgt.id === srcNode.id) return;

        const srcH = cardHeight(srcNode);
        const x1   = srcNode.x + CARD_W / 2;
        const y1   = srcNode.y - srcH / 2 + HEADER_H + fieldIdx * FIELD_H + FIELD_H / 2;
        const x2   = tgt.x - CARD_W / 2;
        const y2   = tgt.y;
        const cx   = (x1 + x2) / 2;
        const d    = `M ${x1} ${y1} C ${cx} ${y1}, ${cx} ${y2}, ${x2} ${y2}`;
        const mx   = (x1 + x2) / 2;
        const my   = (y1 + y2) / 2 - 6;

        svgRef.appendChild(svgEl("path", { d, stroke: "#6366f1", "stroke-width": "1.5", fill: "none", "marker-end": "url(#mochi-arrow)" }));
        svgRef.appendChild(svgEl("text", { x: mx, y: my, fill: "#64748b", "font-size": "10", "font-family": "JetBrains Mono,monospace", "text-anchor": "middle" }));
        svgRef.lastChild.textContent = field.name;
      });
    });
  });

  return h("svg", {
    ref: (el) => {
      svgRef = el;
      // Arrow marker — created once
      const defs   = svgEl("defs");
      const marker = svgEl("marker", { id: "mochi-arrow", markerWidth: "8", markerHeight: "8", refX: "6", refY: "3", orient: "auto" });
      marker.appendChild(svgEl("path", { d: "M0,0 L0,6 L8,3 z", fill: "#6366f1" }));
      defs.appendChild(marker);
      el.appendChild(defs);
    },
    style: {
      position: "absolute",
      top: 0,
      left: 0,
      width: "100%",
      height: "100%",
      overflow: "visible",
      "pointer-events": "none",
    },
  });
}

// ── Drag-to-connect rubber band ───────────────────────────────────────────────

function RubberBand(props) {
  let svgRef;

  createEffect(() => {
    const drag = props.drag;
    if (!svgRef) return;
    while (svgRef.lastChild) svgRef.removeChild(svgRef.lastChild);
    if (!drag) return;
    const { x1, y1, x2, y2 } = drag;
    const cx = (x1 + x2) / 2;
    const d  = `M ${x1} ${y1} C ${cx} ${y1}, ${cx} ${y2}, ${x2} ${y2}`;
    svgRef.appendChild(svgEl("path", { d, stroke: "#6366f1", "stroke-width": "1.5", fill: "none", "stroke-dasharray": "5 3" }));
  });

  return h("svg", {
    ref: (el) => svgRef = el,
    style: {
      position: "absolute",
      top: 0,
      left: 0,
      width: "100%",
      height: "100%",
      overflow: "visible",
      "pointer-events": "none",
    },
  });
}

// ── NodeCard ──────────────────────────────────────────────────────────────────

function NodeCard(props) {
  const color  = () => KIND_COLOR[props.node.kind] ?? "#6366f1";
  const height = () => cardHeight(props.node);

  // Header drag
  const onDragHeader = (e) => {
    if (e.target.tagName === "INPUT" || e.target.tagName === "BUTTON") return;
    e.preventDefault();
    const startX = e.clientX, startY = e.clientY;
    const startNX = props.node.x, startNY = props.node.y;
    const onMove = (e) => props.onMove(props.node.id, startNX + e.clientX - startX, startNY + e.clientY - startY);
    const onUp = () => { document.removeEventListener("mousemove", onMove); document.removeEventListener("mouseup", onUp); };
    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  };

  // Connection port drag (right edge of a field)
  const onPortDown = (e, fieldIdx) => {
    e.preventDefault();
    e.stopPropagation();
    const srcX = props.node.x + CARD_W / 2;
    const srcY = props.node.y - height() / 2 + HEADER_H + fieldIdx * FIELD_H + FIELD_H / 2;
    props.onPortDragStart({ nodeId: props.node.id, fieldIdx, x1: srcX, y1: srcY });
  };

  const update = (fn) => props.onUpdate(props.node.id, fn);

  return h("div", {
    style: {
      position: "absolute",
      left: `${props.node.x}px`,
      top: `${props.node.y}px`,
      transform: "translate(-50%, -50%)",
      width: `${CARD_W}px`,
      border: `1.5px solid ${color()}`,
      "border-radius": "6px",
      overflow: "visible",
      "box-shadow": "0 4px 20px #00000080",
      background: "#0f172a",
    },
  },
    // Header
    h("div", {
      onMouseDown: onDragHeader,
      style: {
        background: `${color()}18`,
        "border-bottom": `1px solid ${color()}30`,
        padding: "7px 10px",
        display: "flex",
        "align-items": "center",
        gap: "8px",
        cursor: "grab",
        "border-radius": "4px 4px 0 0",
      },
    },
      h("span", {
        style: { "font-size": "10px", color: color(), background: `${color()}22`, "border-radius": "3px", padding: "2px 6px", "font-family": "'JetBrains Mono',monospace", "font-weight": 600, "white-space": "nowrap" },
      }, props.node.kind),
      h("input", {
        value: props.node.name,
        placeholder: "TypeName",
        onBlur: (e) => update((n) => ({ ...n, name: e.target.value })),
        onMouseDown: (e) => e.stopPropagation(),
        style: { flex: 1, background: "transparent", border: "none", outline: "none", color: "#e2e8f0", "font-size": "14px", "font-weight": 600, "font-family": "'JetBrains Mono',monospace", "min-width": 0, padding: "2px 0", cursor: "text" },
      }),
      h("button", {
        onClick: () => props.onRemove(props.node.id),
        onMouseDown: (e) => e.stopPropagation(),
        style: { background: "none", border: "none", color: "#475569", cursor: "pointer", "font-size": "16px", "line-height": 1, padding: "0 2px" },
        onMouseEnter: (e) => e.target.style.color = "#ef4444",
        onMouseLeave: (e) => e.target.style.color = "#475569",
      }, "×"),
    ),

    // Fields
    h(For, { each: () => props.node.fields }, (field, i) =>
      h("div", {
        onMouseDown: (e) => e.stopPropagation(),
        style: { display: "flex", "align-items": "center", gap: "6px", padding: "5px 10px", "border-bottom": "1px solid #1e293b", background: "#0f172a", position: "relative" },
      },
        h("input", {
          value: field.name,
          placeholder: "fieldName",
          onBlur: (e) => update((n) => ({ ...n, fields: n.fields.map((f, idx) => idx === i() ? { ...f, name: e.target.value } : f) })),
          style: { flex: 1, background: "transparent", border: "none", outline: "none", color: "#cbd5e1", "font-size": "13px", "font-family": "'JetBrains Mono',monospace", "min-width": 0, padding: "2px 0" },
        }),
        h("input", {
          value: field.field_type,
          placeholder: "String",
          onBlur: (e) => update((n) => ({ ...n, fields: n.fields.map((f, idx) => idx === i() ? { ...f, field_type: e.target.value } : f) })),
          style: { width: "72px", background: "transparent", border: "none", outline: "none", color: color(), "font-size": "13px", "font-family": "'JetBrains Mono',monospace", "text-align": "right", opacity: 0.85, padding: "2px 0" },
        }),
        h("label", {
          title: field.non_null ? "non-null (click to make nullable)" : "nullable (click to make non-null)",
          style: { cursor: "pointer", color: "#475569", "font-size": "12px", "min-width": "12px", "text-align": "center" },
        },
          h("input", { type: "checkbox", checked: field.non_null, onChange: (e) => update((n) => ({ ...n, fields: n.fields.map((f, idx) => idx === i() ? { ...f, non_null: e.target.checked } : f) })), style: { display: "none" } }),
          field.non_null ? "!" : "?",
        ),
        h("span", {
          onClick: () => update((n) => ({ ...n, fields: n.fields.filter((_, idx) => idx !== i()) })),
          style: { color: "#ef4444", cursor: "pointer", "font-size": "15px", "line-height": 1, "min-width": "14px", "text-align": "center", opacity: 0 },
          onMouseEnter: (e) => e.target.style.opacity = 1,
          onMouseLeave: (e) => e.target.style.opacity = 0,
        }, "×"),
        // Connection port — drag from here to another node to link
        h("div", {
          onMouseDown: (e) => onPortDown(e, i()),
          title: "Drag to connect to another type",
          style: {
            position: "absolute",
            right: "-8px",
            top: "50%",
            transform: "translateY(-50%)",
            width: "12px",
            height: "12px",
            "border-radius": "50%",
            background: color(),
            border: "2px solid #0f172a",
            cursor: "crosshair",
            opacity: 0,
            transition: "opacity 0.15s",
            "z-index": 30,
          },
          onMouseEnter: (e) => e.target.style.opacity = 1,
          onMouseLeave: (e) => e.target.style.opacity = 0,
        }),
      ),
    ),

    // Add field
    h("div", {
      onClick: () => update((n) => ({ ...n, fields: [...n.fields, newField()] })),
      onMouseDown: (e) => e.stopPropagation(),
      style: { padding: "6px 10px", "font-size": "12px", color: "#475569", cursor: "pointer", "font-family": "'JetBrains Mono',monospace", "text-align": "center", "user-select": "none", "border-radius": "0 0 4px 4px" },
      onMouseEnter: (e) => e.currentTarget.style.color = color(),
      onMouseLeave: (e) => e.currentTarget.style.color = "#475569",
    }, "+ add field"),
  );
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

function Toolbar(props) {
  const kinds = [
    { kind: "Object",      label: "Object" },
    { kind: "InputObject", label: "Input"  },
    { kind: "Enum",        label: "Enum"   },
    { kind: "Union",       label: "Union"  },
  ];
  return h("div", {
    style: { position: "absolute", top: "12px", left: "12px", display: "flex", "flex-direction": "column", gap: "6px", "z-index": 20 },
  },
    ...kinds.map(({ kind, label }) =>
      h("button", {
        onClick: () => props.onAdd(kind),
        style: { display: "flex", "align-items": "center", gap: "6px", padding: "5px 12px", background: "#1e293b", border: `1px solid ${KIND_COLOR[kind]}44`, "border-radius": "5px", color: KIND_COLOR[kind], "font-size": "12px", "font-family": "'JetBrains Mono',monospace", cursor: "pointer" },
      },
        h("span", { style: { width: "8px", height: "8px", "border-radius": "2px", background: KIND_COLOR[kind], display: "inline-block" } }),
        `+ ${label}`,
      ),
    ),
  );
}

// ── DiagramApp ────────────────────────────────────────────────────────────────

function DiagramApp() {
  const [nodes, setNodes]   = createSignal([]);
  const [pan, setPan]       = createSignal({ x: 0, y: 0 });
  const [zoom, setZoom]     = createSignal(1);
  const [portDrag, setPortDrag] = createSignal(null); // {nodeId, fieldIdx, x1, y1, x2, y2}

  _currentNodes = [];

  const mut = (fn) => updateNodes(setNodes, fn);

  const addNode    = (kind) => mut((ns) => [...ns, newNode(kind)]);
  const removeNode = (id)   => mut((ns) => ns.filter((n) => n.id !== id));
  const updateNode = (id, fn) => mut((ns) => ns.map((n) => n.id === id ? fn(n) : n));
  const moveNode   = (id, x, y) => mut((ns) => ns.map((n) => n.id === id ? { ...n, x, y } : n));

  // Port drag — rubber band line
  const onPortDragStart = (info) => {
    setPortDrag({ ...info, x2: info.x1, y2: info.y1 });

    const onMove = (e) => {
      const rect = e.currentTarget?.getBoundingClientRect?.() ?? { left: 0, top: 0 };
      // Convert screen coords to canvas coords
      const canvasEl = document.getElementById("sb-canvas");
      const cr = canvasEl?.getBoundingClientRect() ?? { left: 0, top: 0 };
      const z  = zoom();
      const p  = pan();
      const cx = (e.clientX - cr.left - p.x) / z;
      const cy = (e.clientY - cr.top  - p.y) / z;
      setPortDrag((d) => d ? { ...d, x2: cx, y2: cy } : null);
    };

    const onUp = (e) => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);

      // Hit-test: did we drop on a node?
      const drag = portDrag();
      if (drag) {
        const z = zoom(), p = pan();
        const canvasEl = document.getElementById("sb-canvas");
        const cr = canvasEl?.getBoundingClientRect() ?? { left: 0, top: 0 };
        const cx = (e.clientX - cr.left - p.x) / z;
        const cy = (e.clientY - cr.top  - p.y) / z;
        const hit = nodes().find((n) => {
          const h = cardHeight(n);
          return Math.abs(cx - n.x) < CARD_W / 2 && Math.abs(cy - n.y) < h / 2 && n.id !== drag.nodeId;
        });
        if (hit) {
          // Set field_type to the target node's name
          updateNode(drag.nodeId, (n) => ({
            ...n,
            fields: n.fields.map((f, idx) => idx === drag.fieldIdx ? { ...f, field_type: hit.name } : f),
          }));
        }
      }
      setPortDrag(null);
    };

    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  };

  // Canvas pan
  const onCanvasDown = (e) => {
    if (e.target !== e.currentTarget) return;
    const startX = e.clientX, startY = e.clientY, startP = pan();
    const onMove = (e) => setPan({ x: startP.x + e.clientX - startX, y: startP.y + e.clientY - startY });
    const onUp   = () => { document.removeEventListener("mousemove", onMove); document.removeEventListener("mouseup", onUp); };
    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  };

  const onWheel = (e) => {
    e.preventDefault();
    setZoom((z) => Math.max(0.2, Math.min(3, z * (e.deltaY > 0 ? 0.9 : 1.1))));
  };

  return h("div", {
    id: "sb-canvas",
    style: { position: "relative", width: "100%", height: "100%", overflow: "hidden", background: "#0f172a" },
    onMouseDown: onCanvasDown,
    onWheel,
  },
    h("div", {
      style: {
        position: "absolute",
        top: 0,
        left: 0,
        width: "100%",
        height: "100%",
        transform: () => `translate(${pan().x}px, ${pan().y}px) scale(${zoom()})`,
        "transform-origin": "0 0",
      },
    },
      h(SvgEdges, { get nodes() { return nodes(); } }),
      h(RubberBand, { get drag() { return portDrag(); } }),
      h(For, { each: nodes },
        (node) => h(NodeCard, {
          node,
          onUpdate: updateNode,
          onRemove: removeNode,
          onMove:   moveNode,
          onPortDragStart,
        }),
      ),
    ),
    h(Toolbar, { onAdd: addNode }),
  );
}

// ── Mount ─────────────────────────────────────────────────────────────────────

let _dispose = null;

export function mount(containerId, _onGenerate) {
  const el = document.getElementById(containerId);
  if (!el) return;
  _dispose = render(() => h(DiagramApp, {}), el);
}

export function unmount() {
  if (_dispose) { _dispose(); _dispose = null; }
}

export function trigger_generate(callback) {
  callback(JSON.stringify(_currentNodes));
}
