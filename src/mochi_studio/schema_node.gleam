// mochi_studio/schema_node.gleam

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type NodeKind {
  Object
  InputObject
  Enum
  Union
}

pub type FieldDef {
  FieldDef(name: String, field_type: String, non_null: Bool)
}

pub type SchemaNode {
  SchemaNode(
    id: String,
    kind: NodeKind,
    name: String,
    fields: List(FieldDef),
    x: Int,
    y: Int,
  )
}

pub type NodeMsg {
  Selected(String)
  Updated(SchemaNode)
  Removed(String)
  FieldAdded(String)
  DragStarted(id: String, start_x: Int, start_y: Int)
}

pub fn new(kind: NodeKind) -> SchemaNode {
  SchemaNode(
    id: do_gen_id(),
    kind: kind,
    name: default_name(kind),
    fields: [],
    x: 80,
    y: 80,
  )
}

pub fn add_field(node: SchemaNode) -> SchemaNode {
  let field = FieldDef(name: "field", field_type: "String", non_null: False)
  SchemaNode(..node, fields: list.append(node.fields, [field]))
}

pub fn view(node: SchemaNode, selected: Option(String)) -> Element(NodeMsg) {
  let is_selected = selected == Some(node.id)
  let border_class = case is_selected {
    True -> "border-pink-500 shadow-pink-500/20"
    False -> "border-gray-700 hover:border-gray-500"
  }
  html.div(
    [
      attribute.class(
        "absolute bg-gray-900 rounded-lg border shadow-xl select-none "
        <> border_class,
      ),
      attribute.style("left", int.to_string(node.x) <> "px"),
      attribute.style("top", int.to_string(node.y) <> "px"),
      attribute.style("width", "220px"),
      attribute.style("min-width", "220px"),
      // Stop propagation on the whole card so canvas pan doesn't fire when clicking nodes
      event.on("mousedown", decode.success(Selected(node.id)))
        |> event.stop_propagation,
    ],
    [view_node_header(node), view_fields(node)],
  )
}

fn view_node_header(node: SchemaNode) -> Element(NodeMsg) {
  let kind_color = case node.kind {
    Object -> "text-pink-400 bg-pink-500/10"
    InputObject -> "text-blue-400 bg-blue-500/10"
    Enum -> "text-green-400 bg-green-500/10"
    Union -> "text-purple-400 bg-purple-500/10"
  }
  html.div(
    [
      attribute.class(
        "flex items-center gap-2 px-3 py-2 border-b border-gray-800 rounded-t-lg cursor-grab active:cursor-grabbing",
      ),
      event.on("mousedown", {
        use mouse_x <- decode.field("clientX", decode.int)
        use mouse_y <- decode.field("clientY", decode.int)
        decode.success(DragStarted(
          id: node.id,
          start_x: mouse_x,
          start_y: mouse_y,
        ))
      }),
      event.on_click(Selected(node.id)),
    ],
    [
      html.span(
        [
          attribute.class(
            "text-xs font-mono px-1.5 py-0.5 rounded " <> kind_color,
          ),
        ],
        [html.text(kind_label(node.kind))],
      ),
      html.input([
        attribute.class(
          "flex-1 bg-transparent text-sm font-semibold text-gray-100 outline-none cursor-text",
        ),
        attribute.value(node.name),
        event.on("mousedown", decode.success(Selected(node.id)))
          |> event.stop_propagation,
        event.on_input(fn(name) { Updated(SchemaNode(..node, name: name)) }),
      ]),
      html.button(
        [
          attribute.class(
            "text-gray-600 hover:text-red-400 text-xs transition-colors ml-1",
          ),
          event.on_click(Removed(node.id)),
        ],
        [html.text("✕")],
      ),
    ],
  )
}

fn view_fields(node: SchemaNode) -> Element(NodeMsg) {
  html.div(
    [attribute.class("px-3 py-2 flex flex-col gap-1")],
    list.append(
      list.index_map(node.fields, fn(field, i) { view_field(node, field, i) }),
      [
        html.button(
          [
            attribute.class(
              "mt-1 text-xs text-gray-600 hover:text-pink-400 text-left transition-colors",
            ),
            event.on_click(FieldAdded(node.id)),
          ],
          [html.text("+ add field")],
        ),
      ],
    ),
  )
}

fn view_field(node: SchemaNode, field: FieldDef, index: Int) -> Element(NodeMsg) {
  html.div([attribute.class("flex gap-1 items-center")], [
    html.div(
      [attribute.class("w-1.5 h-1.5 rounded-full bg-gray-600 shrink-0")],
      [],
    ),
    html.input([
      attribute.class(
        "flex-1 min-w-0 bg-gray-800 rounded px-2 py-0.5 text-xs text-gray-200 outline-none focus:ring-1 focus:ring-pink-500",
      ),
      attribute.value(field.name),
      attribute.placeholder("name"),
      event.on_input(fn(name) {
        let fields =
          list.index_map(node.fields, fn(f, i) {
            case i == index {
              True -> FieldDef(..f, name: name)
              False -> f
            }
          })
        Updated(SchemaNode(..node, fields: fields))
      }),
    ]),
    html.input([
      attribute.class(
        "w-20 bg-gray-800 rounded px-2 py-0.5 text-xs text-blue-300 outline-none focus:ring-1 focus:ring-pink-500",
      ),
      attribute.value(field.field_type),
      attribute.placeholder("type"),
      event.on_input(fn(t) {
        let fields =
          list.index_map(node.fields, fn(f, i) {
            case i == index {
              True -> FieldDef(..f, field_type: t)
              False -> f
            }
          })
        Updated(SchemaNode(..node, fields: fields))
      }),
    ]),
  ])
}

pub fn nodes_to_gleam(nodes: List(SchemaNode)) -> String {
  nodes
  |> list.map(node_to_gleam)
  |> string.join("\n\n")
}

fn node_to_gleam(node: SchemaNode) -> String {
  case node.kind {
    Object | InputObject -> {
      let fields =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> ": " <> gleam_type(f) })
        |> string.join(",\n")
      "pub type "
      <> node.name
      <> " {\n  "
      <> node.name
      <> "(\n"
      <> fields
      <> "\n  )\n}"
    }
    Enum -> {
      let variants =
        node.fields
        |> list.map(fn(f) { "  " <> f.name })
        |> string.join("\n")
      "pub type " <> node.name <> " {\n" <> variants <> "\n}"
    }
    Union -> {
      let variants =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> "(" <> f.field_type <> ")" })
        |> string.join("\n")
      "pub type " <> node.name <> " {\n" <> variants <> "\n}"
    }
  }
}

fn gleam_type(field: FieldDef) -> String {
  let base = case field.field_type {
    "String" | "ID" -> "String"
    "Int" -> "Int"
    "Float" -> "Float"
    "Boolean" -> "Bool"
    t -> t
  }
  case field.non_null {
    True -> base
    False -> "option.Option(" <> base <> ")"
  }
}

fn kind_label(kind: NodeKind) -> String {
  case kind {
    Object -> "type"
    InputObject -> "input"
    Enum -> "enum"
    Union -> "union"
  }
}

fn default_name(kind: NodeKind) -> String {
  case kind {
    Object -> "MyType"
    InputObject -> "MyInput"
    Enum -> "MyEnum"
    Union -> "MyUnion"
  }
}

pub fn nodes_to_sdl(nodes: List(SchemaNode)) -> String {
  nodes
  |> list.map(node_to_sdl)
  |> string.join("\n\n")
}

fn node_to_sdl(node: SchemaNode) -> String {
  case node.kind {
    Object -> {
      let fields =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> ": " <> sdl_type(f) })
        |> string.join("\n")
      "type " <> node.name <> " {\n" <> fields <> "\n}"
    }
    InputObject -> {
      let fields =
        node.fields
        |> list.map(fn(f) { "  " <> f.name <> ": " <> sdl_type(f) })
        |> string.join("\n")
      "input " <> node.name <> " {\n" <> fields <> "\n}"
    }
    Enum -> {
      let values =
        node.fields
        |> list.map(fn(f) { "  " <> f.name })
        |> string.join("\n")
      "enum " <> node.name <> " {\n" <> values <> "\n}"
    }
    Union -> {
      let members =
        node.fields
        |> list.map(fn(f) { f.field_type })
        |> string.join(" | ")
      "union " <> node.name <> " = " <> members
    }
  }
}

fn sdl_type(field: FieldDef) -> String {
  let base = case field.field_type {
    "String" -> "String"
    "Int" -> "Int"
    "Float" -> "Float"
    "Boolean" -> "Boolean"
    "ID" -> "ID"
    t -> t
  }
  case field.non_null {
    True -> base <> "!"
    False -> base
  }
}

pub fn nodes_to_sql(nodes: List(SchemaNode)) -> String {
  let object_nodes = list.filter(nodes, fn(n) { n.kind == Object })
  let object_names = list.map(object_nodes, fn(n) { n.name })
  let tables =
    object_nodes
    |> list.map(fn(n) { node_to_sql(n, object_names) })
    |> string.join("\n\n")
  "-- Generated by mochi studio\n\nBEGIN;\n\n" <> tables <> "\n\nCOMMIT;"
}

fn node_to_sql(node: SchemaNode, object_names: List(String)) -> String {
  let table_name = to_snake_case(node.name) <> "s"
  let has_id = list.any(node.fields, fn(f) { string.lowercase(f.name) == "id" })
  let id_col = case has_id {
    True -> []
    False -> ["  id UUID PRIMARY KEY DEFAULT gen_random_uuid()"]
  }
  let field_cols =
    node.fields
    |> list.filter(fn(f) { string.lowercase(f.name) != "id" })
    |> list.map(fn(f) { "  " <> f.name <> " " <> sql_type(f, object_names) })
  let ts_col = ["  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()"]
  let all_cols = list.append(list.append(id_col, field_cols), ts_col)
  let cols_str = string.join(all_cols, ",\n")
  "CREATE TABLE IF NOT EXISTS " <> table_name <> " (\n" <> cols_str <> "\n);"
}

fn sql_type(field: FieldDef, object_names: List(String)) -> String {
  let base = case field.field_type {
    "ID" -> "UUID"
    "String" -> "TEXT"
    "Int" -> "INTEGER"
    "Float" -> "DOUBLE PRECISION"
    "Boolean" -> "BOOLEAN"
    t ->
      case list.contains(object_names, t) {
        True -> "UUID REFERENCES " <> to_snake_case(t) <> "s(id)"
        False -> "TEXT"
      }
  }
  case field.non_null {
    True -> base <> " NOT NULL"
    False -> base
  }
}

fn to_snake_case(s: String) -> String {
  let chars = string.to_graphemes(s)
  case chars {
    [] -> ""
    [first, ..rest] -> {
      let acc = string.lowercase(first)
      list.fold(rest, acc, fn(result, char) {
        let is_upper = char != string.lowercase(char)
        case is_upper {
          True -> result <> "_" <> string.lowercase(char)
          False -> result <> char
        }
      })
    }
  }
}

pub fn nodes_to_mochi_schema(nodes: List(SchemaNode)) -> String {
  let type_defs =
    nodes
    |> list.map(node_to_gleam)
    |> string.join("\n\n")
  let object_nodes = list.filter(nodes, fn(n) { n.kind == Object })
  let type_fns =
    object_nodes
    |> list.map(node_to_mochi_type_fn)
    |> string.join("\n\n")
  "// Generated by mochi studio\nimport mochi/query\nimport mochi/types\nimport gleam/option\n\n"
  <> type_defs
  <> case type_fns {
    "" -> ""
    s -> "\n\n" <> s
  }
}

fn node_to_mochi_type_fn(node: SchemaNode) -> String {
  let type_name = string.lowercase(node.name)
  let fields =
    node.fields
    |> list.map(fn(f) {
      let builder = case f.field_type {
        "ID" -> "types.id"
        "String" -> "types.string"
        "Int" -> "types.int"
        "Float" -> "types.float"
        "Boolean" -> "types.bool"
        _ -> "types.string"
      }
      "  |> "
      <> builder
      <> "(\""
      <> f.name
      <> "\", fn(u: "
      <> node.name
      <> ") { u."
      <> f.name
      <> " })"
    })
    |> string.join("\n")
  "pub fn "
  <> type_name
  <> "_type() {\n  types.object(\""
  <> node.name
  <> "\")\n"
  <> fields
  <> "\n  |> types.build(fn(_) { Error(\"decoder not implemented\") })\n}"
}

pub fn node_card_width() -> Int {
  220
}

pub fn node_header_height() -> Int {
  36
}

pub fn node_field_height() -> Int {
  28
}

pub fn start_node_drag(
  node_id: String,
  start_x: Int,
  start_y: Int,
  zoom: Float,
  on_move: fn(String, Int, Int) -> msg,
  on_end: fn(String) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    do_start_node_drag(
      node_id,
      start_x,
      start_y,
      zoom,
      fn(id, dx, dy) { dispatch(on_move(id, dx, dy)) },
      fn(id) { dispatch(on_end(id)) },
    )
  })
}

@external(javascript, "./drag_ffi.mjs", "startNodeDrag")
fn do_start_node_drag(
  node_id: String,
  start_x: Int,
  start_y: Int,
  zoom: Float,
  on_move: fn(String, Int, Int) -> Nil,
  on_end: fn(String) -> Nil,
) -> Nil {
  let _ = node_id
  let _ = start_x
  let _ = start_y
  let _ = zoom
  let _ = on_move
  let _ = on_end
  Nil
}

@external(javascript, "./schema_node_ffi.mjs", "genId")
fn do_gen_id() -> String {
  "node-erlang-" <> int.to_string(erlang_unique_integer())
}

@external(erlang, "erlang", "unique_integer")
fn erlang_unique_integer() -> Int
