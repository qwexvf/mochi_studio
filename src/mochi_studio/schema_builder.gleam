// mochi_studio/schema_builder.gleam
// Visual schema builder panel — compose GraphQL types, generate Gleam code

import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import mochi_studio/schema_node.{type SchemaNode}

pub type Model {
  Model(
    nodes: List(SchemaNode),
    selected: Option(String),
    generated_code: Option(String),
  )
}

pub type Msg {
  AddType(kind: schema_node.NodeKind)
  SelectNode(id: String)
  UpdateNode(schema_node.SchemaNode)
  RemoveNode(id: String)
  AddField(node_id: String)
  GenerateCode
  GotCode(String)
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(nodes: [], selected: None, generated_code: None), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    AddType(kind) -> {
      let node = schema_node.new(kind)
      #(Model(..model, nodes: [node, ..model.nodes]), effect.none())
    }

    SelectNode(id) -> #(Model(..model, selected: Some(id)), effect.none())

    UpdateNode(updated) -> {
      let nodes =
        list.map(model.nodes, fn(n) {
          case n.id == updated.id {
            True -> updated
            False -> n
          }
        })
      #(Model(..model, nodes: nodes), effect.none())
    }

    RemoveNode(id) -> {
      let nodes = list.filter(model.nodes, fn(n) { n.id != id })
      #(Model(..model, nodes: nodes, selected: None), effect.none())
    }

    AddField(node_id) -> {
      let nodes =
        list.map(model.nodes, fn(n) {
          case n.id == node_id {
            True -> schema_node.add_field(n)
            False -> n
          }
        })
      #(Model(..model, nodes: nodes), effect.none())
    }

    GenerateCode -> #(model, generate_code(model.nodes))

    GotCode(code) -> #(
      Model(..model, generated_code: Some(code)),
      effect.none(),
    )
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("schema-builder")], [
    view_sidebar(model),
    view_canvas(model),
    view_code_panel(model),
  ])
}

fn view_sidebar(model: Model) -> Element(Msg) {
  html.div([attribute.class("builder-sidebar")], [
    html.h3([], [html.text("Add Type")]),
    html.button([event.on_click(AddType(schema_node.Object))], [
      html.text("Object"),
    ]),
    html.button([event.on_click(AddType(schema_node.InputObject))], [
      html.text("Input"),
    ]),
    html.button([event.on_click(AddType(schema_node.Enum))], [
      html.text("Enum"),
    ]),
    html.button([event.on_click(AddType(schema_node.Union))], [
      html.text("Union"),
    ]),
    html.button([event.on_click(GenerateCode)], [html.text("Generate Code")]),
  ])
}

fn view_canvas(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("builder-canvas")],
    list.map(model.nodes, fn(node) {
      schema_node.view(node, model.selected)
      |> element.map(fn(msg) {
        case msg {
          schema_node.Selected(id) -> SelectNode(id)
          schema_node.Updated(n) -> UpdateNode(n)
          schema_node.Removed(id) -> RemoveNode(id)
          schema_node.FieldAdded(id) -> AddField(id)
        }
      })
    }),
  )
}

fn view_code_panel(model: Model) -> Element(Msg) {
  html.div([attribute.class("builder-code")], [
    html.h3([], [html.text("Generated Gleam")]),
    html.pre([], [
      html.text(option.unwrap(model.generated_code, "// Click Generate Code")),
    ]),
  ])
}

fn generate_code(nodes: List(SchemaNode)) -> Effect(Msg) {
  // TODO: convert nodes → SDL → run through mochi_codegen gleam generator
  let code = schema_node.nodes_to_gleam(nodes)
  effect.from(fn(dispatch) { dispatch(GotCode(code)) })
}
