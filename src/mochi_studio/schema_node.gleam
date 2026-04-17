// mochi_studio/schema_node.gleam
// A single node in the schema builder canvas

import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import lustre/attribute
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
}

pub fn new(kind: NodeKind) -> SchemaNode {
  let id = do_gen_id()
  SchemaNode(
    id: id,
    kind: kind,
    name: default_name(kind),
    fields: [],
    x: 100,
    y: 100,
  )
}

pub fn add_field(node: SchemaNode) -> SchemaNode {
  let field = FieldDef(name: "field", field_type: "String", non_null: False)
  SchemaNode(..node, fields: list.append(node.fields, [field]))
}

pub fn view(node: SchemaNode, selected: Option(String)) -> Element(NodeMsg) {
  let is_selected = selected == Some(node.id)
  html.div(
    [
      attribute.class(case is_selected {
        True -> "schema-node selected"
        False -> "schema-node"
      }),
      attribute.style([
        #("left", int.to_string(node.x) <> "px"),
        #("top", int.to_string(node.y) <> "px"),
      ]),
      event.on_click(Selected(node.id)),
    ],
    [
      view_node_header(node),
      view_fields(node),
    ],
  )
}

fn view_node_header(node: SchemaNode) -> Element(NodeMsg) {
  html.div([attribute.class("node-header")], [
    html.span([attribute.class("node-kind")], [html.text(kind_label(node.kind))]),
    html.input([
      attribute.value(node.name),
      event.on_input(fn(name) { Updated(SchemaNode(..node, name: name)) }),
    ]),
    html.button([event.on_click(Removed(node.id))], [html.text("×")]),
  ])
}

fn view_fields(node: SchemaNode) -> Element(NodeMsg) {
  html.div([attribute.class("node-fields")], [
    html.div(
      [],
      list.index_map(node.fields, fn(field, i) { view_field(node, field, i) }),
    ),
    html.button([event.on_click(FieldAdded(node.id))], [html.text("+ field")]),
  ])
}

fn view_field(node: SchemaNode, field: FieldDef, index: Int) -> Element(NodeMsg) {
  html.div([attribute.class("node-field")], [
    html.input([
      attribute.value(field.name),
      attribute.placeholder("field name"),
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

@external(javascript, "./schema_node_ffi.mjs", "genId")
fn do_gen_id() -> String
