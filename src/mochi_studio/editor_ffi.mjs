import { EditorView, basicSetup } from "https://esm.sh/codemirror@6.0.2";
import { keymap } from "https://esm.sh/@codemirror/view@6.41.0";
import { indentWithTab } from "https://esm.sh/@codemirror/commands@6.10.3";
import { EditorState } from "https://esm.sh/@codemirror/state@6.6.0";
import { oneDark } from "https://esm.sh/@codemirror/theme-one-dark@6.1.3";
import { graphql } from "https://esm.sh/cm6-graphql@0.2.1";
import { buildClientSchema } from "https://esm.sh/graphql@16.13.2";

const editors = new Map();
const callbacks = new Map();

const editorTheme = EditorView.theme({
  "&": { height: "100%", fontSize: "13px" },
  ".cm-scroller": { overflow: "auto", fontFamily: "ui-monospace, monospace" },
  ".cm-content": { padding: "12px" },
  ".cm-editor": { height: "100%" },
});

function buildExtensions(schema, onChange) {
  return [
    basicSetup,
    oneDark,
    keymap.of([indentWithTab]),
    ...(schema ? [graphql(schema)] : []),
    EditorView.updateListener.of((update) => {
      if (update.docChanged && onChange) {
        onChange(update.state.doc.toString());
      }
    }),
    editorTheme,
  ];
}

export function mountEditor(id, initialValue, schemaJson, onChange) {
  const el = document.getElementById(id);
  if (!el || editors.has(id)) return;

  callbacks.set(id, onChange);

  let schema = null;
  if (schemaJson) {
    try {
      const parsed = JSON.parse(schemaJson);
      schema = buildClientSchema(parsed.data ?? parsed);
    } catch (e) {
      console.warn("editor: failed to parse schema", e);
    }
  }

  const view = new EditorView({
    state: EditorState.create({
      doc: initialValue,
      extensions: buildExtensions(schema, onChange),
    }),
    parent: el,
  });

  editors.set(id, view);
}

export function updateEditorSchema(id, introspectionJson) {
  const view = editors.get(id);
  if (!view) return;
  try {
    const parsed = JSON.parse(introspectionJson);
    // GraphQL response wraps in { data: { __schema } }; buildClientSchema needs { __schema }
    const introspection = parsed.data ?? parsed;
    if (!introspection.__schema) return;
    const schema = buildClientSchema(introspection);
    const onChange = callbacks.get(id);
    view.setState(
      EditorState.create({
        doc: view.state.doc.toString(),
        extensions: buildExtensions(schema, onChange),
      })
    );
  } catch (e) {
    console.warn("editor: failed to update schema", e);
  }
}

export function setEditorValue(id, value) {
  const view = editors.get(id);
  if (!view) return;
  const current = view.state.doc.toString();
  if (current === value) return;
  view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: value } });
}

export function destroyEditor(id) {
  const view = editors.get(id);
  if (view) {
    view.destroy();
    editors.delete(id);
    callbacks.delete(id);
  }
}
