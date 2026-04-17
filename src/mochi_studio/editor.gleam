// mochi_studio/editor.gleam
// CodeMirror 6 editor with GraphQL autocomplete via FFI

import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

pub fn view(id: String) -> Element(msg) {
  html.div([attribute.id(id), attribute.class("flex-1 overflow-hidden")], [])
}

pub fn mount(
  id: String,
  value: String,
  on_change: fn(String) -> msg,
) -> Effect(msg) {
  effect.after_paint(fn(dispatch, _) {
    do_mount(id, value, "", fn(v) { dispatch(on_change(v)) })
  })
}

pub fn mount_with_schema(
  id: String,
  value: String,
  schema_json: String,
  on_change: fn(String) -> msg,
) -> Effect(msg) {
  effect.after_paint(fn(dispatch, _) {
    do_mount(id, value, schema_json, fn(v) { dispatch(on_change(v)) })
  })
}

pub fn set_value(id: String, value: String) -> Effect(msg) {
  effect.after_paint(fn(_dispatch, _) { do_set_value(id, value) })
}

pub fn update_schema(id: String, introspection_json: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { do_update_schema(id, introspection_json) })
}

pub fn destroy(id: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { do_destroy(id) })
}

@external(javascript, "./editor_ffi.mjs", "mountEditor")
fn do_mount(
  id: String,
  value: String,
  schema_json: String,
  on_change: fn(String) -> Nil,
) -> Nil {
  let _ = id
  let _ = value
  let _ = schema_json
  let _ = on_change
  Nil
}

@external(javascript, "./editor_ffi.mjs", "setEditorValue")
fn do_set_value(id: String, value: String) -> Nil {
  let _ = id
  let _ = value
  Nil
}

@external(javascript, "./editor_ffi.mjs", "updateEditorSchema")
fn do_update_schema(id: String, introspection_json: String) -> Nil {
  let _ = id
  let _ = introspection_json
  Nil
}

@external(javascript, "./editor_ffi.mjs", "destroyEditor")
fn do_destroy(id: String) -> Nil {
  let _ = id
  Nil
}
